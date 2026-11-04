class_name FX
extends RefCounted
## Fire-and-forget game-feel helpers: pixel FX, damage numbers, explosions,
## hitstop, camera shake/punch and controller rumble.


static func damage_number(parent: Node, pos: Vector3, text: String, color: Color = Color(1, 0.9, 0.3), big: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0075 if big else 0.0055
	label.font_size = 52
	label.outline_size = 14
	label.modulate = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 1.0)
	label.outline_modulate = Color(0.08, 0.0, 0.12)
	label.render_priority = 10
	parent.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.35, 0.35), 0.1, 0)
	label.scale = Vector3.ONE * 0.4
	var tw := label.create_tween()
	tw.set_parallel(true)
	# Pop (overshoot) then drift up and fade.
	tw.tween_property(label, "scale", Vector3.ONE * (1.35 if big else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "global_position:y", label.global_position.y + 0.9, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tw.chain().tween_callback(label.queue_free)


static func spark(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.8, 0.3), amount: int = 10) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	FXSprite.play_at(parent, "hit_spark", pos, 1.0 + amount * 0.02, 2.2, color)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.09
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


static func dust(parent: Node, pos: Vector3, size: float = 1.0) -> void:
	FXSprite.play_at(parent, "dust", pos + Vector3(0, 0.25 * size, 0.05), 1.6 * size, 0.85, Color(0.9, 0.85, 1.0, 0.9))


static func explosion(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	FXSprite.play_at(parent, "explosion", pos + Vector3(0, 0.4, 0), radius * 1.1, 2.4)
	FXSprite.play_at(parent, "telegraph", pos + Vector3(0, 0.05, 0), radius * 0.9, 1.5, Color(1.0, 0.5, 0.2, 0.6), false, true)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 9.0
	light.omni_range = radius * 3.0
	parent.add_child(light)
	light.global_position = pos + Vector3(0, 1.0, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)
	spark(parent, pos + Vector3(0, 0.6, 0), color.lightened(0.3), 24)
	Audio.play_sfx("explosion", 0.1)
	shake(parent.get_tree(), 0.6)
	rumble(0.8, 0.9, 0.35)


## Damage everything in the "damageable" group within radius (falloff to 30%).
static func explode_damage(tree: SceneTree, pos: Vector3, radius: float, damage: float, attacker: Node) -> void:
	for n in tree.get_nodes_in_group("damageable"):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var d: float = (n as Node3D).global_position.distance_to(pos)
		if d > radius:
			continue
		var dmg := damage * lerpf(1.0, 0.3, d / radius)
		var info := {"damage": dmg, "attacker": attacker, "kind": "explosion", "position": pos, "subsystem": ""}
		if n.has_method("receive_attack"):
			n.receive_attack(info)
		elif n.has_method("take_hit"):
			n.take_hit(info)


static func shake(tree: SceneTree, amount: float) -> void:
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("camera_rig"):
		cam.shake(amount)


## Quick camera zoom punch (parry, break, finisher).
static func punch(tree: SceneTree, amount: float = 0.12, duration: float = 0.25) -> void:
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("camera_rig"):
		if cam.has_method("punch"):
			cam.punch(amount, duration)


## Freeze-frame on impact. Uses real time so it always recovers.
static func hitstop(tree: SceneTree, duration: float, scale: float = 0.05) -> void:
	if tree == null or Engine.time_scale < scale:
		return
	Engine.time_scale = scale
	await tree.create_timer(duration, true, false, true).timeout
	if Engine.time_scale <= scale + 0.001:
		Engine.time_scale = 1.0


## Slow motion (perfect dodge, break, last kill).
static func slowmo(tree: SceneTree, scale: float, duration: float) -> void:
	if tree == null:
		return
	Engine.time_scale = scale
	await tree.create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


static func rumble(weak: float, strong: float, duration: float) -> void:
	if not bool(Game.settings.get("rumble", true)):
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, clampf(weak, 0, 1), clampf(strong, 0, 1), duration)
	if OS.has_feature("mobile") and Input.get_connected_joypads().is_empty() and strong > 0.5:
		Input.vibrate_handheld(int(duration * 400.0))
