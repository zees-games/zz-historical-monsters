#!/usr/bin/env bash
# tools/gen_readme.sh [--ids a,b | --data | --text | --check]: regenerate the README's monster gallery (studio
# renders on a GPU box, profile tables from the pack's own config). The driver is shared:
# ../dot-bootstrap/tools/readme/gen_readme.sh, which documents every flag. Look at every image before committing.
cd "$(dirname "$0")/.." && exec ../dot-bootstrap/tools/readme/gen_readme.sh "$@"
