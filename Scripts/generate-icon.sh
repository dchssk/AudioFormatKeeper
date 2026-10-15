#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOURCE_ICON="$PROJECT_ROOT/Assets/AppIcon.png"
OUTPUT_ICON="$PROJECT_ROOT/Assets/AppIcon.icns"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/audioformatkeeper-icon.XXXXXX")"
ICONSET_PATH="$TEMP_ROOT/AppIcon.iconset"

trap 'rm -rf "$TEMP_ROOT"' EXIT

if [[ ! -f "$SOURCE_ICON" ]]; then
    echo "Missing icon master: $SOURCE_ICON" >&2
    exit 1
fi

mkdir -p "$ICONSET_PATH"

render_icon() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET_PATH/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_PATH" -o "$OUTPUT_ICON"
echo "$OUTPUT_ICON"
