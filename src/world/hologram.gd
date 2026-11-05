class_name Hologram
extends Node3D
## A giant holographic advert figure: a random character rendered as an additive
## hologram, several storeys tall, slowly turning and cycling through dances,
## waves and cheers - with a projector base, beam, sparks and a tagline.
## Placed on city plazas and some rooftops by LevelBuilder.

const TAGLINES := ["BREATHE PREMIUM", "OBEY & ENJOY", "YOU ARE VALUED*", "DEBT IS FREEDOM", "LOVE THE CONSORTIUM",
	"SMILE: YOU'RE BILLED", "PASTE+ NOW 4% PASTIER", "STAY LOYAL. STAY ALIVE.", "LUMEN: WATCH. MORE.", "AIR IS A LIFESTYLE"]
const ANIMS := ["dance", "wave", "cheer", "dance", "talk", "idle", "phone"]

@export var figure_scale := 2.7
@export var color_a := Color(0.25, 0.95, 1.0)
@export var color_b := Color(1.0, 0.25, 0.85)
@export var seed_value := 0
@export var with_base := true

var _sprite: BillboardSprite
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _next_anim := 0.0
var _next_look := 0.0
var _glitch := 0.0
var _label: Label3D


func _ready() -> void:
	_rng.seed = seed_value
	_t = _rng.randf() * 10.0
	if with_base:
		_build_base()
	_sprite = BillboardSprite.new()
	_sprite.holo = true
	_sprite.ground_align = false
	add_child(_sprite)
	_sprite.set_look(CharacterLook.random_look(_rng, ["hero", "corporate", "punk", "civilian"][_rng.randi() % 4]))
	_sprite.scale_base = figure_scale
	_sprite.scale = Vector3.ONE * figure_scale
	var foot := float(_sprite.meta.get("foot_row", 60))
	var fh := float(_sprite.meta.get("frame_h", 64))
	_sprite.position.y = (foot - fh * 0.5) * _sprite.pixel_size * figure_scale + (0.45 if with_base else 0.0)
	_apply_colors()
	_sprite.play(ANIMS[_rng.randi() % ANIMS.size()])
	_next_anim = _rng.randf_range(4.0, 8.0)
	_next_look = _rng.randf_range(14.0, 26.0)


func _build_base() -> void:
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.35
	cyl.height = 0.35
	cyl.radial_segments = 16
	ring.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.16)
	m.metallic = 0.7
	m.roughness = 0.3
	ring.material_override = m
	ring.position.y = 0.17
	add_child(ring)
	var lens := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	disc.radial_segments = 16
	lens.mesh = disc
	var lm := StandardMaterial3D.new()
	lm.albedo_color = color_a
	lm.emission_enabled = true
	lm.emission = color_a
	lm.emission_energy_multiplier = 5.0
	lens.material_override = lm
	lens.position.y = 0.37
	add_child(lens)
	# Projection cone.
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = figure_scale * 0.55
	cm.bottom_radius = 0.9
	cm.height = figure_scale * 2.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	bm.albedo_color = Color(color_a.r, color_a.g, color_a.b, 0.06)
	bm.albedo_texture = load("res://assets/textures/light_shaft.png")
	cone.material_override = bm
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position.y = 0.4 + figure_scale
	add_child(cone)
	# Rising data sparks.
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.2
	p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.0
	p.emission_ring_inner_radius = 0.6
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 6.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.18)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	pm.billboard_keep_scale = true
	pm.albedo_color = Color(color_a.r * 2.0, color_a.g * 2.0, color_a.b * 2.0)
	q.material = pm
	p.mesh = q
	p.position.y = 0.4
	add_child(p)
	var light := OmniLight3D.new()
	light.light_color = color_a
	light.light_energy = 2.5
	light.omni_range = 9.0
	light.position = Vector3(0, 2.0, 1.0)
	add_child(light)
	_label = Label3D.new()
	_label.text = Copy.make("slogan", _rng) if _rng.randf() < 0.7 else TAGLINES[_rng.randi() % TAGLINES.size()]
	_label.font_size = 96
	_label.pixel_size = 0.012
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.modulate = Color(color_b.r * 2.2, color_b.g * 2.2, color_b.b * 2.2, 0.9)
	_label.outline_size = 0
	_label.no_depth_test = false
	_label.font_size = 64
	_label.pixel_size = 0.008
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 560  # ~4.5 m: long generated slogans wrap instead of running off the plaza
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.position = Vector3(0, 0.75, 1.45)  # ticker on the projector rim, always in frame
	add_child(_label)


func _apply_colors() -> void:
	if _sprite and _sprite.material_override is ShaderMaterial:
		var m: ShaderMaterial = _sprite.material_override
		m.set_shader_parameter("holo_a", color_a)
		m.set_shader_parameter("holo_b", color_b)


func _process(delta: float) -> void:
	_t += delta
	if _sprite == null:
		return
	# Slow turntable so the figure shows off all 8 facings.
	var ang := _t * 0.35
	_sprite.set_facing(Vector3(sin(ang), 0, cos(ang)))
	_next_anim -= delta
	if _next_anim <= 0.0:
		_next_anim = _rng.randf_range(4.0, 9.0)
		_sprite.play(ANIMS[_rng.randi() % ANIMS.size()], true)
	_next_look -= delta
	if _next_look <= 0.0:
		# "Channel change": glitch out, swap to a new figure.
		_next_look = _rng.randf_range(14.0, 26.0)
		_glitch = 0.6
		_sprite.set_look(CharacterLook.random_look(_rng, ["hero", "corporate", "punk", "civilian", "robot"][_rng.randi() % 5]))
		_apply_colors()
		if _label:
			_label.text = Copy.make("slogan", _rng) if _rng.randf() < 0.7 else TAGLINES[_rng.randi() % TAGLINES.size()]
	if _glitch > 0.0:
		_glitch = maxf(0.0, _glitch - delta)
		_sprite.visible = fmod(_t, 0.1) > 0.03
		if _sprite.material_override is ShaderMaterial:
			(_sprite.material_override as ShaderMaterial).set_shader_parameter("glitch", _glitch * 3.0)
	else:
		_sprite.visible = true
