#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
svg="$root/Packaging/icon.svg"
icns="$root/Packaging/AppIcon.icns"

if [[ ! -f "$svg" ]]; then
  echo "没有找到 $svg" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# icon.svg 带 prefers-color-scheme: dark → 白填充。做 App Icon 时去掉，固定为黑色。
flat="$tmp/icon-black.svg"
python3 - "$svg" "$flat" <<'PY'
from pathlib import Path
import re
import sys
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
text = src.read_text()
text = re.sub(r"<style>.*?</style>", "", text, flags=re.S)
text = text.replace('fill="#000"', 'fill="#000000"')
dest.write_text(text)
PY

glyph="$tmp/glyph.png"
rsvg-convert -w 768 -h 768 --background-color none "$flat" -o "$glyph"

master="$tmp/icon_1024.png"
magick -size 1024x1024 xc:white "$glyph" -gravity center -composite PNG32:"$master"

iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"

render() {
  local size="$1"
  local name="$2"
  magick "$master" -resize "${size}x${size}" PNG32:"$iconset/$name"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$iconset" -o "$icns"
echo "Wrote $icns"
