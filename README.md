# zz-historical-monsters

Six infected, mutated animals that chase and kill players: a T-Rex, an allosaurus, a raptor, a tiger, a thylacine and a bear. Every limb, the head included, can be shot off. Made for Zombie Zone and usable in any game through Dot (`games: ["*"]`). The addon is `addons/zz_historical_monsters`. It is built on dot-npc and dot-npc-ai.

| Monster | Specials (server-side, each warned before it lands) |
| --- | --- |
| T-Rex | roar (stuns everyone in range), tail sweep (everyone close), charge (locks a line, hits once, then staggers) |
| Tiger | pounce (a locked leap that lands on whoever is still there) and a stacking bleed that outlives the fight |
| Allosaurus | as the T-Rex, slower and heavier |
| Raptor | as the T-Rex, fast and light |
| Thylacine | as the tiger: pounce and bleed |
| Bear | maul (a three-swing combo) and ground slam (stuns, weaker with distance) |

## Using it

- Spawn menu: `addons/zz_historical_monsters/spawn_provider.gd` has a static `spawn_entries()`. Each entry's `spawn` is `{health, speed, damage, reach, body, boss?}`.
- Damage: the monsters report to a host through `zhm_targets()`, `zhm_hit(npc, victim, amount, kind, info)` and `zhm_status(victim, status, seconds, info)`. Give the host as the spawner's meta `zhm_host` (or `ZhmRuntime.host`). Without one, monsters still chase, and their hits are recorded and signalled (`ZhmHost`).
- Logging goes through `DotLog` on `zhm.*` channels.

## Settings

Every number is in `cfg/addons/zz_historical_monsters/<name>.yml`, one file per species (`trex`, `tiger`, `bear`, `raptor`, `allosaurus`, `thylacine`). A missing file or key falls back to the defaults in `core/zhm_config.gd`.

## Shooting off limbs

Each species lists its `limbs:` in its yml:

| Key | Meaning |
| --- | --- |
| `bones`, `tip`, `radius` | The region: the line through the bones plus `tip` metres, `radius` thick |
| `health` | Damage the limb takes before it comes off |
| `kills` | On the head: losing it ends the monster |
| `slow`, `attack` | Multipliers on speed and damage once the limb is gone |

A game's shot code calls `body.zhm_limb_hit(world_point, damage, impulse)` on the server, beside the damage it does to the monster. It returns the limb that came off, or `&""`. The limb's stump collapses, the cut drips, and the limb tumbles away as a gib with a blood burst. Which limbs are gone replicates as `net_limbs`, one bit per limb in config order. The machinery is dot-npc's `DotNpcLimbs` and `DotNpcGibs`; see [docs/limb-hook-design.md](docs/limb-hook-design.md).

## Networking

Monsters are decided by the server. `ZhmNetSync` (`core/zhm_net_sync.gd`) lists what goes over the wire as plain data and never names dot-net. The host's net behaviour declares one field per `ZhmNetSync.specs()` entry, calls `pull(npc, body, self)` on the server each tick, and on a client builds the body with `make_mirror(net_species)` and calls `apply(body, self)`. `examples/zhm_net_behaviour.gd` is the whole wiring.

## Testing

`./game.sh test` runs the parse pass and the suites `zhm_selftest`, `zhm_net` and `zhm_shoot`. `tools/screenshot.sh --all` renders every monster (set `GPU_OFFLOAD=0` to render locally).

## Credits

Every shipped model is a modified build product of the sources in `art-src/base/`, made by `tools/build_monsters.py` (Blender, headless): recoloured and wounded, with ribs, spurs, teeth and glowing eyes, decimated for the web. Textures are baked PNGs beside each `.glb`. Sketchfab "Free Standard" models are not used, because that is not a Creative Commons licence. Details and change notes are in [CREDITS.md](CREDITS.md). The code is MIT, see [LICENSE](LICENSE).

| Monster | Base model | Author | Licence | Source |
| --- | --- | --- | --- | --- |
| T-Rex | T-Rex | Quaternius | CC0 1.0 | [Poly Pizza](https://poly.pizza/m/UYtneO5FpF) |
| Tiger | Tiger | Poly by Google | CC BY 3.0 | [Poly Pizza](https://poly.pizza/m/5A3w06FXUup) |
| Bear | Black bear | Poly by Google | CC BY 3.0 | [Poly Pizza](https://poly.pizza/m/56ym_pyVnel) |
| Raptor | Velociraptor (reuploaded and retextured) | seth the yutyrannus | CC BY 4.0 | [Sketchfab](https://sketchfab.com/3d-models/velociraptor-reuploaded-and-retextured-def52bae17f749b0b911a695fdb05218) |
| Allosaurus | Allosaurus | seth the yutyrannus | CC BY 4.0 | [Sketchfab](https://sketchfab.com/3d-models/allosaurus-02e651e39fed47bbaec0aa0546f17fd3) |
| Thylacine | wolf (a Tasmanian wolf, striped) | victory_mirosya | CC BY 4.0 | [Sketchfab](https://sketchfab.com/3d-models/wolf-c5c2c9b77df94d758e732237a7d98af0) |
