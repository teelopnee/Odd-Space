class_name FX
extends RefCounted
## Small fire-and-forget visual effects built from primitives so they cost
## nothing to author: floating damage numbers, hit sparks, explosions.


static func damage_number(parent: Node, pos: Vector3, text: String, color: Color = Color(1, 0.9, 0.3), big: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008 if big else 0.006
	label.font_size = 48
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0.08, 0.0, 0.12)
	parent.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.2, 0)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y + 1.1, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)


static func spark(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.8, 0.3), amount: int = 10) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.mesh = mesh
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func explosion(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.85)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	sm.material = mat
	sphere.mesh = sm
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sphere)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = radius * 2.5
	root.add_child(light)
	spark(root, pos, color.lightened(0.3), 24)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sphere, "scale", Vector3.ONE * radius * 2.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_delay(0.1)
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.chain().tween_interval(0.3)
	tw.chain().tween_callback(root.queue_free)
	Audio.play_sfx("explosion", 0.1)


## Damage everything in the "damageable" group within radius (falloff to 30%).
static func explode_damage(tree: SceneTree, pos: Vector3, radius: float, damage: float, attacker: Node) -> void:
	for n in tree.get_nodes_in_group("damageable"):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var d: float = (n as Node3D).global_position.distance_to(pos)
		if d > radius:
			continue
		var dmg := damage * lerpf(1.0, 0.3, d / radius)
		if n.has_method("receive_attack"):
			n.receive_attack({"damage": dmg, "attacker": attacker, "kind": "explosion", "position": pos})
		elif n.has_method("take_hit"):
			n.take_hit({"damage": dmg, "attacker": attacker, "kind": "explosion", "subsystem": "", "position": pos})
	for cam in tree.get_nodes_in_group("camera_rig"):
		cam.shake(0.5)
