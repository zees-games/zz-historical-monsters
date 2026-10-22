# zz-historical-monsters

Read the family [CLAUDE.md](../../CLAUDE.md) first. Three infected animals (T-Rex, tiger, bear) on dot-npc and dot-npc-ai. See README.md for what they do.

- No `class_name` in pack-loaded scripts (`runtime/`, `view/`, `spawn_provider.gd`): they extend and preload by path. `core/` has class names.
- Every attack is a telegraph then a landing against whoever is still in range; charge and pounce lock direction. All numbers live in the yml and `core/zhm_config.gd`.
- Damage leaves through the host seam (`zhm_*`); never import a combat addon.
- Models are build products: `tools/build_monsters.sh` from `art-src/base/`. Poses are procedural bone rotations (`view/zhm_pose.gd`); the base models are static.
- A server draws nothing: `ZhmView` does nothing in `_process` headless.
- Replication is data in `core/zhm_net_sync.gd`; the pack never names dot-net (only `examples/zhm_net*.gd` does, and links it for the suite). Tests: `./game.sh --no-parse test zhm_selftest` and `zhm_net`. Looks: `GPU_OFFLOAD=0 tools/screenshot.sh`.
