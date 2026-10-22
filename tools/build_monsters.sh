#!/usr/bin/env bash
# Rebuild the monster models from their base models. Usage: tools/build_monsters.sh [species...]
set -euo pipefail
cd "$(dirname "$0")/.."
declare -A BASE=([trex]=trex_quaternius [tiger]=tiger_polygoogle [bear]=bear_polygoogle [allosaurus]=allosaurus_sketchfab [raptor]=raptor_sketchfab [thylacine]=thylacine_sketchfab)
SP=("$@"); [ ${#SP[@]} -gt 0 ] || SP=(trex allosaurus raptor tiger thylacine bear)
for s in "${SP[@]}"; do
    blender -b --factory-startup --python tools/build_monsters.py -- "$s" "art-src/base/${BASE[$s]}.glb" \
        "addons/zz_historical_monsters/monsters/$s.glb" 2>&1 | grep -E "BUILT|Error|Traceback" || true
done
