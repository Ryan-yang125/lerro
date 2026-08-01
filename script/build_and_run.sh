#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
source "$script_dir/signing_support.zsh"
configuration=release
build_triple=arm64-apple-macosx26.0
configuration_directory=Release
should_test=false
should_launch=true
mode=run

for argument in "$@"; do
    case "$argument" in
        --debug)
            configuration=debug
            configuration_directory=Debug
            mode=debug
            ;;
        --release)
            configuration=release
            ;;
        --verify)
            should_test=true
            mode=verify
            ;;
        --logs)
            mode=logs
            ;;
        --telemetry)
            mode=telemetry
            ;;
        --no-launch)
            should_launch=false
            ;;
        --launch)
            should_launch=true
            ;;
        *)
            print -u2 "Unknown argument: $argument"
            exit 64
            ;;
    esac
done

cd "$project_dir"
lerro_resolve_signing
signing_mode="$LERRO_RESOLVED_SIGNING_MODE"
signing_identity="$LERRO_RESOLVED_CODESIGN_IDENTITY"

if $should_launch; then
    /usr/bin/pkill -x Lerro >/dev/null 2>&1 || true
fi

if $should_test; then
    swift test
fi

# SwiftBuild generates app-aware SwiftPM resource accessors that search
# Bundle.main.resourceURL, which matches the canonical macOS Contents/Resources
# layout assembled below.
swift build --build-system swiftbuild --triple "$build_triple" -c "$configuration" --product Lerro
binary_dir=$(swift build --build-system swiftbuild --triple "$build_triple" -c "$configuration" --show-bin-path)

app_path="$project_dir/dist/Lerro.app"
dsym_path="$project_dir/dist/Lerro.app.dSYM"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

stage_arm64_file() {
    local source_path=$1
    local destination_path=$2
    local source_architectures

    source_architectures=$(lipo -archs "$source_path")
    if [[ "$source_architectures" == "arm64" ]]; then
        ditto "$source_path" "$destination_path"
        return
    fi
    if [[ " $source_architectures " == *" arm64 "* ]]; then
        lipo "$source_path" -thin arm64 -output "$destination_path"
        return
    fi

    print -u2 "Required arm64 slice is missing from $source_path: $source_architectures"
    exit 1
}

rm -rf "$app_path"
rm -rf "$dsym_path"
mkdir -p "$macos_path" "$resources_path"
stage_arm64_file "$binary_dir/Lerro" "$macos_path/Lerro"
chmod 755 "$macos_path/Lerro"

dsym_dwarf_path="$dsym_path/Contents/Resources/DWARF/Lerro"
/usr/bin/dsymutil "$macos_path/Lerro" -o "$dsym_path"
[[ -f "$dsym_dwarf_path" ]] || {
    print -u2 "Missing Lerro dSYM after dsymutil: $dsym_path"
    exit 1
}

ditto "$project_dir/config/Info.plist" "$contents_path/Info.plist"
ditto "$project_dir/Sources/Lerro/Resources/PrivacyInfo.xcprivacy" "$resources_path/PrivacyInfo.xcprivacy"
while IFS= read -r -d $'\0' bundle_path; do
    bundle_name="$(basename "$bundle_path")"
    ditto "$bundle_path" "$resources_path/$bundle_name"
done < <(find "$binary_dir" -maxdepth 1 -type d -name '*.bundle' -print0)
source_bundle_inventory=$(find "$binary_dir" -mindepth 1 -maxdepth 1 -type d -name '*.bundle' -exec basename {} \; | sort)
packaged_bundle_inventory=$(find "$resources_path" -mindepth 1 -maxdepth 1 -type d -name '*.bundle' -exec basename {} \; | sort)
[[ "$packaged_bundle_inventory" == "$source_bundle_inventory" ]] || {
    print -u2 "Packaged SwiftPM resource bundles differ from the Release build output."
    diff -u <(print -r -- "$source_bundle_inventory") <(print -r -- "$packaged_bundle_inventory") >&2 || true
    exit 1
}
for document_name in PrivacyPolicy.html TermsOfUse.html; do
    ditto "$project_dir/Sources/Lerro/Resources/$document_name" "$resources_path/$document_name"
done
third_party_licenses_path="$resources_path/ThirdPartyLicenses"
mkdir -p "$third_party_licenses_path"
copy_dependency_records() {
    local package_directory="$1"
    local package_name="$2"
    local license_record_path
    local license_record_name

    while IFS= read -r -d $'\0' license_record_path; do
        license_record_name="$(basename "$license_record_path")"
        ditto "$license_record_path" \
            "$third_party_licenses_path/$package_name-$license_record_name"
    done < <(
        find "$package_directory" -mindepth 1 -maxdepth 1 -type f \( \
            -iname 'LICENSE*' -o -iname 'NOTICE*' \
        \) -print0
    )
}

while IFS= read -r package_identity; do
    checkout_path=$(find "$project_dir/.build/checkouts" \
        -mindepth 1 -maxdepth 1 -type d -iname "$package_identity" -print -quit)
    [[ -n "$checkout_path" ]] || {
        print -u2 "Missing resolved checkout for license collection: $package_identity"
        exit 1
    }
    copy_dependency_records "$checkout_path" "$package_identity"
done < <(python3 - "$project_dir/Package.resolved" <<'PY'
import json
import pathlib
import sys

resolved = json.loads(pathlib.Path(sys.argv[1]).read_text())
for identity in sorted(pin["identity"].casefold() for pin in resolved.get("pins", [])):
    print(identity)
PY
)
while IFS= read -r -d $'\0' vendor_path; do
    copy_dependency_records "$vendor_path" "$(basename "$vendor_path")"
done < <(find "$project_dir/Vendor" -mindepth 1 -maxdepth 1 -type d -print0)
while IFS= read -r provenance_path; do
    package_name="$(basename "$(dirname "$provenance_path")")"
    ditto "$provenance_path" "$third_party_licenses_path/$package_name-UPSTREAM.md"
done < <(find "$project_dir/Vendor" -mindepth 2 -maxdepth 2 -type f -name UPSTREAM.md | sort)
source_icon="$project_dir/Sources/Lerro/Resources/icon.icns"
[[ -f "$source_icon" ]] || {
    print -u2 "Missing Lerro app icon: $source_icon"
    exit 1
}
ditto "$source_icon" "$resources_path/icon.icns"
menu_bar_source="$project_dir/Sources/Lerro/Resources/MenuBar"
[[ -d "$menu_bar_source" ]] || {
    print -u2 "Missing Lerro menu-bar resources: $menu_bar_source"
    exit 1
}
menu_bar_resource_names=(
    LerroMenuIdleTemplate.png
    LerroMenuIdleTemplate@2x.png
    LerroMenuListeningTemplate.png
    LerroMenuListeningTemplate@2x.png
    LerroMenuProcessingTemplate.png
    LerroMenuProcessingTemplate@2x.png
    LerroMenuErrorTemplate.png
    LerroMenuErrorTemplate@2x.png
)
for resource_name in "${menu_bar_resource_names[@]}"; do
    [[ -s "$menu_bar_source/$resource_name" ]] || {
        print -u2 "Missing Lerro menu-bar resource: $resource_name"
        exit 1
    }
done
actual_menu_bar_count=$(find "$menu_bar_source" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
[[ "$actual_menu_bar_count" == "${#menu_bar_resource_names[@]}" ]] || {
    print -u2 "Unexpected Lerro menu-bar resource count: $actual_menu_bar_count"
    exit 1
}
ditto "$menu_bar_source" "$resources_path/MenuBar"

accessor_count=0
while IFS= read -r -d $'\0' accessor_path; do
    if ! grep -q 'Bundle.main.resourceURL' "$accessor_path"; then
        print -u2 "SwiftPM resource accessor is not app-bundle aware: $accessor_path"
        exit 1
    fi
    ((accessor_count += 1))
done < <(
    find "$project_dir/.build/out/Intermediates.noindex" \
        -path "*/$configuration_directory/*/DerivedSources/resource_bundle_accessor.swift" \
        -print0
)
if (( accessor_count == 0 )); then
    print -u2 "No SwiftPM resource accessors were found for $configuration_directory."
    exit 1
fi

unexpected_root_entry=$(
    find "$app_path" -mindepth 1 -maxdepth 1 ! -name Contents -print -quit
)
if [[ -n "$unexpected_root_entry" ]]; then
    print -u2 "Unexpected app-bundle root entry: $unexpected_root_entry"
    exit 1
fi
if [[ "$(lipo -archs "$macos_path/Lerro")" != "arm64" ]]; then
    print -u2 "Lerro release staging must contain only arm64."
    exit 1
fi
if [[ "$(lipo -archs "$dsym_dwarf_path")" != "arm64" ]]; then
    print -u2 "Lerro dSYM staging must contain only arm64."
    exit 1
fi
binary_uuid=$(xcrun dwarfdump --uuid "$macos_path/Lerro" | awk '/UUID:/ {print $2}')
dsym_uuid=$(xcrun dwarfdump --uuid "$dsym_path" | awk '/UUID:/ {print $2}')
if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
    print -u2 "Lerro binary and dSYM UUIDs do not match."
    exit 1
fi

signing_arguments=(--force --sign "$signing_identity" --entitlements "$project_dir/config/Lerro.entitlements")
case "$signing_mode" in
    development)
        signing_arguments+=(--options runtime)
        ;;
    developer-id)
        signing_arguments+=(--options runtime --timestamp)
        ;;
esac
codesign "${signing_arguments[@]}" "$app_path"

plutil -lint "$contents_path/Info.plist" "$project_dir/config/Lerro.entitlements"
codesign --verify --deep --strict --verbose=2 "$app_path"

print "Built $app_path"
print "dSYM: $dsym_path ($dsym_uuid)"
if [[ "$signing_mode" == "ad-hoc" ]]; then
    print "Signing: ad hoc (local use)"
else
    print "Signing: $signing_mode — $signing_identity"
    if [[ "$signing_mode" == "developer-id" ]]; then
        print "Gatekeeper assessment runs after notarization in package_release.sh"
    fi
fi

if ! $should_launch; then
    exit 0
fi

open_app() {
    /usr/bin/open -n "$app_path"
}

case "$mode" in
    run)
        open_app
        ;;
    debug)
        lldb -- "$macos_path/Lerro"
        ;;
    logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate 'process == "Lerro"'
        ;;
    telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.lerro.mac"'
        ;;
    verify)
        open_app
        sleep 1
        /usr/bin/pgrep -x Lerro >/dev/null
        print "Launch verification passed"
        ;;
esac
