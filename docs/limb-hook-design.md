# Limb hook for every NPC

Implemented 2026-10-22 in dot-npc (API level 5). This pack's copy was removed; it now drives the generic one.

- `DotNpcLimbs` (dot-npc `runtime/`): a node a body owns. `setup(id, defs, view)`, `hit(world_point, damage, impulse)` (server), `limb_at`, `sever`, `mask()` / `apply_mask()` (client), `speed_scale()`, `attack_scale()`, `is_lethal()` (a severed limb with `kills: true`), signal `severed(limb, info)`. Regions are lines through bone origins, `radius` thick; a server without a model reads the rest pose from `rest_model` (a scene path), a drawn body uses its live `skeleton`.
- `DotNpcGibs` (dot-npc `view/`): cuts the limb out of the skinned mesh by vertex weight, collapses its root bone, adds a stump and blood. Drawn only.
- `DotNpcNetSync.limb_specs()`: the one `net_limbs` field (8 bits, one per limb in config order). Fill it from `mask()` and apply with `apply_mask()`.
- Tuning: `limbs: {<definition id>: {<limb>: {bones, radius, tip, health, kills, slow, attack, damage_scale}}}` in `cfg/addons/dot-npc/*.yml`, read by `DotNpcLimbs.defs_from_config(id)`; a pack may keep the numbers in its own addon yml (this one does) and pass them to `setup`.

Not done: the `DotHitbox.limb` field in dot-combat. dot-npc must not import dot-combat, so the shot test is a world point handed to `hit`; a game that resolves a shot to a `DotHitbox` can pass the hit point and ignore hitbox groups.

## What game-zombie-zone must do (nightly item `zz-zombie-dismember-1`)

1. Add `limbs:` for `zombie` (and each special) to `cfg/addons/dot-npc/limbs.yml`, listing bones per limb from the skinned zombie skeleton (head first, `kills: true`).
2. In `npcs/zz_zombie_body.gd`, add a `DotNpcLimbs` child, `rest_model` set to the zombie scene, `setup(def_id, DotNpcLimbs.defs_from_config(def_id), view)`; give it the view's `skeleton` and `model`, or a `sever_limb` method on the view that calls `DotNpcGibs.sever`.
3. Route hitscan and projectile hits on a zombie body to `limbs.hit(point, damage, impulse)` on the server, beside the damage it already does.
4. On `severed` with `is_lethal()`, kill through the director's damage path; multiply the zombie's speed by `speed_scale()` and its attack by `attack_scale()`.
5. Replicate `net_limbs` with `DotNpcNetSync.limb_specs()`.
