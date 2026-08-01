#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
model_cache_directory=${LERRO_LIVE_MODEL_CACHE:-"$HOME/Library/Application Support/app.lerro.mac/Models"}
metal_library_path=${LERRO_MLX_METALLIB:-"$project_dir/.build/out/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"}
offline_mode=${LERRO_LIVE_MODEL_OFFLINE:-0}
metal_link=""
previous_metal_link_target=""

if [[ "$offline_mode" != 0 && "$offline_mode" != 1 ]]; then
    print -u2 "LERRO_LIVE_MODEL_OFFLINE must be 0 or 1."
    exit 64
fi

cleanup() {
    if [[ -n "$metal_link" && -L "$metal_link" ]]; then
        unlink "$metal_link"
    fi
    if [[ -n "$metal_link" && -n "$previous_metal_link_target" ]]; then
        ln -s "$previous_metal_link_target" "$metal_link"
    fi
}
trap cleanup EXIT INT TERM

if /usr/bin/pgrep -x Lerro >/dev/null 2>&1; then
    print -u2 "Quit Lerro before running the live model smoke to free MLX memory."
    exit 1
fi
[[ -d "$model_cache_directory" ]] || {
    print -u2 "Model cache directory is missing: $model_cache_directory"
    exit 1
}
[[ -r "$metal_library_path" && -s "$metal_library_path" ]] || {
    print -u2 "MLX default.metallib is missing. Run script/verify_release.sh first or set LERRO_MLX_METALLIB."
    exit 1
}

cd "$project_dir"
LERRO_LIVE_MODEL_SMOKE=0 swift test --filter MLXLanguageModelRuntimeTests

test_binaries=(
    "$project_dir"/.build/*/debug/LerroPackageTests.xctest/Contents/MacOS/LerroPackageTests(N)
)
if (( ${#test_binaries} != 1 )); then
    print -u2 "Expected one Lerro test executable; found ${#test_binaries}."
    exit 1
fi
test_binary="${test_binaries[1]}"
metal_link="${test_binary:h}/mlx.metallib"
if [[ -L "$metal_link" ]]; then
    previous_metal_link_target=$(readlink "$metal_link")
    unlink "$metal_link"
elif [[ -e "$metal_link" ]]; then
    print -u2 "Refusing to replace the existing test Metal library: $metal_link"
    exit 1
fi
ln -s "$metal_library_path" "$metal_link"

if [[ "$offline_mode" == 1 ]]; then
    swift_path=$(xcrun --find swift)
    testing_helper="${swift_path:h:h}/libexec/swift/pm/swiftpm-testing-helper"
    testing_frameworks="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks"
    [[ -x "$testing_helper" ]] || {
        print -u2 "SwiftPM testing helper is missing: $testing_helper"
        exit 1
    }
    [[ -d "$testing_frameworks/Testing.framework" ]] || {
        print -u2 "Swift Testing framework is missing: $testing_frameworks"
        exit 1
    }
    [[ -x /usr/bin/sandbox-exec ]] || {
        print -u2 "sandbox-exec is unavailable; offline proof cannot run."
        exit 1
    }

    print "Running live cached model with network denied by sandbox-exec."
    /usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' \
        /usr/bin/env \
        DYLD_FRAMEWORK_PATH="$testing_frameworks" \
        LERRO_LIVE_MODEL_SMOKE=1 \
        LERRO_LIVE_MODEL_CACHE="$model_cache_directory" \
        LERRO_LIVE_MODEL_ID="${LERRO_LIVE_MODEL_ID:-mlx-community/Qwen3.5-4B-MLX-4bit}" \
        "$testing_helper" \
        --test-bundle-path "$test_binary" \
        --skip-build \
        --filter liveCachedModelSmoke \
        "$test_binary" \
        --testing-library swift-testing
else
    print "Running live cached model with the host network policy."
    LERRO_LIVE_MODEL_SMOKE=1 \
    LERRO_LIVE_MODEL_CACHE="$model_cache_directory" \
        swift test --skip-build --filter liveCachedModelSmoke
fi
