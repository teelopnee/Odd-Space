class_name LookPreview
extends TextureRect
## UI turntable for a CharacterLook: plays an animation and slowly turns through
## all 8 facings (west side mirrored, like the in-world BillboardSprite).

const SHADER := preload("res://assets/shaders/indexed_sprite_2d.gdshader")
const TURN := [["S", false], ["SE", false], ["E", false], ["NE", false], ["N", false], ["NE", true], ["E", true], ["SE", true]]

@export var anim := "idle"
@export var turn_every := 1.1  ## seconds per facing; 0 = always face south

var _look: Dictionary = {}
var _meta: Dictionary = {}
var _atlas := AtlasTexture.new()
var _mat := ShaderMaterial.new()
var _t := 0.0
var _turn := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mat.shader = SHADER
	material = _mat
	texture = _atlas
	if _look.is_empty():
		set_look(CharacterLook.default_look())


func set_look(look: Dictionary) -> void:
	_mat.shader = SHADER
	_look = look.duplicate(true)
	var variant := str(_look.get("variant", "h00"))
	var path := "res://assets/sprites/characters/%s.png" % variant
	if not ResourceLoader.exists(path):
		return
	_atlas.atlas = load(path)
	_meta = BillboardSprite.load_meta(variant)
	_mat.set_shader_parameter("palette", CharacterLook.palette_texture(_look.get("colors", {})))
	_update_frame()


## Multiplies the palette colours (e.g. near-black for an unrevealed silhouette).
func set_tint(c: Color) -> void:
	_mat.shader = SHADER
	_mat.set_shader_parameter("tint", c)


func get_look() -> Dictionary:
	return _look


func _process(delta: float) -> void:
	_t += delta
	if turn_every > 0.0 and _t >= turn_every * (_turn + 1):
		_turn += 1
	_update_frame()


func _update_frame() -> void:
	if _meta.is_empty():
		return
	var anims: Dictionary = _meta.get("anims", {})
	var a: Dictionary = anims.get(anim, anims.get("idle", {}))
	if a.is_empty():
		return
	var fw := int(_meta.get("frame_w", 64))
	var fh := int(_meta.get("frame_h", 64))
	var facing: Array = TURN[_turn % TURN.size()] if turn_every > 0.0 else TURN[0]
	var row := int(a.get("rows", {}).get(facing[0], 0))
	var frame := int(_t * float(a.get("fps", 8))) % maxi(1, int(a.get("frames", 1)))
	_atlas.region = Rect2(frame * fw, row * fh, fw, fh)
	flip_h = facing[1]
