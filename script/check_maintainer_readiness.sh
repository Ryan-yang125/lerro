#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
local_config="$project_dir/config/maintainer.local.env"
require_release=false
require_online=false

usage() {
    print "Usage: $0 [--release] [--online]"
    print "Runs read-only maintainer and publication readiness checks."
}

while (( $# > 0 )); do
    case "$1" in
        --release)
            require_release=true
            shift
            ;;
        --online)
            require_online=true
            shift
            ;;
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
done

[[ -r "$local_config" ]] || {
    print -u2 "Missing config/maintainer.local.env. Copy the tracked template first."
    exit 1
}

permissions=$(stat -f '%Lp' "$local_config")
(( 10#$permissions <= 600 )) || {
    print -u2 "config/maintainer.local.env must use mode 0600 or stricter."
    exit 1
}

source "$local_config"

required_variables=(
    LERRO_NOTARY_PROFILE
    LERRO_SPARKLE_KEY_ACCOUNT
    LERRO_PUBLIC_REPO_DIR
    LERRO_PUBLIC_REMOTE
)
for variable in "${required_variables[@]}"; do
    value=${(P)variable:-}
    [[ -n "$value" && "$value" != *'<'* && "$value" != *'>'* ]] || {
        print -u2 "Local maintainer configuration is incomplete: $variable"
        exit 1
    }
done

required_commands=(git swift xcodebuild xcrun security node npm gh curl)
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null || {
        print -u2 "Missing required command: $command_name"
        exit 1
    }
done

[[ -x "$project_dir/site/node_modules/.bin/wrangler" ]] || {
    print -u2 "Missing project-local Wrangler. Run npm ci in site/."
    exit 1
}
[[ -r "$project_dir/distribution/wrangler.toml" ]] || {
    print -u2 "Missing private distribution/wrangler.toml."
    exit 1
}
[[ -d "$LERRO_PUBLIC_REPO_DIR/.git" ]] || {
    print -u2 "Configured public repository worktree is unavailable."
    exit 1
}
[[ "${LERRO_PUBLIC_REPO_DIR:A}" != "${project_dir:A}" ]] || {
    print -u2 "The public repository worktree must be separate from the source workspace."
    exit 1
}

public_remote=$(git -C "$LERRO_PUBLIC_REPO_DIR" remote get-url origin 2>/dev/null || true)
[[ "$public_remote" == "$LERRO_PUBLIC_REMOTE" ]] || {
    print -u2 "The public worktree origin differs from the configured official remote."
    exit 1
}

node_major=$(node -p 'Number(process.versions.node.split(".")[0])')
(( node_major >= 22 )) || {
    print -u2 "Node.js 22 or later is required."
    exit 1
}

xcrun metal --version >/dev/null

identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
[[ "$identities" == *'"Apple Development:'* ]] || {
    print -u2 "No valid Apple Development signing identity is available."
    exit 1
}
[[ "$identities" == *'"Developer ID Application:'* ]] || {
    print -u2 "No valid Developer ID Application signing identity is available."
    exit 1
}

security find-generic-password -a "$LERRO_SPARKLE_KEY_ACCOUNT" >/dev/null 2>&1 || {
    print -u2 "The configured Sparkle Keychain account is unavailable."
    exit 1
}

if [[ "$require_release" == true ]]; then
    [[ -z "$(git -C "$project_dir" status --short)" ]] || {
        print -u2 "The source workspace must be clean for release readiness."
        exit 1
    }
    [[ -z "$(git -C "$LERRO_PUBLIC_REPO_DIR" status --short)" ]] || {
        print -u2 "The public repository worktree must be clean for release readiness."
        exit 1
    }
fi

if [[ "$require_online" == true ]]; then
    xcrun notarytool history \
        --keychain-profile "$LERRO_NOTARY_PROFILE" >/dev/null
    "$project_dir/site/node_modules/.bin/wrangler" whoami \
        --config "$project_dir/distribution/wrangler.toml" \
        --json >/dev/null
    gh auth status --active --hostname github.com >/dev/null
    git ls-remote "$LERRO_PUBLIC_REMOTE" HEAD >/dev/null
    for route in / /zh /changelog /zh/changelog; do
        curl --fail --silent --show-error \
            "https://lerroapp.com$route" >/dev/null
    done
    curl --fail --silent --show-error \
        https://updates.lerroapp.com/appcast/stable.xml >/dev/null
fi

print "Maintainer readiness passed (release=$require_release, online=$require_online)."
