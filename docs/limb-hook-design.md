# Limb hook for every NPC (design note)

Written 2026-10-22. This pack's dismemberment (`runtime/zhm_limbs.gd`, `view/zhm_gibs.gd`) works for any skinned model whose limbs are bones, and the pieces are generic. They belong in dot-npc (state and the seam) and dot-combat (the shot test), not in this pack. Neither repository was edited here.

What exists today: dot-combat's `DotHitbox` has a `group` and an `enabled` flag, documented as "for a limb that has been destroyed", but nothing turns an enabled flag off or draws the loss. Zombie Zone's zombie body and view have no severing at all (grep for sever, dismember, limb finds nothing there).

Proposed split:

- dot-combat: `DotHitbox.limb: StringName` and a signal on the entity's health when a hitbox's accumulated damage passes `limb_health`; the hitbox disables itself and emits `limb_severed(limb, point, impulse)`. A shot already resolves to a `DotHitbox`, so no region test is needed there.
- dot-npc: `DotNpcLimbs`, the node in this pack made generic: per-definition `limbs` (bones, health, kills, slow, attack) read through `DotAddonConfig`, `mask()` and `apply_mask()` for `DotNpcNetSync` (one `net_limbs` field), and `speed_scale()` for brains.
- Presentation (a small addon or dot-fx): the gib builder in `view/zhm_gibs.gd` (cut a limb out of a skinned mesh by vertex weight, collapse the root bone, stump and blood), which has no game knowledge.

Until then a game with its own hit regions calls `body.zhm_limb_hit(point, damage)` on a monster body. Zombie Zone's common and special zombies would use the same three pieces; their skeletons need a yml listing bones per limb.
