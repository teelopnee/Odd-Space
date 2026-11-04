class_name BillboardSprite
extends Sprite3D
## HD-2D character sprite: a pixel-art sheet drawn on a Y-axis billboard that
## always faces the camera, is LIT by real 3D lights, and CASTS real shadows.
##
## Sheet layout (all characters share it, see tools/gen_sprites.py):
##   6 columns x 7 rows, each frame FRAME_W x FRAME_H px
##   row 0 idle(4) | 1 walk(6) | 2 roll/windup(4) | 3 attack(3)
##   row 4 guard/stagger(2) | 5 hurt(2) | 6 down/dead(3)

const FRAME_W := 32
const FRAME_H := 40
const COLUMNS := 6
const ROWS := 7
const ANIMS := {
	"idle": {"row": 0, "frames": 4, "fps": 5.0, "loop": true},
	"walk": {"row": 1, "frames": 6, "fps": 11.0, "loop": true},
	"roll": {"row": 2, "frames": 4, "fps": 13.0, "loop": false},
	"windup": {"row": 2, "frames": 4, "fps": 8.0, "loop": false},
	"attack": {"row": 3, "frames": 3, "fps": 12.0, "loop": false},
	"guard": {"row": 4, "frames": 2, "fps": 10.0, "loop": true},
	"stagger": {"row": 4, "frames": 2, "fps": 6.0, "loop": true},
	"hurt": {"row": 5, "frames": 2, "fps": 12.0, "loop": false},
	"dead": {"row": 6, "frames": 3, "fps": 7.0, "loop": false},
}

## Path under res://assets/sprites/characters/ without extension, e.g. "player".
@export var sheet_name := "player":
	set(value):
		sheet_name = value
		if is_inside_tree():
			_load_sheet()
@export var ground_align := true

var current := ""
var finished := false
var base_modulate := Color.WHITE
var _time := 0.0
var _flash_time := 0.0
var _flash_color := Color.WHITE


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shaded = true
	double_sided = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	hframes = COLUMNS
	vframes = ROWS
	if pixel_size == 0.01:  # engine default -> use our HD-2D scale
		pixel_size = 0.045
	if ground_align:
		position.y = FRAME_H * pixel_size * 0.5
	_load_sheet()
	play("idle")


func _load_sheet() -> void:
	var path := "res://assets/sprites/characters/%s.png" % sheet_name
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		push_warning("BillboardSprite: missing sheet %s" % path)


func play(anim: String, restart: bool = false) -> void:
	if anim == current and not restart:
		return
	if not ANIMS.has(anim):
		return
	current = anim
	finished = false
	_time = 0.0
	_apply_frame()


func face(direction_x: float) -> void:
	if absf(direction_x) > 0.05:
		flip_h = direction_x < 0.0


func flash(color: Color = Color(3.0, 3.0, 3.0), duration: float = 0.08) -> void:
	_flash_color = color
	_flash_time = duration


func _process(delta: float) -> void:
	if current != "":
		_time += delta
		_apply_frame()
	if _flash_time > 0.0:
		_flash_time -= delta
		modulate = _flash_color
	else:
		modulate = base_modulate


func _apply_frame() -> void:
	var a: Dictionary = ANIMS[current]
	var count: int = a.frames
	var idx := int(_time * float(a.fps))
	if a.loop:
		idx = idx % count
	elif idx >= count:
		idx = count - 1
		finished = true
	frame = int(a.row) * COLUMNS + idx
