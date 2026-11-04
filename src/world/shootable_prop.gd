class_name ShootableProp
extends StaticBody3D
## Destructible world prop.
##   "ad"   : holographic billboard. Shooting it = VANDALISM vs the advertiser.
##   "tank" : explosive tank. Hurts everyone nearby (the player is responsible
##            for anyone it kills - yes, that can be MURDER).

@export_enum("ad", "tank") var kind := "ad"
@export var owner_faction := "lumen"
@export var hp := 20.0
@export var flicker := false

var glow_nodes: Array = []
var broken := false
var _t := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("damageable")


func add_collision(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	add_child(cs)


func _process(delta: float) -> void:
	if not flicker or broken:
		return
	_t += delta
	# Cheap neon flicker: mostly on, occasional stutters.
	var on := fmod(_t * 7.3, 5.0) > 0.25 or sin(_t * 31.0) > 0.0
	for n in glow_nodes:
		if n is OmniLight3D:
			n.visible = on


func take_hit(info: Dictionary) -> void:
	if broken:
		return
	hp -= float(info.get("damage", 1.0))
	FX.spark(get_parent(), info.get("position", global_position), Color(1.0, 0.7, 0.3), 6)
	if hp <= 0.0:
		_break(info.get("attacker"))


func receive_attack(info: Dictionary) -> String:
	take_hit(info)
	return "hit"


func _break(attacker) -> void:
	broken = true
	remove_from_group("damageable")
	var by_player: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	match kind:
		"ad":
			for n in glow_nodes:
				if is_instance_valid(n):
					if n is Label3D:
						n.modulate = Color(0.3, 0.3, 0.35)
						n.text = "ERR 0x%X" % randi_range(4096, 65535) if randf() < 0.5 else n.text
					elif n is OmniLight3D:
						n.visible = false
					elif n is MeshInstance3D:
						n.material_override = null
			Audio.play_sfx("break")
			FX.spark(get_parent(), global_position + Vector3(0, 2.6, 0), Color(1.0, 0.4, 0.9), 24)
			if by_player:
				Causality.record("vandalism", {"target": "Holo-billboard", "target_faction": owner_faction,
					"position": (attacker as Node3D).global_position})
		"tank":
			var pos := global_position + Vector3(0, 0.8, 0)
			FX.explosion(get_parent(), pos, 4.0)
			FX.explode_damage(get_tree(), pos, 4.0, 45.0, attacker)
			queue_free()
