class_name BillboardSprite
extends Sprite3D
## HD-2D character sprite: pixel-art frames on a Y-axis billboard that always
## faces the camera, is LIT by the scene's 3D lights and CASTS real shadows.
##
## Sheets come from tools/sprite_forge.py (or hand-drawn art with the same
## layout): <name>.png + <name>.json describing frame size, animations and one
## atlas row per (animation, direction). Directions S, SE, E, NE, N are drawn;
## SW, W, NW are mirrored, giving 8-way facing.

signal animation_finished(anim: String)

const SECTORS := [["S", false], ["SE", false], ["E", false], ["NE", false], ["N", false], ["NE", true], ["E", true], ["SE", true]]
const DEFAULT_PIXEL_SIZE := 0.034
const INDEXED_SHADER := preload("res://assets/shaders/indexed_sprite.gdshader")

static var _meta_cache: Dictionary = {}

## File name under res://assets/sprites/characters/ without extension.
@export var sheet_name := "h00":
	set(value):
		sheet_name = value
		if is_inside_tree():
			_load_sheet()
@export var ground_align := true

var meta: Dictionary = {}
var current := ""
var finished := false
var direction := "S"
var mirrored := false
var speed_scale := 1.0
var base_modulate := Color.WHITE
var frame_index := 0
var scale_base := 1.0

var _time := 0.0
var _fw := 48
var _fh := 64
var _flash_time := 0.0
var _flash_color := Color.WHITE
var _squash := Vector2.ONE
var _base_y := 0.0
var _mat: ShaderMaterial
var _look: Dictionary = {}
var _alpha := 1.0


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shaded = true
	double_sided = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	region_enabled = true
	if is_equal_approx(pixel_size, 0.01) or is_equal_approx(pixel_size, 0.045):
		pixel_size = DEFAULT_PIXEL_SIZE
	_load_sheet()
	play("idle")


## Apply a CharacterLook ({variant, colors}). Works before or after _ready.
func set_look(look: Dictionary) -> void:
	if look.is_empty():
		return
	_look = look
	sheet_name = str(look.get("variant", sheet_name))
	if is_inside_tree():
		_load_sheet()


func get_look() -> Dictionary:
	return _look


static func load_meta(sheet: String) -> Dictionary:
	if _meta_cache.has(sheet):
		return _meta_cache[sheet]
	var path := "res://assets/sprites/characters/%s.json" % sheet
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
	_meta_cache[sheet] = data
	return data


func _load_sheet() -> void:
	var path := "res://assets/sprites/characters/%s.png" % sheet_name
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		push_warning("BillboardSprite: missing sheet %s" % path)
	meta = load_meta(sheet_name)
	_fw = int(meta.get("frame_w", 48))
	_fh = int(meta.get("frame_h", 64))
	if meta.get("indexed", false):
		if _look.is_empty():
			_look = {"variant": sheet_name, "colors": CharacterLook.random_colors(RandomNumberGenerator.new(), "civilian")}
		_mat = ShaderMaterial.new()
		_mat.shader = INDEXED_SHADER
		_mat.set_shader_parameter("sheet", texture)
		_mat.set_shader_parameter("palette", CharacterLook.palette_texture(_look.get("colors", {})))
		material_override = _mat
	else:
		material_override = null
		_mat = null
	if ground_align:
		var foot := float(meta.get("foot_row", _fh - 4))
		_base_y = (foot - _fh * 0.5) * pixel_size
		position.y = _base_y
	if current != "":
		_apply_frame()


func has_anim(anim: String) -> bool:
	return meta.get("anims", {}).has(anim)


func play(anim: String, restart: bool = false) -> void:
	if not has_anim(anim):
		anim = "idle" if has_anim("idle") else anim
	if anim == current and not restart:
		return
	current = anim
	finished = false
	_time = 0.0
	_apply_frame()


func anim_length(anim: String) -> float:
	var a: Dictionary = meta.get("anims", {}).get(anim, {})
	if a.is_empty():
		return 0.3
	return float(a.get("frames", 1)) / maxf(1.0, float(a.get("fps", 10)))


## Face a world-space direction (XZ). Camera yaw is fixed, so world +Z = screen down.
func set_facing(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.05:
		return
	var ang := atan2(dir.x, dir.z)  # 0 = toward camera (S), +PI/2 = screen right (E)
	var sector := posmod(roundi(ang / (PI / 4.0)), 8)
	direction = SECTORS[sector][0]
	mirrored = SECTORS[sector][1]
	_apply_frame()


## Legacy helper: face left/right by screen X.
func face(direction_x: float) -> void:
	if absf(direction_x) > 0.05:
		set_facing(Vector3(direction_x, 0, 0.35))


func flash(color: Color = Color(3.0, 3.0, 3.0), duration: float = 0.08) -> void:
	_flash_color = color
	_flash_time = duration


## Squash & stretch: e.g. squash(Vector2(1.25, 0.8)) on landing; springs back.
func squash(amount: Vector2) -> void:
	_squash = amount


func _process(delta: float) -> void:
	if current != "":
		var before := frame_index
		_time += delta * speed_scale
		_apply_frame()
		if finished and before != frame_index:
			animation_finished.emit(current)
	if _flash_time > 0.0:
		_flash_time -= delta
		if _mat:
			_mat.set_shader_parameter("flash", 0.85)
			_mat.set_shader_parameter("flash_color", Color(clampf(_flash_color.r / 3.0, 0, 1), clampf(_flash_color.g / 3.0, 0, 1), clampf(_flash_color.b / 3.0, 0, 1)))
		else:
			modulate = _flash_color
	else:
		if _mat:
			_mat.set_shader_parameter("flash", 0.0)
			_mat.set_shader_parameter("tint", base_modulate)
		else:
			modulate = base_modulate
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	scale = Vector3(_squash.x, _squash.y, 1.0) * scale_base
	if ground_align:
		position.y = _base_y * _squash.y * scale_base


func _apply_frame() -> void:
	var anims: Dictionary = meta.get("anims", {})
	if not anims.has(current):
		return
	var a: Dictionary = anims[current]
	var count := int(a.get("frames", 1))
	var idx := int(_time * float(a.get("fps", 10)))
	if a.get("loop", true):
		idx = idx % count
	elif idx >= count:
		idx = count - 1
		finished = true
	frame_index = idx
	var rows: Dictionary = a.get("rows", {})
	var row := int(rows.get(direction, rows.get("S", 0)))
	region_rect = Rect2(idx * _fw, row * _fh, _fw, _fh)
	flip_h = mirrored


## Fade the whole sprite (dithered, keeps shadows) - use instead of modulate:a.
func fade_to(target_alpha: float, duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_alpha, _alpha, target_alpha, duration)


func _set_alpha(a: float) -> void:
	_alpha = a
	if _mat:
		_mat.set_shader_parameter("alpha", a)
	else:
		modulate.a = a


## Leave a fading ghost copy behind (dash afterimages, speed lines).
func spawn_afterimage(tint: Color = Color(0.4, 1.0, 1.0, 0.6), life: float = 0.28) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	if _mat:
		var g := Sprite3D.new()
		g.texture = texture
		g.region_enabled = true
		g.region_rect = region_rect
		g.flip_h = flip_h
		g.pixel_size = pixel_size
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gm: ShaderMaterial = _mat.duplicate()
		gm.set_shader_parameter("ghost", true)
		gm.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
		gm.set_shader_parameter("alpha", tint.a)
		g.material_override = gm
		parent.add_child(g)
		g.global_transform = global_transform
		var gt := g.create_tween()
		gt.tween_method(func(a: float): gm.set_shader_parameter("alpha", a), tint.a, 0.0, life)
		gt.tween_callback(g.queue_free)
		return
	var ghost := Sprite3D.new()
	ghost.texture = texture
	ghost.region_enabled = true
	ghost.region_rect = region_rect
	ghost.flip_h = flip_h
	ghost.pixel_size = pixel_size
	ghost.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	ghost.shaded = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.modulate = Color(tint.r * 1.6, tint.g * 1.6, tint.b * 1.6, tint.a)
	parent.add_child(ghost)
	ghost.global_transform = global_transform
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, life)
	tw.tween_callback(ghost.queue_free)
