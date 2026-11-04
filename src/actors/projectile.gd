class_name Projectile
extends Area3D
## Blaster bolt. Built in code (no scene) so it's trivial to spawn many.
## team "player": hits enemies/NPCs/props. team "enemy": hits the player,
## who may PARRY it (reflects back at double damage) or roll through it.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_NPC := 8
const LAYER_PROJECTILE := 16

var velocity := Vector3.ZERO
var damage := 10.0
var team := "player"
var subsystem := ""
var shooter: Node = null
var life := 1.6
var _done := false
var _mat: StandardMaterial3D
var charged := false
var _hit_bodies: Array = []
var _mesh: MeshInstance3D


static func spawn(parent: Node, from: Vector3, dir: Vector3, speed: float, p_damage: float, p_team: String, p_shooter: Node, p_subsystem: String = "") -> Projectile:
	var p := Projectile.new()
	p.velocity = dir.normalized() * speed
	p.damage = p_damage
	p.team = p_team
	p.shooter = p_shooter
	p.subsystem = p_subsystem
	parent.add_child(p)
	p.global_position = from
	return p


func _ready() -> void:
	collision_layer = LAYER_PROJECTILE
	_update_mask()
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	shape.shape = sphere
	add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.07
	capsule.height = 0.55
	capsule.radial_segments = 6
	capsule.rings = 2
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 5.0
	capsule.material = _mat
	mesh_instance.mesh = capsule
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.rotation_degrees.x = 90.0  # capsule along local -Z
	add_child(mesh_instance)
	_mesh = mesh_instance
	if charged:
		_mesh.scale = Vector3(3.0, 3.0, 2.2)
	_update_color()
	body_entered.connect(_on_body_entered)
	_orient()


## Charge shot: bigger, faster, pierces through enemies, chips 2 shield points.
func make_charged() -> void:
	charged = true
	life = 1.2
	if _mesh:
		_mesh.scale = Vector3(3.0, 3.0, 2.2)
	if _mat:
		_mat.emission_energy_multiplier = 9.0


func _update_mask() -> void:
	if team == "player":
		collision_mask = LAYER_WORLD | LAYER_ENEMY | LAYER_NPC
	else:
		collision_mask = LAYER_WORLD | LAYER_PLAYER


func _update_color() -> void:
	var c := Color(0.3, 1.0, 0.95) if team == "player" else Color(1.0, 0.25, 0.45)
	_mat.albedo_color = c
	_mat.emission = c


func _orient() -> void:
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)


func _physics_process(delta: float) -> void:
	if _done:
		return
	global_position += velocity * delta
	life -= delta
	if life <= 0.0:
		_expire(false)


func _on_body_entered(body: Node) -> void:
	if _done or body == shooter or _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	var info := {"damage": damage, "attacker": shooter, "kind": "projectile", "subsystem": subsystem,
		"position": global_position, "projectile": self, "direction": velocity.normalized(),
		"charged": charged, "shield_damage": 2 if charged else 1, "push": velocity.normalized() * (6.0 if charged else 1.2)}
	if team == "enemy" and body.has_method("receive_attack"):
		var result: String = body.receive_attack(info)
		if result == "parried":
			reflect(body)
			return
		if result == "dodged":
			return  # rolled through it, keep flying
		_hit(body)
		return
	if body.has_method("take_hit"):
		body.take_hit(info)
	if charged and (body is Enemy or body.is_in_group("npc")):
		FX.spark(get_parent(), global_position, Color(0.5, 1.0, 1.0), 14)
		return  # pierce
	_hit(body)


func reflect(new_owner: Node) -> void:
	team = "player"
	shooter = new_owner
	subsystem = ""
	damage *= 2.0
	life = 1.6
	# Send it back toward whoever fired it (or straight back).
	velocity = -velocity * 1.4
	_update_mask()
	_update_color()
	_orient()
	FX.spark(get_parent(), global_position, Color(0.4, 1.0, 1.0), 16)


func _hit(body: Node) -> void:
	var c := Color(0.4, 1.0, 1.0) if team == "player" else Color(1.0, 0.4, 0.5)
	FX.spark(get_parent(), global_position, c)
	_expire(body is Enemy or body.is_in_group("npc"))


func _expire(hit_target: bool) -> void:
	if _done:
		return
	_done = true
	if team == "player" and not hit_target and shooter != null and is_instance_valid(shooter) and shooter.has_method("on_shot_missed"):
		shooter.on_shot_missed()
	queue_free()
