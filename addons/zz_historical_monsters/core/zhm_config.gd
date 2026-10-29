class_name ZhmConfig
extends RefCounted

## Every number that tunes a monster: yml merged over [method defaults] by DotAddonConfig, then env, then argv.
## With no yml a monster must still spawn. DotAddonConfig is reached by reflection: naming it fails to parse
## against an older dot-core, and a config that cannot parse is a pack that cannot load.

const CHANNEL := "zhm.config"
const ADDON := "zz_historical_monsters"
const SPECIES := [&"trex", &"allosaurus", &"raptor", &"tiger", &"thylacine", &"bear"]
## A species that moves and fights like another one (same skeleton names, pose and brain), with its own numbers and model.
const ARCHETYPE := {&"allosaurus": &"trex", &"raptor": &"trex", &"thylacine": &"tiger"}


static func archetype(species: StringName) -> StringName:
	return ARCHETYPE.get(species, species)
const ADDON_CONFIG_PATH := "res://addons/dot_core/core/dot_addon_config.gd"

## The merged tree: `{trex: {...}, tiger: {...}, bear: {...}}`.
var data: Dictionary = {}
## Where it came from, for [method describe]: "defaults" or the files' directory.
var source: String = "defaults"


## The numbers a monster has with no yml at all. Every key here is a key an operator can set.
## Distances are metres, times seconds, damage is on the host's own scale (a survivor has about 100). A
## [code]windup[/code] is the telegraph: the effect lands at its end and range is rechecked then.
static func defaults() -> Dictionary:
	return {
		"trex": {
			"name": "Infected T-Rex",
			"health": 2200.0,
			"walk_speed": 3.2,
			"run_speed": 6.0,
			"sight_range": 45.0,
			"sight_half_angle": 70.0,
			"hearing_range": 30.0,
			"eye_height": 4.6,
			"cost": 12,
			"body": {"radius": 1.1, "height": 5.0},
			"bite": {"damage": 45.0, "reach": 4.2, "interval": 1.8, "windup": 0.45},
			"roar": {"range": 16.0, "stun": 2.5, "cooldown": 16.0, "windup": 1.0, "min_distance": 5.0, "slow": 0.5},
			"tail_sweep": {"radius": 6.5, "damage": 32.0, "knockback": 10.0, "cooldown": 7.0, "windup": 0.8, "recover": 0.6},
			"charge": {"min_distance": 10.0, "max_distance": 32.0, "speed": 13.0, "duration": 2.4, "damage": 65.0, "knockback": 14.0, "cooldown": 13.0, "windup": 1.1, "hit_radius": 2.6, "recover": 1.2},
			"limbs": {
				"head": {"bones": ["head", "jaw"], "radius": 0.75, "tip": 0.6, "health": 320.0, "kills": true},
				"armL": {"bones": ["armL"], "radius": 0.3, "tip": 0.8, "health": 100.0, "attack": 0.9},
				"armR": {"bones": ["armR"], "radius": 0.3, "tip": 0.8, "health": 100.0, "attack": 0.9},
				"legL": {"bones": ["legL_lo", "legL_ft"], "radius": 0.5, "tip": 0.5, "health": 450.0, "slow": 0.55},
				"legR": {"bones": ["legR_lo", "legR_ft"], "radius": 0.5, "tip": 0.5, "health": 450.0, "slow": 0.55},
				"tail": {"bones": ["tail2", "tail3"], "radius": 0.4, "tip": 0.8, "health": 220.0},
			},
		},
		"allosaurus": {
			"name": "Infected Allosaurus",
			"health": 1100.0,
			"walk_speed": 3.4,
			"run_speed": 8.0,
			"sight_range": 42.0,
			"sight_half_angle": 70.0,
			"hearing_range": 30.0,
			"eye_height": 3.0,
			"cost": 8,
			"body": {"radius": 0.85, "height": 3.4},
			"bite": {"damage": 34.0, "reach": 3.4, "interval": 1.5, "windup": 0.4},
			"roar": {"range": 14.0, "stun": 2.0, "cooldown": 18.0, "windup": 0.9, "min_distance": 5.0, "slow": 0.6},
			"tail_sweep": {"radius": 5.0, "damage": 24.0, "knockback": 8.0, "cooldown": 7.0, "windup": 0.7, "recover": 0.5},
			"charge": {"min_distance": 8.0, "max_distance": 28.0, "speed": 12.0, "duration": 2.0, "damage": 48.0, "knockback": 11.0, "cooldown": 11.0, "windup": 0.9, "hit_radius": 2.2, "recover": 1.0},
			"limbs": {
				"head": {"bones": ["head", "jaw"], "radius": 0.55, "tip": 0.5, "health": 240.0, "kills": true},
				"armL": {"bones": ["armL"], "radius": 0.22, "tip": 0.6, "health": 80.0, "attack": 0.9},
				"armR": {"bones": ["armR"], "radius": 0.22, "tip": 0.6, "health": 80.0, "attack": 0.9},
				"legL": {"bones": ["legL_lo", "legL_ft"], "radius": 0.4, "tip": 0.4, "health": 340.0, "slow": 0.55},
				"legR": {"bones": ["legR_lo", "legR_ft"], "radius": 0.4, "tip": 0.4, "health": 340.0, "slow": 0.55},
				"tail": {"bones": ["tail2", "tail3"], "radius": 0.3, "tip": 0.6, "health": 170.0},
			},
		},
		"raptor": {
			"name": "Infected Raptor",
			"health": 380.0,
			"walk_speed": 3.8,
			"run_speed": 10.0,
			"sight_range": 40.0,
			"sight_half_angle": 75.0,
			"hearing_range": 30.0,
			"eye_height": 1.7,
			"cost": 4,
			"body": {"radius": 0.5, "height": 1.9},
			"bite": {"damage": 16.0, "reach": 2.0, "interval": 0.9, "windup": 0.25},
			"roar": {"range": 10.0, "stun": 1.0, "cooldown": 20.0, "windup": 0.7, "min_distance": 4.0, "slow": 0.7},
			"tail_sweep": {"radius": 2.6, "damage": 10.0, "knockback": 5.0, "cooldown": 6.0, "windup": 0.5, "recover": 0.4},
			"charge": {"min_distance": 6.0, "max_distance": 22.0, "speed": 15.0, "duration": 1.6, "damage": 24.0, "knockback": 6.0, "cooldown": 7.0, "windup": 0.6, "hit_radius": 1.4, "recover": 0.8},
			"limbs": {
				"head": {"bones": ["head", "jaw"], "radius": 0.28, "tip": 0.2, "health": 110.0, "kills": true},
				"armL": {"bones": ["armL"], "radius": 0.14, "tip": 0.2, "health": 50.0, "attack": 0.85},
				"armR": {"bones": ["armR"], "radius": 0.14, "tip": 0.2, "health": 50.0, "attack": 0.85},
				"legL": {"bones": ["legL_lo", "legL_ft"], "radius": 0.2, "tip": 0.2, "health": 130.0, "slow": 0.5},
				"legR": {"bones": ["legR_lo", "legR_ft"], "radius": 0.2, "tip": 0.2, "health": 130.0, "slow": 0.5},
				"tail": {"bones": ["tail2", "tail3"], "radius": 0.14, "tip": 0.3, "health": 70.0},
			},
		},
		"tiger": {
			"name": "Infected Tiger",
			"health": 520.0,
			"walk_speed": 3.6,
			"run_speed": 9.5,
			"sight_range": 38.0,
			"sight_half_angle": 80.0,
			"hearing_range": 28.0,
			"eye_height": 1.2,
			"cost": 4,
			"body": {"radius": 0.55, "height": 1.7},
			"claw": {"damage": 14.0, "reach": 2.0, "interval": 0.8, "windup": 0.25},
			"pounce": {"min_distance": 4.0, "max_distance": 16.0, "speed": 17.0, "damage": 24.0, "cooldown": 6.0, "windup": 0.6, "hit_radius": 1.8, "recover": 0.7, "arc": 2.2},
			"bleed": {"damage_per_second": 4.0, "duration": 6.0, "max_stacks": 3, "tick": 1.0},
			"limbs": {
				"head": {"bones": ["head", "jaw"], "radius": 0.3, "tip": 0.3, "health": 110.0, "kills": true},
				"foreL": {"bones": ["armL_lo", "armL_ft"], "radius": 0.15, "tip": 0.2, "health": 70.0, "slow": 0.8, "attack": 0.8},
				"foreR": {"bones": ["armR_lo", "armR_ft"], "radius": 0.15, "tip": 0.2, "health": 70.0, "slow": 0.8, "attack": 0.8},
				"hindL": {"bones": ["legL_lo", "legL_ft"], "radius": 0.17, "tip": 0.2, "health": 80.0, "slow": 0.6},
				"hindR": {"bones": ["legR_lo", "legR_ft"], "radius": 0.17, "tip": 0.2, "health": 80.0, "slow": 0.6},
				"tail": {"bones": ["tail2", "tail3"], "radius": 0.12, "tip": 0.2, "health": 40.0},
			},
		},
		"thylacine": {
			"name": "Infected Thylacine",
			"health": 330.0,
			"walk_speed": 3.4,
			"run_speed": 9.0,
			"sight_range": 36.0,
			"sight_half_angle": 80.0,
			"hearing_range": 30.0,
			"eye_height": 1.0,
			"cost": 3,
			"body": {"radius": 0.45, "height": 1.3},
			"claw": {"damage": 11.0, "reach": 1.8, "interval": 0.8, "windup": 0.25},
			"pounce": {"min_distance": 3.5, "max_distance": 14.0, "speed": 15.0, "damage": 18.0, "cooldown": 6.0, "windup": 0.6, "hit_radius": 1.6, "recover": 0.7, "arc": 1.8},
			"bleed": {"damage_per_second": 3.0, "duration": 6.0, "max_stacks": 3, "tick": 1.0},
			"limbs": {
				"head": {"bones": ["head", "jaw"], "radius": 0.25, "tip": 0.25, "health": 90.0, "kills": true},
				"foreL": {"bones": ["armL_lo", "armL_ft"], "radius": 0.13, "tip": 0.2, "health": 60.0, "slow": 0.8, "attack": 0.8},
				"foreR": {"bones": ["armR_lo", "armR_ft"], "radius": 0.13, "tip": 0.2, "health": 60.0, "slow": 0.8, "attack": 0.8},
				"hindL": {"bones": ["legL_lo", "legL_ft"], "radius": 0.15, "tip": 0.2, "health": 70.0, "slow": 0.6},
				"hindR": {"bones": ["legR_lo", "legR_ft"], "radius": 0.15, "tip": 0.2, "health": 70.0, "slow": 0.6},
				"tail": {"bones": ["tail2", "tail3"], "radius": 0.1, "tip": 0.2, "health": 35.0},
			},
		},
		"bear": {
			"name": "Infected Bear",
			"health": 1100.0,
			"walk_speed": 3.4,
			"run_speed": 7.5,
			"sight_range": 32.0,
			"sight_half_angle": 75.0,
			"hearing_range": 26.0,
			"eye_height": 1.7,
			"cost": 6,
			"body": {"radius": 0.8, "height": 2.0},
			"maul": {"damage": 13.0, "reach": 2.6, "interval": 1.4, "windup": 0.3, "hits": 3, "gap": 0.45},
			"slam": {"radius": 5.5, "damage": 30.0, "stun": 1.2, "knockback": 7.0, "cooldown": 9.0, "windup": 0.95, "recover": 0.8},
			"limbs": {
				"head": {"bones": ["head", "jaw"], "radius": 0.4, "tip": 0.3, "health": 220.0, "kills": true},
				"armL": {"bones": ["armL_lo"], "radius": 0.3, "tip": 0.5, "health": 160.0, "slow": 0.85, "attack": 0.75},
				"armR": {"bones": ["armR_lo"], "radius": 0.3, "tip": 0.5, "health": 160.0, "slow": 0.85, "attack": 0.75},
				"legL": {"bones": ["legL_lo"], "radius": 0.3, "tip": 0.5, "health": 180.0, "slow": 0.6},
				"legR": {"bones": ["legR_lo"], "radius": 0.3, "tip": 0.5, "health": 180.0, "slow": 0.6},
			},
		},
	}


## Loads the layered config. Never fails: a problem is logged and the defaults stand.
static func load_config() -> ZhmConfig:
	var out := new()
	out.data = defaults()

	if not ResourceLoader.exists(ADDON_CONFIG_PATH):
		DotLog.info(CHANNEL, "no DotAddonConfig in this dot-core, using built-in defaults", {})
		return out

	var script: Variant = load(ADDON_CONFIG_PATH)
	if not (script is Script) or not (script as Script).has_method(&"load_dir"):
		DotLog.info(CHANNEL, "DotAddonConfig is not callable, using built-in defaults", {})
		return out

	var res: Variant = (script as Script).call(&"load_dir", ADDON, defaults())
	if res is DotResult and (res as DotResult).ok and (res as DotResult).value is Dictionary:
		out.data = (res as DotResult).value
		out.source = String(script.call(&"dir_for", ADDON)) if (script as Script).has_method(&"dir_for") else "cfg"
		DotLog.debug(CHANNEL, "monster config loaded", {"from": out.source})
	elif res is DotResult:
		DotLog.warn(CHANNEL, "monster config refused, using built-in defaults", {"why": (res as DotResult).error.message})

	return out


## One species' tree, always a Dictionary, with every default key present even when a yml file
## wrote half of it (a hand edit that deletes a number must not leave a hole).
func species(id: StringName) -> Dictionary:
	var base: Dictionary = defaults().get(String(id), {})
	var got: Variant = data.get(String(id), {})
	return _merged(base, got if got is Dictionary else {})


## A number at a dotted path inside a species, e.g. [code]get_num(&"trex", "charge.speed", 10)[/code].
func get_num(id: StringName, path: String, fallback: float) -> float:
	var node: Variant = species(id)
	for part in path.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		else:
			return fallback
	return float(node) if node is float or node is int else fallback


static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = _merged(out[k], over[k])
		elif typeof(out.get(k)) == typeof(over[k]) or (out.get(k) is float and over[k] is int):
			out[k] = float(over[k]) if out.get(k) is float else over[k]
		elif not out.has(k):
			out[k] = over[k]
	return out


func describe() -> Dictionary:
	return {"source": source, "species": SPECIES.size()}
