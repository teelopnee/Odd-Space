class_name Flicker
extends Node
## Makes a few neon signs stutter like failing tubes: toggles the parent's
## visibility in short irregular bursts. Cheap, and the street feels alive.

@export var seed_value := 0
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _burst := 0


func _ready() -> void:
	_rng.seed = seed_value
	_t = _rng.randf_range(1.0, 6.0)


func _process(delta: float) -> void:
	var p := get_parent() as Node3D
	if p == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	if _burst > 0:
		_burst -= 1
		p.visible = not p.visible
		_t = _rng.randf_range(0.03, 0.12)
		if _burst == 0:
			p.visible = true
			_t = _rng.randf_range(2.0, 9.0)
	else:
		_burst = _rng.randi_range(2, 7) * 2
		_t = 0.05
