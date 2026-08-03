#!/bin/zsh
set -euo pipefail

script_path=$0
script_dir=${0:A:h}
project_dir=${script_dir:h}
distribution_dir="$project_dir/distribution"
distribution_config="$distribution_dir/wrangler.toml"
publication_sql_renderer="$distribution_dir/bin/render-publication-sql.mjs"
outputs_path="$project_dir/outputs"
archive_path="$outputs_path/Lerro-macOS-arm64.zip"
manifest_path="$outputs_path/Lerro-release-manifest.json"
worker_binary="$project_dir/site/node_modules/.bin/wrangler"
release_notes_url="https://lerroapp.com/changelog"

usage() {
    print "Usage: $script_path"
    print "Publishes the current Developer ID + notarized Sparkle archive to updates.lerroapp.com."
}

if (( $# > 0 )); then
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown option: $1"
            usage >&2
            exit 64
            ;;
    esac
fi

[[ -x "$worker_binary" ]] || {
    print -u2 "Missing project-local Wrangler: $worker_binary"
    exit 1
}
[[ -r "$distribution_config" ]] || {
    print -u2 "Missing private distribution configuration: $distribution_config"
    print -u2 "Copy distribution/wrangler.toml.example and fill the D1 database ID first."
    exit 1
}
[[ -r "$publication_sql_renderer" ]] || {
    print -u2 "Missing shared D1 publication SQL renderer: $publication_sql_renderer"
    exit 1
}
command -v node >/dev/null || {
    print -u2 "Node.js is required to render the controlled D1 publication batch."
    exit 1
}
[[ -f "$archive_path" && -f "$manifest_path" ]] || {
    print -u2 "Package a release before publishing it."
    exit 1
}

r2_bucket=$(awk -F '"' '/^bucket_name = / { print $2; exit }' "$distribution_config")
d1_database=$(awk -F '"' '/^database_name = / { print $2; exit }' "$distribution_config")
d1_database_id=$(awk -F '"' '/^database_id = / { print $2; exit }' "$distribution_config")
[[ -n "$r2_bucket" && -n "$d1_database" && -n "$d1_database_id" ]] || {
    print -u2 "The private distribution configuration is missing an R2 bucket, D1 name, or D1 ID."
    exit 1
}
python3 - "$d1_database_id" <<'PY'
import re
import sys

if re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", sys.argv[1], re.I) is None:
    raise SystemExit("The private distribution configuration has an invalid D1 database ID.")
PY

IFS=$'\t' read -r version build_number minimum_macos archive_name archive_sha256 archive_bytes sparkle_signature < <(
    python3 - "$manifest_path" <<'PY'
import json
import pathlib
import re
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
signing = manifest.get("signing", {})
application = manifest.get("application", {})
archive = manifest.get("artifacts", {}).get("applicationArchive", {})
sparkle = archive.get("sparkle", {})

if signing.get("resolvedMode") != "developer-id" or signing.get("notarized") is not True:
    raise SystemExit("Cloudflare publication requires a notarized Developer ID package.")

version = str(application.get("version", ""))
build = application.get("build")
minimum_macos = str(application.get("minimumOS", ""))
filename = str(archive.get("file", ""))
sha256 = str(archive.get("sha256", ""))
bytes_value = archive.get("bytes")
signature = sparkle.get("edSignature")
length = sparkle.get("length")

if not re.fullmatch(r"[0-9][0-9A-Za-z.-]{0,63}", version):
    raise SystemExit("Manifest version is invalid.")
if not isinstance(build, str) or not build.isdecimal() or int(build) < 1:
    raise SystemExit("Manifest build is invalid.")
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", minimum_macos):
    raise SystemExit("Manifest minimum macOS version must have three numeric components.")
if filename != "Lerro-macOS-arm64.zip":
    raise SystemExit("Manifest archive filename is invalid.")
if not re.fullmatch(r"[0-9a-f]{64}", sha256):
    raise SystemExit("Manifest archive SHA-256 is invalid.")
if not isinstance(bytes_value, int) or bytes_value < 1:
    raise SystemExit("Manifest archive size is invalid.")
if not isinstance(signature, str) or not re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", signature):
    raise SystemExit("Manifest lacks a Sparkle archive signature.")
if length != bytes_value:
    raise SystemExit("Manifest Sparkle archive length differs from the archive size.")

print("\t".join((version, build, minimum_macos, filename, sha256, str(bytes_value), signature)))
PY
)

actual_sha256=$(shasum -a 256 "$archive_path" | awk '{print $1}')
actual_bytes=$(stat -f '%z' "$archive_path")
[[ "$actual_sha256" == "$archive_sha256" && "$actual_bytes" == "$archive_bytes" ]] || {
    print -u2 "The current archive differs from its release manifest. Package it again from a stable tree."
    exit 1
}

r2_key="releases/$version/$build_number/$archive_name"
release_lookup_sql=$(python3 - "$version" "$build_number" <<'PY'
import sys

version, build = sys.argv[1:]
quoted_version = "'" + version.replace("'", "''") + "'"
print(f"""
SELECT
  release.id AS release_id,
  release.status,
  release.minimum_macos,
  artifact.r2_key,
  artifact.filename,
  artifact.bytes,
  artifact.sha256,
  artifact.sparkle_ed_signature
FROM releases AS release
LEFT JOIN artifacts AS artifact
  ON artifact.release_id = release.id AND artifact.kind = 'macos-zip'
WHERE release.channel = 'stable'
  AND release.version = {quoted_version}
  AND release.build_number = {build}
  AND release.platform = 'macos'
  AND release.architecture = 'arm64';
""".strip())
PY
)
existing_release_json=$("$worker_binary" d1 execute "$d1_database" \
    --remote \
    --config "$distribution_config" \
    --json \
    --command "$release_lookup_sql")
existing_release_state=$(python3 - \
    "$existing_release_json" \
    "$minimum_macos" \
    "$r2_key" \
    "$archive_name" \
    "$archive_bytes" \
    "$archive_sha256" \
    "$sparkle_signature" <<'PY'
import json
import sys

(
    payload,
    expected_minimum_macos,
    expected_r2_key,
    expected_filename,
    expected_bytes,
    expected_sha256,
    expected_signature,
) = sys.argv[1:]

decoded = json.loads(payload)
if not isinstance(decoded, list) or len(decoded) != 1 or not decoded[0].get("success"):
    raise SystemExit("D1 release lookup returned an unexpected response.")

rows = decoded[0].get("results")
if not isinstance(rows, list):
    raise SystemExit("D1 release lookup did not return rows.")
if len(rows) == 0:
    print("absent")
    raise SystemExit(0)
if len(rows) != 1:
    raise SystemExit("D1 release lookup returned duplicate stable release rows.")

row = rows[0]
expected = {
    "status": "published",
    "minimum_macos": expected_minimum_macos,
    "r2_key": expected_r2_key,
    "filename": expected_filename,
    "bytes": int(expected_bytes),
    "sha256": expected_sha256,
    "sparkle_ed_signature": expected_signature,
}
if any(row.get(key) != value for key, value in expected.items()):
    raise SystemExit("An existing stable release has different metadata or bytes.")
print("identical")
PY
)

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/lerro-cloudflare-publish.XXXXXX")
downloaded_archive="$temporary_directory/$archive_name"
publication_json="$temporary_directory/publication.json"
appcast_response="$temporary_directory/appcast.xml"
cleanup() {
    rm -rf -- "$temporary_directory"
}
trap cleanup EXIT INT TERM

if [[ "$existing_release_state" == "absent" ]]; then
    head_generation_json=$("$worker_binary" d1 execute "$d1_database" \
        --remote \
        --config "$distribution_config" \
        --json \
        --command "SELECT generation FROM channel_heads WHERE channel = 'stable' AND platform = 'macos' AND architecture = 'arm64';")
    expected_generation=$(python3 - "$head_generation_json" <<'PY'
import json
import sys

decoded = json.loads(sys.argv[1])
if not isinstance(decoded, list) or len(decoded) != 1 or not decoded[0].get("success"):
    raise SystemExit("D1 channel-head lookup returned an unexpected response.")
rows = decoded[0].get("results")
if not isinstance(rows, list) or len(rows) > 1:
    raise SystemExit("D1 channel-head lookup returned an unexpected number of rows.")
if not rows:
    print(0)
    raise SystemExit(0)
generation = rows[0].get("generation")
if not isinstance(generation, int) or generation < 1:
    raise SystemExit("D1 channel-head generation is invalid.")
print(generation)
PY
)
    next_generation=$(( expected_generation + 1 ))

    if r2_get_output=$("$worker_binary" r2 object get "$r2_bucket/$r2_key" \
        --remote \
        --config "$distribution_config" \
        --file "$downloaded_archive" 2>&1); then
        existing_sha256=$(shasum -a 256 "$downloaded_archive" | awk '{print $1}')
        [[ "$existing_sha256" == "$archive_sha256" ]] || {
            print -u2 "The immutable R2 release key already contains different bytes: $r2_key"
            exit 1
        }
    elif [[ "$r2_get_output" == *"The specified key does not exist."* ]]; then
        # The exact GET above proved this immutable key absent. Keep Wrangler's
        # standard R2 validation enabled; SHA-256 readback below remains the
        # publication gate before any D1 record becomes public.
        "$worker_binary" r2 object put "$r2_bucket/$r2_key" \
            --remote \
            --config "$distribution_config" \
            --file "$archive_path" \
            --content-type application/zip \
            --cache-control "public, max-age=31536000, immutable"
        r2_readback_succeeded=0
        for readback_attempt in {1..5}; do
            if "$worker_binary" r2 object get "$r2_bucket/$r2_key" \
                --remote \
                --config "$distribution_config" \
                --file "$downloaded_archive" >/dev/null 2>&1; then
                r2_readback_succeeded=1
                break
            fi
            if (( readback_attempt < 5 )); then
                sleep 2
            fi
        done
        (( r2_readback_succeeded == 1 )) || {
            print -u2 "R2 did not make the immutable release key readable after upload: $r2_key"
            exit 1
        }
        uploaded_sha256=$(shasum -a 256 "$downloaded_archive" | awk '{print $1}')
        [[ "$uploaded_sha256" == "$archive_sha256" ]] || {
            print -u2 "R2 readback does not match the packaged ZIP."
            exit 1
        }
    else
        print -u2 "Unable to determine whether the immutable R2 release key exists."
        print -u2 -- "$r2_get_output"
        exit 1
    fi

    release_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    artifact_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    published_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    python3 - \
        "$publication_json" \
        "$release_id" \
        "$artifact_id" \
        "$version" \
        "$build_number" \
        "$minimum_macos" \
        "$published_at" \
        "$r2_key" \
        "$archive_name" \
        "$archive_bytes" \
        "$archive_sha256" \
        "$sparkle_signature" \
        "$next_generation" \
        "$expected_generation" \
        "$release_notes_url" <<'PY'
import json
import pathlib
import sys

(
    output_path,
    release_id,
    artifact_id,
    version,
    build_number,
    minimum_macos,
    published_at,
    r2_key,
    archive_name,
    archive_bytes,
    archive_sha256,
    sparkle_signature,
    generation,
    expected_generation,
    release_notes_url,
) = sys.argv[1:]

publication = {
    "release": {
        "id": release_id,
        "channel": "stable",
        "version": version,
        "buildNumber": int(build_number),
        "platform": "macos",
        "architecture": "arm64",
        "minimum_macos": minimum_macos,
        "publishedAt": published_at,
        "releaseNotesURL": release_notes_url,
    },
    "artifact": {
        "id": artifact_id,
        "r2Key": r2_key,
        "filename": archive_name,
        "bytes": int(archive_bytes),
        "sha256": archive_sha256,
        "edSignature": sparkle_signature,
        "contentType": "application/zip",
    },
    "generation": int(generation),
    "expectedGeneration": int(expected_generation),
}
pathlib.Path(output_path).write_text(json.dumps(publication), encoding="utf-8")
PY
    publication_sql=$(node "$publication_sql_renderer" "$publication_json")
    publication_result_json=$("$worker_binary" d1 execute "$d1_database" \
        --remote \
        --config "$distribution_config" \
        --json \
        --command "$publication_sql")
    python3 - "$publication_result_json" <<'PY'
import json
import sys

results = json.loads(sys.argv[1])
if not isinstance(results, list) or len(results) != 3:
    raise SystemExit("D1 publication did not return the expected three-statement batch result.")
for result in results:
    if result.get("success") is not True or result.get("meta", {}).get("changes") != 1:
        raise SystemExit("D1 publication did not atomically create the release, artifact, and channel head.")
PY
elif [[ "$existing_release_state" != "identical" ]]; then
    print -u2 "D1 release lookup returned an unsupported state: $existing_release_state"
    exit 1
fi

verification_token=$(uuidgen | tr '[:upper:]' '[:lower:]')
appcast_url="https://updates.lerroapp.com/appcast/stable.xml"
immutable_url="https://updates.lerroapp.com/releases/$version/$build_number/$archive_name"
latest_url="https://updates.lerroapp.com/download/macos/latest"
appcast_verified=0
for attempt in {1..10}; do
    if curl --fail --silent --show-error \
        --header 'Cache-Control: no-cache' \
        --output "$appcast_response" \
        "$appcast_url?verify=$verification_token"; then
        if python3 - \
            "$appcast_response" \
            "$version" \
            "$build_number" \
            "$minimum_macos" \
            "$archive_name" \
            "$archive_bytes" \
            "$sparkle_signature" \
            "$immutable_url" \
            "$release_notes_url" <<'PY'
import sys
import xml.etree.ElementTree as ET

(
    appcast_path,
    version,
    build_number,
    minimum_macos,
    archive_name,
    archive_bytes,
    sparkle_signature,
    immutable_url,
    release_notes_url,
) = sys.argv[1:]
namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = ET.parse(appcast_path).getroot()
matches = [
    enclosure
    for enclosure in root.findall(".//enclosure")
    if enclosure.get(f"{namespace}version") == build_number
]
if len(matches) != 1:
    raise SystemExit("Published appcast did not contain exactly one enclosure for the expected build.")
enclosure = matches[0]
expected = {
    "url": immutable_url,
    f"{namespace}version": build_number,
    f"{namespace}shortVersionString": version,
    f"{namespace}minimumSystemVersion": minimum_macos,
    f"{namespace}hardwareRequirements": "arm64",
    f"{namespace}edSignature": sparkle_signature,
    "length": archive_bytes,
    "type": "application/octet-stream",
}
if any(enclosure.get(key) != value for key, value in expected.items()):
    raise SystemExit("Published appcast enclosure differs from the release manifest.")
notes = root.find(".//{http://www.andymatuschak.org/xml-namespaces/sparkle}releaseNotesLink")
if notes is None or notes.text != release_notes_url:
    raise SystemExit("Published appcast release notes URL differs from the changelog URL.")
PY
        then
            appcast_verified=1
            break
        fi
    fi
    if (( attempt < 10 )); then
        sleep 2
    fi
done
(( appcast_verified == 1 )) || {
    print -u2 "Published appcast did not converge to the expected release."
    exit 1
}

verify_public_archive() {
    local label="$1"
    local url="$2"
    local headers_path="$temporary_directory/$label.headers"
    local downloaded_sha256

    curl --fail --silent --show-error \
        --location \
        --head \
        --header 'Cache-Control: no-cache' \
        --dump-header "$headers_path" \
        --output /dev/null \
        "$url?verify=$verification_token"
    python3 - "$headers_path" "$archive_bytes" <<'PY'
import pathlib
import sys

headers = {}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if ":" not in line:
        continue
    name, value = line.split(":", 1)
    headers[name.lower()] = value.strip()
if headers.get("content-type") != "application/zip":
    raise SystemExit("Public download did not return application/zip.")
if headers.get("content-length") != sys.argv[2]:
    raise SystemExit("Public download length differs from the release manifest.")
PY
    downloaded_sha256=$(curl --fail --silent --show-error \
        --location \
        --header 'Cache-Control: no-cache' \
        "$url?verify=$verification_token" \
        | shasum -a 256 \
        | awk '{print $1}')
    [[ "$downloaded_sha256" == "$archive_sha256" ]] || {
        print -u2 "The public $label ZIP SHA-256 differs from the release manifest."
        exit 1
    }
}

verify_public_archive immutable "$immutable_url"
verify_public_archive latest "$latest_url"

print "Published Lerro $version ($build_number) to $latest_url"
