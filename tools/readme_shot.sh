#!/usr/bin/env bash
# tools/readme_shot.sh [--ids a,b | --data]: the README studio shots, one PNG per monster and pose, into
# screenshots/readme/. A GPU job: heavy routes tools/*_shot.sh to staging02/staging, never llvmpipe. Run it through
# tools/gen_readme.sh, which copies the shared studio (../gs-bootstrap/tools/readme/) into tools/readme_studio/
# first, because a GPU box gets this pack's tree and no sibling repositories.
cd "$(dirname "$0")/.." || exit 2
if [[ -x tools/readme_studio/shot.sh ]]; then exec tools/readme_studio/shot.sh "$@"; fi
exec ../gs-bootstrap/tools/readme/shot.sh "$@"
