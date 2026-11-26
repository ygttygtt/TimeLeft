#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="$PWD/dist.noindex/TimeLeft.app"

icon_dir="$(mktemp -d)"
iconset="$icon_dir/AppIcon.iconset"
mkdir "$iconset"
trap 'rm -f "$iconset"/*.png; rmdir "$iconset" "$icon_dir"' EXIT

for size in 16 32 128 256 512; do
    retina=$((size * 2))
    sips -z "$size" "$size" Packaging/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$retina" "$retina" Packaging/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$bin_dir/TimeLeft" "$app/Contents/MacOS/TimeLeft"
install -m 644 Packaging/Info.plist "$app/Contents/Info.plist"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
