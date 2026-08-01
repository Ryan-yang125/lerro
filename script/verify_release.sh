#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
outputs_path="$project_dir/outputs"
archive_path="$outputs_path/Lerro-macOS-arm64.zip"
dsym_archive_path="$outputs_path/Lerro-macOS-arm64.dSYM.zip"
manifest_path="$outputs_path/Lerro-release-manifest.json"
checksum_path="$outputs_path/SHA256SUMS.txt"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/Lerro Release Verify.XXXXXX")
application_extract_path="$temporary_directory/Application Archive"
symbols_extract_path="$temporary_directory/Debug Symbols Archive"
fixture_home_path="$temporary_directory/Fixture Home"
fixture_log_path="$temporary_directory/fixture.log"
ask_fixture_log_path="$temporary_directory/ask-fixture.log"
fixture_pid=""

cleanup() {
    if [[ -n "$fixture_pid" ]] && kill -0 "$fixture_pid" >/dev/null 2>&1; then
        kill -TERM "$fixture_pid" >/dev/null 2>&1 || true
        for _ in {1..20}; do
            kill -0 "$fixture_pid" >/dev/null 2>&1 || break
            sleep 0.1
        done
        if kill -0 "$fixture_pid" >/dev/null 2>&1; then
            kill -KILL "$fixture_pid" >/dev/null 2>&1 || true
        fi
        wait "$fixture_pid" 2>/dev/null || true
    fi
    rm -rf -- "$temporary_directory"
}
trap cleanup EXIT INT TERM

cd "$project_dir"

print "[1/8] Linting release entrypoints and property lists"
zsh -n \
    "$project_dir/Brand/scripts"/*.sh \
    "$script_dir"/*.sh \
    "$script_dir"/*.zsh
plutil -lint config/Info.plist config/Lerro.entitlements Sources/Lerro/Resources/PrivacyInfo.xcprivacy

print "[2/8] Verifying deterministic Brand Kit assets"
"$project_dir/Brand/scripts/verify-assets.sh"

print "[3/8] Verifying SwiftPM test discovery"
swift package describe --type json > "$temporary_directory/package-description.json"
python3 - "$project_dir" "$temporary_directory/package-description.json" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
description = json.loads(pathlib.Path(sys.argv[2]).read_text())
discovered = set()
for target in description["targets"]:
    if target["type"] != "test":
        continue
    target_path = pathlib.Path(target["path"])
    if not target_path.is_absolute():
        target_path = root / target_path
    for source in target.get("sources", []):
        source_path = pathlib.Path(source)
        if not source_path.is_absolute():
            source_path = target_path / source_path
        discovered.add(source_path.resolve().relative_to(root).as_posix())

expected = {
    path.resolve().relative_to(root).as_posix()
    for path in (root / "Tests").rglob("*Tests.swift")
}
missing = sorted(expected - discovered)
if not expected:
    raise SystemExit("No *Tests.swift files were found under Tests/")
if missing:
    raise SystemExit("Test files missing from SwiftPM targets: " + ", ".join(missing))
print(f"Verified {len(expected)} test source files in SwiftPM targets.")
PY

print "[4/8] Running the full test suite"
swift test

print "[5/8] Building and packaging the Release app"
"$script_dir/package_release.sh"

print "[6/8] Verifying checksums and extracting through paths containing spaces"
for required_path in "$archive_path" "$dsym_archive_path" "$manifest_path" "$checksum_path"; do
    [[ -f "$required_path" ]] || { print -u2 "Missing release artifact: $required_path"; exit 1; }
done
(cd "$outputs_path" && shasum -a 256 -c "$(basename "$checksum_path")")
if zipinfo -1 "$archive_path" | grep -q '^__MACOSX/'; then
    print -u2 "Application archive contains AppleDouble metadata entries."
    exit 1
fi
mkdir -p "$application_extract_path" "$symbols_extract_path" "$fixture_home_path"
ditto -x -k "$archive_path" "$application_extract_path"
ditto -x -k "$dsym_archive_path" "$symbols_extract_path"

app_path="$application_extract_path/Lerro.app"
dsym_path="$symbols_extract_path/Lerro.app.dSYM"
binary_path="$app_path/Contents/MacOS/Lerro"
[[ -d "$app_path" && -f "$binary_path" ]] || { print -u2 "Application archive has an invalid layout."; exit 1; }
[[ -d "$dsym_path" ]] || { print -u2 "Debug-symbol archive has an invalid layout."; exit 1; }
if [[ $(find "$application_extract_path" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ') != 1 ]]; then
    print -u2 "Application archive must contain exactly one root entry."
    exit 1
fi
if [[ $(find "$symbols_extract_path" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ') != 1 ]]; then
    print -u2 "Debug-symbol archive must contain exactly one root entry."
    exit 1
fi
if [[ -n "$(find "$app_path" -mindepth 1 -maxdepth 1 ! -name Contents -print -quit)" ]]; then
    print -u2 "The .app root contains an unexpected entry."
    exit 1
fi

print "[7/8] Verifying architecture, signing, resources, manifest, and dSYM"
[[ "$(lipo -archs "$binary_path")" == "arm64" ]] || { print -u2 "Release binary must be arm64-only."; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app_path"
plutil -lint "$app_path/Contents/Info.plist" "$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
if LC_ALL=C grep -aFq "$HOME/" "$binary_path"; then
    print -u2 "Release binary contains a path from the build user's home directory."
    exit 1
fi

required_resources=(
    PrivacyInfo.xcprivacy
    PrivacyPolicy.html
    TermsOfUse.html
    icon.icns
    MenuBar/LerroMenuIdleTemplate.png
    MenuBar/LerroMenuIdleTemplate@2x.png
    MenuBar/LerroMenuListeningTemplate.png
    MenuBar/LerroMenuListeningTemplate@2x.png
    MenuBar/LerroMenuProcessingTemplate.png
    MenuBar/LerroMenuProcessingTemplate@2x.png
    MenuBar/LerroMenuErrorTemplate.png
    MenuBar/LerroMenuErrorTemplate@2x.png
)
for relative_path in "${required_resources[@]}"; do
    [[ -r "$app_path/Contents/Resources/$relative_path" ]] || {
        print -u2 "Missing release resource: $relative_path"
        exit 1
    }
done
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
menu_bar_resource_path="$app_path/Contents/Resources/MenuBar"
actual_menu_bar_count=$(find "$menu_bar_resource_path" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
[[ "$actual_menu_bar_count" == "${#menu_bar_resource_names[@]}" ]] || {
    print -u2 "Unexpected packaged menu-bar resource count: $actual_menu_bar_count"
    exit 1
}
for resource_name in "${menu_bar_resource_names[@]}"; do
    packaged_resource="$menu_bar_resource_path/$resource_name"
    source_resource="$project_dir/Sources/Lerro/Resources/MenuBar/$resource_name"
    brand_resource="$project_dir/Brand/exports/menu-bar/$resource_name"
    cmp -s "$packaged_resource" "$source_resource" || {
        print -u2 "Packaged menu-bar resource differs from app source: $resource_name"
        exit 1
    }
    cmp -s "$source_resource" "$brand_resource" || {
        print -u2 "App menu-bar resource differs from the Brand Kit: $resource_name"
        exit 1
    }
    sips -g pixelWidth -g pixelHeight "$packaged_resource" >/dev/null 2>&1 || {
        print -u2 "Packaged menu-bar resource cannot be decoded: $resource_name"
        exit 1
    }
done
cmp -s "$app_path/Contents/Resources/icon.icns" "$project_dir/Brand/exports/app-icon/Lerro.icns" || {
    print -u2 "Packaged app icon differs from the Brand Kit."
    exit 1
}
expected_bundles=(mlx-swift_Cmlx.bundle swift-crypto_Crypto.bundle swift-transformers_Hub.bundle)
for bundle_name in "${expected_bundles[@]}"; do
    bundle_path="$app_path/Contents/Resources/$bundle_name"
    [[ -d "$bundle_path" ]] || { print -u2 "Missing SwiftPM resource bundle: $bundle_name"; exit 1; }
    plutil -lint "$bundle_path/Contents/Info.plist"
done
actual_bundle_count=$(find "$app_path/Contents/Resources" -mindepth 1 -maxdepth 1 -type d -name '*.bundle' | wc -l | tr -d ' ')
(( actual_bundle_count >= ${#expected_bundles[@]} )) || { print -u2 "SwiftPM resource-bundle count is too small: $actual_bundle_count"; exit 1; }
metal_library_path="$app_path/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
[[ -r "$metal_library_path" && -s "$metal_library_path" ]] || { print -u2 "MLX default.metallib is missing or unreadable."; exit 1; }
file "$metal_library_path" | grep -q 'MetalLib executable' || { print -u2 "MLX default.metallib has an unexpected file type."; exit 1; }
license_count=$(find "$app_path/Contents/Resources/ThirdPartyLicenses" -type f | wc -l | tr -d ' ')
(( license_count > 0 )) || { print -u2 "Third-party licenses are missing."; exit 1; }
vendor_record_pairs=(
    "$project_dir/Vendor/swift-huggingface/LICENSE|$app_path/Contents/Resources/ThirdPartyLicenses/swift-huggingface-LICENSE"
    "$project_dir/Vendor/swift-huggingface/UPSTREAM.md|$app_path/Contents/Resources/ThirdPartyLicenses/swift-huggingface-UPSTREAM.md"
    "$project_dir/Vendor/swift-transformers/LICENSE|$app_path/Contents/Resources/ThirdPartyLicenses/swift-transformers-LICENSE"
    "$project_dir/Vendor/swift-transformers/UPSTREAM.md|$app_path/Contents/Resources/ThirdPartyLicenses/swift-transformers-UPSTREAM.md"
)
for record_pair in "${vendor_record_pairs[@]}"; do
    source_record="${record_pair%%|*}"
    packaged_record="${record_pair#*|}"
    [[ -s "$source_record" && -s "$packaged_record" ]] || {
        print -u2 "Missing or empty vendored dependency record: $packaged_record"
        exit 1
    }
    cmp -s "$source_record" "$packaged_record" || {
        print -u2 "Vendored dependency record differs from source: $packaged_record"
        exit 1
    }
done

binary_uuid=$(xcrun dwarfdump --uuid "$binary_path" | awk '/UUID:/ {print $2}')
dsym_uuid=$(xcrun dwarfdump --uuid "$dsym_path" | awk '/UUID:/ {print $2}')
[[ -n "$binary_uuid" && "$binary_uuid" == "$dsym_uuid" ]] || { print -u2 "Release binary and dSYM UUIDs differ."; exit 1; }

python3 - "$project_dir" "$manifest_path" "$app_path" "$archive_path" "$dsym_archive_path" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import sys

project, manifest_raw, app_raw, archive_raw, dsym_archive_raw = map(pathlib.Path, sys.argv[1:])
manifest = json.loads(manifest_raw.read_text())
app = app_raw
binary = app / "Contents/MacOS/Lerro"
actual_resource_bundles = sorted(
    child.name for child in (app / "Contents/Resources").iterdir()
    if child.is_dir() and child.suffix == ".bundle"
)

def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def output(*arguments: str) -> str:
    return subprocess.check_output(list(arguments), text=True, stderr=subprocess.STDOUT).strip()

if manifest.get("schemaVersion") != 1:
    raise SystemExit("Unsupported release-manifest schema")
source = manifest.get("source", {})
if manifest.get("builtFromDirtyTree") is not source.get("dirty"):
    raise SystemExit("Dirty-tree truth fields disagree")
for field in ("commit", "tree", "statusSHA256", "workingTreeContentSHA256"):
    if not re.fullmatch(r"[0-9a-f]{40,64}", str(source.get(field, ""))):
        raise SystemExit(f"Invalid source field: {field}")

artifacts = manifest["artifacts"]
if artifacts["applicationArchive"]["sha256"] != sha256(archive_raw):
    raise SystemExit("Application archive hash differs from manifest")
if artifacts["debugSymbolsArchive"]["sha256"] != sha256(dsym_archive_raw):
    raise SystemExit("dSYM archive hash differs from manifest")
if manifest["application"]["binarySHA256"] != sha256(binary):
    raise SystemExit("Binary hash differs from manifest")
if manifest["application"]["resourceBundles"] != actual_resource_bundles:
    raise SystemExit("Packaged resource-bundle inventory differs from manifest")
if manifest["toolchains"]["packageResolvedSHA256"] != sha256(project / "Package.resolved"):
    raise SystemExit("Package.resolved hash differs from manifest")

codesign = output("codesign", "-dvvv", str(app))
details = {}
for line in codesign.splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        details[key] = value
if manifest["signing"]["cdHash"] != details.get("CDHash"):
    raise SystemExit("CDHash differs from manifest")

mode = manifest["signing"]["resolvedMode"]
identity = manifest["signing"]["identity"]
if mode == "ad-hoc" and identity != "-":
    raise SystemExit("Ad-hoc manifest has a certificate identity")
if mode == "development" and not identity.startswith("Apple Development:"):
    raise SystemExit("Development manifest has the wrong certificate class")
if mode == "developer-id" and not identity.startswith("Developer ID Application:"):
    raise SystemExit("Developer ID manifest has the wrong certificate class")
if mode == "developer-id" and not manifest["signing"]["notarized"]:
    raise SystemExit("Developer ID release is missing notarization evidence")

with (app / "Contents/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
if manifest["application"]["bundleIdentifier"] != info["CFBundleIdentifier"]:
    raise SystemExit("Bundle identifier differs from manifest")
PY

if [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["signing"]["resolvedMode"])' "$manifest_path")" == "developer-id" ]]; then
    xcrun stapler validate "$app_path"
    spctl -a -vv "$app_path"
fi

print "[8/8] Running the inert home and Ask fixtures and cleaning up their exact PIDs"
fixture_binary="$app_path/Contents/MacOS/Lerro"

run_fixture_smoke() {
    local presentation="$1"
    local log_path="$2"
    local isolated_home="$fixture_home_path/$presentation"
    mkdir -p "$isolated_home"

    CFFIXED_USER_HOME="$isolated_home" \
    LERRO_FIXTURE_MODE=1 \
    LERRO_FIXTURE_PRESENTATION="$presentation" \
        "$fixture_binary" >"$log_path" 2>&1 &
    fixture_pid=$!
    sleep 3
    kill -0 "$fixture_pid" >/dev/null 2>&1 || {
        print -u2 "$presentation fixture exited during launch smoke."
        tail -80 "$log_path" >&2 || true
        exit 1
    }
    if lsof -nP -a -p "$fixture_pid" -iTCP 2>/dev/null | awk 'NR > 1 { found=1 } END { exit !found }'; then
        print -u2 "$presentation fixture opened a TCP socket."
        lsof -nP -a -p "$fixture_pid" -iTCP >&2 || true
        exit 1
    fi
    kill -TERM "$fixture_pid"
    wait "$fixture_pid" 2>/dev/null || true
    fixture_pid=""
    if /usr/bin/grep -Eiq 'CoreAudio|HALC_|AudioComponent|(^|[^[:alnum:]])TCC([^[:alnum:]]|$)|accessibility.*(denied|permission)|microphone.*(denied|permission)|NSInternalInconsistencyException|canBecome(Key|Main)Window|Assertion failure|Fatal error|Segmentation fault' "$log_path"; then
        print -u2 "$presentation fixture log contains a system-integration error or crash marker."
        tail -80 "$log_path" >&2 || true
        exit 1
    fi
}

run_fixture_smoke home "$fixture_log_path"
run_fixture_smoke ask "$ask_fixture_log_path"
fixture_log_bytes=$(stat -f %z "$fixture_log_path")
ask_fixture_log_bytes=$(stat -f %z "$ask_fixture_log_path")

print "Release verification passed"
print "Archive: $archive_path"
print "dSYM UUID: $dsym_uuid"
print "Manifest: $manifest_path"
print "Home fixture log bytes: $fixture_log_bytes (no integration errors)"
print "Ask fixture log bytes: $ask_fixture_log_bytes (panel opened without crash)"
