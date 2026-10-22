extends CharacterBody3D

## One monster's body: a collider on the floor and, where something is drawn, the skinned model.
## No `class_name` (a mounted pack's globals do not register); the scene names this by path. Headless loads
## no model: only [member action], one integer, replicates, and a client's body picks the clip by it.

const Pose := preload("../view/zhm_pose.gd")
const View := preload("../view/zhm_view.gd")
const Limbs := preload("zhm_limbs.gd")

## A limb came off: `limb`, and `info` with `point`, `impulse`, `def`. The brain listens; a host may too.
signal limb_severed(limb: StringName, info: Dictionary)

var species: StringName = &""
## What the brain says it is doing, a [enum ZhmPose.Anim], or -1 to let the gait decide.
var action: int = -1
## Which side of a combo.
var variant: int = 0
## Loads the model even without a display. For the suite.
var force_view: bool = false

var view: Node3D = null
var limbs: Node = null
## Replicated: bit `i` set when the `i`th limb (config order) is gone. Setting it severs the missing ones.
var limb_mask: int = 0:
	set(value):
		limb_mask = value
		if limbs != null and value != limbs.call(&"mask"):
			limbs.call(&"apply_mask", value)
var _shape: CollisionShape3D = null
var _last_pos: Vector3 = Vector3.ZERO
var _speed: float = 0.0


## Sizes the collider and, when something is drawn, loads the model. Called by the brain once.
func setup(p_species: StringName, body: Dictionary, limb_defs: Dictionary = {}) -> void:
	species = p_species
	var radius := float(body.get("radius", 0.6))
	var height := maxf(float(body.get("height", 1.8)), radius * 2.0 + 0.1)

	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Collision"
		add_child(_shape)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	_shape.shape = capsule
	_shape.position.y = height * 0.5

	if view == null and (force_view or DisplayServer.get_name() != "headless"):
		view = View.new()
		view.species = species
		view.name = "View"
		add_child(view)

	if limbs == null:
		limbs = Limbs.new()
		limbs.name = "Limbs"
		add_child(limbs)
		limbs.connect(&"severed", _on_severed)
	limbs.call(&"setup", species, limb_defs, view)
	if limb_mask != 0:
		limbs.call(&"apply_mask", limb_mask)

	# A client's mirror is set up before it is in the tree, where global_position is an error.
	_last_pos = global_position if is_inside_tree() else position


func _ready() -> void:
	_last_pos = global_position


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved := global_position - _last_pos
	moved.y = 0.0
	# Smoothed, so a one-frame hitch does not flick the gait.
	_speed = lerpf(_speed, moved.length() / delta, clampf(delta * 8.0, 0.0, 1.0))
	_last_pos = global_position

	if view != null:
		view.speed = _speed
		view.variant = variant
		view.anim = effective_anim()


## What to draw: the brain's action, else the gait for how fast it is going.
func effective_anim() -> int:
	if action >= 0:
		return action
	if _speed < 0.4:
		return Pose.Anim.IDLE
	return Pose.Anim.RUN if _speed > 5.0 else Pose.Anim.WALK


## The seam for a game's shot code: hurts the limb at [param world_point]; returns the limb it took off, or
## `&""`. Call it on the server beside the damage the shot does to the monster itself.
func zhm_limb_hit(world_point: Vector3, damage: float, impulse: Vector3 = Vector3.ZERO) -> StringName:
	return limbs.call(&"hit", world_point, damage, impulse) if limbs != null else &""


## The intact limb at [param world_point], or `&""`: for a game that wants to know before it decides.
func zhm_limb_at(world_point: Vector3) -> StringName:
	return limbs.call(&"limb_at", world_point) if limbs != null else &""


func _on_severed(limb: StringName, info: Dictionary) -> void:
	limb_mask = limbs.call(&"mask")
	limb_severed.emit(limb, info)


## Speed multiplier from lost limbs (legs), and the damage multiplier from lost arms.
func speed_scale() -> float:
	return limbs.call(&"speed_scale") if limbs != null else 1.0


func attack_scale() -> float:
	return limbs.call(&"attack_scale") if limbs != null else 1.0


func gait_speed() -> float:
	return _speed


func describe() -> Dictionary:
	return {
		"species": String(species),
		"action": Pose.Anim.keys()[action] if action >= 0 else "gait",
		"speed": snappedf(_speed, 0.1),
		"drawn": view != null,
		"limbs": limbs.call(&"describe") if limbs != null else {},
	}
