class_name Critter
extends Node3D
## Ambient life. No gameplay, just a world that keeps moving:
##   "bot"    : little maintenance robot puttering around the floor, blinking
##   "drone"  : ad-drone cruising overhead with a spotlight and a sales pitch
##   "flyby"  : a distant ship crossing the space backdrop behind station windows

@export_enum("bot", "drone", "flyby") var kind := "bot"
var bounds := Rect2(0, 0, 40, 40)
var seed_value := 0

var _rng := RandomNumberGenerator.new()
var _target := Vector3.ZERO
var _speed := 1.0
var _t := 0.0
var _blink: MeshInstance3D
var _wait := 0.0
var _label: Label3D

const PITCHES := ["BUY!", "SALE!", "CONSUME", "50% OFF AIR", "OBEY*", "*terms apply", "NEW!", "TRY PASTE"]


func _ready() -> void:
	_rng.seed = seed_value
	_t = _rng.randf() * 10.0
	match kind:
		"bot":
			_build_bot()
		"drone":
			_build_drone()
		"flyby":
			_build_flyby()
	_pick_target()
	if kind != "flyby":
		position = _target
		_pick_target()


func _mat(color: Color, emit: float = 0.0, metal: float = 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = 0.4
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_bot() -> void:
	var dome := SphereMesh.new()
	dome.radius = 0.32
	dome.height = 0.32
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 3
	_add(dome, _mat(Color(0.85, 0.82, 0.7)), Vector3(0, 0.08, 0))
	var base := CylinderMesh.new()
	base.top_radius = 0.34
	base.bottom_radius = 0.34
	base.height = 0.1
	base.radial_segments = 10
	_add(base, _mat(Color(0.25, 0.25, 0.3)), Vector3(0, 0.06, 0))
	var led := SphereMesh.new()
	led.radius = 0.05
	led.height = 0.1
	_blink = _add(led, _mat(Color(0.3, 1.0, 0.5), 6.0), Vector3(0, 0.36, 0.1), false)
	_speed = _rng.randf_range(0.6, 1.1)


func _build_drone() -> void:
	var body := SphereMesh.new()
	body.radius = 0.3
	body.height = 0.4
	body.radial_segments = 8
	body.rings = 4
	_add(body, _mat(Color(0.75, 0.7, 0.3), 0.0, 0.6), Vector3.ZERO)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.5
	ring.bottom_radius = 0.5
	ring.height = 0.04
	ring.radial_segments = 12
	_add(ring, _mat(Color(0.3, 0.3, 0.35)), Vector3(0, 0, 0))
	var eye := SphereMesh.new()
	eye.radius = 0.08
	eye.height = 0.16
	var col := [Color(1.0, 0.25, 0.8), Color(0.25, 0.9, 1.0), Color(1.0, 0.8, 0.2)][_rng.randi() % 3] as Color
	_blink = _add(eye, _mat(col, 7.0), Vector3(0, -0.05, 0.28), false)
	var spot := SpotLight3D.new()
	spot.light_color = col
	spot.light_energy = 3.0
	spot.spot_range = 7.0
	spot.spot_angle = 22.0
	spot.rotation_degrees.x = -90.0
	add_child(spot)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.modulate = col * 1.8
	_label.outline_size = 0
	_label.position = Vector3(0, 0.55, 0)
	_label.text = PITCHES[_rng.randi() % PITCHES.size()]
	add_child(_label)
	_speed = _rng.randf_range(1.5, 2.6)


func _build_flyby() -> void:
	var hull := CapsuleMesh.new()
	hull.radius = 0.5
	hull.height = 3.0
	hull.radial_segments = 6
	var h := _add(hull, _mat(Color(0.15, 0.14, 0.2)), Vector3.ZERO, false)
	h.rotation.z = PI * 0.5
	for i in 3:
		var light := SphereMesh.new()
		light.radius = 0.12
		light.height = 0.24
		_add(light, _mat([Color(1, 0.3, 0.3), Color(0.3, 1, 1), Color(1, 1, 0.6)][i], 8.0), Vector3(-1.0 + i * 1.0, 0.3, 0.4), false)
	var engine := SphereMesh.new()
	engine.radius = 0.35
	engine.height = 0.7
	_blink = _add(engine, _mat(Color(0.4, 0.8, 1.0), 9.0), Vector3(-1.7, 0, 0), false)
	_speed = _rng.randf_range(2.5, 5.0)


func _pick_target() -> void:
	match kind:
		"bot":
			_target = Vector3(_rng.randf_range(bounds.position.x, bounds.end.x), 0.0, _rng.randf_range(bounds.position.y, bounds.end.y))
		"drone":
			_target = Vector3(_rng.randf_range(bounds.position.x, bounds.end.x), _rng.randf_range(3.5, 5.5), _rng.randf_range(bounds.position.y, bounds.end.y))
		"flyby":
			var left := _rng.randf() < 0.5
			position = Vector3(bounds.position.x - 20.0 if left else bounds.end.x + 20.0, _rng.randf_range(1.5, 4.5), bounds.position.y)
			_target = Vector3(bounds.end.x + 20.0 if left else bounds.position.x - 20.0, position.y + _rng.randf_range(-1, 1), bounds.position.y)
			scale = Vector3(-1 if not left else 1, 1, 1) * _rng.randf_range(0.6, 1.2)


func _process(delta: float) -> void:
	_t += delta
	if _blink:
		_blink.visible = fmod(_t, 1.2) < 0.9 if kind == "bot" else true
	if _wait > 0.0:
		_wait -= delta
		return
	var to := _target - position
	if kind == "bot":
		to.y = 0.0
	if to.length() < 0.3:
		if kind == "flyby":
			_wait = _rng.randf_range(4.0, 14.0)
		else:
			_wait = _rng.randf_range(0.5, 3.0)
			if _label:
				_label.text = PITCHES[_rng.randi() % PITCHES.size()]
		_pick_target()
		return
	position += to.normalized() * minf(_speed * delta, to.length())
	if kind == "drone":
		position.y += sin(_t * 2.2) * 0.005
		rotation.z = clampf(-to.normalized().x * 0.3, -0.3, 0.3)
	elif kind == "bot":
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 6.0 * delta)
