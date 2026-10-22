class_name ZhmNetSync
extends RefCounted

## What a client needs to see a monster, as data. The pack's half of replication.
##
## [b]dot-net is not named here[/b], exactly as in [DotNpcNetSync]: a host's net behaviour
## declares one replicated field per entry of [method specs] (resolving `type` with
## `DotNetVar.Type[spec.type]`), copies the server's row in with [method pull] each tick, and on
## a client calls [method apply] on the mirror body it got from [method make_mirror]. The fields
## are dot-npc's own (position, yaw, health, state) plus the three this pack adds: which species
## to build, and what the body is doing.
##
## [b]Before this, monsters existed only on the server[/b]: a connected player was mauled by
## something nobody drew, and [code]body.action[/code] (which picks the clip) never left the
## machine that decided it.
##
## [b]Server-authoritative, never predicted[/b] (see dot-npc's runtime doc): [method apply] is for
## a mirror and must never be called on a body the local brain drives.

const Pose := preload("../view/zhm_pose.gd")
const Config := preload("zhm_config.gd")

const SPECIES_BITS := 2
## `action + 1`, so that 0 means "let the gait decide" (the body's -1) and no sign crosses the wire.
const ACTION_BITS := 5
const VARIANT_BITS := 2

const BODY_SCENE := "res://addons/zz_historical_monsters/runtime/zhm_body.tscn"


## One entry per replicated property, in dot-npc's shape: `{property, type, bits, interpolated}`.
static func specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = DotNpcNetSync.specs()
	out.append({"property": &"net_species", "type": "UINT", "bits": SPECIES_BITS, "interpolated": false})
	out.append({"property": &"net_action", "type": "UINT", "bits": ACTION_BITS, "interpolated": false})
	out.append({"property": &"net_variant", "type": "UINT", "bits": VARIANT_BITS, "interpolated": false})
	return out


static func species_index(species: StringName) -> int:
	return Config.SPECIES.find(species)


## The species a replicated index names, or &"" for one this build does not know.
static func species_of(index: int) -> StringName:
	return Config.SPECIES[index] if index >= 0 and index < Config.SPECIES.size() else &""


## Server: copies a monster onto the replicating object [param into].
static func pull(npc: DotNpcInstance, body: Node, into: Object) -> void:
	if npc == null or body == null or into == null:
		return
	var action := int(body.get(&"action"))
	var state := DotNpcNetSync.State.IDLE
	if not npc.is_alive() or action == Pose.Anim.DEAD:
		state = DotNpcNetSync.State.DEAD
	elif action >= 0:
		state = DotNpcNetSync.State.ATTACKING
	elif float(body.call(&"gait_speed")) > 0.4:
		state = DotNpcNetSync.State.MOVING
	DotNpcNetSync.pull(npc, into, state)
	into.set(&"net_species", maxi(species_index(StringName(body.get(&"species"))), 0))
	into.set(&"net_action", clampi(action + 1, 0, (1 << ACTION_BITS) - 1))
	into.set(&"net_variant", clampi(int(body.get(&"variant")), 0, (1 << VARIANT_BITS) - 1))


## Client: writes replicated state onto a mirror from [method make_mirror].
static func apply(body: Node3D, from: Object) -> void:
	if body == null or from == null:
		return
	DotNpcNetSync.apply(body, from)
	body.set(&"action", int(from.get(&"net_action")) - 1)
	body.set(&"variant", int(from.get(&"net_variant")))


## Client: the body for a monster the server announced, or null for an unknown species. It has
## the model and the animation but no collider that blocks anything and no brain: it draws
## what [method apply] is given.
static func make_mirror(index: int, config: Config = null) -> Node3D:
	var species := species_of(index)
	if species == &"":
		return null
	var cfg := config if config != null else Config.load_config()
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as Node3D
	body.name = "Mirror_%s" % String(species)
	body.call(&"setup", species, cfg.species(species).get("body", {}))
	# A shape on a mirror would shove the local player about on a position the server decided.
	body.set(&"collision_layer", 0)
	body.set(&"collision_mask", 0)
	body.set_meta(&"zhm_mirror", true)
	return body
