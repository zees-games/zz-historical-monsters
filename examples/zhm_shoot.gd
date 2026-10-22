extends Node

## A monster shot by a hitscan: dot-combat resolves the hit on a tagged hitbox to a limb and a world point,
## its duck-typed `limb_target_fn` hands that to the body's `DotNpcLimbs`, the head comes off and the
## replicated bitmask carries it to a client mirror. The pack never names dot-combat; only this suite does.
##
## [codeblock]
## ./game.sh --no-parse test zhm_shoot
## [/codeblock]

const Config := preload("../addons/zz_historical_monsters/core/zhm_config.gd")
const NetSync := preload("../addons/zz_historical_monsters/core/zhm_net_sync.gd")
const BODY := "res://addons/zz_historical_monsters/runtime/zhm_body.tscn"

const CHECKS := 14
const SECTIONS := 1

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0


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
	print("zz_historical_monsters shot suite")
	_entered += 1
	_test_head_shot()
	_completed += 1
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered or _passed + _failed != CHECKS:
		print("ERROR: %d sections, %d checks; expected %d and %d." % [_completed, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _body(cfg: Config, species: StringName) -> Node3D:
	var body := (load(BODY) as PackedScene).instantiate() as Node3D
	add_child(body)
	body.call(&"setup", species, cfg.species(species).get("body", {}), cfg.species(species).get("limbs", {}))
	return body


func _test_head_shot() -> void:
	var cfg := Config.load_config()
	var sp := &"trex"
	var defs: Dictionary = cfg.species(sp)["limbs"]
	# A server draws nothing: the regions come from the rest pose of the model.
	var body := _body(cfg, sp)
	var limbs: Node = body.get(&"limbs")
	_check(body.get(&"view") == null, "the server body draws nothing")
	var head_at: Vector3 = (limbs.call(&"points_of", defs["head"]) as PackedVector3Array)[0]
	var head_hp: float = defs["head"]["health"]

	var manager := DotCombatManager.new()
	manager.register_service = false
	manager.trace = DotTraceFlat.new()
	manager.rules = DotDamageRules.new()
	manager.config = DotCombatConfig.new()
	add_child(manager)

	var health := DotHealth.new()
	health.max_health = 100000.0
	health.regen_per_second = 0.0
	body.add_child(health)
	var set_node := DotHitboxSet.new()
	set_node.bounds_offset = head_at
	set_node.bounds_radius = 3.0
	var box := DotHitbox.new()
	box.shape = DotHitbox.Shape.SPHERE
	box.group = DotHitGroup.HEAD
	box.limb = &"head"
	box.radius = float(defs["head"]["radius"])
	box.position = head_at
	set_node.add_child(box)
	body.add_child(set_node)
	set_node.refresh()
	set_node.register_with(manager, 7)
	manager.register_health(7, health)

	manager.limb_min_damage = {"default": 50.0, "head": head_hp * 0.5}
	manager.limb_target_fn = func(entity: Node) -> Object: return entity.get(&"limbs")
	var severed: Array = []
	body.connect(&"limb_severed", func(l: StringName, info: Dictionary) -> void: severed.append([l, info]))

	var type := DotDamageType.make(&"bullet", "Bullet")
	manager.register_damage_type(type)

	var weak := DotShot.make(&"rifle", 1, 10, 1)
	weak.damage = head_hp * 0.05
	weak.damage_type = type
	weak.max_range = 200.0
	weak.origin = head_at + Vector3(0.0, 0.0, 12.0)
	weak.direction = Vector3.FORWARD
	weak.scatter()
	manager.resolve_shot(weak)
	_check(weak.damages.size() == 1 and weak.damages[0].limb == &"head", "the shot lands on the head hitbox and says which limb")
	_check(not bool(limbs.call(&"is_severed", &"head")) and severed.is_empty(), "a hit under the limb's threshold leaves the head on")

	var strong := DotShot.make(&"rifle", 1, 11, 2)
	strong.damage = head_hp
	strong.damage_type = type
	strong.max_range = 200.0
	strong.origin = weak.origin
	strong.direction = Vector3.FORWARD
	strong.scatter()
	manager.resolve_shot(strong)
	_check(strong.damages.size() == 1 and not strong.damages[0].refused, "the shot does damage")
	_check(bool(limbs.call(&"is_severed", &"head")), "the head comes off")
	_check(severed.size() == 1 and severed[0][0] == &"head", "the body announced it once")
	_check(severed.size() == 1 and (severed[0][1]["point"] as Vector3).distance_to(head_at) < float(defs["head"]["radius"]) * 2.0 + 0.5,
		"at the point the shot landed", str(severed[0][1].get("point") if severed.size() == 1 else "none"))
	_check(bool(limbs.call(&"is_lethal")), "a head off is lethal to the host")
	_check(int(limbs.call(&"mask")) == 1, "the mask is the head's bit", str(limbs.call(&"mask")))

	# What crosses the wire is the mask under LIMB_BITS; a client mirror applies it and severs the same limb.
	var wire := int(body.get(&"limb_mask")) & ((1 << NetSync.LIMB_BITS) - 1)
	_check(wire == 1, "the replicated field carries the bit", str(wire))
	var mirror := _body(cfg, sp)
	mirror.set(&"limb_mask", wire)
	_check(bool(mirror.get(&"limbs").call(&"is_severed", &"head")), "a client mirror severs the head from the bitmask")
	_check(not bool(mirror.get(&"limbs").call(&"is_severed", &"armL")), "and only the head")
	_check(NetSync.specs().any(func(s: Dictionary) -> bool: return s["property"] == &"net_limbs"), "net_limbs is in the replicated specs")

	var again := DotShot.make(&"rifle", 1, 12, 3)
	again.damage = head_hp
	again.damage_type = type
	again.max_range = 200.0
	again.origin = weak.origin
	again.direction = Vector3.FORWARD
	again.scatter()
	manager.resolve_shot(again)
	_check(severed.size() == 1, "a severed head is not cut twice")
	manager.queue_free()
