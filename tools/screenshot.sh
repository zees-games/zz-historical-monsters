#!/usr/bin/env bash
#
# Render a monster and save frames, so a person can look at it.
#
#   tools/screenshot.sh trex                          # screenshots/trex_<clip>.png, a few clips
#   tools/screenshot.sh tiger --anims idle,bite,leap --cam head --t 0.3
#   tools/screenshot.sh --all                         # every monster, idle, three-quarter view
#   tools/screenshot.sh --sheet trex                  # one contact sheet: views x clips
#   tools/screenshot.sh trex --sever head,legL --cam side   # with those limbs shot off
#   OUT=/tmp/x tools/screenshot.sh bear --anims maul --variant 1
#
# Clips are stepped at a fixed 60 fps for --t seconds (default 0.5), so the same frame is the same
# picture every run. Not --headless: Godot's headless driver does no rendering and saves a black
# PNG. This runs the real renderer on an Xvfb framebuffer (Mesa llvmpipe).
#
# Everything about a monster's look is shape, colour and motion, and no assertion reaches any of
# them. Touch a model or a pose, run this, look.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed (apt install xvfb)" >&2; exit 3; }

OUT_DIR="${OUT:-screenshots}"
mkdir -p "$OUT_DIR"; touch screenshots/.gdignore 2>/dev/null || true
SPECIES=(); ANIMS="idle,walk,bite"; CAM="three"; T="0.5"; VARIANT=0; SHEET=0; SEVER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --all) SPECIES=(trex tiger bear); shift ;;
        --anims) ANIMS="$2"; shift 2 ;;
        --cam) CAM="$2"; shift 2 ;;
        --t) T="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        --sheet) SHEET=1; shift ;;
        --sever) SEVER="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^set/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) SPECIES+=("$1"); shift ;;
    esac
done
[ ${#SPECIES[@]} -gt 0 ] || SPECIES=(trex)

shoot() {  # species cam anims t prefix
    local disp=$((90 + RANDOM % 8))
    Xvfb ":$disp" -screen 0 "1280x720x24" >/dev/null 2>&1 &
    local xpid=$!
    sleep 1.5
    DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1 timeout 180 godot --path . --resolution 1280x720 \
        --rendering-driver opengl3 res://examples/zhm_gallery.tscn -- \
        --species "$1" --cam "$2" --anims "$3" --t "$4" --variant "$VARIANT" --sever "$SEVER" --out "$5" 2>&1 \
        | grep -i "error\|wrote" 
    kill "$xpid" 2>/dev/null
}

for sp in "${SPECIES[@]}"; do
    if [ "$SHEET" = 1 ]; then
        for cam in three side front head; do
            shoot "$sp" "$cam" "$ANIMS" "$T" "$OUT_DIR/sheet_$cam"
        done
    else
        shoot "$sp" "$CAM" "$ANIMS" "$T" "$OUT_DIR/$CAM"
    fi
done
