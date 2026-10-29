class_name ZhmRuntime
extends Node

## A self-contained place to run monsters for a game with no NPC spawner of its own (and the spawn menu).
## Owns a [DotNpcSpawner], a [ZhmHost] and the tick; prey comes from [member candidates_source].
## A game with its own spawner calls [method attach]. Server only.

const CHANNEL := "zhm.runtime"
const Host := preload("zhm_host.gd")
const Config := preload("zhm_config.gd")
const Catalogue := preload("zhm_catalogue.gd")

var config: Config = null
var spawner: DotNpcSpawner = null
var host: Object = null
## `func() -> Array` of `{id: StringName, position: Vector3}`. Null means the `players` group.
var candidates_source: Callable = Callable()
var authoritative: bool = true:
	set(value):
		authoritative = value
		if spawner != null:
			spawner.authoritative = value
## Whether this node ticks the spawner itself. False when a game's own loop calls `spawner.tick`.
var self_ticking: bool = true


## The runtime under [param parent], created once: a second spawn menu entry finds the first.
static func find_or_create(parent: Node, p_config: Config = null) -> Node:
	for c in parent.get_children():
		if c.has_meta(&"zhm_runtime"):
			return c
	var rt := new()
	rt.set_meta(&"zhm_runtime", true)
	rt.name = "ZhmRuntime"
	rt.config = p_config
	parent.add_child(rt)
	return rt


func _ready() -> void:
	if config == null:
		config = Config.load_config()
	if spawner == null:
		spawner = DotNpcSpawner.new()
		spawner.name = "Spawner"
		spawner.authoritative = authoritative
		spawner.catalogue = Catalogue.build(config)
		# The spawn menu already rate-limits who may ask; a second per-owner interval here would
		# refuse the second monster of one request.
		var limits := DotNpcLimits.new()
		limits.spawn_interval = 0.0
		spawner.limits = limits
		add_child(spawner)
	if host == null:
		host = Host.new(spawner)
	spawner.set_meta(&"zhm_host", host)
	DotLog.debug(CHANNEL, "monster runtime ready", {"config": config.source, "monsters": spawner.catalogue.size()})


## Puts the monsters into a spawner the game already has, and tells them where to send damage.
## [param p_host] is the game's own (see [ZhmHost]); null keeps the recording default.
func attach(existing: DotNpcSpawner, p_host: Object = null) -> int:
	spawner = existing
	if config == null:
		config = Config.load_config()
	if existing.catalogue == null:
		existing.catalogue = DotNpcCatalogue.new()
	var added := Catalogue.add_to(existing.catalogue, config)
	host = p_host if p_host != null else Host.new(existing)
	existing.set_meta(&"zhm_host", host)
	self_ticking = false
	return added


func _physics_process(delta: float) -> void:
	if not self_ticking or spawner == null or not authoritative:
		return
	spawner.set_candidates(_candidates())
	spawner.tick(delta)


func _candidates() -> Array:
	var out: Array = []
	var list: Array = []
	if candidates_source.is_valid():
		list = candidates_source.call()
	else:
		for n in get_tree().get_nodes_in_group(&"players"):
			if n is Node3D:
				list.append({"id": StringName(n.name), "position": (n as Node3D).global_position})
	for e in list:
		out.append(DotNpcSenses.Candidate.new(e["id"], e["position"], e.get("faction", &"player"), float(e.get("loudness", 12.0))))
	return out


## Spawns one monster, [param species] being `trex`, `tiger` or `bear`. Null when refused.
func spawn(species: StringName, at: Vector3, owner_id: StringName = &"") -> DotNpcInstance:
	if spawner == null or not authoritative:
		return null
	var id := Catalogue.id_of(species)
	if id == &"":
		DotLog.warn(CHANNEL, "no such monster", {"species": String(species)})
		return null
	var npc := spawner.spawn(id, at, owner_id)
	if npc != null:
		DotLog.info(CHANNEL, "monster spawned", {"species": String(species), "at": at, "owner": String(owner_id)})
	return npc


func describe() -> Dictionary:
	return {
		"monsters": spawner.world_count() if spawner != null else 0,
		"host": host.describe() if host != null and host.has_method(&"describe") else {},
		"config": config.source if config != null else "-",
	}
