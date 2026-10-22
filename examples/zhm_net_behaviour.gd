extends DotNetBehaviour

## The suite's stand-in for a host's net behaviour: the only file here that names dot-net, which
## is the point, because the pack ships [ZhmNetSync] as data and a host writes this much.
##
## On the server it pulls a monster into the replicated fields each tick. On a client it builds
## the mirror body from the first snapshot (the species is in it) and applies every one after.

var npc: DotNpcInstance = null
var body: Node = null
## Where a client puts the bodies it builds.
var world: Node = null

var net_x: float = 0.0
var net_y: float = 0.0
var net_z: float = 0.0
var net_yaw: int = 0
var net_health: int = 0
var net_state: int = 0
var net_species: int = 0
var net_action: int = 0
var net_variant: int = 0


func _register_net_vars() -> void:
	for spec in ZhmNetSync.specs():
		var field := replicate(spec["property"], DotNetVar.Type[spec["type"]])
		if int(spec["bits"]) > 0:
			field.bits(int(spec["bits"]))
		if bool(spec["interpolated"]):
			field.interpolated()


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		ZhmNetSync.pull(npc, body, self)


func _net_state_applied(_tick: int) -> void:
	_draw()


func _net_interpolated(_tick: int) -> void:
	_draw()


func _draw() -> void:
	if identity != null and identity.is_authoritative:
		return
	if body == null:
		body = ZhmNetSync.make_mirror(net_species)
		if body == null:
			return
		world.add_child(body)
	ZhmNetSync.apply(body, self)
