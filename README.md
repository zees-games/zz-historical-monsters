# Zee's Historical Monsters

An addon (`zz_historical_monsters`) with six infected, mutated animals that chase and kill players: a T-Rex, an allosaurus, a raptor, a tiger, a thylacine and a bear. Every limb, the head included, can be shot off (docs/limb-hook-design.md). It works in Zombie Zone and in any game through Dot (`games: ["*"]`).

| Monster | Specials (server-authoritative, each telegraphed) |
| --- | --- |
| T-Rex | roar (stuns everyone in range), tail sweep (everyone close), charge (locks a line, hits once, then staggers) |
| Tiger | pounce (a locked leap that lands on whoever is still there) and a stacking bleed that outlives the fight |
| Allosaurus | as the T-Rex, slower and heavier |
| Raptor | as the T-Rex, fast and light (a leaper) |
| Thylacine | as the tiger: pounce and bleed |
| Bear | maul (a three-swing combo) and ground slam (falloff by distance, stuns) |

Built on dot-npc and dot-npc-ai; everything logs through `DotLog` on `zhm.*` channels.

## Configuration

Every number is in `cfg/addons/zz_historical_monsters/<name>.yml` (every yml in the directory is read; keys are `trex`, `tiger`, `bear`), through dot-core's `DotAddonConfig`. A missing file or key falls back to the built-in defaults in `core/zhm_config.gd`.

## Dismemberment

Heads and limbs can be shot off. Each species lists its `limbs:` in its yml (region = the line through `bones` plus `tip` metres, `radius` thick; `health` is damage the limb takes before it comes off; `kills` on the head ends the monster; `slow` and `attack` multiply speed and damage once a limb is gone). A game's shot code calls, on the server, `body.zhm_limb_hit(world_point, damage, impulse)` beside the damage it does to the monster, and gets back the limb that came off (or `&""`). On the drawn body the limb's root bone collapses, a raw stump with a drip covers the cut, and the limb's own triangles tumble away as a gib with a blood burst. Which limbs are gone replicates as `net_limbs`, one bit per limb in config order. The machinery is dot-npc's generic `DotNpcLimbs` and `DotNpcGibs` ([docs/limb-hook-design.md](docs/limb-hook-design.md)); this pack supplies only the species yml and models.

## Hooking it into a game

- Spawn menu: `addons/zz_historical_monsters/spawn_provider.gd` returns `spawn_entries()` (static): `spawn` is `{health, speed, damage, reach, body, boss?}` for Zombie Zone, the play menu Callable is `spawn_fn`.
- Damage: the monsters report to a host with `zhm_targets()`, `zhm_hit(npc, victim, amount, kind, info)` and `zhm_status(victim, status, seconds, info)`, given as the spawner's meta `zhm_host` (or `ZhmRuntime.host`). Without one they chase and the hits are recorded and signalled (`ZhmHost`).

## Credits and licences

See [CREDITS.md](CREDITS.md). Base models are Quaternius (CC0) and Poly by Google (CC-BY 3.0), both from Poly Pizza (T-Rex https://poly.pizza/m/UYtneO5FpF, tiger https://poly.pizza/m/5A3w06FXUup, bear "Black bear" https://poly.pizza/m/56ym_pyVnel). Sketchfab's "Free Standard" licence is not a Creative Commons licence, so no Sketchfab model was used; Poly Pizza models under CC0 and CC-BY were substituted.

## Checks

`./game.sh test` runs the parse pass and the self-test scene (71 checks). Looks: `tools/screenshot.sh --all` (set `GPU_OFFLOAD=0` to render locally).

## Replication

Monsters are server-authoritative. `ZhmNetSync` (`core/zhm_net_sync.gd`) describes what crosses the wire as data (dot-npc's position, yaw, health and state, plus species, action and variant) and never names dot-net: the host's net behaviour declares one field per `ZhmNetSync.specs()` entry, calls `pull(npc, body, self)` on the server each tick, and on a client builds the body with `make_mirror(net_species)` and calls `apply(body, self)`. `examples/zhm_net_behaviour.gd` is the whole of that wiring, and `examples/zhm_net.tscn` proves it between two peers (it links dot-net, for the suite only).
