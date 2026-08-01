#!/bin/zsh

# Shared signing-mode resolution for local builds and release packaging.
# Call lerro_resolve_signing after sourcing this file. The function exports:
#   LERRO_RESOLVED_SIGNING_MODE
#   LERRO_RESOLVED_CODESIGN_IDENTITY

lerro_find_codesign_identity() {
    local required_prefix="$1"
    local identities line quoted_name

    identities=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
    while IFS= read -r line; do
        [[ "$line" == *\"*\"* ]] || continue
        quoted_name="${line#*\"}"
        quoted_name="${quoted_name%%\"*}"
        if [[ "$quoted_name" == "$required_prefix"* ]]; then
            print -r -- "$quoted_name"
            return 0
        fi
    done <<< "$identities"
    return 1
}

lerro_validate_codesign_identity() {
    local identity="$1"
    local identities line quoted_name

    identities=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
    while IFS= read -r line; do
        [[ "$line" == *\"*\"* ]] || continue
        quoted_name="${line#*\"}"
        quoted_name="${quoted_name%%\"*}"
        [[ "$quoted_name" == "$identity" ]] && return 0
    done <<< "$identities"
    return 1
}

lerro_resolve_signing() {
    local requested_mode="${LERRO_SIGNING_MODE:-auto}"
    local requested_identity="${LERRO_CODESIGN_IDENTITY:-}"
    local resolved_mode resolved_identity

    case "$requested_mode" in
        auto)
            if [[ -n "$requested_identity" ]]; then
                case "$requested_identity" in
                    -)
                        resolved_mode=ad-hoc
                        resolved_identity=-
                        ;;
                    "Apple Development:"*)
                        resolved_mode=development
                        resolved_identity="$requested_identity"
                        ;;
                    "Developer ID Application:"*)
                        resolved_mode=developer-id
                        resolved_identity="$requested_identity"
                        ;;
                    *)
                        print -u2 "LERRO_CODESIGN_IDENTITY must be '-', an Apple Development identity, or a Developer ID Application identity."
                        return 64
                        ;;
                esac
            elif resolved_identity=$(lerro_find_codesign_identity "Apple Development:"); then
                resolved_mode=development
            else
                resolved_mode=ad-hoc
                resolved_identity=-
            fi
            ;;
        development)
            if [[ -n "$requested_identity" ]]; then
                [[ "$requested_identity" == "Apple Development:"* ]] || {
                    print -u2 "development mode requires an Apple Development identity."
                    return 64
                }
                resolved_identity="$requested_identity"
            elif ! resolved_identity=$(lerro_find_codesign_identity "Apple Development:"); then
                print -u2 "No valid Apple Development signing identity was found."
                return 69
            fi
            resolved_mode=development
            ;;
        ad-hoc)
            if [[ -n "$requested_identity" && "$requested_identity" != "-" ]]; then
                print -u2 "ad-hoc mode only accepts LERRO_CODESIGN_IDENTITY='-'."
                return 64
            fi
            resolved_mode=ad-hoc
            resolved_identity=-
            ;;
        developer-id)
            if [[ -n "$requested_identity" ]]; then
                [[ "$requested_identity" == "Developer ID Application:"* ]] || {
                    print -u2 "developer-id mode requires a Developer ID Application identity."
                    return 64
                }
                resolved_identity="$requested_identity"
            elif ! resolved_identity=$(lerro_find_codesign_identity "Developer ID Application:"); then
                print -u2 "No valid Developer ID Application signing identity was found."
                return 69
            fi
            resolved_mode=developer-id
            ;;
        *)
            print -u2 "Unknown LERRO_SIGNING_MODE: $requested_mode"
            print -u2 "Expected one of: auto, development, ad-hoc, developer-id"
            return 64
            ;;
    esac

    if [[ "$resolved_mode" != "ad-hoc" ]] && ! lerro_validate_codesign_identity "$resolved_identity"; then
        print -u2 "The requested signing identity is not currently valid: $resolved_identity"
        return 69
    fi

    export LERRO_RESOLVED_SIGNING_MODE="$resolved_mode"
    export LERRO_RESOLVED_CODESIGN_IDENTITY="$resolved_identity"
}
