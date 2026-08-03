#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
source "$script_dir/signing_support.zsh"

app_path="$project_dir/dist/Lerro.app"
dsym_path="$project_dir/dist/Lerro.app.dSYM"
outputs_path="$project_dir/outputs"
archive_name=Lerro-macOS-arm64.zip
dsym_archive_name=Lerro-macOS-arm64.dSYM.zip
manifest_name=Lerro-release-manifest.json
checksum_name=SHA256SUMS.txt
archive_path="$outputs_path/$archive_name"
dsym_archive_path="$outputs_path/$dsym_archive_name"
manifest_path="$outputs_path/$manifest_name"
checksum_path="$outputs_path/$checksum_name"
pending_archive_path="$outputs_path/.$archive_name.pending"
pending_dsym_archive_path="$outputs_path/.$dsym_archive_name.pending"
pending_manifest_path="$outputs_path/.$manifest_name.pending"
pending_checksum_path="$outputs_path/.$checksum_name.pending"
requested_signing_mode=${LERRO_SIGNING_MODE:-auto}
notary_profile=${LERRO_NOTARY_PROFILE:-}
sparkle_key_account=${LERRO_SPARKLE_KEY_ACCOUNT:-app.lerro.mac}
sparkle_sign_update="$project_dir/.build/artifacts/sparkle/Sparkle/bin/sign_update"
sparkle_ed_signature=""
sparkle_archive_length=""

mkdir -p "$outputs_path"
lerro_resolve_signing
signing_mode="$LERRO_RESOLVED_SIGNING_MODE"
signing_identity="$LERRO_RESOLVED_CODESIGN_IDENTITY"

if [[ -n "$notary_profile" && "$signing_mode" != "developer-id" ]]; then
    print -u2 "Notarization requires LERRO_SIGNING_MODE=developer-id and a Developer ID Application identity."
    exit 64
fi
if [[ "$signing_mode" == "developer-id" && -z "$notary_profile" ]]; then
    print -u2 "LERRO_NOTARY_PROFILE is required for a Developer ID release archive."
    exit 64
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/lerro-package.XXXXXX")
source_before_path="$temporary_directory/source-before.json"
source_after_path="$temporary_directory/source-after.json"

cleanup_pending_artifacts() {
    rm -f -- \
        "$pending_archive_path" \
        "$pending_dsym_archive_path" \
        "$pending_manifest_path" \
        "$pending_checksum_path"
}
cleanup_all() {
    cleanup_pending_artifacts
    rm -rf -- "$temporary_directory"
}
trap cleanup_all EXIT INT TERM
cleanup_pending_artifacts

capture_source_snapshot() {
    local destination="$1"
    python3 - "$project_dir" "$destination" <<'PY'
import hashlib
import json
import os
import pathlib
import stat
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
destination = pathlib.Path(sys.argv[2])

def git_bytes(*arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *arguments])

status = git_bytes("status", "--porcelain=v1", "-z", "--untracked-files=all")
paths = [
    value.decode("utf-8", "surrogateescape")
    for value in git_bytes("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0")
    if value
]

content = hashlib.sha256()
for relative in sorted(paths):
    path = root / relative
    if not path.exists() and not path.is_symlink():
        content.update(relative.encode("utf-8", "surrogateescape"))
        content.update(b"\0missing\0")
        continue
    mode = path.lstat().st_mode
    content.update(relative.encode("utf-8", "surrogateescape"))
    content.update(b"\0")
    content.update(oct(stat.S_IMODE(mode)).encode())
    content.update(b"\0")
    if path.is_symlink():
        content.update(os.readlink(path).encode("utf-8", "surrogateescape"))
    elif path.is_file():
        content.update(path.read_bytes())
    content.update(b"\0")

payload = {
    "commit": git_bytes("rev-parse", "HEAD").decode().strip(),
    "tree": git_bytes("rev-parse", "HEAD^{tree}").decode().strip(),
    "dirty": bool(status),
    "statusSHA256": hashlib.sha256(status).hexdigest(),
    "statusPorcelain": [
        value.decode("utf-8", "surrogateescape")
        for value in status.split(b"\0")
        if value
    ],
    "workingTreeContentSHA256": content.hexdigest(),
}
destination.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
PY
}

capture_source_snapshot "$source_before_path"

print "Cleaning SwiftPM build artifacts for a source-prefix-mapped Release rebuild"
swift package clean

LERRO_SIGNING_MODE="$signing_mode" \
LERRO_CODESIGN_IDENTITY="$signing_identity" \
    "$script_dir/build_and_run.sh" --release --no-launch

capture_source_snapshot "$source_after_path"
if ! cmp -s "$source_before_path" "$source_after_path"; then
    print -u2 "The source tree changed while the Release app was being built; run packaging again from a stable tree."
    diff -u "$source_before_path" "$source_after_path" >&2 || true
    exit 75
fi

[[ -d "$app_path" ]] || { print -u2 "Missing app bundle: $app_path"; exit 1; }
[[ -d "$dsym_path" ]] || { print -u2 "Missing dSYM bundle: $dsym_path"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app_path"
plutil -lint "$app_path/Contents/Info.plist" "$app_path/Contents/Resources/PrivacyInfo.xcprivacy"

if [[ -n "$notary_profile" ]]; then
    ditto -c -k --norsrc --keepParent "$app_path" "$pending_archive_path"
    xcrun notarytool submit "$pending_archive_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app_path"
    rm -f -- "$pending_archive_path"
    codesign --verify --deep --strict --verbose=2 "$app_path"
    spctl -a -vv "$app_path"
fi

ditto -c -k --norsrc --keepParent "$app_path" "$pending_archive_path"
ditto -c -k --norsrc --keepParent "$dsym_path" "$pending_dsym_archive_path"

archive_hash=$(shasum -a 256 "$pending_archive_path" | awk '{print $1}')
dsym_archive_hash=$(shasum -a 256 "$pending_dsym_archive_path" | awk '{print $1}')

if [[ "$signing_mode" == "developer-id" ]]; then
    [[ -x "$sparkle_sign_update" ]] || {
        print -u2 "Missing Sparkle archive signing tool: $sparkle_sign_update"
        exit 1
    }
    sparkle_signature_output=$("$sparkle_sign_update" \
        --account "$sparkle_key_account" \
        "$pending_archive_path")
    sparkle_signature_fields=$(python3 - "$sparkle_signature_output" <<'PY'
import re
import sys

match = re.search(
    r'sparkle:edSignature="([A-Za-z0-9+/]+={0,2})"\s+length="([0-9]+)"',
    sys.argv[1],
)
if match is None:
    raise SystemExit("Sparkle did not return an archive signature and length.")
print(f"{match.group(1)}\t{match.group(2)}")
PY
)
    sparkle_ed_signature=${sparkle_signature_fields%%$'\t'*}
    sparkle_archive_length=${sparkle_signature_fields##*$'\t'}
    [[ "$sparkle_archive_length" == "$(stat -f '%z' "$pending_archive_path")" ]] || {
        print -u2 "Sparkle archive length does not match the final ZIP."
        exit 1
    }
fi

LERRO_MANIFEST_REQUESTED_MODE="$requested_signing_mode" \
LERRO_MANIFEST_RESOLVED_MODE="$signing_mode" \
LERRO_MANIFEST_IDENTITY="$signing_identity" \
LERRO_MANIFEST_NOTARIZED="$([[ -n "$notary_profile" ]] && print true || print false)" \
LERRO_MANIFEST_SPARKLE_ED_SIGNATURE="$sparkle_ed_signature" \
LERRO_MANIFEST_SPARKLE_LENGTH="$sparkle_archive_length" \
python3 - \
    "$project_dir" \
    "$source_before_path" \
    "$pending_manifest_path" \
    "$app_path" \
    "$pending_archive_path" \
    "$archive_name" \
    "$archive_hash" \
    "$pending_dsym_archive_path" \
    "$dsym_archive_name" \
    "$dsym_archive_hash" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import sys

(
    project_raw,
    source_raw,
    destination_raw,
    app_raw,
    archive_raw,
    archive_name,
    archive_hash,
    dsym_archive_raw,
    dsym_archive_name,
    dsym_archive_hash,
) = sys.argv[1:]
project = pathlib.Path(project_raw)
source_snapshot = json.loads(pathlib.Path(source_raw).read_text())
destination = pathlib.Path(destination_raw)
app = pathlib.Path(app_raw)
archive = pathlib.Path(archive_raw)
dsym_archive = pathlib.Path(dsym_archive_raw)
binary = app / "Contents/MacOS/Lerro"
dsym = project / "dist/Lerro.app.dSYM"
info_path = app / "Contents/Info.plist"
resolved_path = project / "Package.resolved"

def output(*arguments: str, stderr=False) -> str:
    return subprocess.check_output(
        list(arguments),
        text=True,
        stderr=subprocess.STDOUT if stderr else None,
    ).strip()

def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def uuid(path: pathlib.Path) -> str:
    line = output("xcrun", "dwarfdump", "--uuid", str(path)).splitlines()[0]
    return line.split()[1]

codesign_details = output("codesign", "-dvvv", str(app), stderr=True)
signing = {}
authorities = []
for line in codesign_details.splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    if key == "Authority":
        authorities.append(value)
    elif key in {"Identifier", "TeamIdentifier", "CDHash", "Signature", "Runtime Version"}:
        signing[key] = value

requirement = output("codesign", "-dr", "-", str(app), stderr=True)
if "designated => " in requirement:
    requirement = requirement.split("designated => ", 1)[1]

with info_path.open("rb") as handle:
    info = plistlib.load(handle)
package_resolved = json.loads(resolved_path.read_text())

resource_bundles = sorted(
    child.name for child in (app / "Contents/Resources").iterdir()
    if child.is_dir() and child.suffix == ".bundle"
)

manifest = {
    "schemaVersion": 1,
    "createdAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "builtFromDirtyTree": source_snapshot["dirty"],
    "source": source_snapshot,
    "build": {
        "configuration": "release",
        "triple": "arm64-apple-macosx26.0",
        "buildSystem": "swiftbuild",
    },
    "application": {
        "name": info.get("CFBundleName"),
        "bundleIdentifier": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "minimumOS": info.get("LSMinimumSystemVersion"),
        "architecture": output("lipo", "-archs", str(binary)),
        "binarySHA256": sha256(binary),
        "binaryUUID": uuid(binary),
        "dSYMUUID": uuid(dsym),
        "resourceBundles": resource_bundles,
    },
    "signing": {
        "requestedMode": os.environ["LERRO_MANIFEST_REQUESTED_MODE"],
        "resolvedMode": os.environ["LERRO_MANIFEST_RESOLVED_MODE"],
        "identity": os.environ["LERRO_MANIFEST_IDENTITY"],
        "identifier": signing.get("Identifier"),
        "teamIdentifier": signing.get("TeamIdentifier"),
        "authorities": authorities,
        "signature": signing.get("Signature"),
        "runtimeVersion": signing.get("Runtime Version"),
        "cdHash": signing.get("CDHash"),
        "designatedRequirement": requirement,
        "notarized": os.environ["LERRO_MANIFEST_NOTARIZED"] == "true",
        "entitlementsSHA256": sha256(project / "config/Lerro.entitlements"),
    },
    "toolchains": {
        "swift": output("swift", "--version"),
        "xcode": output("xcodebuild", "-version"),
        "metal": output("xcrun", "metal", "--version"),
        "macOSSDK": output("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "packageResolvedSHA256": sha256(resolved_path),
    },
    "packageResolved": package_resolved,
    "artifacts": {
        "applicationArchive": {
            "file": archive_name,
            "sha256": archive_hash,
            "bytes": archive.stat().st_size,
            "sparkle": {
                "edSignature": os.environ["LERRO_MANIFEST_SPARKLE_ED_SIGNATURE"] or None,
                "length": int(os.environ["LERRO_MANIFEST_SPARKLE_LENGTH"])
                if os.environ["LERRO_MANIFEST_SPARKLE_LENGTH"] else None,
            },
        },
        "debugSymbolsArchive": {
            "file": dsym_archive_name,
            "sha256": dsym_archive_hash,
            "bytes": dsym_archive.stat().st_size,
        },
    },
}
destination.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
PY

manifest_hash=$(shasum -a 256 "$pending_manifest_path" | awk '{print $1}')
{
    print "$archive_hash  $archive_name"
    print "$dsym_archive_hash  $dsym_archive_name"
    print "$manifest_hash  $manifest_name"
} > "$pending_checksum_path"

mv -f "$pending_archive_path" "$archive_path"
mv -f "$pending_dsym_archive_path" "$dsym_archive_path"
mv -f "$pending_manifest_path" "$manifest_path"
mv -f "$pending_checksum_path" "$checksum_path"
source_tree_dirty=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))["dirty"]).lower())' "$source_before_path")
trap - EXIT INT TERM
rm -rf -- "$temporary_directory"

(cd "$outputs_path" && shasum -a 256 -c "$checksum_name")
print "Packaged $archive_path"
print "Debug symbols: $dsym_archive_path"
print "Release manifest: $manifest_path"
print "Source tree dirty: $source_tree_dirty"
if [[ -n "$sparkle_ed_signature" ]]; then
    print "Sparkle archive signature: present"
else
    print "Sparkle archive signature: skipped for $signing_mode packaging"
fi
