#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
default_repo=${script_dir:h}
repo_argument="$default_repo"
require_empty_history=false

usage() {
    print "Usage: $0 [--require-empty-history] [repository-path]"
}

while (( $# > 0 )); do
    case "$1" in
        --require-empty-history)
            require_empty_history=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -* )
            print -u2 "Unknown option: $1"
            usage >&2
            exit 64
            ;;
        *)
            repo_argument="$1"
            shift
            if (( $# > 0 )); then
                print -u2 "Only one repository path is accepted."
                exit 64
            fi
            ;;
    esac
done

[[ -d "$repo_argument" ]] || {
    print -u2 "Repository directory is missing: $repo_argument"
    exit 1
}
repo_root=${repo_argument:A}
allowlist_path="$repo_root/script/public_repo_allowlist.txt"
legacy_allowlist_path="$repo_root/script/public_repo_legacy_allowlist.txt"
license_source=${LERRO_LICENSE_SOURCE:-$repo_root}

for required_path in "$allowlist_path" "$legacy_allowlist_path"; do
    [[ -r "$required_path" ]] || {
        print -u2 "Missing public-repository policy file: $required_path"
        exit 1
    }
done

print "[1/6] Checking allowlisted inventory, prohibited artifacts, and assets"
python3 - "$repo_root" "$allowlist_path" "$legacy_allowlist_path" <<'PY'
from __future__ import annotations

import fnmatch
import json
import os
import pathlib
import re
import stat
import sys

root = pathlib.Path(sys.argv[1]).resolve()
allowlist_path = pathlib.Path(sys.argv[2])
legacy_allowlist_path = pathlib.Path(sys.argv[3])
errors: list[str] = []


def policy_lines(path: pathlib.Path) -> list[str]:
    result = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        value = raw.strip()
        if not value or value.startswith("#"):
            continue
        candidate = pathlib.PurePosixPath(value.rstrip("/"))
        if candidate.is_absolute() or ".." in candidate.parts:
            errors.append(f"unsafe policy entry in {path.name}: {value}")
            continue
        result.append(value)
    return result


allowlist = policy_lines(allowlist_path)
legacy_allowlist = set(policy_lines(legacy_allowlist_path))


def is_allowed(relative: str) -> bool:
    for entry in allowlist:
        if entry.endswith("/") and relative.startswith(entry):
            return True
        if relative == entry:
            return True
    return False


for entry in allowlist:
    candidate = root / entry.rstrip("/")
    if not candidate.exists():
        errors.append(f"allowlisted entry is missing: {entry}")

required_files = [
    "LICENSE",
    "LICENSES/CC-BY-4.0.txt",
    "NOTICE",
    "THIRD_PARTY_NOTICES.md",
    "TRADEMARKS.md",
    "PRIVACY.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "SECURITY.md",
    "SUPPORT.md",
    "CHANGELOG.md",
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/feature_request.yml",
    ".github/pull_request_template.md",
]
for relative in required_files:
    path = root / relative
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"required public file is missing or empty: {relative}")

for path in root.rglob("*"):
    relative = path.relative_to(root).as_posix()
    if relative == ".git" or relative.startswith(".git/"):
        continue
    if path.is_symlink():
        errors.append(f"symbolic links are excluded from the public export: {relative}")
        continue
    if not path.is_file():
        continue
    if not is_allowed(relative):
        errors.append(f"path is outside the public allowlist: {relative}")

    if path.name == "wrangler.toml":
        errors.append(
            f"private Wrangler configuration is excluded from the public export: {relative}"
        )

    parts = pathlib.PurePosixPath(relative).parts
    forbidden_parts = {
        ".build",
        ".next",
        ".swiftpm",
        ".vinext",
        ".wrangler",
        "clean-public",
        "coverage",
        "dist",
        "node_modules",
        "out",
        "outputs",
        "work",
        "xcuserdata",
    }
    if any(part in forbidden_parts for part in parts):
        errors.append(f"prohibited generated or private path: {relative}")

    lower = relative.casefold()
    prohibited_suffixes = (
        ".app",
        ".a",
        ".bin",
        ".caf",
        ".db",
        ".dmg",
        ".dsym",
        ".dylib",
        ".gguf",
        ".log",
        ".m4a",
        ".metallib",
        ".mlmodelc",
        ".mp3",
        ".o",
        ".otf",
        ".sqlite",
        ".sqlite3",
        ".swiftmodule",
        ".ttf",
        ".wav",
        ".woff",
        ".woff2",
        ".xctest",
        ".zip",
    )
    if lower.endswith(prohibited_suffixes):
        errors.append(f"prohibited binary, data, font, or release artifact: {relative}")
    if lower.endswith(".safetensors"):
        synthetic_tensor = (
            relative.startswith("Vendor/")
            and "/Tests/" in relative
            and "/Resources/" in relative
            and path.stat().st_size <= 4096
        )
        if not synthetic_tensor:
            errors.append(f"model weight is excluded from the public repository: {relative}")

    head = path.read_bytes()[:16]
    if head.startswith((b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe")):
        errors.append(f"Mach-O or universal binary is excluded: {relative}")
    if head.startswith(b"SQLite format 3"):
        errors.append(f"SQLite data is excluded: {relative}")
    if head.startswith(b"PK\x03\x04"):
        errors.append(f"archive container is excluded: {relative}")

    asset_suffixes = (".gif", ".icns", ".jpeg", ".jpg", ".pdf", ".png")
    if lower.endswith(asset_suffixes):
        approved_asset_root = (
            relative.startswith("Brand/")
            or relative.startswith("Sources/Lerro/Resources/")
            or relative.startswith("site/public/")
            or relative.startswith("Vendor/")
        )
        if not approved_asset_root:
            errors.append(f"binary asset is outside a licensed asset root: {relative}")

brand_root = root / "Brand"
if brand_root.is_dir():
    asset_manifest_path = brand_root / "licenses" / "ASSET-LICENSES.json"
    if not asset_manifest_path.is_file():
        errors.append("Brand exists without licenses/ASSET-LICENSES.json")
    else:
        try:
            asset_manifest = json.loads(asset_manifest_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            errors.append(f"invalid Brand asset-license manifest: {error}")
            asset_manifest = {}
        records = asset_manifest.get("assets", [])
        patterns: list[tuple[str, str]] = []
        accepted_licenses = {
            "Apache-2.0",
            "CC-BY-4.0",
            "LicenseRef-Lerro-Trademark",
            "OFL-1.1",
        }
        for record in records:
            license_name = str(record.get("license", ""))
            if license_name not in accepted_licenses:
                errors.append(f"unrecognized Brand asset license: {license_name}")
            for pattern in str(record.get("glob", "")).split(","):
                pattern = pattern.strip()
                if pattern:
                    patterns.append((pattern, license_name))
        for asset in brand_root.rglob("*"):
            if not asset.is_file():
                continue
            relative = asset.relative_to(brand_root).as_posix()
            if relative == "README.md" or relative == "SHA256SUMS.txt":
                continue
            if relative.startswith("licenses/"):
                continue
            if not any(fnmatch.fnmatch(relative, pattern) for pattern, _ in patterns):
                errors.append(f"Brand asset has no matching license record: Brand/{relative}")
        for font in asset_manifest.get("fonts", []):
            if font.get("bundled") is True:
                errors.append(
                    "Apple-native public Brand Kit expects system fonts; "
                    f"bundled font declared: {font.get('family', '<unknown>')}"
                )

old_fragments = [
    "Type" + "less",
    "Speak" + "More",
    "SPEAK" + "MORE_",
    "Koe" + "ji",
    "Pin" + "drop",
]
old_pattern = re.compile("|".join(map(re.escape, old_fragments)), re.IGNORECASE)
context_pattern = re.compile(
    r"legacy|migrat|compatib|previous|旧|迁移|兼容",
    re.IGNORECASE,
)

local_path_patterns = [
    re.compile(r"/Users/([A-Za-z0-9._-]+)"),
    re.compile(r"/home/([A-Za-z0-9._-]+)"),
    re.compile(r"[A-Za-z]:\\\\Users\\\\[A-Za-z0-9._-]+"),
    re.compile(r"file:///Users/[A-Za-z0-9._-]+"),
    re.compile(r"/private/var/folders/[A-Za-z0-9._/-]+"),
]
secret_patterns = [
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(r"(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{30,}")),
    ("Hugging Face token", re.compile(r"\bhf_[A-Za-z0-9]{24,}\b")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("OpenAI-style key", re.compile(r"\bsk-[A-Za-z0-9_-]{32,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Groq API key", re.compile(r"\bgsk_[A-Za-z0-9_-]{20,}\b")),
    ("xAI API key", re.compile(r"\bxai-[A-Za-z0-9_-]{20,}\b")),
    (
        "Apple signing identity",
        re.compile(
            r"(?:Apple Development|Developer ID Application):[^\n]*(?:[\w.+-]+@[\w.-]+|\([A-Z0-9]{10}\))"
        ),
    ),
    (
        "Apple Team ID",
        re.compile(
            r"(?:DEVELOPMENT_TEAM|TeamIdentifier|Team ID)\s*[:=]\s*[\"']?[A-Z0-9]{10}\b"
        ),
    ),
    (
        "assigned notary profile",
        re.compile(r"LERRO_NOTARY_PROFILE\s*=\s*[\"']?(?!<|\$|\{)[A-Za-z0-9._-]{4,}"),
    ),
]

for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    relative = path.relative_to(root).as_posix()
    if relative == ".git" or relative.startswith(".git/"):
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue

    legacy_matches = list(old_pattern.finditer(text))
    if legacy_matches:
        if relative not in legacy_allowlist:
            errors.append(f"legacy identity outside approved migration boundary: {relative}")
        elif not context_pattern.search(text):
            errors.append(f"legacy allowlist path lacks migration context: {relative}")

    for pattern in local_path_patterns:
        for match in pattern.finditer(text):
            matched = match.group(0)
            if matched.startswith(("/Users/test-user", "/home/test-user")):
                continue
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"local absolute path at {relative}:{line}: {matched}")

    for label, pattern in secret_patterns:
        match = pattern.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"{label} candidate at {relative}:{line}")

if errors:
    for error in sorted(set(errors)):
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print("Allowlist, artifact, asset-license, legacy-identity, local-path, and built-in secret checks passed.")
PY

print "[2/6] Verifying third-party licenses against Package.resolved and source files"
python3 "$repo_root/script/check_third_party_licenses.py" \
    "$repo_root" \
    --license-source "${license_source:A}"

print "[3/6] Checking property-list and JSON syntax"
plutil -lint \
    "$repo_root/config/Info.plist" \
    "$repo_root/config/Lerro.entitlements" \
    "$repo_root/Sources/Lerro/Resources/PrivacyInfo.xcprivacy"
while IFS= read -r -d $'\0' json_path; do
    python3 -m json.tool "$json_path" >/dev/null
done < <(find "$repo_root/Brand" -type f -name '*.json' -print0)

print "[4/6] Checking optional dedicated secret scanner"
if command -v gitleaks >/dev/null 2>&1; then
    if [[ -d "$repo_root/.git" ]] && git -C "$repo_root" rev-parse --verify HEAD >/dev/null 2>&1; then
        gitleaks detect --source "$repo_root" --redact --no-banner
    else
        gitleaks detect --source "$repo_root" --no-git --redact --no-banner
    fi
    print "gitleaks passed."
else
    print "gitleaks unavailable; mandatory built-in credential patterns passed."
fi

print "[5/6] Checking Git repository boundary and history"
if [[ -d "$repo_root/.git" ]]; then
    git_top=$(git -C "$repo_root" rev-parse --show-toplevel)
    [[ "${git_top:A}" == "$repo_root" ]] || {
        print -u2 "Git top level differs from scan root: $git_top"
        exit 1
    }

    if [[ "$require_empty_history" == true ]]; then
        [[ -z "$(git -C "$repo_root" remote)" ]] || {
            print -u2 "Fresh public export must have no configured remote."
            exit 1
        }
        [[ -z "$(git -C "$repo_root" for-each-ref --format='%(refname)')" ]] || {
            print -u2 "Fresh public export must have no refs or commits."
            exit 1
        }
        [[ -z "$(git -C "$repo_root" config --local --get-regexp '^user\.' 2>/dev/null || true)" ]] || {
            print -u2 "Fresh public export must not contain a local author identity."
            exit 1
        }
        if [[ -n "$(find "$repo_root/.git/objects" -type f -print -quit)" ]]; then
            print -u2 "Fresh public export inherited or created Git objects."
            exit 1
        fi
        print "Verified empty independent Git history, no objects, no author identity, and no remote."
    else
        forbidden_history_paths=$(python3 - "$repo_root" <<'PY'
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
history_paths = subprocess.check_output(
    ["git", "-C", str(root), "log", "--all", "--name-only", "--format="],
    text=True,
).splitlines()
forbidden = re.compile(
    r"(^|/)(outputs|out|dist|work|clean-public|node_modules|coverage|"
    r"\.build|\.swiftpm|\.next|\.vinext|\.wrangler)(/|$)|"
    r"\.(app|dmg|dSYM|zip|sqlite3?|caf|wav|m4a|gguf|safetensors)$"
)

for relative in history_paths:
    if not relative or not forbidden.search(relative):
        continue
    path = root / relative
    synthetic_tensor = (
        relative.startswith("Vendor/")
        and "/Tests/" in relative
        and "/Resources/" in relative
        and relative.casefold().endswith(".safetensors")
        and path.is_file()
        and path.stat().st_size <= 4096
    )
    if not synthetic_tensor:
        print(relative)
PY
)
        [[ -z "$forbidden_history_paths" ]] || {
            print -u2 "Git history contains prohibited paths:"
            print -u2 "$forbidden_history_paths"
            exit 1
        }
        print "Git history path scan passed."
    fi
else
    [[ "$require_empty_history" == false ]] || {
        print -u2 "Expected an initialized Git repository at $repo_root"
        exit 1
    }
    print "Pre-initialization tree has no Git metadata."
fi

print "[6/6] Public repository scan passed"
print "Root: $repo_root"
