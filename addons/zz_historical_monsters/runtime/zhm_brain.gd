extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"

## The mind of all three monsters: hunt what the senses committed to, and use the special attacks
## that suit the range. One script; `meta.species` tells the species apart. Extends the AI brain by path:
## a mounted pack's globals do not register. Server-authoritative; every attack is a telegraph then a
## landing against whoever is still in range, and effects leave only through the host's methods.

const CHANNEL := "zhm.brain"
const Pose := preload("../view/zhm_pose.gd")
const Host := preload("../core/zhm_host.gd")

var species: StringName = &""
var cfg: Dictionary = {}
var host: Object = null

var _cooldown: Dictionary = {}
## victim -> {stacks, until, next, dps}: the bleed a tiger put on somebody.
var _bleeds: Dictionary = {}
var _locked_dir: Vector3 = Vector3.FORWARD
var _locked_target: Vector3 = Vector3.ZERO
var _landed: bool = false
var _hit_victims: Dictionary = {}
var _claws: int = 0
var _combo: int = 0
var _combo_next: float = 0.0
var _vy: float = 0.0
## What a suite reads: how many of each special attack this monster has started.
var started: Dictionary = {}
var _by_id: Dictionary = {}


func _npc_ready() -> void:
	species = StringName(tune_string(&"species", "trex"))
	var raw: Variant = npc.def.meta.get("cfg", {}) if npc != null and npc.def != null else {}
	cfg = raw if raw is Dictionary else {}
	super()
	var body := _body()
	if body != null and body.has_method(&"setup"):
		body.call(&"setup", species, cfg.get("body", {}), cfg.get("limbs", {}))
		if body.has_signal(&"limb_severed"):
			body.connect(&"limb_severed", _limb_lost)
	DotLog.debug(CHANNEL, "monster ready", {"species": String(species), "id": npc.instance_id})


func _build() -> void:
	machine = DotNpcAiMachine.new()
	initial_state = &"idle"

	_add(DotNpcAiState.make(&"idle", _tick_idle).when(_has_prey, &"hunt"))
	_add(DotNpcAiState.make(&"hunt", _tick_hunt).when(_no_prey, &"idle"))

	match species:
		&"trex":
			_build_trex()
		&"tiger":
			_build_tiger()
		_:
			_build_bear()



func _add(state: DotNpcAiState) -> DotNpcAiState:
	_by_id[state.id] = state
	machine.add(state)
	return state


func _action(id: StringName, anim: int, windup: float, recover: float, effect: Callable) -> void:
	var state := DotNpcAiState.make(id, _tick_action.bind(effect, windup))
	state.on_enter = _enter_action.bind(id, anim)
	state.on_exit = _exit_action
	state.after(windup + recover, &"hunt")
	_add(state)


func _build_trex() -> void:
	var sweep: Dictionary = cfg.get("tail_sweep", {})
	var roar: Dictionary = cfg.get("roar", {})
	var charge: Dictionary = cfg.get("charge", {})
	var bite: Dictionary = cfg.get("bite", {})
	_action(&"bite", Pose.Anim.BITE, _f(bite, "windup", 0.45), 0.5, _land_bite.bind(&"bite", bite))
	_action(&"sweep", Pose.Anim.SWEEP, _f(sweep, "windup", 0.8), _f(sweep, "recover", 0.6), _land_sweep)
	_action(&"roar", Pose.Anim.ROAR, _f(roar, "windup", 1.0), 1.0, _land_roar)

	var wind := DotNpcAiState.make(&"charge_wind", _tick_charge_wind)
	wind.on_enter = _enter_charge_wind
	wind.after(_f(charge, "windup", 1.1), &"charge")
	_add(wind)
	var run := DotNpcAiState.make(&"charge", _tick_charge)
	run.on_enter = _enter_charge
	run.on_exit = _exit_action
	run.after(_f(charge, "duration", 2.4), &"stagger")
	_add(run)
	var stagger := DotNpcAiState.make(&"stagger", _tick_halt_action.bind(Pose.Anim.STAGGER))
	stagger.on_exit = _exit_action
	stagger.after(_f(charge, "recover", 1.2), &"hunt")
	_add(stagger)

	var hunt: DotNpcAiState = _by_id[&"hunt"]
	# Priority is order: a sweep when somebody is close, a bite in reach, a charge or a roar across
	# a gap. A transition is tried in the order it was added.
	hunt.when(_can_sweep, &"sweep")
	hunt.when(_can_bite.bind(bite), &"bite")
	hunt.when(_can_charge, &"charge_wind")
	hunt.when(_can_roar, &"roar")


func _build_tiger() -> void:
	var claw: Dictionary = cfg.get("claw", {})
	var pounce: Dictionary = cfg.get("pounce", {})
	_action(&"claw", Pose.Anim.BITE, _f(claw, "windup", 0.25), 0.3, _land_claw.bind(claw))

	var wind := DotNpcAiState.make(&"pounce_wind", _tick_pounce_wind)
	wind.on_enter = _enter_pounce_wind
	wind.after(_f(pounce, "windup", 0.6), &"leap")
	_add(wind)
	var leap := DotNpcAiState.make(&"leap", _tick_leap)
	leap.on_enter = _enter_leap
	leap.on_exit = _exit_action
	leap.after(3.0, &"land")
	_add(leap)
	var land := DotNpcAiState.make(&"land", _tick_halt_action.bind(Pose.Anim.LAND))
	land.on_exit = _exit_action
	land.after(_f(pounce, "recover", 0.7), &"hunt")
	_add(land)

	var hunt: DotNpcAiState = _by_id[&"hunt"]
	hunt.when(_can_bite.bind(claw), &"claw")
	hunt.when(_can_pounce, &"pounce_wind")


func _build_bear() -> void:
	var maul: Dictionary = cfg.get("maul", {})
	var slam: Dictionary = cfg.get("slam", {})
	var hits := int(_f(maul, "hits", 3.0))
	var gap := _f(maul, "gap", 0.45)
	var first := _f(maul, "windup", 0.3)
	# The combo is one state long enough for every swing; each swing lands on its own beat.
	_action(&"maul", Pose.Anim.MAUL, first + gap * float(hits - 1), 0.5, _land_maul.bind(maul, first, gap, hits))
	_action(&"slam", Pose.Anim.SLAM, _f(slam, "windup", 0.95), _f(slam, "recover", 0.8), _land_slam)

	var hunt: DotNpcAiState = _by_id[&"hunt"]
	hunt.when(_can_slam, &"slam")
	hunt.when(_can_bite.bind(maul), &"maul")



func _has_prey(_c: DotNpcAiContext) -> bool:
	return npc != null and npc.has_target()


func _no_prey(_c: DotNpcAiContext) -> bool:
	return npc == null or not npc.has_target()


func _ready_to(name: StringName) -> bool:
	return context.now >= float(_cooldown.get(name, -INF))


func _dist() -> float:
	return _flat(npc.position(), target_position(npc.position()))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback


func _can_bite(_c: DotNpcAiContext, attack: Dictionary) -> bool:
	return _ready_to(&"melee") and _dist() <= _f(attack, "reach", 2.0)


func _can_sweep(_c: DotNpcAiContext) -> bool:
	var sweep: Dictionary = cfg.get("tail_sweep", {})
	if not _ready_to(&"sweep"):
		return false
	var radius := _f(sweep, "radius", 6.0)
	# Anybody close enough, not just the committed target: a sweep is the answer to being flanked.
	return not _targets_within(radius * 0.85).is_empty()


func _can_charge(_c: DotNpcAiContext) -> bool:
	var ch: Dictionary = cfg.get("charge", {})
	if not _ready_to(&"charge"):
		return false
	var d := _dist()
	return d >= _f(ch, "min_distance", 10.0) and d <= _f(ch, "max_distance", 30.0)


func _can_roar(_c: DotNpcAiContext) -> bool:
	var r: Dictionary = cfg.get("roar", {})
	if not _ready_to(&"roar"):
		return false
	var d := _dist()
	return d >= _f(r, "min_distance", 5.0) and d <= _f(r, "range", 16.0)


func _can_pounce(_c: DotNpcAiContext) -> bool:
	var p: Dictionary = cfg.get("pounce", {})
	if not _ready_to(&"pounce"):
		return false
	var d := _dist()
	return d >= _f(p, "min_distance", 4.0) and d <= _f(p, "max_distance", 16.0)


func _can_slam(_c: DotNpcAiContext) -> bool:
	var s: Dictionary = cfg.get("slam", {})
	if not _ready_to(&"slam"):
		return false
	var radius := _f(s, "radius", 5.0)
	var near := _targets_within(radius * 0.8)
	return near.size() >= 2 or (near.size() == 1 and _dist() <= radius * 0.55)



func _tick_idle(_c: DotNpcAiContext) -> void:
	var body := _body()
	if body != null:
		body.set(&"action", -1)

	# Walk to where the prey was last known rather than stopping dead the instant it is lost.
	if remembers_target():
		steer_along_path(last_known_position(), _f(cfg, "walk_speed", 3.0) * _scale(&"speed_scale"), context.delta)
	else:
		halt()
	_tick_bleeds()


func _tick_hunt(_c: DotNpcAiContext) -> void:
	var body := _body()
	if body != null:
		body.set(&"action", -1)
	_tick_bleeds()

	if not npc.has_target():
		return
	var to := target_position(npc.position())
	var far := _flat(npc.position(), to) > 8.0
	steer_along_path(to, (_f(cfg, "run_speed", 6.0) if far else _f(cfg, "walk_speed", 3.0) * 1.4) * _scale(&"speed_scale"), context.delta)


func _tick_halt_action(_c: DotNpcAiContext, anim: int) -> void:
	halt()
	_set_action(anim)
	_tick_bleeds()



func _enter_action(_c: DotNpcAiContext, id: StringName, anim: int) -> void:
	_landed = false
	_hit_victims.clear()
	_combo = 0
	_combo_next = 0.0
	_set_action(anim)
	started[id] = int(started.get(id, 0)) + 1
	halt()
	_face_target()
	DotLog.debug(CHANNEL, "monster begins an attack", {"species": String(species), "attack": String(id), "npc": npc.instance_id})


func _exit_action(_c: DotNpcAiContext) -> void:
	_set_action(-1)


## Holds still facing the target until [param windup], then lands the effect once.
func _tick_action(_c: DotNpcAiContext, effect: Callable, windup: float) -> void:
	halt()
	_tick_bleeds()
	var t := context.now - _entered_at()
	if t < windup * 0.8:
		_face_target()
	if effect.is_valid():
		effect.call(t, windup)


func _entered_at() -> float:
	return context.now - machine.elapsed(context.now)


func _land_bite(t: float, windup: float, kind: StringName, attack: Dictionary) -> void:
	if _landed or t < windup:
		return
	_landed = true
	_cooldown[&"melee"] = context.now + _f(attack, "interval", 1.5)
	var reach := _f(attack, "reach", 2.0) + 0.5
	for v in _targets_within(reach, _facing_cone()):
		_hit(v.id, _f(attack, "damage", 10.0), kind, _impulse_to(v.position, 3.0))


func _land_claw(t: float, windup: float, attack: Dictionary) -> void:
	if _landed or t < windup:
		return
	_landed = true
	_cooldown[&"melee"] = context.now + _f(attack, "interval", 0.8)
	_claws += 1
	for v in _targets_within(_f(attack, "reach", 2.0) + 0.5, _facing_cone()):
		_hit(v.id, _f(attack, "damage", 14.0), &"claw", _impulse_to(v.position, 2.0))
		# Every third claw opens a wound: the bleed is a threat of its own, not only a pounce rider.
		if _claws % 3 == 0:
			_add_bleed(v.id)


func _land_maul(t: float, _windup: float, attack: Dictionary, first: float, gap: float, hits: int) -> void:
	_cooldown[&"melee"] = context.now + _f(attack, "interval", 1.4)
	while _combo < hits and t >= first + gap * float(_combo):
		var swing := _combo
		_combo += 1
		var body := _body()
		if body != null:
			body.set(&"variant", swing % 2)
		for v in _targets_within(_f(attack, "reach", 2.6) + 0.5, _facing_cone()):
			_hit(v.id, _f(attack, "damage", 13.0), &"maul", _impulse_to(v.position, 2.5))


func _land_sweep(t: float, windup: float) -> void:
	if _landed or t < windup:
		return
	_landed = true
	var s: Dictionary = cfg.get("tail_sweep", {})
	_cooldown[&"sweep"] = context.now + _f(s, "cooldown", 7.0)
	# The tail covers the half behind the monster and the sides; the front is the bite's.
	for v in _targets_within(_f(s, "radius", 6.0)):
		_hit(v.id, _f(s, "damage", 30.0), &"tail", _impulse_to(v.position, _f(s, "knockback", 9.0)))


func _land_roar(t: float, windup: float) -> void:
	if _landed or t < windup:
		return
	_landed = true
	var r: Dictionary = cfg.get("roar", {})
	_cooldown[&"roar"] = context.now + _f(r, "cooldown", 16.0)
	for v in _targets_within(_f(r, "range", 16.0)):
		_status(v.id, &"stun", _f(r, "stun", 2.5))
		_status(v.id, &"slow", _f(r, "stun", 2.5) * 2.0)


func _land_slam(t: float, windup: float) -> void:
	if _landed or t < windup:
		return
	_landed = true
	var s: Dictionary = cfg.get("slam", {})
	_cooldown[&"slam"] = context.now + _f(s, "cooldown", 9.0)
	var radius := _f(s, "radius", 5.0)
	for v in _targets_within(radius):
		# Closer takes more: a slam is a shockwave, not a flat area.
		var falloff := 1.0 - 0.5 * clampf(_flat(npc.position(), v.position) / radius, 0.0, 1.0)
		_hit(v.id, _f(s, "damage", 30.0) * falloff, &"slam", _impulse_to(v.position, _f(s, "knockback", 7.0)))
		_status(v.id, &"stun", _f(s, "stun", 1.2))



func _enter_charge_wind(_c: DotNpcAiContext) -> void:
	started[&"charge"] = int(started.get(&"charge", 0)) + 1
	_cooldown[&"charge"] = context.now + _f(cfg.get("charge", {}), "cooldown", 13.0) + _f(cfg.get("charge", {}), "windup", 1.1)
	_set_action(Pose.Anim.CHARGE_WIND)
	halt()
	DotLog.debug(CHANNEL, "monster begins an attack", {"species": String(species), "attack": "charge", "npc": npc.instance_id})


func _tick_charge_wind(_c: DotNpcAiContext) -> void:
	halt()
	_face_target()
	_tick_bleeds()


func _enter_charge(_c: DotNpcAiContext) -> void:
	_hit_victims.clear()
	_locked_dir = _dir_to_target()
	_set_action(Pose.Anim.CHARGE)


## Runs straight along the direction locked at the end of the windup; it does not steer, so sidestepping is the counter.
func _tick_charge(_c: DotNpcAiContext) -> void:
	var ch: Dictionary = cfg.get("charge", {})
	var speed := _f(ch, "speed", 13.0)
	steer_toward(npc.position() + _locked_dir * 10.0, speed, context.delta)
	_tick_bleeds()

	for v in _targets_within(_f(ch, "hit_radius", 2.6)):
		if _hit_victims.has(v.id):
			continue
		_hit_victims[v.id] = true
		_hit(v.id, _f(ch, "damage", 60.0), &"charge", _locked_dir * _f(ch, "knockback", 14.0))



func _enter_pounce_wind(_c: DotNpcAiContext) -> void:
	started[&"pounce"] = int(started.get(&"pounce", 0)) + 1
	_cooldown[&"pounce"] = context.now + _f(cfg.get("pounce", {}), "cooldown", 6.0)
	_set_action(Pose.Anim.POUNCE_WIND)
	halt()
	DotLog.debug(CHANNEL, "monster begins an attack", {"species": String(species), "attack": "pounce", "npc": npc.instance_id})


func _tick_pounce_wind(_c: DotNpcAiContext) -> void:
	halt()
	_face_target()
	_tick_bleeds()


func _enter_leap(_c: DotNpcAiContext) -> void:
	var p: Dictionary = cfg.get("pounce", {})
	_hit_victims.clear()
	_landed = false
	var to := target_position(npc.position())
	_locked_target = to
	var flat := Vector3(to.x - npc.position().x, 0.0, to.z - npc.position().z)
	_locked_dir = flat.normalized() if flat.length() > 0.01 else -npc.node.global_transform.basis.z
	# Aim to land at the target at the leap's own speed: flight time is distance over speed, and
	# the vertical launch is what makes that flight take that long under gravity.
	var speed := _f(p, "speed", 17.0)
	var flight := maxf(flat.length() / speed, 0.25)
	_vy = 9.8 * flight * 0.5
	_set_action(Pose.Anim.LEAP)
	var b := _body()
	if b != null and b is CharacterBody3D:
		(b as CharacterBody3D).velocity.y = _vy


func _tick_leap(_c: DotNpcAiContext) -> void:
	var p: Dictionary = cfg.get("pounce", {})
	var b := _body() as CharacterBody3D
	if b == null:
		return
	var speed := _f(p, "speed", 17.0)
	var remaining := Vector3(_locked_target.x - b.global_position.x, 0.0, _locked_target.z - b.global_position.z)
	var run := minf(speed, remaining.length() / maxf(context.delta, 0.001))
	b.velocity.x = _locked_dir.x * run
	b.velocity.z = _locked_dir.z * run
	b.velocity.y -= 9.8 * context.delta
	b.move_and_slide()
	face(_locked_dir)
	_tick_bleeds()

	var t := context.now - _entered_at()
	if t < 0.12 or not b.is_on_floor():
		return
	if not _landed:
		_landed = true
		for v in _targets_within(_f(p, "hit_radius", 1.8)):
			_hit(v.id, _f(p, "damage", 24.0), &"pounce", _impulse_to(v.position, 3.0))
			_add_bleed(v.id)
	machine.go_to(context, &"land")



func _add_bleed(victim: StringName) -> void:
	var b: Dictionary = cfg.get("bleed", {})
	var entry: Dictionary = _bleeds.get(victim, {"stacks": 0, "until": 0.0, "next": context.now + _f(b, "tick", 1.0)})
	entry["stacks"] = mini(int(entry["stacks"]) + 1, int(_f(b, "max_stacks", 3.0)))
	entry["until"] = context.now + _f(b, "duration", 6.0)
	_bleeds[victim] = entry
	_status(victim, &"bleed", _f(b, "duration", 6.0))


## Ticks every wound this monster opened, whatever its state: a bleed outlives the pounce.
func _tick_bleeds() -> void:
	if _bleeds.is_empty():
		return
	var b: Dictionary = cfg.get("bleed", {})
	var tick := maxf(_f(b, "tick", 1.0), 0.1)
	for victim in _bleeds.keys():
		var e: Dictionary = _bleeds[victim]
		if context.now >= float(e["until"]):
			_bleeds.erase(victim)
			continue
		if context.now >= float(e["next"]):
			e["next"] = float(e["next"]) + tick
			_hit(victim, _f(b, "damage_per_second", 4.0) * float(e["stacks"]) * tick, &"bleed", Vector3.ZERO)



func _body() -> Node:
	return npc.node if npc != null else null


func _scale(method: StringName) -> float:
	var b := _body()
	return float(b.call(method)) if b != null and b.has_method(method) else 1.0


## A limb was shot off. A head takes the monster with it; the director's own damage path does the dying, so
## the kill is scored like any other.
func _limb_lost(limb: StringName, info: Dictionary) -> void:
	var d: Dictionary = info.get("def", {})
	DotLog.info(CHANNEL, "monster loses a limb", {"species": String(species), "limb": String(limb), "npc": npc.instance_id})
	if bool(d.get("kills", false)) and npc.is_alive() and director != null and director.has_method(&"damage"):
		director.call(&"damage", npc.instance_id, npc.health + 1.0, &"decapitation")


func _set_action(anim: int) -> void:
	var b := _body()
	if b != null:
		b.set(&"action", anim)


func _dir_to_target() -> Vector3:
	var to := target_position(npc.position())
	var d := Vector3(to.x - npc.position().x, 0.0, to.z - npc.position().z)
	if d.length() < 0.01:
		return -(npc.node as Node3D).global_transform.basis.z
	return d.normalized()


func _face_target() -> void:
	var d := _dir_to_target()
	face(d)


## A cone in front of the monster as a dot-product floor: bites and claws hit what they face.
func _facing_cone() -> float:
	return 0.2


func _impulse_to(at: Vector3, strength: float) -> Vector3:
	var d := Vector3(at.x - npc.position().x, 0.0, at.z - npc.position().z)
	return (d.normalized() if d.length() > 0.01 else Vector3.ZERO) * strength + Vector3.UP * strength * 0.3


func _host() -> Object:
	if host != null and is_instance_valid(host):
		return host
	if director != null and director.has_meta(&"zhm_host"):
		host = director.get_meta(&"zhm_host")
	else:
		host = Host.new(director)
		if director != null:
			director.set_meta(&"zhm_host", host)
	return host


## Every player within [param radius] of the monster (flat), nearest first; with [param cone] also
## in front of it by that dot-product floor.
func _targets_within(radius: float, cone: float = -2.0) -> Array:
	var h := _host()
	var raw: Array = h.call(&"zhm_targets") if h != null and h.has_method(&"zhm_targets") else []
	var out: Array = []
	var me := npc.position()
	var fwd := -(npc.node as Node3D).global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for e in raw:
		var pos: Vector3 = e["position"]
		var d := _flat(me, pos)
		if d > radius or absf(pos.y - me.y) > 3.5:
			continue
		if cone > -1.5 and d > 0.5:
			var dir := Vector3(pos.x - me.x, 0.0, pos.z - me.z).normalized()
			if fwd.dot(dir) < cone:
				continue
		out.append({"id": e["id"], "position": pos, "d": d})
	out.sort_custom(func(a, b): return a["d"] < b["d"])
	return out


func _hit(victim: StringName, amount: float, kind: StringName, impulse: Vector3) -> void:
	var h := _host()
	if h == null or not h.has_method(&"zhm_hit"):
		return
	DotLog.debug(CHANNEL, "monster hits", {"species": String(species), "kind": String(kind), "victim": String(victim), "amount": snappedf(amount, 0.1)})
	h.call(&"zhm_hit", npc, victim, amount * _scale(&"attack_scale"), kind, {"impulse": impulse, "source": npc.position()})


func _status(victim: StringName, st: StringName, seconds: float) -> void:
	var h := _host()
	if h == null or not h.has_method(&"zhm_status"):
		return
	DotLog.debug(CHANNEL, "monster afflicts", {"species": String(species), "status": String(st), "victim": String(victim), "seconds": seconds})
	h.call(&"zhm_status", victim, st, seconds, {"source": npc.position()})


func _npc_died(_by: StringName) -> void:
	_set_action(Pose.Anim.DEAD)
	_bleeds.clear()
	halt()


func describe() -> Dictionary:
	var out := super()
	out["species"] = String(species)
	out["state"] = String(machine.current()) if machine != null else "-"
	out["bleeding"] = _bleeds.size()
	out["started"] = started
	return out
