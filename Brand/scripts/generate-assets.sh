#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
brand_dir=${script_dir:h}
source_dir="$brand_dir/source"
exports_dir="$brand_dir/exports"
templates_dir="$brand_dir/templates"
validation_dir="$brand_dir/validation"
app_resources_dir="$brand_dir/../Sources/Lerro/Resources"
temporary_dir=$(mktemp -d /tmp/lerro-brand-assets.XXXXXX)
trap 'find "$temporary_dir" -depth -delete 2>/dev/null || true' EXIT

renderer="$temporary_dir/render-svg"
/usr/bin/swiftc -O "$script_dir/render-svg.swift" -o "$renderer"

mkdir -p \
  "$exports_dir" \
  "$templates_dir" \
  "$validation_dir"
find "$exports_dir" -mindepth 1 -delete
mkdir -p \
  "$exports_dir/logo" \
  "$exports_dir/app-icon" \
  "$exports_dir/menu-bar" \
  "$exports_dir/dmg"

render_png() {
  "$renderer" png "$1" "$2" "$3" "$4"
}

render_pdf() {
  "$renderer" pdf "$1" "$2" "$3" "$4"
}

copy_and_render_logo() {
  local name=$1
  local width=$2
  local height=$3
  local png_width=$4
  local png_height=$5
  local source="$source_dir/logo/$name.svg"
  /bin/cp "$source" "$exports_dir/logo/$name.svg"
  render_pdf "$source" "$exports_dir/logo/$name.pdf" "$width" "$height"
  render_png "$source" "$exports_dir/logo/$name.png" "$png_width" "$png_height"
}

copy_and_render_logo lerro-mark 44 69 440 690
copy_and_render_logo lerro-mark-reversed 44 69 440 690
copy_and_render_logo lerro-mark-mono 44 69 440 690
copy_and_render_logo lerro-wordmark 172 69 1376 552
copy_and_render_logo lerro-wordmark-reversed 172 69 1376 552
copy_and_render_logo lerro-lockup-horizontal 207 80 828 320
copy_and_render_logo lerro-lockup-horizontal-dark 207 80 828 320
copy_and_render_logo lerro-construction 640 400 1280 800

dmg_background_source="$source_dir/dmg/lerro-dmg-background.svg"
render_png "$dmg_background_source" "$temporary_dir/lerro-dmg-background.png" 660 400
render_png "$dmg_background_source" "$temporary_dir/lerro-dmg-background@2x.png" 1320 800
/usr/bin/tiffutil -cathidpicheck \
  "$temporary_dir/lerro-dmg-background.png" \
  "$temporary_dir/lerro-dmg-background@2x.png" \
  -out "$exports_dir/dmg/lerro-dmg-background.tiff" >/dev/null

flat_icon_source="$source_dir/app-icon/lerro-app-icon-flat.svg"
/bin/cp "$flat_icon_source" "$exports_dir/app-icon/lerro-app-icon-flat.svg"
render_png "$flat_icon_source" "$exports_dir/app-icon/lerro-app-icon-1024.png" 1024 1024

actool_output="$temporary_dir/actool"
mkdir -p "$actool_output"
/usr/bin/xcrun actool "$source_dir/app-icon/AppIcon.icon" "$source_dir/app-icon/Accent.xcassets" "$source_dir/icons/Glyphs.xcassets" \
  --compile "$actool_output" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --output-partial-info-plist "$actool_output/partial.plist"
for icon_file in AppIcon.icns Assets.car; do
  [[ -s "$actool_output/$icon_file" ]] || {
    print -u2 "actool did not produce $icon_file"
    exit 1
  }
  /bin/cp "$actool_output/$icon_file" "$exports_dir/app-icon/$icon_file"
done

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
for entry in $menu_states; do
  state=${entry%%:*}
  title=${entry#*:}
  source="$source_dir/menu-bar/lerro-menubar-$state.svg"
  /bin/cp "$source" "$exports_dir/menu-bar/lerro-menubar-$state.svg"
  render_pdf "$source" "$exports_dir/menu-bar/lerro-menubar-$state.pdf" 18 18
  render_png "$source" "$exports_dir/menu-bar/LerroMenu${title}Template.png" 18 18
  render_png "$source" "$exports_dir/menu-bar/LerroMenu${title}Template@2x.png" 36 36
done

[[ -d "$app_resources_dir/MenuBar" ]] || {
  print -u2 "Missing Lerro app resource directory: $app_resources_dir/MenuBar"
  exit 1
}
for icon_file in AppIcon.icns Assets.car; do
  /bin/cp "$exports_dir/app-icon/$icon_file" "$app_resources_dir/$icon_file"
done
find "$app_resources_dir/MenuBar" -type f -delete
for entry in $menu_states; do
  title=${entry#*:}
  /bin/cp \
    "$exports_dir/menu-bar/LerroMenu${title}Template.png" \
    "$exports_dir/menu-bar/LerroMenu${title}Template@2x.png" \
    "$app_resources_dir/MenuBar/"
done

render_png "$source_dir/templates/github-social-preview.svg" "$templates_dir/github-social-preview.png" 1280 640
render_png "$source_dir/templates/readme-hero-light.svg" "$templates_dir/readme-hero-light.png" 1600 900
render_png "$source_dir/templates/readme-hero-dark.svg" "$templates_dir/readme-hero-dark.png" 1600 900
/bin/cp "$source_dir/templates/release-card.svg" "$templates_dir/release-card.svg"
/bin/cp "$source_dir/templates/screenshot-frame.svg" "$templates_dir/screenshot-frame.svg"
render_png "$source_dir/templates/release-card.svg" "$templates_dir/release-card.png" 1200 630
render_png "$source_dir/templates/screenshot-frame.svg" "$templates_dir/screenshot-frame.png" 1600 1100

render_png "$source_dir/validation/small-size-light.svg" "$validation_dir/small-size-light.png" 960 420
render_png "$source_dir/validation/small-size-dark.svg" "$validation_dir/small-size-dark.png" 960 420
/bin/cp "$source_dir/validation/small-size-light.svg" "$validation_dir/small-size-light.svg"
/bin/cp "$source_dir/validation/small-size-dark.svg" "$validation_dir/small-size-dark.svg"

(
  cd "$brand_dir"
  find . -type f ! -name SHA256SUMS.txt -print \
    | LC_ALL=C sort \
    | while IFS= read -r path; do
        /usr/bin/shasum -a 256 "$path"
      done \
    > SHA256SUMS.txt
)

print "Generated Lerro Brand Kit assets in $brand_dir"
print "Synchronized Lerro runtime icon resources in $app_resources_dir"
