class_name ZhmConfig
extends RefCounted

## Every number that tunes a monster, and where it comes from.
##
## [b]The yml files are the interface, this file is the fallback.[/b] `cfg/addons/zz_historical_monsters/*.yml`
## (one file per monster is the shipped shape, any number is read) are merged over [method defaults]
## by dot-core's [code]DotAddonConfig[/code], then environment, then the command line. A host that
## ships no yml, or a dot-core too old to have [code]DotAddonConfig[/code], gets exactly the numbers
## below: a monster must spawn with nothing configured.
##
## [b]Reached by reflection, never named.[/b] `DotAddonConfig` landed in dot-core after this pack's
## first consumers pinned it; naming it would make this file fail to parse against theirs, and a
## config class that cannot parse is a pack that cannot load at all. The script is loaded by path
## and [code]load_dir[/code] is called on it.

const CHANNEL := "zhm.config"
const ADDON := "zz_historical_monsters"
const SPECIES := [&"trex", &"tiger", &"bear"]
const ADDON_CONFIG_PATH := "res://addons/dot_core/core/dot_addon_config.gd"

## The merged tree: `{trex: {...}, tiger: {...}, bear: {...}}`.
var data: Dictionary = {}
## Where it came from, for [method describe]: "defaults" or the files' directory.
var source: String = "defaults"


## The numbers a monster has with no yml at all. Every key here is a key an operator can set.
##
## Distances are metres, times seconds, damage is health points on the host's own scale (a
## survivor has about 100). A [code]windup[/code] is the telegraph: the animation winds up for that
## long and the effect lands at its end, so a player who has moved away takes nothing. That is the
## whole of fair melee, and it is also why every ability's range is rechecked when it lands.
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
