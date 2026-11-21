extends RefCounted

## The README studio's view of this pack (gs-bootstrap tools/readme/, run by tools/gen_readme.sh): which monsters,
## their models and poses, and the default-profile rows the README prints. Every number is read from the pack's
## effective config (ZhmConfig: the built-in defaults merged with cfg/addons/zz_historical_monsters/*.yml) and the
## catalogue's NPC definition, never typed here.

const Config := preload("res://addons/zz_historical_monsters/core/zhm_config.gd")
const Catalogue := preload("res://addons/zz_historical_monsters/core/zhm_catalogue.gd")
const View := preload("res://addons/zz_historical_monsters/view/zhm_view.gd")
const Pose := preload("res://addons/zz_historical_monsters/view/zhm_pose.gd")

## Movement speed per pose while it is stepped (the gallery's values).
const SPEEDS := {"walk": 2.0, "run": 8.0, "stalk": 1.2, "charge": 12.0}

var _cfg: Config = Config.load_config()


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for sp in Config.SPECIES:
		out.append(String(sp))
	return out


func model(id: String) -> Node3D:
	var v := View.new()
	v.species = StringName(id)
	v.manual = true
	return v


## Step the clip at a fixed 60 fps for `t` seconds, so the same pose is the same picture every run.
func pose(node: Node3D, id: String, pose_name: String, opts: Dictionary) -> void:
	var anim: int = Pose.Anim.get(pose_name.to_upper(), -1)
	if anim < 0:
		push_error("readme_adapter: %s has no clip %s" % [id, pose_name])
		return
	node.set("anim", anim)
	node.set("speed", float(opts.get("speed", SPEEDS.get(pose_name, 0.0))))
	node.set("variant", int(opts.get("variant", 0)))
	var steps := int(float(opts.get("t", 0.5)) * 60.0)
	for i in steps:
		node.call("step", 1.0 / 60.0)


func profile(id: String) -> Dictionary:
	var c := _cfg.species(StringName(id))
	var def := Catalogue.def_for(StringName(id), _cfg)
	var rows: Array = []
	var weight := {GSNpcDef.Weight.NORMAL: "Normal", GSNpcDef.Weight.HEAVY: "Heavy", GSNpcDef.Weight.BOSS: "Boss"}
	rows.append(["Health", _n(def.max_health)])
	rows.append(["Speed", "%s m/s walking, %s m/s running" % [_n(c.get("walk_speed")), _n(c.get("run_speed"))]])
	var primary := ""
	var primary_dmg := ""
	if c.has("bite"):
		var b: Dictionary = c["bite"]
		rows.append(["Bite", "%s damage, %s m reach, every %s s (%s s windup)" % [_n(b.damage), _n(b.reach), _n(b.interval), _n(b.windup)]])
		primary = "bite"
		primary_dmg = _n(b.damage)
	if c.has("claw"):
		var b: Dictionary = c["claw"]
		rows.append(["Claw", "%s damage, %s m reach, every %s s (%s s windup)" % [_n(b.damage), _n(b.reach), _n(b.interval), _n(b.windup)]])
		primary = "claw"
		primary_dmg = _n(b.damage)
	if c.has("maul"):
		var b: Dictionary = c["maul"]
		rows.append(["Maul", "%s hits of %s damage, %s s apart, %s m reach, every %s s (%s s windup)" % [_n(b.hits), _n(b.damage), _n(b.gap), _n(b.reach), _n(b.interval), _n(b.windup)]])
		primary = "maul"
		primary_dmg = "%s x %s" % [_n(b.hits), _n(b.damage)]
	if c.has("bleed"):
		var b: Dictionary = c["bleed"]
		rows.append(["Bleed", "%s damage per second for %s s, stacks up to %s" % [_n(b.damage_per_second), _n(b.duration), _n(b.max_stacks)]])
	if c.has("pounce"):
		var b: Dictionary = c["pounce"]
		rows.append(["Pounce", "%s damage, leaps from %s to %s m at %s m/s; %s s cooldown (%s s windup)" % [_n(b.damage), _n(b.min_distance), _n(b.max_distance), _n(b.speed), _n(b.cooldown), _n(b.windup)]])
	if c.has("roar"):
		var b: Dictionary = c["roar"]
		rows.append(["Roar", "stuns %s s and slows to %s %% within %s m; %s s cooldown (%s s windup)" % [_n(b.stun), _n(float(b.slow) * 100.0), _n(b.range), _n(b.cooldown), _n(b.windup)]])
	if c.has("tail_sweep"):
		var b: Dictionary = c["tail_sweep"]
		rows.append(["Tail sweep", "%s damage within %s m, knockback %s; %s s cooldown (%s s windup)" % [_n(b.damage), _n(b.radius), _n(b.knockback), _n(b.cooldown), _n(b.windup)]])
	if c.has("charge"):
		var b: Dictionary = c["charge"]
		rows.append(["Charge", "%s damage, knockback %s, at %s m/s from %s to %s m; %s s cooldown (%s s windup)" % [_n(b.damage), _n(b.knockback), _n(b.speed), _n(b.min_distance), _n(b.max_distance), _n(b.cooldown), _n(b.windup)]])
	if c.has("slam"):
		var b: Dictionary = c["slam"]
		rows.append(["Slam", "%s damage within %s m, stuns %s s, knockback %s; %s s cooldown (%s s windup)" % [_n(b.damage), _n(b.radius), _n(b.stun), _n(b.knockback), _n(b.cooldown), _n(b.windup)]])
	rows.append(["Sight", "%s m, %s deg cone" % [_n(def.sight_range), _n(def.sight_half_angle_deg * 2.0)]])
	rows.append(["Hearing", "%s m" % _n(def.hearing_range)])
	rows.append(["Weight class", weight.get(def.weight, str(def.weight))])
	rows.append(["Spawn cost", _n(def.cost)])
	var body: Dictionary = c.get("body", {})
	rows.append(["Body", "%s m tall, %s m radius" % [_n(body.get("height")), _n(body.get("radius"))]])
	var limbs: Dictionary = c.get("limbs", {})
	if not limbs.is_empty():
		var parts := PackedStringArray()
		for k in limbs:
			var l: Dictionary = limbs[k]
			parts.append("%s %s%s" % [k, _n(l.get("health")), " (kills)" if l.get("kills", false) else ""])
		rows.append(["Shootable limbs", ", ".join(parts)])
	return {
		"name": def.display_name,
		"npc_id": String(def.id),
		"summary": {"Health": _n(def.max_health), "Damage": "%s %s" % [primary_dmg, primary] if primary != "" else "-", "Weight": weight.get(def.weight, "")},
		"rows": rows,
	}


## A number as a reader writes it: 2200, 0.45, 12.5.
static func _n(v: Variant) -> String:
	if v == null:
		return "-"
	var f := float(v)
	if is_equal_approx(f, roundf(f)):
		return str(int(roundf(f)))
	return ("%.2f" % f).rstrip("0").rstrip(".")
