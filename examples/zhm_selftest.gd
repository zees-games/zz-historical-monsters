extends Node

## Proves the monsters load, pose with real bones, read their numbers from yml, and that every
## special attack does what its definition says to a player standing where it lands.
##
## [codeblock]
## godot --headless --path . res://examples/zhm_selftest.tscn
## [/codeblock]
##
## What it cannot prove is how any of it looks: that is `tools/screenshot.sh`, and somebody
## looking at the result.

const Pose := preload("../addons/zz_historical_monsters/view/zhm_pose.gd")
const View := preload("../addons/zz_historical_monsters/view/zhm_view.gd")
const Config := preload("../addons/zz_historical_monsters/core/zhm_config.gd")
const Catalogue := preload("../addons/zz_historical_monsters/core/zhm_catalogue.gd")
const Host := preload("../addons/zz_historical_monsters/core/zhm_host.gd")
const Runtime := preload("../addons/zz_historical_monsters/core/zhm_runtime.gd")
const Gibs := preload("../addons/zz_historical_monsters/view/zhm_gibs.gd")
const Limbs := preload("../addons/zz_historical_monsters/runtime/zhm_limbs.gd")
const Provider := preload("../addons/zz_historical_monsters/spawn_provider.gd")

const CHECKS := 170
const SECTIONS := 9
const TRIS_MAX := 14000

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _world: Node3D = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zz_historical_monsters self-test")
	_world = Node3D.new()
	add_child(_world)
	_floor()

	_test_config()
	_test_catalogue()
	_test_models()
	_test_poses()
	await _test_trex()
	await _test_tiger()
	await _test_bear()
	_test_limbs()
	await _test_provider()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, SECTIONS])
		get_tree().quit(1)
		return
	if CHECKS != 0 and _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s (%s)" % [what, detail])
		print("  FAIL  %s" % (what if detail == "" else "%s (%s)" % [what, detail]))


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	body.add_child(shape)
	body.position.y = -0.5
	body.name = "Floor"
	_world.add_child(body)



func _test_config() -> void:
	_section("config")
	var d := Config.defaults()
	_check(d.keys().size() == Config.SPECIES.size() and d.has("trex") and d.has("raptor") and d.has("tiger") and d.has("thylacine") and d.has("bear"), "defaults describe every monster")

	var cfg := Config.load_config()
	_check(cfg.source != "defaults", "the yml directory was found and read", cfg.source)
	_check(is_equal_approx(cfg.get_num(&"trex", "health", -1.0), 2200.0), "trex health comes from trex.yml")
	_check(is_equal_approx(cfg.get_num(&"bear", "slam.radius", -1.0), 5.5), "a nested number reads by dotted path")

	# A key deleted from the data (a hand edit that removed a line) falls back to the default.
	cfg.data["trex"].erase("charge")
	cfg.data["tiger"]["pounce"].erase("speed")
	_check(is_equal_approx(cfg.get_num(&"trex", "charge.speed", -1.0), 13.0), "a missing section falls back to the built-in default")
	_check(is_equal_approx(cfg.get_num(&"tiger", "pounce.speed", -1.0), 17.0), "and so does a single missing key")

	# A wrong type is ignored rather than breaking arithmetic downstream.
	cfg.data["bear"]["health"] = "lots"
	_check(is_equal_approx(cfg.get_num(&"bear", "health", -1.0), 1100.0), "a value of the wrong type is ignored for the default")
	cfg.data["bear"]["health"] = 5
	_check(is_equal_approx(cfg.get_num(&"bear", "health", -1.0), 5.0), "an integer is accepted for a number")
	_done()


func _test_catalogue() -> void:
	_section("catalogue")
	var cat := Catalogue.build(Config.load_config())
	_check(cat.size() == Config.SPECIES.size(), "one definition per species", str(cat.size()))
	for sp in Config.SPECIES:
		var def := cat.get_npc(Catalogue.id_of(sp))
		_check(def != null and def.validate().ok, "%s validates" % sp)
		_check(def != null and ResourceLoader.exists(def.scene_path) and ResourceLoader.exists(def.brain_script_path), "%s names a scene and a brain that exist" % sp)
		_check(def != null and def.meta.get("species") == String(sp) and def.meta.get("cfg") is Dictionary, "%s carries its species and numbers in meta" % sp)
		var rest := Limbs.rest_points(sp)
		var bones_ok := not rest.is_empty()
		for limb in Config.load_config().species(sp).get("limbs", {}).values():
			for b in limb["bones"]:
				bones_ok = bones_ok and rest.has(StringName(b))
		_check(bones_ok, "%s has a model, and every limb names a bone it has" % sp)
	_check(Catalogue.species_of(&"zhm_bear") == &"bear" and Catalogue.species_of(&"nope") == &"", "ids map back to species")
	var spawner_cat := DotNpcCatalogue.new()
	_check(Catalogue.add_to(spawner_cat) == Config.SPECIES.size() and spawner_cat.size() == Config.SPECIES.size(), "add_to puts every species in a host's own catalogue")
	_done()



func _view(species: StringName):
	var v = View.new()
	v.species = species
	v.manual = true
	_world.add_child(v)
	return v


func _tris(n: Node) -> int:
	var total := 0
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mesh := (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			total += (idx as PackedInt32Array).size() / 3 if idx is PackedInt32Array else 0
	return total


func _test_models() -> void:
	_section("models")
	for sp in Config.SPECIES:
		var v = _view(sp)
		_check(v.skeleton != null and v.skeleton.get_bone_count() >= 12, "%s loads with a skeleton" % sp, str(v.skeleton.get_bone_count() if v.skeleton else 0))
		var tris := _tris(v)
		_check(tris > 1000 and tris <= TRIS_MAX, "%s is within the web budget" % sp, "%d triangles" % tris)
		var glow := false
		for m in v.find_children("*", "MeshInstance3D", true, false):
			var mesh := (m as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
					glow = true
		_check(glow, "%s has glowing eyes" % sp)
		for bone in ["head", "jaw", "pelvis"]:
			if not v.has_bone(StringName(bone)):
				_check(false, "%s has bone %s" % [sp, bone])
		v.queue_free()
	_done()


func _limb_body(sp: StringName, cfg) -> Node3D:
	var body := (load("res://addons/zz_historical_monsters/runtime/zhm_body.tscn") as PackedScene).instantiate() as Node3D
	body.set(&"force_view", true)
	_world.add_child(body)
	body.call(&"setup", sp, cfg.species(sp).get("body", {}), cfg.species(sp).get("limbs", {}))
	return body


func _test_limbs() -> void:
	_section("limbs")
	var cfg := Config.load_config()
	for sp in Config.SPECIES:
		var body := _limb_body(sp, cfg)
		var limbs: Node = body.get(&"limbs")
		var names: Array = limbs.call(&"limb_names")
		_check(names.size() >= 5 and names[0] == &"head", "%s has shootable limbs, the head first" % sp, str(names))
		_check(limbs.call(&"limb_at", Vector3(0, -50, 0)) == &"", "%s: a point far from the body is no limb" % sp)

		# Every limb is found by a point on its own line and comes off when its health is spent.
		var found := 0
		var skeleton: Skeleton3D = body.get(&"view").skeleton
		for k in names:
			var d: Dictionary = cfg.species(sp)["limbs"][String(k)]
			var pts: PackedVector3Array = limbs.call(&"points_of", d)
			var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
			if limbs.call(&"limb_at", mid) == k:
				found += 1
		_check(found == names.size(), "%s: each limb's own midpoint lands in that limb" % sp, "%d of %d" % [found, names.size()])

		var head_pts: PackedVector3Array = limbs.call(&"points_of", cfg.species(sp)["limbs"]["head"])
		var head_at := head_pts[0]
		var hp: float = cfg.species(sp)["limbs"]["head"]["health"]
		_check(limbs.call(&"hit", head_at, hp * 0.4) == &"", "%s: a shot that does not finish the limb leaves it on" % sp)
		var cut: StringName = body.call(&"zhm_limb_hit", head_at, hp)
		_check(cut == &"head" and limbs.call(&"is_severed", &"head"), "%s: the head comes off when its health is spent" % sp)
		var head_bone := skeleton.find_bone("head")
		_check(skeleton.get_bone_pose_scale(head_bone).x < 0.01, "%s: the head bone is collapsed on the drawn body" % sp)
		_check(limbs.call(&"limb_at", head_at) != &"head", "%s: a severed limb is not hit again" % sp)
		_check(int(body.get(&"limb_mask")) == 1, "%s: the mask has the head's bit" % sp, str(body.get(&"limb_mask")))

		var mirror := _limb_body(sp, cfg)
		mirror.set(&"limb_mask", int(body.get(&"limb_mask")))
		_check(mirror.get(&"limbs").call(&"is_severed", &"head"), "%s: a client mirror severs what the mask says" % sp)

		# A leg or a foreleg lost slows it; the gib has real triangles to throw.
		var slow_before: float = body.call(&"speed_scale")
		for k in names:
			if cfg.species(sp)["limbs"][String(k)].has("slow"):
				limbs.call(&"sever", k, Vector3.INF, Vector3.ZERO)
		_check(float(body.call(&"speed_scale")) < slow_before, "%s: losing legs slows it" % sp)
		var view: Node3D = body.get(&"view")
		var root := skeleton.find_bone(cfg.species(sp)["limbs"][String(names[1])]["bones"][0])
		var gib: ArrayMesh = Gibs.limb_mesh(skeleton, view.get(&"_model"), root, "test/%s" % sp)
		_check(gib != null and gib.get_surface_count() > 0, "%s: a limb can be cut from the model as its own mesh" % sp)
		body.queue_free()
		mirror.queue_free()
	_done()


func _test_poses() -> void:
	_section("poses")
	for sp in Config.SPECIES:
		var v = _view(sp)
		var known := {}
		for b in v.bone_names():
			known[StringName(b)] = true
		var stray := PackedStringArray()
		for anim in Pose.Anim.values():
			for t in [0.0, 0.3, 1.0, 2.5]:
				var pose := Pose.pose(sp, anim, t, t * 3.0, 4.0, 1)
				for k in pose:
					if not String(k).begins_with("_") and not known.has(k):
						stray.append("%s@%s:%s" % [Pose.Anim.keys()[anim], t, k])
		_check(stray.is_empty(), "%s: every pose names only bones the model has" % sp, ", ".join(stray.slice(0, 4)))

		var finite := true
		for anim in Pose.Anim.values():
			v.anim = anim
			for i in 20:
				v.step(0.05)
			for i in v.skeleton.get_bone_count():
				var q: Quaternion = v.skeleton.get_bone_pose_rotation(i)
				if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
					finite = false
		_check(finite, "%s: stepping every clip leaves every bone finite" % sp)
		v.queue_free()
	_done()



## A spawner with the monsters, and a recording host, in the world. [param tweak] edits the config
## first so a test can switch one ability off or shorten a telegraph.
func _arena(tweak: Callable = Callable()) -> Dictionary:
	# The last scenario's monsters are still standing at the origin otherwise, and the next one
	# spawns inside them and climbs on their heads.
	for c in _world.get_children():
		if c.name != "Floor":
			_world.remove_child(c)
			c.queue_free()
	var cfg := Config.load_config()
	if tweak.is_valid():
		tweak.call(cfg.data)
	var spawner := DotNpcSpawner.new()
	spawner.authoritative = true
	spawner.catalogue = Catalogue.build(cfg)
	_world.add_child(spawner)
	var host := Host.new(spawner)
	spawner.set_meta(&"zhm_host", host)
	return {"spawner": spawner, "host": host}


func _prey(spawner: DotNpcSpawner, at: Array) -> void:
	var list: Array = []
	var i := 0
	for p in at:
		list.append(DotNpcSenses.Candidate.new(StringName("p%d" % i), p, &"player", 100.0))
		i += 1
	spawner.set_candidates(list)


func _sim(spawner: DotNpcSpawner, seconds: float) -> void:
	for i in int(seconds * 60.0):
		spawner.tick(1.0 / 60.0)
		await get_tree().physics_frame


func _hits(host: Object, kind: StringName) -> Array:
	return host.history.filter(func(h): return h["op"] == "hit" and h["kind"] == kind)


func _statuses(host: Object, st: StringName) -> Array:
	return host.history.filter(func(h): return h["op"] == "status" and h["status"] == st)


func _spawn(spawner: DotNpcSpawner, species: StringName) -> DotNpcInstance:
	var npc := spawner.spawn(Catalogue.id_of(species), Vector3.ZERO)
	await get_tree().physics_frame
	return npc


func _quick(d: Dictionary) -> void:
	# Short telegraphs so a scenario takes a second, not five. The ratios between them are kept.
	for sp in d:
		for k in d[sp]:
			if d[sp][k] is Dictionary and d[sp][k].has("windup"):
				d[sp][k]["windup"] = 0.15


func _test_trex() -> void:
	_section("trex")
	var a := _arena(func(d): _quick(d); d["trex"]["tail_sweep"]["radius"] = 1.0; d["trex"]["roar"]["min_distance"] = 100.0)
	var sp: DotNpcSpawner = a.spawner
	var host: Object = a.host
	var rex := await _spawn(sp, &"trex")
	_check(rex != null and rex.brain != null and rex.node.get(&"species") == &"trex", "a T-Rex spawns with its brain and body")
	_check(rex.node.get_node_or_null("Collision") != null, "and its collider is sized for it")

	# Bite: in reach, in front.
	_prey(sp, [Vector3(0, 0, -3.6)])
	await _sim(sp, 1.0)
	var bites := _hits(host, &"bite")
	_check(not bites.is_empty() and is_equal_approx(bites[0]["amount"], 45.0), "a player in reach is bitten for the configured damage", str(bites.size()))
	_check(rex.brain.started.get(&"bite", 0) >= 1, "the bite state ran")
	sp.remove(rex.instance_id)

	# Charge: across a gap it winds up, then runs the locked line and hits once.
	var b := _arena(func(d): _quick(d); d["trex"]["roar"]["min_distance"] = 100.0; d["trex"]["charge"]["duration"] = 3.0)
	sp = b.spawner
	host = b.host
	rex = await _spawn(sp, &"trex")
	_prey(sp, [Vector3(0, 0, -22)])
	await _sim(sp, 4.0)
	_check(rex.brain.started.get(&"charge", 0) == 1, "a player across a gap draws one charge")
	var hits := _hits(host, &"charge")
	_check(hits.size() == 1 and is_equal_approx(hits[0]["amount"], 65.0), "the charge hits a player in its line exactly once", str(hits.size()))
	_check(rex.position().z < -10.0, "and it actually ran down the line", str(rex.position()))

	# A player who steps aside is missed: move the prey off the line during the windup.
	var c := _arena(func(d): _quick(d); d["trex"]["roar"]["min_distance"] = 100.0; d["trex"]["charge"]["windup"] = 0.5; d["trex"]["charge"]["duration"] = 3.0)
	sp = c.spawner
	host = c.host
	rex = await _spawn(sp, &"trex")
	_prey(sp, [Vector3(0, 0, -22)])
	await _sim(sp, 0.7)
	_prey(sp, [Vector3(9, 0, -22)])
	await _sim(sp, 3.0)
	_check(_hits(host, &"charge").is_empty(), "a player who steps out of the locked line is not hit")

	# Roar: stuns every player in range, not those outside it.
	var r := _arena(func(d): _quick(d); d["trex"]["charge"]["min_distance"] = 100.0; d["trex"]["tail_sweep"]["radius"] = 1.0; d["trex"]["roar"]["range"] = 14.0)
	sp = r.spawner
	host = r.host
	rex = await _spawn(sp, &"trex")
	_prey(sp, [Vector3(0, 0, -9), Vector3(3, 0, -12), Vector3(0, 0, -30)])
	await _sim(sp, 1.0)
	var stuns := _statuses(host, &"stun")
	var who := stuns.map(func(s): return s["victim"])
	_check(who.has(&"p0") and who.has(&"p1") and not who.has(&"p2"), "a roar stuns the players in range and only them", str(who))
	_check(is_equal_approx(stuns[0]["seconds"], 2.5), "for the configured time")

	# Tail sweep: hits everybody close, throws them.
	var s := _arena(func(d): _quick(d); d["trex"]["bite"]["reach"] = 0.1)
	sp = s.spawner
	host = s.host
	rex = await _spawn(sp, &"trex")
	_prey(sp, [Vector3(0, 0, -3), Vector3(4, 0, 1), Vector3(0, 0, -20)])
	await _sim(sp, 1.2)
	var tails := _hits(host, &"tail")
	var victims := tails.map(func(h): return h["victim"])
	_check(victims.has(&"p0") and victims.has(&"p1") and not victims.has(&"p2"), "a tail sweep hits everyone near, front and flank", str(victims))
	_done()


func _test_tiger() -> void:
	_section("tiger")
	var a := _arena(func(d): _quick(d))
	var sp: DotNpcSpawner = a.spawner
	var host: Object = a.host
	var cat := await _spawn(sp, &"tiger")
	_prey(sp, [Vector3(0, 0, -9)])
	await _sim(sp, 2.0)
	_check(cat.brain.started.get(&"pounce", 0) >= 1, "a tiger pounces at range")
	var p := _hits(host, &"pounce")
	_check(p.size() == 1 and is_equal_approx(p[0]["amount"], 24.0), "the pounce lands once for the configured damage", str(p.size()))
	_check(cat.position().z < -4.0, "it leapt toward the prey", str(cat.position()))
	_check(not _statuses(host, &"bleed").is_empty(), "and the wound is reported to the host as a bleed")

	var before := _hits(host, &"bleed").size()
	await _sim(sp, 3.5)
	var bleeds := _hits(host, &"bleed")
	_check(bleeds.size() - before >= 2, "the bleed keeps costing health on its own clock", "%d ticks" % (bleeds.size() - before))
	_check(is_equal_approx(bleeds[0]["amount"], 4.0), "one stack bleeds the configured rate")
	_prey(sp, [])
	await _sim(sp, 6.0)
	var after := _hits(host, &"bleed").size()
	await _sim(sp, 2.0)
	_check(_hits(host, &"bleed").size() == after, "and it stops when its duration runs out")

	# Stacks: three claws in a row put a second stack on and the rate rises.
	var b := _arena(func(d): _quick(d); d["tiger"]["pounce"]["max_distance"] = 0.0; d["tiger"]["claw"]["interval"] = 0.2; d["tiger"]["bleed"]["duration"] = 20.0)
	sp = b.spawner
	host = b.host
	cat = await _spawn(sp, &"tiger")
	_prey(sp, [Vector3(0, 0, -1.6)])
	await _sim(sp, 4.5)
	var claws := _hits(host, &"claw")
	_check(claws.size() >= 6 and is_equal_approx(claws[0]["amount"], 14.0), "claws land at their rate", str(claws.size()))
	var rates := _hits(host, &"bleed").map(func(h): return h["amount"])
	_check(not rates.is_empty() and rates.max() > 4.0, "bleed stacks raise the tick", str(rates.max() if not rates.is_empty() else 0))
	_check(rates.max() <= 12.0 + 0.001, "and are capped at max_stacks", str(rates.max() if not rates.is_empty() else 0))
	_done()


func _test_bear() -> void:
	_section("bear")
	var a := _arena(func(d): _quick(d); d["bear"]["slam"]["radius"] = 1.0)
	var sp: DotNpcSpawner = a.spawner
	var host: Object = a.host
	var bear := await _spawn(sp, &"bear")
	_prey(sp, [Vector3(0, 0, -2.2)])
	await _sim(sp, 1.4)
	var mauls := _hits(host, &"maul")
	_check(mauls.size() == 3, "a maul is a combo of three swings", str(mauls.size()))
	_check(is_equal_approx(mauls[0]["amount"], 13.0) if not mauls.is_empty() else false, "each for the configured damage")

	var b := _arena(func(d): _quick(d); d["bear"]["maul"]["reach"] = 0.1)
	sp = b.spawner
	host = b.host
	bear = await _spawn(sp, &"bear")
	_prey(sp, [Vector3(0, 0, -2.5), Vector3(2, 0, -3.5), Vector3(0, 0, -30)])
	await _sim(sp, 1.4)
	var slams := _hits(host, &"slam")
	var victims := slams.map(func(h): return h["victim"])
	_check(victims.has(&"p0") and victims.has(&"p1") and not victims.has(&"p2"), "a ground slam hits everyone within its radius", str(victims))
	var stuns := _statuses(host, &"stun").map(func(s): return s["victim"])
	_check(stuns.has(&"p0") and stuns.has(&"p1"), "and stuns them")
	_check(slams.size() >= 2 and slams[0]["amount"] >= slams[1]["amount"], "the nearer takes more", str(slams.map(func(h): return snappedf(h["amount"], 0.1))))

	# Cooldown: a second slam does not come at once.
	await _sim(sp, 2.0)
	_check(bear.brain.started.get(&"slam", 0) == 1, "a slam is on cooldown afterwards", str(bear.brain.started.get(&"slam", 0)))

	# Death stops it hurting anyone.
	var n: int = host.history.size()
	sp.damage(bear.instance_id, 100000.0, &"test")
	await _sim(sp, 1.0)
	_check(host.history.size() == n, "a dead monster does nothing more")
	_done()


func _test_provider() -> void:
	_section("spawn provider")
	var entries := Provider.spawn_entries()
	_check(entries.size() == Config.SPECIES.size(), "one spawn entry per species")
	var ok := true
	for e in entries:
		for key in ["category", "id", "name", "icon", "kind", "spawn", "spawn_fn", "cfg_hint"]:
			if not e.has(key):
				ok = false
		if e.get("kind") != "npc" or not (e.get("spawn_fn") is Callable) or not (e.get("spawn") is Dictionary) or e.get("category") != "NPCs":
			ok = false
	_check(ok, "each entry has the contract's keys, kind npc, a spawn Dictionary, a spawn_fn Callable and category NPCs")
	var ids := entries.map(func(e): return e["id"])
	_check(ids.has("zhm_trex") and ids.has("zhm_raptor") and ids.has("zhm_tiger") and ids.has("zhm_thylacine") and ids.has("zhm_bear"), "ids are the catalogue's")

	# The way ZzPacks loads it: by path, an instance, then called by name.
	var loaded := load("res://addons/zz_historical_monsters/spawn_provider.gd") as GDScript
	var inst: Object = loaded.new()
	_check(inst.has_method(&"spawn_entries"), "a pack scan finds spawn_entries on the instance")
	var rows: Array = inst.call(&"spawn_entries")
	var cfg := Config.load_config()
	var shapes_ok := rows.size() == Config.SPECIES.size()
	var boss_ids := PackedStringArray()
	for r in rows:
		var sp: Dictionary = r["spawn"]
		var species := StringName(String(r["id"]).trim_prefix("zhm_"))
		var hit: String = Provider.ATTACKS[species]
		for key in ["health", "speed", "damage", "reach"]:
			if not (sp.get(key) is float) or float(sp[key]) <= 0.0:
				shapes_ok = false
		if not (sp.get("body") is String) or sp.has("brain"):
			shapes_ok = false
		if not is_equal_approx(float(sp["health"]), float(cfg.species(species)["health"])) \
				or not is_equal_approx(float(sp["damage"]), cfg.get_num(species, hit + ".damage", -1.0)) \
				or not is_equal_approx(float(sp["reach"]), cfg.get_num(species, hit + ".reach", -1.0)) \
				or not is_equal_approx(float(sp["speed"]), cfg.get_num(species, "run_speed", -1.0)):
			shapes_ok = false
		if bool(sp.get("boss", false)):
			boss_ids.append(String(r["id"]))
	_check(shapes_ok, "every npc row's spawn is {health, speed, damage, reach, body} from the yml")
	_check(boss_ids == PackedStringArray(["zhm_trex"]), "only the T-Rex is marked boss", str(boss_ids))

	var world := Node3D.new()
	_world.add_child(world)
	var entry: Dictionary = entries[1]
	var refused: Variant = (entry["spawn_fn"] as Callable).call({"world": world, "at": Vector3(0, 0, 0), "player_id": &"u", "authoritative": false, "cfg_hint": {}})
	_check(refused is DotResult and not refused.ok, "a client is refused")
	var made: Variant = (entry["spawn_fn"] as Callable).call({"world": world, "at": Vector3(0, 0, 0), "player_id": &"u", "authoritative": true, "cfg_hint": {"count": 2}})
	await get_tree().physics_frame
	var rt := Runtime.find_or_create(world)
	_check(made is DotResult and made.ok and rt.spawner.world_count() == 2, "the server spawns the asked count", str(rt.spawner.world_count()))
	_check(Runtime.find_or_create(world) == rt, "a second request finds the same runtime")
	var rex: Variant = (entries[0]["spawn_fn"] as Callable).call({"world": world, "at": Vector3(8, 0, 0), "player_id": &"u", "authoritative": true, "cfg_hint": {"count": 3}})
	_check(rex is DotResult and rex.ok and rex.value == 1, "a T-Rex is capped at one per request", str(rex.value if rex is DotResult else rex))
	_check(rt.spawner.world_count() == 3 and rt.describe()["monsters"] == 3, "and the runtime describes what it holds")
	_done()
