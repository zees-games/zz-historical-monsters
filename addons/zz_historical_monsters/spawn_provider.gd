extends RefCounted

## Puts the three monsters in a game's spawn menu (game-playground's Q menu, and any host that
## reads `res://addons/<pack>/spawn_provider.gd`). Duck-typed and `class_name`-free, as the contract
## asks: a mounted pack's globals do not register.
##
## Each entry's `spawn` is a Callable the server runs with the context
## `{game, world, player_id, at, kind, cfg_hint, authoritative}`. It puts the monster in the game's
## own world under a [ZhmRuntime] (created once), so the entries need nothing from the game but a
## world node and a point. Damage to players leaves through the runtime's host: until a game gives
## it its own (`runtime.host = ...`, the three `zhm_*` methods) the monsters chase and the hits are
## recorded and signalled, which is honest about what is not wired yet.
##
## [b]Limits.[/b] `cfg_hint.count` (1 to 3, default 1) is honoured; the tiger and bear can come in
## small numbers, the T-Rex is capped at one per request because its `cost` in the catalogue is
## the game's budget and a menu that spawns five of them is a griefing tool.

const Config := preload("core/zhm_config.gd")
const Catalogue := preload("core/zhm_catalogue.gd")
const Runtime := preload("core/zhm_runtime.gd")
const CHANNEL := "zhm.spawn"
const MAX_ALIVE := 6


func spawn_entries() -> Array[Dictionary]:
	var cfg := Config.load_config()
	var out: Array[Dictionary] = []
	for sp in Config.SPECIES:
		var c := cfg.species(sp)
		out.append({
			"category": "NPCs",
			"id": String(Catalogue.id_of(sp)),
			"name": str(c.get("name", String(sp))),
			"icon": "res://addons/zz_historical_monsters/icons/%s.png" % String(sp),
			"kind": "npc",
			"spawn": _spawn.bind(sp),
			"cfg_hint": {
				"count": 1,
				"health": c.get("health"),
				"special": {"trex": "roar stun, tail sweep, charge", "tiger": "pounce, bleed", "bear": "maul combo, ground slam"}.get(String(sp), ""),
			},
		})
	return out


## Runs on the server. Returns a DotResult (the contract allows it).
func _spawn(ctx: Dictionary, species: StringName) -> Variant:
	if not bool(ctx.get("authoritative", false)):
		return DotResult.fail(DotError.CODE_INVALID, "Monsters are spawned by the server.")
	var world: Variant = ctx.get("world")
	if not (world is Node) or not is_instance_valid(world):
		return DotResult.fail(DotError.CODE_INVALID, "No world to put a monster in.")

	var runtime: Object = Runtime.find_or_create(world as Node)
	if runtime.spawner.world_count() >= MAX_ALIVE:
		return DotResult.fail(DotError.CODE_INVALID, "Too many monsters already.")

	var at: Vector3 = ctx.get("at", Vector3.ZERO)
	var hint: Variant = ctx.get("cfg_hint", {})
	var count := clampi(int((hint as Dictionary).get("count", 1)) if hint is Dictionary else 1, 1, 1 if species == &"trex" else 3)
	var made := 0
	for i in count:
		var spot := at + Vector3(float(i) * 2.5, 0.0, 0.0)
		if runtime.call(&"spawn", species, spot, StringName(str(ctx.get("player_id", &"")))) != null:
			made += 1
	DotLog.info(CHANNEL, "spawn menu asked for monsters", {"species": String(species), "made": made, "by": str(ctx.get("player_id", ""))})
	if made == 0:
		return DotResult.fail(DotError.CODE_INVALID, "The monster could not be spawned there.")
	return DotResult.success(made)
