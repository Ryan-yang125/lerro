#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
brand_dir=${script_dir:h}
project_dir=${brand_dir:h}
app_resources_dir="$project_dir/Sources/Lerro/Resources"
temporary_dir=$(mktemp -d /tmp/lerro-brand-verify.XXXXXX)
trap 'find "$temporary_dir" -depth -delete 2>/dev/null || true' EXIT

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

if /usr/bin/grep -RniE \
  '#007AFF|#0A84FF|linearGradient|radialGradient|feDropShadow' \
  "$brand_dir/source/logo" "$brand_dir/source/app-icon" \
  --include='*.svg'; then
  fail "logo or app-icon source contains retired blue or dimensional artwork"
fi

/usr/bin/jq -e '.brand.name == "Lerro" and .brand.pronunciation == "LEH-ro"' \
  "$brand_dir/tokens/brand.tokens.json" >/dev/null
/usr/bin/jq -e '.thirdPartyRasterOrVectorAssets | length == 0' \
  "$brand_dir/licenses/ASSET-LICENSES.json" >/dev/null
/usr/bin/swiftc -typecheck "$brand_dir/tokens/LerroTokens.swift"

expected_files=(
  "$brand_dir/exports/app-icon/Lerro.icns"
  "$brand_dir/exports/app-icon/lerro-app-icon-1024.png"
  "$brand_dir/exports/logo/lerro-micro-16.svg"
  "$brand_dir/exports/logo/lerro-micro-24.svg"
  "$brand_dir/templates/github-social-preview.png"
  "$brand_dir/templates/readme-hero-light.png"
  "$brand_dir/templates/readme-hero-dark.png"
  "$brand_dir/templates/release-card.svg"
  "$brand_dir/templates/screenshot-frame.svg"
  "$brand_dir/validation/small-size-light.png"
  "$brand_dir/validation/small-size-dark.png"
)
for asset_path in $expected_files; do
  [[ -s "$asset_path" ]] || fail "missing required asset: $asset_path"
done

for source_path in "$brand_dir"/source/logo/*.svg; do
  expect_identical "$source_path" "$brand_dir/exports/logo/${source_path:t}"
done
for source_path in "$brand_dir"/source/app-icon/*.svg; do
  expect_identical "$source_path" "$brand_dir/exports/app-icon/${source_path:t}"
done
for source_path in "$brand_dir"/source/menu-bar/*.svg; do
  expect_identical "$source_path" "$brand_dir/exports/menu-bar/${source_path:t}"
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

for state in idle listening processing error; do
  [[ -s "$brand_dir/exports/menu-bar/lerro-menubar-$state.svg" ]] \
    || fail "missing menu state: $state"
  [[ -s "$brand_dir/exports/menu-bar/LerroMenu${(C)state}Template.png" ]] \
    || fail "missing menu template PNG: $state"
  expect_dimensions \
    "$brand_dir/exports/menu-bar/LerroMenu${(C)state}Template.png" 18 18
  expect_dimensions \
    "$brand_dir/exports/menu-bar/LerroMenu${(C)state}Template@2x.png" 36 36
  if /usr/bin/grep -Eo '#[0-9A-Fa-f]{6}' \
    "$brand_dir/source/menu-bar/lerro-menubar-$state.svg" \
    | /usr/bin/grep -Ev '^#000000$' \
    | /usr/bin/grep -q .; then
    fail "menu template contains color: $state"
  fi
done

if /usr/bin/find "$brand_dir" -type f \( -name '*.ttf' -o -name '*.otf' \) | /usr/bin/grep -q .; then
  fail "Brand Kit contains redistributed font files"
fi

expect_dimensions "$brand_dir/exports/app-icon/lerro-app-icon-1024.png" 1024 1024
expect_dimensions "$brand_dir/exports/logo/lerro-micro-16.png" 16 16
expect_dimensions "$brand_dir/exports/logo/lerro-micro-24.png" 24 24
expect_dimensions "$brand_dir/templates/github-social-preview.png" 1280 640
expect_dimensions "$brand_dir/templates/readme-hero-light.png" 1600 900
expect_dimensions "$brand_dir/templates/readme-hero-dark.png" 1600 900
expect_dimensions "$brand_dir/validation/small-size-light.png" 960 420
expect_dimensions "$brand_dir/validation/small-size-dark.png" 960 420

/usr/bin/file "$brand_dir/exports/app-icon/Lerro.icns" | /usr/bin/grep -q 'Mac OS X icon' \
  || fail "Lerro.icns is invalid"

/usr/bin/iconutil -c iconset "$brand_dir/exports/app-icon/Lerro.icns" -o "$temporary_dir/Lerro.iconset"
expected_iconset_files=(
  icon_16x16.png
  icon_16x16@2x.png
  icon_32x32.png
  icon_32x32@2x.png
  icon_128x128.png
  icon_128x128@2x.png
  icon_256x256.png
  icon_256x256@2x.png
  icon_512x512.png
  icon_512x512@2x.png
)
for iconset_file in $expected_iconset_files; do
  [[ -s "$temporary_dir/Lerro.iconset/$iconset_file" ]] \
    || fail "ICNS lacks representation: $iconset_file"
done
expect_dimensions "$temporary_dir/Lerro.iconset/icon_16x16.png" 16 16
expect_dimensions "$temporary_dir/Lerro.iconset/icon_16x16@2x.png" 32 32
expect_dimensions "$temporary_dir/Lerro.iconset/icon_32x32.png" 32 32
expect_dimensions "$temporary_dir/Lerro.iconset/icon_32x32@2x.png" 64 64
expect_dimensions "$temporary_dir/Lerro.iconset/icon_128x128.png" 128 128
expect_dimensions "$temporary_dir/Lerro.iconset/icon_128x128@2x.png" 256 256
expect_dimensions "$temporary_dir/Lerro.iconset/icon_256x256.png" 256 256
expect_dimensions "$temporary_dir/Lerro.iconset/icon_256x256@2x.png" 512 512
expect_dimensions "$temporary_dir/Lerro.iconset/icon_512x512.png" 512 512
expect_dimensions "$temporary_dir/Lerro.iconset/icon_512x512@2x.png" 1024 1024

[[ -s "$app_resources_dir/icon.icns" ]] || fail "runtime app icon is missing"
/usr/bin/cmp -s \
  "$brand_dir/exports/app-icon/Lerro.icns" \
  "$app_resources_dir/icon.icns" \
  || fail "runtime app icon differs from the Brand Kit"
for state in idle listening processing error; do
  state_title=${(C)state}
  for suffix in .png @2x.png; do
    runtime_name="LerroMenu${state_title}Template${suffix}"
    [[ -s "$app_resources_dir/MenuBar/$runtime_name" ]] \
      || fail "runtime menu template is missing: $runtime_name"
    /usr/bin/cmp -s \
      "$brand_dir/exports/menu-bar/$runtime_name" \
      "$app_resources_dir/MenuBar/$runtime_name" \
      || fail "runtime menu template differs from the Brand Kit: $runtime_name"
  done
done

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
