class_name FXSprite
extends Sprite3D
## One-shot pixel-art effect from assets/sprites/fx/<name>.png (see tools/gen_fx.py).
## Unshaded + HDR modulate so the scene bloom makes it glow.

static var _meta: Dictionary = {}

var fx_name := ""
var fps := 20.0
var frames := 1
var loop := false
var _fw := 32
var _fh := 32
var _t := 0.0


static func meta() -> Dictionary:
	if _meta.is_empty():
		var path := "res://assets/sprites/fx/fx.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_meta = parsed
	return _meta


## Spawn an effect. glow > 1 brightens (bloom). flat=true lays it on the floor.
static func play_at(parent: Node, fx: String, pos: Vector3, size: float = 1.0, glow: float = 2.0,
		tint: Color = Color.WHITE, flip: bool = false, flat: bool = false, rotation_z: float = 0.0) -> FXSprite:
	if parent == null or not parent.is_inside_tree():
		return null
	var m: Dictionary = meta().get(fx, {})
	if m.is_empty():
		return null
	var s := FXSprite.new()
	s.fx_name = fx
	s.texture = load("res://assets/sprites/fx/%s.png" % fx)
	s._fw = int(m.get("w", 32))
	s._fh = int(m.get("h", 32))
	s.frames = int(m.get("frames", 1))
	s.fps = float(m.get("fps", 20))
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, s._fw, s._fh)
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.transparent = true
	s.no_depth_test = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.pixel_size = 0.034 * size
	s.flip_h = flip
	s.modulate = Color(tint.r * glow, tint.g * glow, tint.b * glow, tint.a)
	if flat:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.rotation_degrees.x = -90.0
	else:
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.rotation.z = rotation_z
	parent.add_child(s)
	s.global_position = pos
	return s


func _process(delta: float) -> void:
	_t += delta
	var idx := int(_t * fps)
	if idx >= frames:
		if loop:
			idx = idx % frames
		else:
			queue_free()
			return
	region_rect = Rect2(idx * _fw, 0, _fw, _fh)
