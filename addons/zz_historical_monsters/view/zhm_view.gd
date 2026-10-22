extends Node3D

## Draws one monster: loads its skinned model and poses the skeleton from what the monster looks
## like it is doing ([member anim]).
##
## [b]Server and client share it, and a server never renders.[/b] The body's simulation does not
## read the pose back, so under the headless display driver [method _process] does nothing at all:
## thirty monsters' skeletons are not worth a server's tick. A suite or a screenshot calls
## [method step] by hand.
##
## [b]No `class_name`[/b], like every script the Workshop form of this pack loads: a mounted pack's
## globals do not register. The body names this by path.

const Pose := preload("zhm_pose.gd")

## Which monster: `trex`, `tiger` or `bear`. Set before the node enters the tree.
var species: StringName = &"trex"
## The model, relative to the addon's root: `monsters/<species>.glb` by default.
var model_path: String = ""
## What it looks like it is doing, a [enum ZhmPose.Anim] value.
var anim: int = Pose.Anim.IDLE:
	set(value):
		if value != anim:
			anim = value
			_anim_t = 0.0
## Which side of a combo, for clips that alternate.
var variant: int = 0
## Horizontal speed, m/s, for the gait.
var speed: float = 0.0
## Set by a suite or a screenshot that steps the view itself.
var manual: bool = false
## Seconds since the clip began. Reset when [member anim] changes.
var _anim_t: float = 0.0

var skeleton: Skeleton3D = null
var _pivot: Node3D = null
var _bones: Dictionary = {}
var _order: Array[int] = []
var _rest_local: Array[Transform3D] = []
var _rest_global_basis: Array[Basis] = []
var _phase: float = 0.0
var _clock: float = 0.0
var _body_height: float = 2.0
var _body_length: float = 3.0
var _dead_fall: float = 0.0


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	var path := model_path if model_path != "" else _default_model()
	var packed: Variant = load(path) if ResourceLoader.exists(path) else null
	if not (packed is PackedScene):
		push_error("ZhmView: no model at %s" % path)
		return
	var model := (packed as PackedScene).instantiate()
	_pivot.add_child(model)
	skeleton = _find_skeleton(model)
	_use_vertex_colour(model)

	if skeleton == null:
		push_error("ZhmView: %s has no skeleton" % path)
		return

	_index_bones()
	var aabb := _aabb_of(model)
	_body_height = aabb.size.y
	_body_length = aabb.size.z


func _default_model() -> String:
	var here: String = get_script().resource_path
	return here.get_base_dir().get_base_dir().path_join("monsters/%s.glb" % species)


## The model carries its colour in the vertices (no textures, so a pack stays small); the glTF
## importer does not always switch that on for a material that has no base colour of its own.
func _use_vertex_colour(n: Node) -> void:
	# Nothing is drawn headless, and the dummy renderer prints an error per override material
	# when the mesh is freed.
	if DisplayServer.get_name() == "headless":
		return
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var copy := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				copy.vertex_color_use_as_albedo = true
				mi.set_surface_override_material(s, copy)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _aabb_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a := mi.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _index_bones() -> void:
	var count := skeleton.get_bone_count()
	_rest_local.resize(count)
	_rest_global_basis.resize(count)
	for i in count:
		_bones[StringName(skeleton.get_bone_name(i))] = i
		_rest_local[i] = skeleton.get_bone_rest(i)
		_rest_global_basis[i] = skeleton.get_bone_global_rest(i).basis

	# Parents before children, whatever order the file wrote them in.
	var depth: Array[int] = []
	depth.resize(count)
	for i in count:
		var d := 0
		var p := skeleton.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = skeleton.get_bone_parent(p)
		depth[i] = d
	var idx: Array[int] = []
	for i in count:
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return depth[a] < depth[b])
	_order = idx


func has_bone(bone: StringName) -> bool:
	return _bones.has(bone)


func bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _bones.keys():
		out.append(String(k))
	return out


func _process(delta: float) -> void:
	if manual or DisplayServer.get_name() == "headless":
		return
	step(delta)


## Advances the clip and the gait by [param delta] and poses the skeleton.
func step(delta: float) -> void:
	_anim_t += delta
	_clock += delta
	_phase += speed * delta * Pose.stride(species)
	apply(_clock)


## Poses the skeleton for the current state, [param clock] seconds on a clock that never resets.
func apply(clock: float) -> void:
	if skeleton == null:
		return

	var pose := Pose.pose(species, anim, _anim_t, _phase, speed, variant)
	# The twitch in an idle runs on the monster's own clock, the clip on its own.
	var global_of: Array[Transform3D] = []
	global_of.resize(skeleton.get_bone_count())

	for i in _order:
		var rot: Vector3 = pose.get(StringName(skeleton.get_bone_name(i)), Vector3.ZERO)
		var d := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)), EULER_ORDER_YXZ)
		var rest := _rest_local[i]
		var rg := _rest_global_basis[i]
		# D is a rotation in the model's own axes; this is the same rotation in the bone's rest
		# frame, so that with every parent at rest the bone's global basis is exactly D * rest.
		var local_rot := rg.inverse() * d * rg
		var local := Transform3D(rest.basis * local_rot, rest.origin)
		var parent := skeleton.get_bone_parent(i)
		global_of[i] = local if parent < 0 else global_of[parent] * local
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())

	var root: Vector3 = pose.get(&"_root", Vector3.ZERO)
	var lift: float = pose.get(&"_lift", 0.0)
	var lunge: float = pose.get(&"_lunge", 0.0)
	_pivot.rotation = Vector3(deg_to_rad(root.x), deg_to_rad(root.y), deg_to_rad(root.z))
	# -Z is forward.
	_pivot.position = Vector3(0.0, lift * _body_height, -lunge * _body_length)


func describe() -> Dictionary:
	return {
		"species": String(species),
		"anim": Pose.Anim.keys()[anim] if anim >= 0 and anim < Pose.Anim.size() else str(anim),
		"bones": _bones.size(),
		"posed": skeleton != null,
	}
