#!/bin/bash
# Publishes this pack to the gs-cloud CDN. Linked addons and README art stay out.
#   tools/publish.sh VERSION [extra publish_pack.sh flags, e.g. --token-file F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [flags]}; shift
exec "$HERE/../gs-cloud/tools/publish_pack.sh" publish --source "$HERE" --id zz-historical-monsters --version "$V" \
    --exclude-dir gs_combat --exclude-dir gs_core --exclude-dir gs_net --exclude-dir gs_npc --exclude-dir gs_npc_ai --exclude-dir gs_profile --exclude-dir examples --exclude-dir tools --exclude-dir screenshots --exclude-dir docs --exclude-dir art-src --exclude-dir reports \
    --lock "$HERE/content.lock.json" "$@"
