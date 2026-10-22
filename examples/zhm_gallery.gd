extends Node3D

## A viewing stage for the monsters, and the render target of tools/screenshot.sh.
##
##   godot --path . res://examples/zhm_gallery.tscn -- --species trex --anims idle,walk,bite \
##       --cam three --out /tmp/shot
##
## Each clip is stepped at a fixed 60 fps for --t seconds (default: just past its strike) and the
## frame saved as <out>_<species>_<anim>.png, so a before and an after are the same picture. With
## no --out it just shows the monsters.

const Pose := preload("../addons/zz_historical_monsters/view/zhm_pose.gd")
const Config := preload("../addons/zz_historical_monsters/core/zhm_config.gd")
const View := preload("../addons/zz_historical_monsters/view/zhm_view.gd")

var _args := {}
var _view: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	_build_stage()
	var species := String(_args.get("species", "trex"))
	_view = View.new()
	_view.species = StringName(species)
	_view.manual = true
	add_child(_view)

	if not _args.has("out"):
		_view.manual = false
		_view.anim = Pose.Anim.WALK
		_view.speed = 2.0
		_frame_camera(String(_args.get("cam", "three")))
		return

	_run_shots.call_deferred()


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--"):
			out[argv[i].substr(2)] = argv[i + 1] if i + 1 < argv.size() else ""
			i += 2
		else:
			i += 1
	return out


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.58)
	env.ambient_light_energy = 2.2
	env.glow_enabled = true
	env.glow_intensity = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25.0, -150.0, 0.0)
	rim.light_energy = 1.0
	rim.light_color = Color(0.6, 0.7, 1.0)
	add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.18)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 40.0
	add_child(_cam)


func _frame_camera(mode: String) -> void:
	var sp := String(_args.get("species", "trex"))
	var size: float = {"trex": 11.5, "allosaurus": 8.5}.get(sp, 3.2)
	var h := size * 0.5
	var target := Vector3(0, h * 0.5, 0)
	var pos := Vector3.ZERO
	match mode:
		"side":
			pos = Vector3(size * 1.5, h * 0.6, 0)
		"front":
			pos = Vector3(0, h * 0.7, -size * 1.4)
			# Models face -Z; the camera looks back toward +Z.
		"head":
			var hp := Vector3(0, {"trex": 4.6, "allosaurus": 3.2, "raptor": 1.8, "tiger": 1.3, "thylacine": 1.2, "bear": 1.4}.get(sp, 1.5), -size * 0.42)
			target = hp
			pos = hp + Vector3(size * 0.2, size * 0.03, -size * 0.3)
		"back":
			pos = Vector3(size * 0.4, h * 0.8, size * 1.3)
		_:
			pos = Vector3(size * 0.95, h * 0.9, -size * 1.0)
	_cam.position = pos
	_cam.look_at(target, Vector3.UP)


func _run_shots() -> void:
	var out := String(_args["out"])
	var species := String(_args.get("species", "trex"))
	_frame_camera(String(_args.get("cam", "three")))
	var anims := String(_args.get("anims", "idle")).split(",")
	if _args.has("sever"):
		var defs: Dictionary = Config.load_config().species(StringName(species)).get("limbs", {})
		for k in String(_args["sever"]).split(","):
			if defs.has(k):
				_view.sever_limb(StringName(k), defs[k], Vector3(0, 0, -3))
		# the gib falls and the stump drips in real time
		await get_tree().create_timer(float(_args.get("wait", 0.7))).timeout
	var speeds := {"walk": 2.0, "run": 8.0, "stalk": 1.2, "charge": 12.0}
	for name in anims:
		var key := String(name).strip_edges().to_upper()
		var id: int = Pose.Anim.get(key, -1)
		if id < 0:
			push_error("no clip %s" % name)
			continue
		_view.anim = id
		_view.speed = float(speeds.get(String(name), 0.0))
		_view.variant = int(_args.get("variant", 0))
		var secs := float(_args.get("t", 0.5))
		var steps := int(secs * 60.0)
		for i in steps:
			_view.step(1.0 / 60.0)
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%s_%s.png" % [out, species, name]
		img.save_png(path)
		print("wrote ", path)
	get_tree().quit()
