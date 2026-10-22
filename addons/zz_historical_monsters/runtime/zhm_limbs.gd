extends Node

## Shootable limbs for one monster: which region a point is in, how much each limb has taken, and which are
## gone. The regions and numbers are data (`limbs:` in cfg/addons/zz_historical_monsters/<species>.yml); this
## node is the same for every species and has no combat import, so any game's shot code can drive it:
## `body.zhm_limb_hit(world_point, damage, impulse)`. No `class_name`: a mounted pack's globals do not register.
##
## A server has no model, so region geometry comes from the rest pose of the species' skeleton, read once and
## cached (`rest_points`). A drawn monster uses its live skeleton instead, so a raised head is where it is drawn.

const CHANNEL := "zhm.limbs"
## Bits of the replicated mask: the limbs of one species, in config order.
const MAX_LIMBS := 8

## A limb came off. `info`: `point` (world), `impulse`, `limb` def.
signal severed(limb: StringName, info: Dictionary)

var species: StringName = &""
## `bones[0]` is the joint that comes off with everything below it. `{limb: {bones: [...], radius, health, kills?, slow?, attack?, damage_scale?, tip?}}` in config order.
var defs: Dictionary = {}
var view: Node3D = null

var _health: Dictionary = {}
var _gone: Dictionary = {}

static var _rest_cache: Dictionary = {}


func setup(p_species: StringName, p_defs: Dictionary, p_view: Node3D) -> void:
	species = p_species
	view = p_view
	defs = {}
	for k in p_defs:
		if p_defs[k] is Dictionary and (p_defs[k] as Dictionary).get("bones") is Array and defs.size() < MAX_LIMBS:
			defs[StringName(k)] = p_defs[k]
	_health.clear()
	_gone.clear()
	for k in defs:
		_health[k] = float((defs[k] as Dictionary).get("health", 100.0))


func limb_names() -> Array:
	return defs.keys()


func is_severed(limb: StringName) -> bool:
	return _gone.has(limb)


## Bit `i` is set when the `i`th limb in config order is gone. Replicated as one small integer.
func mask() -> int:
	var m := 0
	var i := 0
	for k in defs:
		if _gone.has(k):
			m |= 1 << i
		i += 1
	return m


## Client: brings the severed set to [param m]. Only ever severs (a limb never grows back).
func apply_mask(m: int) -> void:
	var i := 0
	for k in defs.keys():
		if m & (1 << i) and not _gone.has(k):
			sever(k, Vector3.INF, Vector3.ZERO)
		i += 1


## The nearest intact limb whose region contains [param world_point], or `&""`.
func limb_at(world_point: Vector3) -> StringName:
	var best: StringName = &""
	var best_gap := 0.0
	for k in defs:
		if _gone.has(k):
			continue
		var d := defs[k] as Dictionary
		var gap := _distance(d, world_point) - float(d.get("radius", 0.3))
		# Listed order breaks a tie, so the head (first) wins where it overlaps the neck.
		if gap <= 0.0 and (best == &"" or gap < best_gap - 0.05):
			best = k
			best_gap = gap
	return best


## Hurts the limb at [param world_point]. Returns the limb it severed, or `&""` (nothing there, or it held).
func hit(world_point: Vector3, damage: float, impulse: Vector3 = Vector3.ZERO) -> StringName:
	var k := limb_at(world_point)
	if k == &"" or damage <= 0.0:
		return &""
	_health[k] = float(_health[k]) - damage * float((defs[k] as Dictionary).get("damage_scale", 1.0))
	if float(_health[k]) > 0.0:
		return &""
	sever(k, world_point, impulse)
	return k


## Takes a limb off, whatever it has left. [param world_point] is where it was cut (`Vector3.INF` to use the
## joint).
func sever(limb: StringName, world_point: Vector3, impulse: Vector3) -> void:
	if not defs.has(limb) or _gone.has(limb):
		return
	_gone[limb] = true
	_health[limb] = 0.0
	var d := defs[limb] as Dictionary
	var at := world_point
	if view != null and view.has_method(&"sever_limb"):
		at = view.call(&"sever_limb", limb, d, impulse)
	DotLog.debug(CHANNEL, "limb severed", {"species": String(species), "limb": String(limb)})
	severed.emit(limb, {"point": at, "impulse": impulse, "def": d})


## Product of `slow` over the limbs that are gone: legs lost make a monster crawl. Never below 0.2.
func speed_scale() -> float:
	var s := 1.0
	for k in _gone:
		s *= float((defs[k] as Dictionary).get("slow", 1.0))
	return maxf(s, 0.2)


## Product of `attack` over the lost limbs: an arm lost hits softer.
func attack_scale() -> float:
	var s := 1.0
	for k in _gone:
		s *= float((defs[k] as Dictionary).get("attack", 1.0))
	return s


func describe() -> Dictionary:
	var gone := PackedStringArray()
	for k in _gone:
		gone.append(String(k))
	return {"limbs": defs.size(), "severed": gone, "mask": mask()}


# --- Geometry ---------------------------------------------------------------------------------------------

## World-space polyline of a limb: each of its bones' origins, then a tip past the last one.
func points_of(d: Dictionary) -> PackedVector3Array:
	var bones: Array = d.get("bones", [])
	var out := PackedVector3Array()
	var live: Skeleton3D = view.get("skeleton") if view != null else null
	if live != null:
		for b in bones:
			var i := live.find_bone(String(b))
			if i >= 0:
				out.append(live.global_transform * live.get_bone_global_pose(i).origin)
				if out.size() == 1 and bones.size() == 1 and live.get_bone_parent(i) >= 0:
					out.insert(0, live.global_transform * live.get_bone_global_pose(live.get_bone_parent(i)).origin)
		_add_tip(out, d)
		return out
	var rest := rest_points(species)
	var host := get_parent() as Node3D
	var xf := host.global_transform if host != null and host.is_inside_tree() else Transform3D.IDENTITY
	for b in bones:
		if rest.has(StringName(b)):
			out.append(xf * (rest[StringName(b)] as Vector3))
			if out.size() == 1 and bones.size() == 1 and rest.has(rest.get("@" + String(b), &"")):
				out.insert(0, xf * (rest[rest["@" + String(b)]] as Vector3))
	_add_tip(out, d)
	return out


func _add_tip(out: PackedVector3Array, d: Dictionary) -> void:
	if out.size() >= 2:
		var dir := out[out.size() - 1] - out[out.size() - 2]
		if dir.length() > 0.001:
			out.append(out[out.size() - 1] + dir.normalized() * float(d.get("tip", 0.0)))
	elif out.size() == 1:
		out.append(out[0])


func _distance(d: Dictionary, p: Vector3) -> float:
	var pts := points_of(d)
	if pts.is_empty():
		return INF
	var best := INF
	for i in pts.size():
		var a := pts[i]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 0.000001 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Bone name to origin in the body's own space, at rest, read from the species' model once and kept.
static func rest_points(sp: StringName) -> Dictionary:
	if _rest_cache.has(sp):
		return _rest_cache[sp]
	var out := {}
	var path := (new().get_script() as Script).resource_path.get_base_dir().get_base_dir().path_join("monsters/%s.glb" % sp)
	if ResourceLoader.exists(path):
		var packed: Variant = load(path)
		if packed is PackedScene:
			var model := (packed as PackedScene).instantiate()
			var skel := model.find_children("*", "Skeleton3D", true, false)
			if not skel.is_empty():
				var sk := skel[0] as Skeleton3D
				var to_model := Transform3D.IDENTITY
				var n: Node = sk
				while n != null and n != model:
					if n is Node3D:
						to_model = (n as Node3D).transform * to_model
					n = n.get_parent()
				if model is Node3D:
					to_model = (model as Node3D).transform * to_model
				for i in sk.get_bone_count():
					out[StringName(sk.get_bone_name(i))] = to_model * sk.get_bone_global_rest(i).origin
					if sk.get_bone_parent(i) >= 0:
						out["@" + sk.get_bone_name(i)] = StringName(sk.get_bone_name(sk.get_bone_parent(i)))
			model.free()
	_rest_cache[sp] = out
	return out
