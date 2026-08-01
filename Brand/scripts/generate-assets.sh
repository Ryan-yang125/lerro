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
  "$exports_dir/logo" \
  "$exports_dir/app-icon" \
  "$exports_dir/menu-bar" \
  "$templates_dir" \
  "$validation_dir"

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

copy_and_render_logo lerro-symbol 64 64 512 512
copy_and_render_logo lerro-symbol-monochrome 64 64 512 512
copy_and_render_logo lerro-symbol-reversed 64 64 512 512
copy_and_render_logo lerro-micro-16 16 16 16 16
copy_and_render_logo lerro-micro-24 24 24 24 24
copy_and_render_logo lerro-wordmark 220 64 880 256
copy_and_render_logo lerro-lockup-horizontal 300 80 1200 320
copy_and_render_logo lerro-lockup-horizontal-dark 300 80 1200 320
copy_and_render_logo lerro-lockup-vertical 180 180 720 720
copy_and_render_logo lerro-construction 640 400 1280 800

app_icon_source="$source_dir/app-icon/lerro-app-icon.svg"
app_icon_mono_source="$source_dir/app-icon/lerro-app-icon-monochrome.svg"
/bin/cp "$app_icon_source" "$exports_dir/app-icon/lerro-app-icon.svg"
/bin/cp "$app_icon_mono_source" "$exports_dir/app-icon/lerro-app-icon-monochrome.svg"
render_pdf "$app_icon_source" "$exports_dir/app-icon/lerro-app-icon.pdf" 1024 1024
render_pdf "$app_icon_mono_source" "$exports_dir/app-icon/lerro-app-icon-monochrome.pdf" 1024 1024
render_png "$app_icon_source" "$exports_dir/app-icon/lerro-app-icon-1024.png" 1024 1024
render_png "$app_icon_mono_source" "$exports_dir/app-icon/lerro-app-icon-monochrome-1024.png" 1024 1024

iconset="$exports_dir/app-icon/Lerro.iconset"
find "$iconset" -depth -delete 2>/dev/null || true
mkdir -p "$iconset"
render_png "$app_icon_source" "$iconset/icon_16x16.png" 16 16
render_png "$app_icon_source" "$iconset/icon_16x16@2x.png" 32 32
render_png "$app_icon_source" "$iconset/icon_32x32.png" 32 32
render_png "$app_icon_source" "$iconset/icon_32x32@2x.png" 64 64
render_png "$app_icon_source" "$iconset/icon_128x128.png" 128 128
render_png "$app_icon_source" "$iconset/icon_128x128@2x.png" 256 256
render_png "$app_icon_source" "$iconset/icon_256x256.png" 256 256
render_png "$app_icon_source" "$iconset/icon_256x256@2x.png" 512 512
render_png "$app_icon_source" "$iconset/icon_512x512.png" 512 512
render_png "$app_icon_source" "$iconset/icon_512x512@2x.png" 1024 1024
/usr/bin/iconutil -c icns "$iconset" -o "$exports_dir/app-icon/Lerro.icns"

for state in idle listening processing error; do
  source="$source_dir/menu-bar/lerro-menubar-$state.svg"
  /bin/cp "$source" "$exports_dir/menu-bar/lerro-menubar-$state.svg"
  render_pdf "$source" "$exports_dir/menu-bar/lerro-menubar-$state.pdf" 24 24
  render_png "$source" "$exports_dir/menu-bar/lerro-menubar-$state-16.png" 16 16
  render_png "$source" "$exports_dir/menu-bar/lerro-menubar-$state-16@2x.png" 32 32
  render_png "$source" "$exports_dir/menu-bar/lerro-menubar-$state-24.png" 24 24
  render_png "$source" "$exports_dir/menu-bar/lerro-menubar-$state-24@2x.png" 48 48
  state_title=${(C)state}
  render_png "$source" "$exports_dir/menu-bar/LerroMenu${state_title}Template.png" 18 18
  render_png "$source" "$exports_dir/menu-bar/LerroMenu${state_title}Template@2x.png" 36 36
done

[[ -d "$app_resources_dir/MenuBar" ]] || {
  print -u2 "Missing Lerro app resource directory: $app_resources_dir/MenuBar"
  exit 1
}
/bin/cp "$exports_dir/app-icon/Lerro.icns" "$app_resources_dir/icon.icns"
for state in idle listening processing error; do
  state_title=${(C)state}
  /bin/cp \
    "$exports_dir/menu-bar/LerroMenu${state_title}Template.png" \
    "$app_resources_dir/MenuBar/LerroMenu${state_title}Template.png"
  /bin/cp \
    "$exports_dir/menu-bar/LerroMenu${state_title}Template@2x.png" \
    "$app_resources_dir/MenuBar/LerroMenu${state_title}Template@2x.png"
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
