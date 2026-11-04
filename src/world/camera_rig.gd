class_name CameraRig
extends Node3D
## HD-2D diorama camera: fixed yaw, steep-ish pitch, narrow FOV, and a
## tilt-shift depth of field (near + far blur around the player) which is
## what makes the 3D world read like a miniature. Also does screen shake and
## fades buildings that block the view of the player.

const TILT_SHIFT := preload("res://assets/shaders/tilt_shift.gdshader")

@export var distance := 18.0
@export var pitch_degrees := 38.0
@export var fov := 33.0
@export var follow_speed := 7.0
## "tilt_shift" = screen-space HD-2D miniature blur (default, works on every GPU)
## "physical"   = depth-based DOF via CameraAttributes (GPU/driver dependent)
## "off"        = everything sharp (fastest)
@export_enum("tilt_shift", "physical", "off") var dof_mode := "tilt_shift"
@export var dof_near_margin := 6.0
@export var dof_far_margin := 5.0
@export var dof_amount := 0.05

var target: Node3D
var camera: Camera3D
var attributes: CameraAttributesPractical
var tilt_shift_rect: ColorRect
var dof_enabled := false
var _shake := 0.0
var _faded: Dictionary = {}  # body -> true


func _ready() -> void:
	add_to_group("camera_rig")
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.3
	camera.far = 160.0
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0, 0)
	attributes = CameraAttributesPractical.new()
	camera.attributes = attributes
	add_child(camera)
	camera.make_current()
	# Tilt-shift overlay sits under the HUD (HUD is layer 10).
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	tilt_shift_rect = ColorRect.new()
	tilt_shift_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tilt_shift_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TILT_SHIFT
	tilt_shift_rect.material = mat
	layer.add_child(tilt_shift_rect)
	set_dof_mode(str(Game.settings.get("dof_mode", dof_mode)))


func set_dof_mode(mode: String) -> void:
	dof_mode = mode
	dof_enabled = mode == "physical"
	attributes.dof_blur_far_enabled = dof_enabled
	attributes.dof_blur_near_enabled = dof_enabled
	attributes.dof_blur_amount = dof_amount
	if tilt_shift_rect:
		tilt_shift_rect.visible = mode == "tilt_shift"


func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position + Vector3(0, 0.9, 0)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		var goal := target.global_position + Vector3(0, 0.9, 0)
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))
	if _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.35
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.35
		_shake = maxf(0.0, _shake - delta * 2.5)
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
		var body = hit.collider
		hits[body] = true
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
