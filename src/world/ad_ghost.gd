class_name AdGhost
extends Node3D
## Anomaly "Ad Ghosts": holograms of discontinued products drifting around,
## still trying to sell themselves. Purely atmospheric.

const PRODUCTS := [
	"NEW! COKE-FLAVOURED AIR\n(discontinued 3014)",
	"PROTEIN PASTE CLASSIC\nnow with original teeth",
	"HALCYON BABY BONDS\nborn in debt, raised in debt",
	"LUMEN MEMORY IMPLANT\nremember better ads",
	"PARAGON HOME ARREST KIT\nfun for the whole family",
	"OXYGENIX GOLD\nbreathe like a CEO",
]

var bounds := Rect2(0, 0, 40, 40)
var seed_value := 0
var _rng := RandomNumberGenerator.new()
var _label: Label3D
var _vel := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	_rng.seed = seed_value
	_label = Label3D.new()
	_label.text = PRODUCTS[_rng.randi() % PRODUCTS.size()]
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.font_size = 56
	_label.pixel_size = 0.008
	var hue := _rng.randf()
	_label.modulate = Color.from_hsv(hue, 0.6, 1.0, 0.55) * 1.8
	_label.outline_size = 0
	add_child(_label)
	position = Vector3(_rng.randf_range(bounds.position.x, bounds.end.x), _rng.randf_range(2.0, 3.5), _rng.randf_range(bounds.position.y, bounds.end.y))
	_vel = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.5, 1.2)
	_t = _rng.randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	position += _vel * delta
	position.y += sin(_t * 1.3) * delta * 0.3
	if position.x < bounds.position.x or position.x > bounds.end.x:
		_vel.x = -_vel.x
	if position.z < bounds.position.y or position.z > bounds.end.y:
		_vel.z = -_vel.z
	_label.modulate.a = 0.35 + 0.25 * sin(_t * 3.0) + (0.2 if fmod(_t, 4.0) < 0.1 else 0.0)
