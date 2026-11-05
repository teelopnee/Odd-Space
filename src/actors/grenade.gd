class_name Grenade
extends Node3D
## Paste Grenade: lobbed in an arc, bursts in a green splash. Hits enemies and props, never
## civilians (the Consortium would bill you for them).

var from := Vector3.ZERO
var to := Vector3.ZERO
var flight := 0.65
var radius := 3.0
var damage := 20.0
var shooter: Node = null
var _t := 0.0


static func throw(parent: Node, p_from: Vector3, p_to: Vector3, p_damage: float, p_radius: float, p_shooter: Node) -> Grenade:
	var g := Grenade.new()
	g.from = p_from
	g.to = p_to
	g.damage = p_damage
	g.radius = p_radius
	g.shooter = p_shooter
	g.flight = clampf(p_from.distance_to(p_to) / 12.0, 0.35, 0.8)
	parent.add_child(g)
	g.global_position = p_from
	return g


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 8
	sphere.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 1.0, 0.3)
	m.emission_enabled = true
	m.emission = Color(0.45, 1.0, 0.3)
	m.emission_energy_multiplier = 3.0
	sphere.material = m
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / flight, 0.0, 1.0)
	global_position = from.lerp(to, k) + Vector3(0, 4.0 * k * (1.0 - k) * 2.2, 0)
	rotation.x += delta * 12.0
	if k >= 1.0:
		_explode()


func _explode() -> void:
	set_process(false)
	var at := global_position
	FXSprite.play_at(get_parent(), "explosion", at + Vector3(0, 0.5, 0), radius * 0.9, 2.6, Color(0.6, 1.0, 0.45))
	FX.shake(get_tree(), 0.4)
	FX.rumble(0.5, 0.5, 0.15)
	Audio.play_sfx("explosion", 0.1, -2.0)
	for n in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(n) or n == shooter or not n is Node3D or n.is_in_group("npc") or n.is_in_group("player"):
			continue
		var d := ((n as Node3D).global_position - at) * Vector3(1, 0, 1)
		if d.length() <= radius:
			n.take_hit({"damage": damage * (1.0 - 0.4 * d.length() / radius), "attacker": shooter, "kind": "explosion",
				"position": (n as Node3D).global_position + Vector3(0, 1.0, 0), "push": d.normalized() * 7.0, "shield_damage": 2})
	queue_free()
