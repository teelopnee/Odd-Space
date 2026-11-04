class_name Pickup
extends Node3D
## Credit chip / item loot. Pops out in an arc, then magnetises to the player.

var credits := 0
var item_id := ""
var _vel := Vector3.ZERO
var _t := 0.0
var _sprite: FXSprite
var _player: Node3D


static func spawn_credits(parent: Node, pos: Vector3, amount: int) -> void:
	if amount <= 0 or parent == null:
		return
	var chips := clampi(int(ceil(amount / 6.0)), 1, 8)
	var per := int(ceil(float(amount) / chips))
	var left := amount
	for i in chips:
		var p := Pickup.new()
		p.credits = mini(per, left)
		left -= p.credits
		parent.add_child(p)
		p.global_position = pos + Vector3(0, 0.8, 0)
		var a := randf() * TAU
		p._vel = Vector3(cos(a) * randf_range(1.5, 3.5), randf_range(4.0, 6.5), sin(a) * randf_range(1.5, 3.5))


func _ready() -> void:
	_sprite = FXSprite.play_at(self, "chip", global_position, 1.6, 2.2)
	if _sprite:
		_sprite.loop = true
		_sprite.position = Vector3.ZERO


func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _t < 0.45 or _player == null:
		_vel.y -= 20.0 * delta
		position += _vel * delta
		if position.y < 0.25:
			position.y = 0.25
			_vel *= Vector3(0.6, -0.35, 0.6)
		return
	var goal := _player.global_position + Vector3(0, 1.0, 0)
	var to := goal - global_position
	if to.length() < 0.5:
		Game.add_credits(credits)
		Audio.play_sfx("coin", 0.15, -8.0)
		queue_free()
		return
	var speed := 6.0 + _t * 14.0
	global_position += to.normalized() * minf(speed * delta, to.length())
