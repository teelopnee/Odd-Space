class_name Enemy
extends CharacterBody3D
## Data-driven enemy (data/enemies.json) with SUBSYSTEM TARGETING:
## every archetype has body parts with their own HP. Breaking one triggers an
## effect: crit (head), crippled (legs: falls + slows), explode (jetpack/tank:
## AoE that hurts its friends), disarmed (no more shooting), blinded, crash.
##
## Faction guards ("hostility": "rep") are peaceful until your reputation with
## their faction drops (e.g. after a witness REPORTS your crime) or you attack
## them - attacking a peaceful guard is recorded as ASSAULT, killing as MURDER.

const GRAVITY := 24.0
const LAYER_TARGET_PICK := 64
const MARKER_X := {"jetpack": -0.5, "thruster": -0.45, "weapon": 0.5, "eye": 0.35}
const FLY_HEIGHT := 0.7

@export var enemy_type := "paragon_officer"
@export var display_name_override := ""
@export var sprite_override := ""
@export var force_hostile := false

@onready var sprite: BillboardSprite = $Sprite
@onready var agent: NavigationAgent3D = $NavAgent
@onready var witness: WitnessComponent = $Witness

var def: Dictionary = {}
var faction := ""
var display_name := ""
var hp := 30.0
var max_hp := 30.0
var hostile := false
var flying := false
var is_bug := false
var subsystems: Dictionary = {}
var state := "idle"
var gravity_scale := 1.0
var world_speed_mult := 1.0

var _state_time := 0.0
var _attack_cd := 1.0
var _burst_left := 0
var _burst_timer := 0.0
var _repath := 0.0
var _hostility_check := 0.0
var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _speed_mult := 1.0
var _accuracy_mult := 1.0
var _cooldown_mult := 1.0
var _disarmed := false
var _assault_node := -1
var _was_peaceful := false
var _markers: Dictionary = {}
var _targeted := false
var _selected_sub := ""
var _alert_label: Label3D
var _player: Node3D = null


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("damageable")
	def = DataDB.enemies.get(enemy_type, {})
	if def.is_empty():
		push_error("Enemy: unknown type %s" % enemy_type)
	faction = def.get("faction", "")
	display_name = display_name_override if display_name_override != "" else def.get("name", enemy_type)
	max_hp = float(def.get("hp", 30))
	hp = max_hp
	flying = def.get("flying", false)
	is_bug = def.get("bug", false)
	sprite.sheet_name = sprite_override if sprite_override != "" else def.get("sprite", "officer")
	if flying:
		sprite.position.y += FLY_HEIGHT
	var subs: Dictionary = def.get("subsystems", {})
	for id in subs:
		var s: Dictionary = subs[id].duplicate()
		s["max_hp"] = float(s.get("hp", 10))
		s["hp"] = s["max_hp"]
		s["broken"] = false
		subsystems[id] = s
	_home = global_position
	_wander_target = _home
	_attack_cd = randf_range(0.5, 1.5)
	witness.calls_faction = faction if faction != "" else "paragon"
	if is_bug:
		witness.active = false
	_update_hostility(true)
	_was_peaceful = not hostile
	_build_markers()
	_alert_label = _make_label(Vector3(0, 2.3, 0), 64, Color(1, 0.3, 0.3))
	_alert_label.visible = false


func is_alive() -> bool:
	return state != "dead"


# --- Subsystem API (used by Player targeting & HUD) --------------------------------------

func subsystem_ids(only_intact: bool = true) -> Array:
	var out := []
	for id in subsystems:
		if not only_intact or not subsystems[id].broken or id == "core":
			out.append(id)
	return out


func subsystem_label(id: String) -> String:
	return subsystems.get(id, {}).get("label", id.to_upper())


func get_subsystem_position(id: String) -> Vector3:
	var s: Dictionary = subsystems.get(id, subsystems.get("core", {}))
	var y := float(s.get("y", 1.0)) + (FLY_HEIGHT if flying else 0.0)
	return global_position + Vector3(MARKER_X.get(id, 0.0), y, 0.05)


func subsystem_accuracy(id: String) -> float:
	return float(subsystems.get(id, {}).get("acc", 1.0))


func set_targeted(on: bool, sub: String) -> void:
	_targeted = on
	_selected_sub = sub
	_refresh_markers()


# --- Main loop ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_state_time -= delta
	_attack_cd -= delta
	_hostility_check -= delta
	if _hostility_check <= 0.0:
		_hostility_check = 0.5
		_update_hostility(false)

	var move := Vector3.ZERO
	var dist := INF
	var player_ok: bool = _player != null and _player.is_alive()
	if player_ok:
		dist = _flat_dist(_player.global_position)

	match state:
		"idle":
			move = _wander(delta)
			if hostile and player_ok and dist < float(def.get("aggro_range", 10.0)) and _has_los(_player.global_position):
				_set_state("chase")
		"reporting":
			pass  # standing still, talking into the radio
		"chase":
			if not player_ok or dist > float(def.get("aggro_range", 10.0)) * 1.8:
				_set_state("idle")
			else:
				var attack_range := _attack_range()
				var keep := attack_range * 0.7 if _is_ranged() else attack_range * 0.8
				if dist > keep:
					move = _nav_dir(_player.global_position)
				if dist <= attack_range and _attack_cd <= 0.0 and _has_los(_player.global_position):
					_set_state("windup", float(def.get("telegraph", 0.5)))
		"windup":
			if _state_time <= 0.0:
				_do_attack()
		"attack":
			if _burst_left > 0:
				_burst_timer -= delta
				if _burst_timer <= 0.0:
					_fire_bolt()
			elif _state_time <= 0.0:
				_set_state("chase")
		"stagger", "down":
			if _state_time <= 0.0:
				_set_state("chase" if hostile else "idle")
		"dead":
			pass

	var speed := float(def.get("speed", 3.0)) * _speed_mult * world_speed_mult
	if state == "idle":
		speed *= 0.4
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	if flying:
		velocity.y = 0.0
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * gravity_scale * delta
	if state != "dead":
		move_and_slide()
	_animate(move)


func _set_state(new_state: String, duration: float = 0.0) -> void:
	state = new_state
	_state_time = duration
	match new_state:
		"windup":
			sprite.play("windup", true)
			sprite.flash(Color(3.0, 1.2, 0.4), duration)  # readable telegraph = parry cue
			_show_alert("!", Color(1.0, 0.6, 0.1), duration)
		"stagger":
			sprite.play("stagger", true)
		"down":
			sprite.play("dead", true)


func _animate(move: Vector3) -> void:
	if _player != null and state in ["chase", "windup", "attack"]:
		sprite.face(_player.global_position.x - global_position.x)
	else:
		sprite.face(move.x)
	match state:
		"idle", "chase", "reporting":
			sprite.play("walk" if move.length() > 0.1 else "idle")
		"attack":
			sprite.play("attack")


# --- Movement helpers --------------------------------------------------------------------

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _nav_dir(goal: Vector3) -> Vector3:
	_repath -= get_physics_process_delta_time()
	if _repath <= 0.0:
		_repath = 0.3
		agent.target_position = goal
	var next := agent.get_next_path_position()
	var dir := Vector3(next.x - global_position.x, 0, next.z - global_position.z)
	if dir.length() < 0.05 or agent.is_navigation_finished():
		dir = Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	return dir.normalized()


func _wander(_delta: float) -> Vector3:
	if _flat_dist(_wander_target) < 0.5 or _state_time < -4.0:
		_state_time = randf_range(-2.0, 0.0)
		_wander_target = _home + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		return Vector3.ZERO
	if _state_time > -1.0:
		return Vector3.ZERO  # pause between strolls
	return _nav_dir(_wander_target)


func _has_los(p: Vector3) -> bool:
	var from := global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, p + Vector3(0, 1.0, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Hostility ----------------------------------------------------------------------------

func _update_hostility(initial: bool) -> void:
	if hostile or state == "dead":
		return
	var h: bool = force_hostile or def.get("hostility", "always") == "always"
	if not h and faction != "":
		h = Factions.is_hostile(faction, int(def.get("hostile_below", -30)))
	if h:
		hostile = true
		if not initial:
			_show_alert("!!", Color(1, 0.2, 0.2), 1.2)
			Audio.play_sfx("alert")


func provoke() -> void:
	if hostile:
		return
	hostile = true
	_show_alert("!!", Color(1, 0.2, 0.2), 1.2)
	if state == "idle" or state == "reporting":
		_set_state("chase")


func _alert_allies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != self and e.faction == faction and e.global_position.distance_to(global_position) < 12.0:
			e.provoke()


# --- Attacking ------------------------------------------------------------------------------

func _is_ranged() -> bool:
	return def.get("attack", "melee") == "ranged" and not _disarmed


func _attack_range() -> float:
	return 1.3 if _disarmed else float(def.get("range", 1.5))


func _do_attack() -> void:
	_attack_cd = float(def.get("cooldown", 1.5)) * _cooldown_mult * randf_range(0.85, 1.2)
	sprite.play("attack", true)
	if _is_ranged():
		_burst_left = int(def.get("burst", 1))
		_burst_timer = 0.0
		_set_state("attack", 0.5)
		sprite.play("attack", true)
		return
	_set_state("attack", 0.45)
	sprite.play("attack", true)
	Audio.play_sfx("swing")
	if _player == null or not _player.is_alive():
		return
	var reach := _attack_range() + 0.5
	if _flat_dist(_player.global_position) <= reach:
		var dmg := float(def.get("damage", 8)) * (0.5 if _disarmed else 1.0)
		_player.receive_attack({"damage": dmg, "attacker": self, "kind": "melee", "bug": is_bug,
			"position": global_position})


func _fire_bolt() -> void:
	_burst_left -= 1
	_burst_timer = 0.14
	if _player == null:
		return
	var from := global_position + Vector3(0, 1.0 + (FLY_HEIGHT if flying else 0.0), 0)
	var aim := _player.global_position + Vector3(0, 0.9, 0)
	# Lead the target slightly, then scatter by accuracy.
	if _player is CharacterBody3D:
		aim += (_player as CharacterBody3D).velocity * 0.15
	var spread := (1.0 - 0.8 * _accuracy_mult) * 1.2
	aim += Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
	var dir := (aim - from).normalized()
	Projectile.spawn(get_parent(), from + dir * 0.5, dir, float(def.get("projectile_speed", 14.0)),
		float(def.get("damage", 8)), "enemy", self)
	Audio.play_sfx("enemy_shoot", 0.1, -6.0)


## Called by the player when they parry our melee swing.
func on_parried(_by: Node) -> void:
	_burst_left = 0
	_set_state("stagger", Game.stat("stagger_time"))
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.0, 0), "PARRIED!", Color(0.4, 1.0, 1.0), true)


# --- Taking damage ---------------------------------------------------------------------------

func take_hit(info: Dictionary) -> void:
	if state == "dead":
		return
	var attacker = info.get("attacker")
	var by_player: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	if by_player and not hostile:
		# Attacking someone peaceful is a crime, with everyone nearby as witnesses.
		_assault_node = Causality.record("assault", {
			"target": display_name, "target_faction": faction,
			"position": global_position, "exclude": [self]})
		provoke()
		_alert_allies()
	elif not hostile:
		provoke()
	var dmg := float(info.get("damage", 1.0))
	var kind: String = info.get("kind", "projectile")
	if kind == "explosion" and by_player:
		dmg *= Game.stat("explosion_damage")
	var sub: String = info.get("subsystem", "")
	var is_crit := false
	if sub != "" and subsystems.has(sub) and not subsystems[sub].broken and sub != "core":
		var s: Dictionary = subsystems[sub]
		dmg *= float(s.get("dmg", 1.0))
		is_crit = s.get("effect", "") == "crit"
		s.hp = float(s.hp) - float(info.get("damage", 1.0))
		if s.hp <= 0.0:
			_break_subsystem(sub, attacker)
	if state == "stagger" or state == "down":
		dmg *= 1.5
	hp -= dmg
	var col := Color(1.0, 0.35, 1.0) if is_crit else Color(1.0, 0.9, 0.3)
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.9 + (FLY_HEIGHT if flying else 0.0), 0),
		str(roundi(dmg)) + ("!" if is_crit else ""), col, is_crit)
	sprite.flash()
	Audio.play_sfx("enemy_hit", 0.12, -4.0)
	if hp <= 0.0:
		_die(attacker)
	else:
		_refresh_markers()
		if state == "idle" or state == "reporting":
			_set_state("chase")


func _break_subsystem(sub: String, attacker) -> void:
	var s: Dictionary = subsystems[sub]
	s.broken = true
	var effect: String = s.get("effect", "")
	EventBus.subsystem_broken.emit(self, sub, effect)
	var label := "%s BROKEN" % s.get("label", sub)
	match effect:
		"crit":
			label = "CRITICAL!"
			_set_state("stagger", 1.0)
		"crippled":
			label = "CRIPPLED!"
			_speed_mult = 0.4
			_set_state("down", 1.8)
		"explode":
			label = "KABOOM!"
			var pos := get_subsystem_position(sub)
			FX.explosion(get_parent(), pos, 3.5)
			# Deferred so we don't recurse into take_hit while handling this hit.
			call_deferred("_deferred_explode", pos, attacker)
		"disarmed":
			label = "DISARMED!"
			_disarmed = true
			_burst_left = 0
		"blinded":
			label = "BLINDED!"
			_accuracy_mult = 0.4
			_cooldown_mult = 1.5
		"crash":
			label = "CRASHED!"
			flying = false
			sprite.position.y -= FLY_HEIGHT
			_set_state("down", 2.5)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.4, 0), label, Color(0.5, 1.0, 1.0), true)
	Audio.play_sfx("break")
	for cam in get_tree().get_nodes_in_group("camera_rig"):
		cam.shake(0.2)


func _deferred_explode(pos: Vector3, attacker) -> void:
	FX.explode_damage(get_tree(), pos, 3.5, 35.0, attacker)


func _die(attacker) -> void:
	state = "dead"
	hp = 0.0
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	collision_mask = 1
	witness.silence("killed")
	sprite.play("dead", true)
	_alert_label.visible = false
	for m in _markers.values():
		m.label.visible = false
		m.area.queue_free()
	_markers.clear()
	var by_player: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	if by_player:
		var credits_range: Array = def.get("credits", [0, 0])
		var loot := roundi(randi_range(int(credits_range[0]), int(credits_range[1])) * Game.stat("loot_mult"))
		if loot > 0:
			Game.add_credits(loot)
			FX.damage_number(get_parent(), global_position + Vector3(0, 1.5, 0), "+%d cr" % loot, Color(1.0, 0.85, 0.2))
		if _was_peaceful and _assault_node >= 0:
			Causality.record("murder", {"target": display_name, "target_faction": faction,
				"position": global_position, "exclude": [self], "causes": [_assault_node]})
		elif faction != "" and not is_bug:
			Causality.record("kill_hostile", {"target": display_name, "target_faction": faction,
				"position": global_position, "exclude": [self]})
	EventBus.enemy_killed.emit(self, {"by_player": by_player, "type": enemy_type})
	Audio.play_sfx("enemy_die")
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


## Explosions & other AoE call this (we're in the "damageable" group).
func receive_attack(info: Dictionary) -> String:
	take_hit(info)
	return "hit"


# --- Witness hooks --------------------------------------------------------------------------

func on_report_started() -> void:
	if not hostile:
		_set_state("reporting")
		_show_alert("((o))", Color(1, 0.85, 0.2), 0.8)


func on_report_finished() -> void:
	if state == "reporting":
		_set_state("idle")


# --- Markers / labels ------------------------------------------------------------------------

func _make_label(pos: Vector3, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.005
	l.font_size = font_size
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.0, 0.1)
	l.position = pos
	add_child(l)
	return l


func _build_markers() -> void:
	for id in subsystems:
		var local: Vector3 = get_subsystem_position(id) - global_position
		var label := _make_label(local, 34, Color(0.4, 1.0, 1.0))
		label.visible = false
		var area := Area3D.new()
		area.collision_layer = LAYER_TARGET_PICK
		area.collision_mask = 0
		area.monitoring = false
		area.set_meta("enemy", self)
		area.set_meta("subsystem", id)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.45 if id == "core" else 0.32
		shape.shape = sphere
		area.add_child(shape)
		area.position = local
		add_child(area)
		_markers[id] = {"label": label, "area": area}


func _refresh_markers() -> void:
	for id in _markers:
		var m: Dictionary = _markers[id]
		var s: Dictionary = subsystems[id]
		var label: Label3D = m.label
		label.position = get_subsystem_position(id) - global_position
		(m.area as Area3D).position = label.position
		label.visible = _targeted and not (s.broken and id != "core")
		if id == "core":
			label.text = "%s  %d/%d" % [display_name.to_upper(), maxi(0, roundi(hp)), roundi(max_hp)]
			label.position.y += 1.0
		else:
			label.text = ("[ %s ]" if id == _selected_sub else "%s") % s.get("label", id)
		var selected: bool = id == _selected_sub
		label.modulate = Color(1.0, 0.3, 0.9) if selected else Color(0.4, 1.0, 1.0)
		label.font_size = 40 if selected else 30


func _show_alert(text: String, color: Color, duration: float) -> void:
	_alert_label.text = text
	_alert_label.modulate = color
	_alert_label.visible = true
	var tw := create_tween()
	tw.tween_interval(maxf(duration, 0.3))
	tw.tween_callback(func(): if is_instance_valid(_alert_label): _alert_label.visible = false)
