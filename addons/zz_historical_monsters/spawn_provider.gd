extends RefCounted

## Puts the three monsters in a game's spawn menu. Duck-typed and `class_name`-free, as the contract asks
## (a mounted pack's globals do not register). Each entry's `spawn_fn` runs on the server with
## `{game, world, player_id, at, kind, cfg_hint, authoritative}` and spawns under a [ZhmRuntime] (created once);
## until a game sets `runtime.host`, hits are only recorded and signalled.
## `cfg_hint.count` (1 to 3) is honoured; the T-Rex is capped at one per request because its catalogue `cost`
## is the game's budget and five at once is a griefing tool.

const Config := preload("core/zhm_config.gd")
const Catalogue := preload("core/zhm_catalogue.gd")
const Runtime := preload("core/zhm_runtime.gd")
const CHANNEL := "zhm.spawn"
const MAX_ALIVE := 6


## Zombie Zone's body for each species (its `ZzPacks` draws a monster as one of its own zombie
## bodies, so the client needs no scene of ours): the big two as the brute, the cat as the leaper.
## The basic attack's section in the yml, per species.
const ATTACKS := {&"trex": "bite", &"allosaurus": "bite", &"raptor": "bite", &"tiger": "claw", &"thylacine": "claw", &"bear": "maul"}
const BODIES := {&"trex": "brute", &"allosaurus": "brute", &"raptor": "leaper", &"tiger": "leaper", &"thylacine": "leaper", &"bear": "brute"}


## Static, because a host may call it on the script or on an instance of it.
## `spawn` is the shape Zombie Zone's pack scan reads, `{health, speed, damage, reach, body, boss?}` (no
## `brain`: the game's own chase and bite). The menu's Callable is `spawn_fn`; one key cannot be both.
static func spawn_entries() -> Array[Dictionary]:
	var cfg := Config.load_config()
	var out: Array[Dictionary] = []
	for sp in Config.SPECIES:
		var c := cfg.species(sp)
		var hit := String(ATTACKS.get(sp, "bite"))
		var shape := {
			"health": float(c.get("health", 200.0)),
			"speed": cfg.get_num(sp, "run_speed", 4.4),
			"damage": cfg.get_num(sp, hit + ".damage", 8.0),
			"reach": cfg.get_num(sp, hit + ".reach", 1.6),
			"body": String(BODIES.get(sp, "common")),
		}
		if sp == &"trex":
			shape["boss"] = true
		out.append({
			"category": "NPCs",
			"id": String(Catalogue.id_of(sp)),
			"name": str(c.get("name", String(sp))),
			"icon": "res://addons/zz_historical_monsters/icons/%s.png" % String(sp),
			"kind": "npc",
			"spawn": shape,
			"spawn_fn": Callable(load("res://addons/zz_historical_monsters/spawn_provider.gd"), &"_spawn").bind(sp),
			"cfg_hint": {
				"count": 1,
				"health": c.get("health"),
				"special": {"trex": "roar stun, tail sweep, charge", "allosaurus": "roar stun, tail sweep, charge", "raptor": "lunge, tail whip", "tiger": "pounce, bleed", "thylacine": "pounce, bleed", "bear": "maul combo, ground slam"}.get(String(sp), ""),
			},
		})
	return out


## Runs on the server. Returns a DotResult (the contract allows it).
static func _spawn(ctx: Dictionary, species: StringName) -> Variant:
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
