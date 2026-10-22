# Design notes

Reasoning moved out of code comments so the scripts stay short. Each entry names the file it came from.

## Telegraph, then landing (runtime/zhm_brain.gd)

Every attack winds up for `windup` seconds while the animation shows it coming, and the effect is applied at the end against whoever is still in range then. A player who moves in time takes nothing, which makes a roar, a tail sweep and a pounce things to react to rather than things that happen to you. The pounce and the charge move the monster: they lock a direction when they start, so they can be sidestepped as well. Effects reach the game only through the host's three methods, so Zombie Zone, Playground and a game with neither differ only in the host. The brain is server-authoritative like every NPC: a client sees `body.action` replicate and draws a clip, and never decides a hit.

## Replication (core/zhm_net_sync.gd)

Before `ZhmNetSync`, monsters existed only on the server: a connected player was mauled by something nobody drew, and `body.action` (which picks the clip) never left the machine that decided it. The fields are dot-npc's own (position, yaw, health, state) plus the species to build, and what the body is doing. See dot-npc's runtime doc for why replication is never predicted.

## Why the headless server draws nothing (view/zhm_view.gd, runtime/zhm_body.gd)

The body's simulation does not read the pose back, and the skeletons of a thirty-monster horde are not worth a server's tick, so `_process` does nothing under the headless display driver and no model loads. Only `action`, one small integer, replicates.

## Pose axes (view/zhm_pose.gd)

The base models are static meshes, so every clip is code. `_lift` is a fraction of the body's height and `_lunge` of its length. No assertion reaches a pose; look at one with `tools/screenshot.sh`.

## Wetness (view/zhm_view.gd, tools/build_monsters.py)

COLOR_0's alpha is wetness (0 dry hide, 1 fresh flesh and gut). Per-vertex wetness fades smoothly across a wound's edge, where a second glossy material would have had to be chosen per triangle and turned every wound rim into a row of teeth. Only the wet part is glossy and faintly self-lit, so a wound still reads in a dim room.

## Config by reflection (core/zhm_config.gd)

`DotAddonConfig` landed in dot-core after this pack's first consumers pinned it. Naming it would make the file fail to parse against theirs, and a config class that cannot parse is a pack that cannot load at all, so the script is loaded by path and `load_dir` is called on it. A windup being the telegraph is the whole of fair melee, and is why every ability's range is rechecked when it lands.

## Spawn provider (spawn_provider.gd)

Zombie Zone's `ZzPacks` draws a monster as one of its own zombie bodies, so the client needs no scene of ours: the big two as the brute, the cat as the leaper. The play menu's Callable moved to `spawn_fn` because the pack scan's `spawn` key could not be both.
