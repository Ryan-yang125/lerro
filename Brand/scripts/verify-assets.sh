#!/bin/zsh
set -euo pipefail
export LC_ALL=en_US.UTF-8

script_dir=${0:A:h}
brand_dir=${script_dir:h}
project_dir=${brand_dir:h}
app_resources_dir="$project_dir/Sources/Lerro/Resources"

fail() {
  print -u2 "verify-assets: $1"
  exit 1
}

expect_identical() {
  local source_path=$1
  local generated_path=$2
  /usr/bin/cmp -s "$source_path" "$generated_path" \
    || fail "generated asset differs from its editable source: $generated_path"
}

expect_dimensions() {
  local path=$1
  local expected_width=$2
  local expected_height=$3
  local width height
  width=$(/usr/bin/sips -g pixelWidth "$path" | /usr/bin/awk '/pixelWidth:/{print $2}')
  height=$(/usr/bin/sips -g pixelHeight "$path" | /usr/bin/awk '/pixelHeight:/{print $2}')
  [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]] \
    || fail "$path is ${width}x${height}; expected ${expected_width}x${expected_height}"
}

find "$brand_dir" -type f -name '*.svg' -print0 \
  | while IFS= read -r -d '' svg; do
      /usr/bin/xmllint --noout "$svg"
    done

if /usr/bin/grep -RniE --include='*.svg' '<image([[:space:]]|>)' "$brand_dir/source"; then
  fail "source SVG contains embedded raster artwork"
fi

/usr/bin/jq -e '(.groups | length) == 2' \
  "$brand_dir/source/app-icon/AppIcon.icon/icon.json" >/dev/null
/usr/bin/jq -e '.brand.name == "Lerro" and .brand.pronunciation == "LEH-ro"' \
  "$brand_dir/tokens/brand.tokens.json" >/dev/null
/usr/bin/jq -e '.thirdPartyRasterOrVectorAssets | length == 0' \
  "$brand_dir/licenses/ASSET-LICENSES.json" >/dev/null
/usr/bin/swiftc -typecheck "$brand_dir/tokens/LerroTokens.swift"

logo_names=(
  lerro-mark
  lerro-mark-reversed
  lerro-mark-mono
  lerro-wordmark
  lerro-wordmark-reversed
  lerro-lockup-horizontal
  lerro-lockup-horizontal-dark
  lerro-construction
)
menu_states=(
  idle:Idle
  listening:Listening
  listening-dim:ListeningDim
  processing-1:Processing1
  processing-2:Processing2
  processing-3:Processing3
  processing-4:Processing4
  error:Error
)
runtime_menu_files=()

for name in $logo_names; do
  for extension in svg pdf png; do
    [[ -s "$brand_dir/exports/logo/$name.$extension" ]] \
      || fail "missing logo export: $name.$extension"
  done
  expect_identical "$brand_dir/source/logo/$name.svg" "$brand_dir/exports/logo/$name.svg"
done
expect_dimensions "$brand_dir/exports/logo/lerro-mark.png" 440 690
expect_dimensions "$brand_dir/exports/logo/lerro-wordmark.png" 1376 552
expect_dimensions "$brand_dir/exports/logo/lerro-lockup-horizontal.png" 828 320

expect_identical \
  "$brand_dir/source/app-icon/lerro-app-icon-flat.svg" \
  "$brand_dir/exports/app-icon/lerro-app-icon-flat.svg"
expect_dimensions "$brand_dir/exports/app-icon/lerro-app-icon-1024.png" 1024 1024

for entry in $menu_states; do
  state=${entry%%:*}
  title=${entry#*:}
  expect_identical \
    "$brand_dir/source/menu-bar/lerro-menubar-$state.svg" \
    "$brand_dir/exports/menu-bar/lerro-menubar-$state.svg"
  [[ -s "$brand_dir/exports/menu-bar/lerro-menubar-$state.pdf" ]] \
    || fail "missing menu PDF: $state"
  expect_dimensions "$brand_dir/exports/menu-bar/LerroMenu${title}Template.png" 18 18
  expect_dimensions "$brand_dir/exports/menu-bar/LerroMenu${title}Template@2x.png" 36 36
  if /usr/bin/grep -Eo '#[0-9A-Fa-f]{6}' \
    "$brand_dir/source/menu-bar/lerro-menubar-$state.svg" \
    | /usr/bin/grep -Ev '^#000000$' \
    | /usr/bin/grep -q .; then
    fail "menu template contains color: $state"
  fi
  runtime_menu_files+=("LerroMenu${title}Template.png" "LerroMenu${title}Template@2x.png")
done

for asset_name in release-card screenshot-frame; do
  expect_identical \
    "$brand_dir/source/templates/$asset_name.svg" \
    "$brand_dir/templates/$asset_name.svg"
done
for asset_name in small-size-light small-size-dark; do
  expect_identical \
    "$brand_dir/source/validation/$asset_name.svg" \
    "$brand_dir/validation/$asset_name.svg"
done
expect_dimensions "$brand_dir/templates/github-social-preview.png" 1280 640
expect_dimensions "$brand_dir/templates/readme-hero-light.png" 1600 900
expect_dimensions "$brand_dir/templates/readme-hero-dark.png" 1600 900
expect_dimensions "$brand_dir/templates/release-card.png" 1200 630
expect_dimensions "$brand_dir/templates/screenshot-frame.png" 1600 1100
expect_dimensions "$brand_dir/validation/small-size-light.png" 960 420
expect_dimensions "$brand_dir/validation/small-size-dark.png" 960 420

if /usr/bin/find "$brand_dir" -type f \( -name '*.ttf' -o -name '*.otf' \) | /usr/bin/grep -q .; then
  fail "Brand Kit contains redistributed font files"
fi

for icon_file in AppIcon.icns Assets.car; do
  [[ -s "$brand_dir/exports/app-icon/$icon_file" ]] || fail "missing app icon export: $icon_file"
  [[ -s "$app_resources_dir/$icon_file" ]] || fail "runtime app icon resource is missing: $icon_file"
  /usr/bin/cmp -s \
    "$brand_dir/exports/app-icon/$icon_file" \
    "$app_resources_dir/$icon_file" \
    || fail "runtime app icon resource differs from the Brand Kit: $icon_file"
done
/usr/bin/file "$brand_dir/exports/app-icon/AppIcon.icns" | /usr/bin/grep -q 'Mac OS X icon' \
  || fail "AppIcon.icns is invalid"
/usr/bin/xcrun assetutil --info "$brand_dir/exports/app-icon/Assets.car" \
  | /usr/bin/jq -e 'any(.[]; .Name == "AppIcon")' >/dev/null \
  || fail "Assets.car lacks the AppIcon asset"

for runtime_name in $runtime_menu_files; do
  [[ -s "$app_resources_dir/MenuBar/$runtime_name" ]] \
    || fail "runtime menu template is missing: $runtime_name"
  /usr/bin/cmp -s \
    "$brand_dir/exports/menu-bar/$runtime_name" \
    "$app_resources_dir/MenuBar/$runtime_name" \
    || fail "runtime menu template differs from the Brand Kit: $runtime_name"
done
runtime_menu_count=$(/usr/bin/find "$app_resources_dir/MenuBar" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[[ "$runtime_menu_count" == "${#runtime_menu_files}" ]] \
  || fail "runtime MenuBar holds $runtime_menu_count files; expected ${#runtime_menu_files}"

/usr/bin/find "$brand_dir/exports" -type f -name '*.pdf' -print0 \
  | while IFS= read -r -d '' pdf; do
      /usr/bin/file "$pdf" | /usr/bin/grep -q 'PDF document' || fail "invalid PDF: $pdf"
    done

prohibited_pattern=$'\u4e0d\u662f.*\u800c\u662f|\u5148\u522b.*\u66f4\u503c\u5f97|not[[:space:]].*but'
if /usr/bin/grep -RniE "$prohibited_pattern" "$brand_dir" \
  --include='*.md' --include='*.json' --include='*.swift' --include='*.css' --include='*.svg'; then
  fail "copy contains a prohibited contrast pattern"
fi

retired_pattern='Warm'' Ink|Rice'' Paper|Cinna''bar|News''reader|Prompt[[:space:]]+(font|typeface)'
if /usr/bin/grep -RniE "$retired_pattern" "$brand_dir" \
  --include='*.md' --include='*.json' --include='*.swift' --include='*.css' --include='*.svg'; then
  fail "Brand Kit contains a retired visual-system reference"
fi

(
  cd "$brand_dir"
  /usr/bin/shasum -a 256 -c SHA256SUMS.txt
)

print "Lerro Brand Kit verification passed"
