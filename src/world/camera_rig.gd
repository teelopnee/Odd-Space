class_name CameraRig
extends Node3D
## HD-2D diorama camera: fixed yaw, tilted pitch, narrow FOV, plus the "lens":
## tilt-shift miniature blur, vignette, chromatic aberration, grain and split
## toning (assets/shaders/hd2d_post.gdshader). Also: smooth follow with
## look-ahead, combat framing (zooms out when enemies are near), zoom punches,
## screen shake, and fading of buildings that hide the player.

const POST := preload("res://assets/shaders/hd2d_post.gdshader")

@export var distance := 18.0
@export var pitch_degrees := 38.0
@export var fov := 33.0
@export var follow_speed := 6.5
@export var look_ahead := 1.6
## "tilt_shift" = screen-space HD-2D lens (default, works on every GPU)
## "physical"   = depth-based DOF via CameraAttributes (GPU/driver dependent)
## "off"        = lens effects off (fastest)
@export_enum("tilt_shift", "physical", "off") var dof_mode := "tilt_shift"
@export var dof_near_margin := 6.0
@export var dof_far_margin := 5.0
@export var dof_amount := 0.05

var target: Node3D
var camera: Camera3D
var attributes: CameraAttributesPractical
var post_rect: ColorRect
var post_mat: ShaderMaterial
var dof_enabled := false
var _shake := 0.0
var _punch := 0.0
var _punch_time := 0.0
var _combat_zoom := 0.0
var _ahead := Vector3.ZERO
var _faded: Dictionary = {}


func _ready() -> void:
	add_to_group("camera_rig")
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.3
	camera.far = 260.0
	attributes = CameraAttributesPractical.new()
	camera.attributes = attributes
	add_child(camera)
	camera.make_current()
	_apply_pose(0.0)
	var layer := CanvasLayer.new()
	layer.layer = 1  # under the HUD (layer 10)
	add_child(layer)
	post_rect = ColorRect.new()
	post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST
	post_rect.material = post_mat
	layer.add_child(post_rect)
	set_dof_mode(str(Game.settings.get("dof_mode", dof_mode)))


func configure(p_pitch: float, p_distance: float, p_fov: float) -> void:
	pitch_degrees = p_pitch
	distance = p_distance
	fov = p_fov
	if camera:
		camera.fov = fov
		_apply_pose(0.0)


func _apply_pose(extra_zoom: float) -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var dist := distance * (1.0 + extra_zoom)
	camera.position = Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	camera.rotation = Vector3(-pitch, 0, 0)


func set_dof_mode(mode: String) -> void:
	dof_mode = mode
	dof_enabled = mode == "physical"
	attributes.dof_blur_far_enabled = dof_enabled
	attributes.dof_blur_near_enabled = dof_enabled
	attributes.dof_blur_amount = dof_amount
	if post_mat:
		post_rect.visible = mode != "off"
		post_mat.set_shader_parameter("tilt_shift", mode == "tilt_shift")


func set_grade(shadow: Color, highlight: Color, toning: float = 0.22) -> void:
	if post_mat:
		post_mat.set_shader_parameter("shadow_tint", shadow)
		post_mat.set_shader_parameter("highlight_tint", highlight)
		post_mat.set_shader_parameter("toning", toning)


func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position + Vector3(0, 0.9, 0)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Quick zoom-in punch.
func punch(amount: float = 0.12, duration: float = 0.25) -> void:
	_punch = amount
	_punch_time = duration


func _process(delta: float) -> void:
	var rdelta := delta / maxf(Engine.time_scale, 0.05)  # real-time camera feel during slow-mo
	if target != null and is_instance_valid(target):
		var vel := Vector3.ZERO
		if target is CharacterBody3D:
			vel = (target as CharacterBody3D).velocity * Vector3(1, 0, 1)
		_ahead = _ahead.lerp(vel.limit_length(6.0) / 6.0 * look_ahead, 1.0 - exp(-3.0 * rdelta))
		var goal := target.global_position + Vector3(0, 0.9, 0) + _ahead
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * rdelta))
		# Combat framing: pull back a little when hostiles are around.
		var near := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.hostile and e.global_position.distance_to(target.global_position) < 11.0:
				near += 1
		_combat_zoom = lerpf(_combat_zoom, 0.12 if near > 0 else 0.0, 1.0 - exp(-1.5 * rdelta))
	var punch_amt := 0.0
	if _punch_time > 0.0:
		_punch_time -= rdelta
		punch_amt = -_punch * clampf(_punch_time / 0.25, 0.0, 1.0)
	_apply_pose(_combat_zoom + punch_amt)
	if _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.32
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.32
		_shake = maxf(0.0, _shake - rdelta * 2.6)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	if dof_enabled:
		var focus := camera.global_position.distance_to(global_position)
		attributes.dof_blur_far_distance = focus + dof_far_margin
		attributes.dof_blur_far_transition = 12.0
		attributes.dof_blur_near_distance = maxf(0.5, focus - dof_near_margin)
		attributes.dof_blur_near_transition = 4.0
	_update_occluders()


func _update_occluders() -> void:
	if target == null or not is_instance_valid(target):
		return
	var space := get_world_3d().direct_space_state
	var hits := {}
	var exclude: Array[RID] = []
	var from := camera.global_position
	var to := target.global_position + Vector3(0, 1.0, 0)
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to, 128, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		hits[hit.collider] = true
		exclude.append(hit.rid)
	for body in hits:
		if not _faded.has(body):
			_set_faded(body, true)
	for body in _faded.keys():
		if not hits.has(body):
			_set_faded(body, false)


func _set_faded(body: Object, faded: bool) -> void:
	if not is_instance_valid(body):
		_faded.erase(body)
		return
	if faded:
		_faded[body] = true
	else:
		_faded.erase(body)
	for mat in body.get_meta("fade_mats", []):
		var m: StandardMaterial3D = mat
		var tw := create_tween()
		tw.tween_property(m, "albedo_color:a", 0.22 if faded else 1.0, 0.2)
	for n in body.get_meta("fade_hide", []):
		if is_instance_valid(n):
			n.visible = not faded
