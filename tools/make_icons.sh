#!/usr/bin/env bash
#
# The spawn menu's icons: each monster whole, three-quarter view, idle, from the real renderer, cropped square
# and scaled to 128 px (ImageMagick). Run, then look at every PNG (the crop is a fixed box).
#
#   tools/make_icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."
command -v convert >/dev/null || { echo "ImageMagick not installed" >&2; exit 3; }
OUT=screenshots tools/screenshot.sh --all --anims idle --cam three --t 0.5 >/dev/null
for sp in trex allosaurus raptor tiger thylacine bear; do
    convert "screenshots/three_${sp}_idle.png" -crop 640x640+350+60 +repage -resize 128x128 "addons/zz_historical_monsters/icons/${sp}.png"
done
