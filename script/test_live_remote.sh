#!/bin/zsh
set -euo pipefail
umask 077

script_dir=${0:A:h}
project_dir=${script_dir:h}
environment_file=${LERRO_REMOTE_ENV_FILE:-"$project_dir/.env.deepseek.local"}

if [[ -f "$environment_file" ]]; then
    environment_permissions=$(stat -f '%Lp' "$environment_file")
    if [[ "$environment_permissions" != 600 ]]; then
        print -u2 "Remote smoke environment file must use mode 0600: $environment_file"
        exit 64
    fi
    set -a
    source "$environment_file"
    set +a
fi

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    print -u2 "DEEPSEEK_API_KEY is required in the environment or the local smoke environment file."
    exit 64
fi

cd "$project_dir"
LERRO_LIVE_REMOTE_SMOKE=1 swift test --filter liveDeepSeek
