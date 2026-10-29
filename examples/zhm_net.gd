extends Node

## Two peers: a server running a bear and a client that must see it. Proves the monsters' body and `action`
## cross the wire through [ZhmNetSync]'s data alone. Run: `./game.sh --no-parse test zhm_net`.

const Behaviour := preload("zhm_net_behaviour.gd")
const Runtime := preload("../addons/zz_historical_monsters/core/zhm_runtime.gd")
const Pose := preload("../addons/zz_historical_monsters/view/zhm_pose.gd")

const CHECKS := 12
const SECTIONS := 2
const TICK_RATE := 60
const DT := 1.0 / 60.0

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0
var _server_world: Node3D = null
var _client_world: Node3D = null
var _server: DotNetManager = null
var _client: DotNetManager = null
var _wire: Array[PackedByteArray] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok   %s" % what)
	else:
		_failed += 1
		print("  FAIL %s%s" % [what, "" if detail == "" else "  - " + detail])


func _run() -> void:
	print("zz_historical_monsters two-peer replication")
	_entered += 1
	await _test_replication()
	_completed += 1

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS - 1 or _completed != _entered:
		print("ERROR: %d sections entered and %d completed." % [_entered, _completed])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _manager(is_server: bool) -> DotNetManager:
	var net := DotNetManager.new()
	net.name = "Server" if is_server else "Client"
	net.is_server = is_server
	net.service_scope = &"zhm_server" if is_server else &"zhm_client"
	net.local_peer_id = 1 if is_server else 2
	net.auto_tick = false
	net.config_file = ""
	net.config = DotNetConfig.new()
	net.config.tick_rate = TICK_RATE
	net.config.snapshot_rate = 30
	add_child(net)
	return net


func _build(_context: Dictionary) -> Node:
	var root := Node3D.new()
	root.name = "Entity"
	var identity := DotNetIdentity.new()
	identity.name = "NetIdentity"
	identity.prefab_id = &"zhm_monster"
	identity.authority = DotNetIdentity.Authority.SERVER
	root.add_child(identity)
	var behaviour: DotNetBehaviour = Behaviour.new()
	behaviour.name = "Behaviour"
	root.add_child(behaviour)
	identity.entity = root
	identity.behaviours = [behaviour]
	behaviour.identity = identity
	behaviour._bind(DotNetConfig.new())
	return root


func _test_replication() -> void:
	print("[replication]")
	_server_world = Node3D.new()
	add_child(_server_world)
	_client_world = Node3D.new()
	_client_world.name = "ClientWorld"
	add_child(_client_world)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_server_world.add_child(floor_body)

	# The server's monster, running its real brain against one player standing in reach.
	var prey := Vector3(0, 0, -2.2)
	var runtime: Node = Runtime.find_or_create(_server_world)
	runtime.candidates_source = func() -> Array: return [{"id": &"p0", "position": prey, "loudness": 100.0}]
	runtime.self_ticking = false
	await get_tree().physics_frame
	var npc: DotNpcInstance = runtime.call(&"spawn", &"bear", Vector3.ZERO)
	await get_tree().physics_frame
	_check(npc != null and npc.node != null, "the server spawns a bear")

	_server = _manager(true)
	_client = _manager(false)
	var ok_setup := _server.setup().ok and _client.setup().ok
	_server.send_fn = func(peer_id: int, payload: PackedByteArray, d: int) -> void:
		if peer_id == 2 and d == DotNetMessage.Delivery.UNRELIABLE:
			_wire.append(payload)
	_server.start()
	_client.start()
	_server.add_peer(2)
	_server.spawner.register_factory(&"zhm_monster", _build)
	_client.spawner.register_factory(&"zhm_monster", _build)
	_check(ok_setup, "both peers set up")

	var made := _server.spawner.spawn(&"zhm_monster", 0, Transform3D.IDENTITY, 0)
	var s_id: DotNetIdentity = made.value if made.ok else null
	var s_beh: Node = s_id.behaviours[0] if s_id != null else null
	s_beh.npc = npc
	s_beh.body = npc.node
	var c_made := _client.spawner.spawn_remote(&"zhm_monster", s_id.net_id, 0, Transform3D.IDENTITY, 0)
	var c_id: DotNetIdentity = c_made.value if c_made.ok else null
	var c_beh: Node = c_id.behaviours[0] if c_id != null else null
	c_beh.world = _client_world
	_check(s_id != null and c_id != null and not c_id.is_authoritative, "the client holds a non-authoritative mirror entity")
	_check(_client_world.get_child_count() == 0, "and no body yet: nothing has been replicated")

	var seen_actions := {}
	var server_actions := {}
	for tick in range(1, 6 * TICK_RATE):
		runtime.spawner.set_candidates(runtime._candidates())
		runtime.spawner.tick(DT)
		var act := int(npc.node.get(&"action"))
		server_actions[act] = true
		_server.server_tick(tick)
		for payload in _wire:
			_client.clock.tick = tick
			var _applied := _client.receive_snapshot(payload)
		_wire.clear()
		for quarter in range(4):
			_client.interpolate_frame(float(quarter) * 0.25)
		_client.step(DT)
		if c_beh.body != null:
			seen_actions[int(c_beh.body.get(&"action"))] = true
		await get_tree().physics_frame
		if tick == 5:
			pass

	var mirror: Node3D = c_beh.body
	_check(mirror != null and mirror.get_parent() == _client_world, "the client built a body from the replicated species")
	_check(mirror != null and mirror.get(&"species") == &"bear", "and it is a bear", str(mirror.get(&"species")) if mirror != null else "none")
	_check(mirror != null and mirror.collision_layer == 0, "and it blocks nothing on the client")
	var attacked := server_actions.keys().any(func(a: int) -> bool: return a >= 0)
	_check(attacked, "the server bear took an action (%s)" % str(server_actions.keys()))
	var client_attacked := seen_actions.keys().any(func(a: int) -> bool: return a >= 0)
	_check(client_attacked, "the client saw an action change (%s)" % str(seen_actions.keys()))
	_check(
		seen_actions.has(Pose.Anim.MAUL) == server_actions.has(Pose.Anim.MAUL) and seen_actions.has(Pose.Anim.MAUL),
		"including the maul, the server's own action"
	)
	_check(
		mirror != null and mirror.global_position.distance_to(npc.node.global_position) < 1.0,
		"the mirror stands where the server's bear does",
		"%.2f m" % mirror.global_position.distance_to(npc.node.global_position) if mirror != null else "none"
	)
	_check(
		mirror != null and absf(angle_difference(mirror.rotation.y, npc.node.rotation.y)) < 0.1,
		"and faces the way it does"
	)

	_server.stop()
	_client.stop()
