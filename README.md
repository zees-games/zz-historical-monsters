# Zee's Historical Monsters

An addon (`zz_historical_monsters`) with three infected, mutated animals that chase and kill players: a T-Rex, a tiger and a bear. It works in Zombie Zone and in any game through Dot (`games: ["*"]`).

| Monster | Specials (server-authoritative, each telegraphed) |
| --- | --- |
| T-Rex | roar (stuns everyone in range), tail sweep (everyone close), charge (locks a line, hits once, then staggers) |
| Tiger | pounce (a locked leap that lands on whoever is still there) and a stacking bleed that outlives the fight |
| Bear | maul (a three-swing combo) and ground slam (falloff by distance, stuns) |

Built on dot-npc and dot-npc-ai; everything logs through `DotLog` on `zhm.*` channels.

## Configuration

Every number is in `cfg/addons/zz_historical_monsters/<name>.yml` (every yml in the directory is read; keys are `trex`, `tiger`, `bear`), through dot-core's `DotAddonConfig`. A missing file or key falls back to the built-in defaults in `core/zhm_config.gd`.

## Hooking it into a game

- Spawn menu: `addons/zz_historical_monsters/spawn_provider.gd` returns `spawn_entries()` in the contract's shape.
- Damage: the monsters report to a host with `zhm_targets()`, `zhm_hit(npc, victim, amount, kind, info)` and `zhm_status(victim, status, seconds, info)`, given as the spawner's meta `zhm_host` (or `ZhmRuntime.host`). Without one they chase and the hits are recorded and signalled (`ZhmHost`).

## Credits and licences

See [CREDITS.md](CREDITS.md). Base models are Quaternius (CC0) and Poly by Google (CC-BY 3.0), both from Poly Pizza (T-Rex https://poly.pizza/m/UYtneO5FpF, tiger https://poly.pizza/m/5A3w06FXUup, bear "Black bear" https://poly.pizza/m/56ym_pyVnel). Sketchfab's "Free Standard" licence is not a Creative Commons licence, so no Sketchfab model was used; Poly Pizza models under CC0 and CC-BY were substituted.

## Checks

`./game.sh test` runs the parse pass and the self-test scene (71 checks). Looks: `tools/screenshot.sh --all` (set `GPU_OFFLOAD=0` to render locally).

## Replication

Monsters are server-authoritative. `ZhmNetSync` (`core/zhm_net_sync.gd`) describes what crosses the wire as data (dot-npc's position, yaw, health and state, plus species, action and variant) and never names dot-net: the host's net behaviour declares one field per `ZhmNetSync.specs()` entry, calls `pull(npc, body, self)` on the server each tick, and on a client builds the body with `make_mirror(net_species)` and calls `apply(body, self)`. `examples/zhm_net_behaviour.gd` is the whole of that wiring, and `examples/zhm_net.tscn` proves it between two peers (it links dot-net, for the suite only).
