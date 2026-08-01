#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source_root=${script_dir:h}
public_parent="$source_root/clean-public"
destination_argument="$public_parent/lerro"
replace_existing=false

usage() {
    print "Usage: $0 [--destination PATH] [--replace]"
}

while (( $# > 0 )); do
    case "$1" in
        --destination)
            (( $# >= 2 )) || {
                print -u2 "--destination requires a path."
                exit 64
            }
            destination_argument="$2"
            shift 2
            ;;
        --replace)
            replace_existing=true
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

mkdir -p "$public_parent"
public_parent=${public_parent:A}
if [[ "$destination_argument" != /* ]]; then
    destination_argument="$source_root/$destination_argument"
fi
destination=${destination_argument:A}
if [[ "$destination" != "$public_parent"/* || "$destination" == "$public_parent" ]]; then
    print -u2 "Destination must be a child of $public_parent"
    exit 1
fi
if [[ -L "$destination" ]]; then
    print -u2 "Destination cannot be a symbolic link: $destination"
    exit 1
fi
if [[ -e "$destination" && "$replace_existing" == false ]]; then
    print -u2 "Destination already exists: $destination"
    print -u2 "Review it, then rerun with --replace to regenerate it."
    exit 1
fi

allowlist_path="$source_root/script/public_repo_allowlist.txt"
[[ -r "$allowlist_path" ]] || {
    print -u2 "Missing allowlist: $allowlist_path"
    exit 1
}

staging=$(mktemp -d "$public_parent/.lerro-export.XXXXXX")
backup=""
cleanup() {
    if [[ -n "$staging" && -d "$staging" ]]; then
        rm -rf -- "$staging"
    fi
    if [[ -n "$backup" && -d "$backup" && ! -e "$destination" ]]; then
        mv "$backup" "$destination"
    fi
}
trap cleanup EXIT INT TERM

print "[1/5] Copying explicit public allowlist"
while IFS= read -r entry; do
    source_path="$source_root/${entry%/}"
    destination_path="$staging/${entry%/}"
    if [[ "$entry" == */ ]]; then
        [[ -d "$source_path" ]] || {
            print -u2 "Allowlisted directory is missing: $entry"
            exit 1
        }
        mkdir -p "$destination_path"
        rsync -a \
            --exclude='.git/' \
            --exclude='.build/' \
            --exclude='.swiftpm/' \
            --exclude='.next/' \
            --exclude='.vinext/' \
            --exclude='.wrangler/' \
            --exclude='.env' \
            --exclude='.env.*' \
            --exclude='clean-public/' \
            --exclude='coverage/' \
            --exclude='dist/' \
            --exclude='node_modules/' \
            --exclude='next-env.d.ts' \
            --exclude='out/' \
            --exclude='outputs/' \
            --exclude='work/' \
            --exclude='xcuserdata/' \
            --exclude='.DS_Store' \
            --exclude='*.xcuserstate' \
            --exclude='/local.json' \
            "$source_path/" "$destination_path/"
    else
        [[ -f "$source_path" && ! -L "$source_path" ]] || {
            print -u2 "Allowlisted regular file is missing: $entry"
            exit 1
        }
        mkdir -p "${destination_path:h}"
        ditto "$source_path" "$destination_path"
    fi
done < <(awk 'NF && $1 !~ /^#/ { print $1 }' "$allowlist_path")

print "[2/5] Scanning the pre-initialization tree"
LERRO_LICENSE_SOURCE="$source_root" \
    /bin/zsh "$staging/script/scan_public_repo.sh" "$staging"

print "[3/5] Initializing an independent empty Git repository"
git init -q -b main "$staging"

print "[4/5] Verifying the empty history and Git boundary"
LERRO_LICENSE_SOURCE="$source_root" \
    /bin/zsh "$staging/script/scan_public_repo.sh" \
    --require-empty-history "$staging"

print "[5/5] Publishing the generated tree locally"
if [[ -e "$destination" ]]; then
    backup="$public_parent/.${destination:t}.previous.$$"
    [[ ! -e "$backup" ]] || {
        print -u2 "Temporary backup path already exists: $backup"
        exit 1
    }
    mv "$destination" "$backup"
fi
mv "$staging" "$destination"
staging=""
if [[ -n "$backup" ]]; then
    rm -rf -- "$backup"
    backup=""
fi
trap - EXIT INT TERM

file_count=$(find "$destination" -type f -not -path "$destination/.git/*" | wc -l | tr -d ' ')
print "Public repository export passed"
print "Destination: $destination"
print "Files: $file_count"
print "Git: empty main branch, no commits, no remote"
