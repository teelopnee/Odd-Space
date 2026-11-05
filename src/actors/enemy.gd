class_name Enemy
extends CharacterBody3D
## Data-driven enemy (data/enemies.json).
##  * SUBSYSTEMS: body parts with their own HP; breaking one triggers an effect
##    (crit / crippled / explode / disarmed / blinded / crash).
##  * BREAK: a shield counter floats over the enemy with its weaknesses.
##    Hits matching a weakness chip the shield; at 0 the enemy is BROKEN
##    (stunned, takes x2 damage). Unknown weaknesses show "??" until discovered.
##  * Feel: flinch + knockback, telegraphed attacks (orange flash, ground ring
##    for melee lunges), strafing ranged AI, loot chips, death bursts.
## Faction guards stay peaceful until rep drops or you attack them (ASSAULT).

const GRAVITY := 24.0
const LAYER_TARGET_PICK := 64
const MARKER_X := {"jetpack": -0.5, "thruster": -0.45, "weapon": 0.5, "eye": 0.35}
const FLY_HEIGHT := 0.7
const BREAK_TIME := 3.5
const WEAK_TAGS := {"melee": "MEL", "blaster": "BLS", "charged": "CHG", "explosion": "EXP", "parry": "PRY",
	"legs": "LEG", "jetpack": "JET", "eye": "EYE", "thruster": "THR", "head": "HED", "weapon": "WPN"}

@export var enemy_type := "paragon_officer"
@export var display_name_override := ""
@export var sprite_override := ""
var look_override: Dictionary = {}
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
var armored := false
var subsystems: Dictionary = {}
var state := "idle"
var gravity_scale := 1.0
var world_speed_mult := 1.0
var shield := 0
var shield_max := 0
var weak: Array = []
var broken_time := 0.0

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
var _shield_label: Label3D
var _weak_label: Label3D
var _shield_icon: FXSprite
var _player: Node3D = null
var _knock := Vector3.ZERO
var _flinch := 0.0
var _orbit := 1.0
var _orbit_timer := 0.0
var _lunge_dir := Vector3.ZERO
var _telegraph: FXSprite


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
	armored = def.get("armored", false)
	shield_max = int(def.get("shield", 3))
	shield = shield_max
	weak = def.get("weak", [])
	if not look_override.is_empty():
		sprite.set_look(look_override)
	else:
		var lrng := RandomNumberGenerator.new()
		lrng.randomize()
		sprite.set_look(CharacterLook.random_look(lrng, str(def.get("look", "punk"))))
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
	_attack_cd = randf_range(0.6, 1.6)
	_orbit = 1.0 if randf() < 0.5 else -1.0
	witness.calls_faction = faction if faction != "" else "paragon"
	if is_bug:
		witness.active = false
	_update_hostility(true)
	_was_peaceful = not hostile
	_build_markers()
	_alert_label = _make_label(Vector3(0, 2.5, 0), 64, Color(1, 0.3, 0.3))
	_alert_label.visible = false
	_build_shield_display()


func is_alive() -> bool:
	return state != "dead"


# --- Subsystem API ----------------------------------------------------------------------

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


# --- Main loop ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_state_time -= delta
	_attack_cd -= delta
	_hostility_check -= delta
	_flinch -= delta
	_orbit_timer -= delta
	if _hostility_check <= 0.0:
		_hostility_check = 0.5
		_update_hostility(false)
	if broken_time > 0.0:
		broken_time -= delta
		if broken_time <= 0.0 and state == "broken":
			shield = shield_max
			_refresh_shield()
			_set_state("chase")

	var move := Vector3.ZERO
	var dist := INF
	var player_ok: bool = _player != null and _player.is_alive()
	if player_ok:
		dist = _flat_dist(_player.global_position)

	if _flinch > 0.0 and state != "dead":
		pass  # reeling from a hit
	else:
		match state:
			"idle":
				move = _wander(delta)
				if hostile and player_ok and dist < float(def.get("aggro_range", 10.0)) and _has_los(_player.global_position):
					_set_state("chase")
					_show_alert("!", Color(1, 0.4, 0.3), 0.8)
			"reporting":
				pass
			"chase":
				move = _chase(dist, player_ok)
			"windup":
				if _player and not _is_ranged():
					_lunge_dir = ((_player.global_position - global_position) * Vector3(1, 0, 1)).normalized()
				if _state_time <= 0.0:
					_do_attack()
			"attack":
				if _burst_left > 0:
					_burst_timer -= delta
					if _burst_timer <= 0.0:
						_fire_bolt()
				elif not _is_ranged() and _state_time > 0.15:
					move = _lunge_dir * 2.6  # melee lunge
				if _state_time <= 0.0:
					_set_state("chase")
			"stagger", "down", "broken":
				if _state_time <= 0.0 and state != "broken":
					_set_state("chase" if hostile else "idle")
			"dead":
				pass

	var speed := float(def.get("speed", 3.0)) * _speed_mult * world_speed_mult
	if state == "idle":
		speed *= 0.4
	velocity.x = move.x * speed + _knock.x
	velocity.z = move.z * speed + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 22.0 * delta)
	if flying:
		velocity.y = 0.0
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * gravity_scale * delta
	if state != "dead" or _knock.length() > 0.1:
		move_and_slide()
	_animate(move)
	_update_shield_visibility(dist)


func _chase(dist: float, player_ok: bool) -> Vector3:
	if not player_ok or dist > float(def.get("aggro_range", 10.0)) * 1.8:
		_set_state("idle")
		return Vector3.ZERO
	var attack_range := _attack_range()
	var move := Vector3.ZERO
	var to := (_player.global_position - global_position) * Vector3(1, 0, 1)
	if _is_ranged():
		# Keep a band of distance and strafe around the player.
		if _orbit_timer <= 0.0:
			_orbit_timer = randf_range(1.5, 3.5)
			if randf() < 0.35:
				_orbit = -_orbit
		var side := Vector3(-to.z, 0, to.x).normalized() * _orbit
		if dist > attack_range * 0.85:
			move = _nav_dir(_player.global_position) + side * 0.3
		elif dist < attack_range * 0.45:
			move = -to.normalized() * 0.8 + side * 0.5
		else:
			move = side * 0.6
	elif dist > attack_range * 0.85:
		move = _nav_dir(_player.global_position)
	move += _separation()
	if dist <= attack_range and _attack_cd <= 0.0 and _has_los(_player.global_position):
		_set_state("windup", float(def.get("telegraph", 0.5)))
	return move.limit_length(1.0)


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self:
			continue
		var d: Vector3 = (global_position - e.global_position) * Vector3(1, 0, 1)
		var l := d.length()
		if l > 0.01 and l < 1.3:
			push += d / l * (1.3 - l)
	return push


func _set_state(new_state: String, duration: float = 0.0) -> void:
	state = new_state
	_state_time = duration
	if _telegraph and is_instance_valid(_telegraph) and new_state != "windup":
		_telegraph.queue_free()
		_telegraph = null
	match new_state:
		"windup":
			sprite.play("charge", true)
			sprite.flash(Color(3.0, 1.3, 0.4), duration)
			_show_alert("!", Color(1.0, 0.6, 0.1), duration)
			if not _is_ranged() and _player:
				# Ground warning ring where the lunge will land.
				var reach := _attack_range() + 1.4
				var spot := global_position + ((_player.global_position - global_position) * Vector3(1, 0, 1)).normalized() * reach * 0.5
				_telegraph = FXSprite.play_at(get_parent(), "telegraph", spot + Vector3(0, 0.06, 0), reach * 0.75, 1.8, Color(1.0, 0.35, 0.3, 0.9), false, true)
				if _telegraph:
					_telegraph.fps = _telegraph.frames / maxf(duration, 0.1)
		"stagger":
			sprite.play("hurt", true)
		"down":
			sprite.play("dead", true)
		"broken":
			sprite.play("hurt", true)


func _animate(move: Vector3) -> void:
	var face := move
	if _player != null and state in ["chase", "windup", "attack"]:
		face = _player.global_position - global_position
	sprite.set_facing(face)
	if _flinch > 0.0 and state != "dead":
		sprite.play("hurt")
		return
	match state:
		"idle", "chase", "reporting":
			var sp := Vector2(velocity.x, velocity.z).length()
			sprite.play("run" if sp > 3.2 else ("walk" if sp > 0.2 else ("talk" if state == "reporting" else "idle")))
		"attack":
			if sprite.current != "shoot" and sprite.current != "slash1" and sprite.current != "slash3":
				sprite.play("shoot" if _is_ranged() else ("slash3" if armored else "slash1"), true)
		"broken":
			sprite.play("hurt")


# --- Movement helpers ------------------------------------------------------------------------

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
		return Vector3.ZERO
	return _nav_dir(_wander_target)


func _has_los(p: Vector3) -> bool:
	var from := global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, p + Vector3(0, 1.0, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Hostility ---------------------------------------------------------------------------------

func _update_hostility(initial: bool) -> void:
	if hostile or state == "dead" or state == "surrender" or has_meta("stood_down"):
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


# --- Attacking ----------------------------------------------------------------------------------

func _is_ranged() -> bool:
	return def.get("attack", "melee") == "ranged" and not _disarmed


func _attack_range() -> float:
	return 1.3 if _disarmed else float(def.get("range", 1.5))


func _do_attack() -> void:
	_attack_cd = float(def.get("cooldown", 1.5)) * _cooldown_mult * randf_range(0.85, 1.25)
	if _is_ranged():
		_burst_left = int(def.get("burst", 1))
		_burst_timer = 0.0
		_set_state("attack", 0.5)
		sprite.play("shoot", true)
		return
	_set_state("attack", 0.42)
	sprite.play("slash3" if armored else "slash1", true)
	Audio.play_sfx("swing")
	if _player == null or not _player.is_alive():
		return
	# Resolve the hit slightly into the lunge.
	await get_tree().create_timer(0.12).timeout
	if state != "attack" or _player == null or not is_instance_valid(_player):
		return
	var reach := _attack_range() + 0.9
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
	if _player is CharacterBody3D:
		aim += (_player as CharacterBody3D).velocity * 0.15
	var spread := (1.0 - 0.8 * _accuracy_mult) * 1.2
	aim += Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
	var dir := (aim - from).normalized()
	Projectile.spawn(get_parent(), from + dir * 0.5, dir, float(def.get("projectile_speed", 14.0)),
		float(def.get("damage", 8)), "enemy", self)
	FXSprite.play_at(get_parent(), "muzzle", from + dir * 0.6, 0.8, 2.5, Color(1.0, 0.5, 0.6), dir.x < 0)
	Audio.play_sfx("enemy_shoot", 0.1, -6.0)


## Called by the player when they parry our melee swing.
func on_parried(by: Node) -> void:
	_burst_left = 0
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_damage_shield(2, "parry", true)
	if state != "broken":
		_set_state("stagger", Game.stat("stagger_time"))
	if by is Node3D:
		_knock = ((global_position - (by as Node3D).global_position) * Vector3(1, 0, 1)).normalized() * 6.0


# --- Taking damage ---------------------------------------------------------------------------------

func take_hit(info: Dictionary) -> void:
	if state == "dead":
		return
	var attacker = info.get("attacker")
	var by_player: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	if by_player and not hostile:
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
	# --- weaknesses -> shield
	var keys := ["melee" if kind == "melee" else ("blaster" if kind == "projectile" else kind)]
	if info.get("charged", false):
		keys.append("charged")
	if sub != "" and sub != "core":
		keys.append(sub)
	var hit_weak := false
	for k in keys:
		if weak.has(k):
			hit_weak = true
			_reveal_weakness(k)
	if hit_weak and state != "broken":
		_damage_shield(int(info.get("shield_damage", 1)), "", true)
		dmg *= 1.3
	# --- subsystem damage
	var is_crit := false
	if sub != "" and subsystems.has(sub) and not subsystems[sub].broken and sub != "core":
		var s: Dictionary = subsystems[sub]
		dmg *= float(s.get("dmg", 1.0))
		is_crit = s.get("effect", "") == "crit"
		s.hp = float(s.hp) - float(info.get("damage", 1.0))
		if s.hp <= 0.0:
			_break_subsystem(sub, attacker)
	if state == "broken":
		dmg *= 2.0
	elif state == "stagger" or state == "down":
		dmg *= 1.5
	hp -= dmg
	# Story targets (saga / planet stories / bounties) beg for their lives first.
	var can_surrender: bool = by_player and has_meta("saga_tag") and not has_meta("surrender_asked")
	if can_surrender and hp <= max_hp * 0.25:
		hp = maxf(hp, 1.0)
	var col := Color(1.0, 0.92, 0.4)
	if is_crit:
		col = Color(1.0, 0.35, 1.0)
	elif state == "broken":
		col = Color(1.0, 0.55, 0.2)
	elif hit_weak:
		col = Color(0.5, 1.0, 1.0)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.0 + (FLY_HEIGHT if flying else 0.0), 0),
		str(roundi(dmg)) + ("!" if is_crit else ""), col, is_crit or state == "broken")
	FX.spark(get_parent(), info.get("position", global_position + Vector3(0, 1.0, 0)), col, 8)
	sprite.flash(Color(3.0, 3.0, 3.0), 0.07)
	Audio.play_sfx("enemy_hit", 0.12, -4.0)
	# --- reaction: flinch + knockback
	var push: Vector3 = info.get("push", Vector3.ZERO)
	if push == Vector3.ZERO and attacker is Node3D:
		push = ((global_position - (attacker as Node3D).global_position) * Vector3(1, 0, 1)).normalized() * 1.5
	if not armored or state == "broken":
		_knock += push * (1.6 if state == "broken" else 1.0)
		_flinch = 0.16 if kind != "explosion" else 0.4
		if state == "windup":
			_set_state("chase")  # interrupted!
			_attack_cd = maxf(_attack_cd, 0.6)
	else:
		_knock += push * 0.2
	if can_surrender and hp <= max_hp * 0.25:
		_surrender()
	elif hp <= 0.0:
		_die(attacker, push)
	else:
		_refresh_markers()
		if state == "idle" or state == "reporting":
			_set_state("chase")


## Drop to the knees and let the story decide (Saga / Stories show the choices).
func _surrender() -> void:
	set_meta("surrender_asked", true)
	_set_state("surrender")
	hostile = false
	force_hostile = false
	_burst_left = 0
	_knock = Vector3.ZERO
	velocity = Vector3.ZERO
	sprite.play("hurt", true)
	_show_alert("?", Color(1.0, 0.9, 0.3), 3.0)
	FX.slowmo(get_tree(), 0.3, 0.35)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != self and e.has_method("stand_down") and e.global_position.distance_to(global_position) < 14.0:
			e.stand_down()
	var tag := str(get_meta("saga_tag", ""))
	if tag.begins_with("story:"):
		Stories.on_surrender(self, tag)
	else:
		Saga.on_surrender(self, tag)


## Guards stop fighting when their boss gives up.
func stand_down() -> void:
	if state == "dead" or has_meta("saga_tag"):
		return
	hostile = false
	force_hostile = false
	set_meta("stood_down", true)
	_set_state("idle")


## Called by the story after you decide: "kill" finishes them, anything else lets them walk.
func resolve_surrender(outcome: String) -> void:
	if state == "dead":
		return
	if outcome == "kill":
		var p := get_tree().get_first_node_in_group("player")
		_die(p, Vector3.ZERO)
		return
	state = "dead"
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	_alert_label.visible = false
	_set_shield_visible(false)
	for m in _markers.values():
		m.label.visible = false
		m.area.queue_free()
	_markers.clear()
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(sprite.fade_to.bind(0.0, 0.8))
	tw.tween_interval(0.8)
	tw.tween_callback(queue_free)


func _reveal_weakness(key: String) -> void:
	var flag := "weak_%s_%s" % [enemy_type, key]
	if not Game.has_flag(flag):
		Game.flags[flag] = true
		FX.damage_number(get_parent(), global_position + Vector3(0, 2.8, 0), "WEAK: %s" % WEAK_TAGS.get(key, key.to_upper()), Color(0.5, 1.0, 1.0))
	_refresh_shield()


func _damage_shield(amount: int, reveal_key: String, force: bool) -> void:
	if state == "broken" or shield_max <= 0:
		return
	if reveal_key != "":
		if weak.has(reveal_key):
			_reveal_weakness(reveal_key)
		elif not force:
			return
	shield = maxi(0, shield - amount)
	EventBus.enemy_shield_changed.emit(self, shield)
	_refresh_shield()
	if _shield_icon:
		_shield_icon.modulate = Color(3.0, 3.0, 3.0)
	if shield <= 0:
		_break_guard()


func _break_guard() -> void:
	broken_time = BREAK_TIME
	_burst_left = 0
	_set_state("broken")
	_knock *= 0.5
	FXSprite.play_at(get_parent(), "break", global_position + Vector3(0, 1.1, 0.1), 2.0, 2.6, Color(0.7, 1.0, 1.0))
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.6, 0), "BREAK!", Color(1.0, 0.85, 0.2), true)
	FX.shake(get_tree(), 0.4)
	FX.punch(get_tree(), 0.1, 0.25)
	FX.rumble(0.7, 0.9, 0.25)
	Audio.play_sfx("shield_break")
	EventBus.enemy_broken.emit(self)
	FX.slowmo(get_tree(), 0.35, 0.25)
	if _player and _player.has_method("add_overclock"):
		_player.add_overclock(15.0)


func _break_subsystem(sub: String, attacker) -> void:
	var s: Dictionary = subsystems[sub]
	s.broken = true
	var effect: String = s.get("effect", "")
	EventBus.subsystem_broken.emit(self, sub, effect)
	var label := "%s BROKEN" % s.get("label", sub)
	match effect:
		"crit":
			label = "CRITICAL!"
			if state != "broken":
				_set_state("stagger", 1.0)
		"crippled":
			label = "CRIPPLED!"
			_speed_mult = 0.4
			if state != "broken":
				_set_state("down", 1.8)
		"explode":
			label = "KABOOM!"
			var pos := get_subsystem_position(sub)
			FX.explosion(get_parent(), pos, 3.5)
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
			if state != "broken":
				_set_state("down", 2.5)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.4, 0), label, Color(0.5, 1.0, 1.0), true)
	Audio.play_sfx("break")
	FX.shake(get_tree(), 0.2)


func _deferred_explode(pos: Vector3, attacker) -> void:
	FX.explode_damage(get_tree(), pos, 3.5, 35.0, attacker)


func _die(attacker, push: Vector3) -> void:
	state = "dead"
	hp = 0.0
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	collision_mask = 1
	witness.silence("killed")
	sprite.play("dead", true)
	sprite.flash(Color(3.0, 3.0, 3.0), 0.12)
	_knock = push * 1.8
	_alert_label.visible = false
	_set_shield_visible(false)
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	for m in _markers.values():
		m.label.visible = false
		m.area.queue_free()
	_markers.clear()
	if flying or enemy_type == "repo_drone":
		FXSprite.play_at(get_parent(), "explosion", global_position + Vector3(0, 1.0, 0), 1.6, 2.4)
	var by_player: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	if by_player:
		var credits_range: Array = def.get("credits", [0, 0])
		var loot := roundi(randi_range(int(credits_range[0]), int(credits_range[1])) * Game.stat("loot_mult"))
		Pickup.spawn_credits(get_parent(), global_position, loot)
		if _was_peaceful and _assault_node >= 0:
			Causality.record("murder", {"target": display_name, "target_faction": faction,
				"position": global_position, "exclude": [self], "causes": [_assault_node]})
		elif faction != "" and not is_bug:
			Causality.record("kill_hostile", {"target": display_name, "target_faction": faction,
				"position": global_position, "exclude": [self]})
		# Last hostile in the area -> cinematic slow-mo.
		var left := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.hostile and e.global_position.distance_to(global_position) < 18.0:
				left += 1
		if left == 0:
			FX.slowmo(get_tree(), 0.25, 0.6)
			FX.punch(get_tree(), 0.12, 0.4)
	EventBus.enemy_killed.emit(self, {"by_player": by_player, "type": enemy_type})
	Audio.play_sfx("enemy_die")
	FX.rumble(0.3, 0.3, 0.12)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(sprite.fade_to.bind(0.0, 0.6))
	tw.tween_interval(0.6)
	tw.tween_callback(queue_free)


## Explosions & other AoE call this (we're in the "damageable" group).
func receive_attack(info: Dictionary) -> String:
	take_hit(info)
	return "hit"


# --- Witness hooks -----------------------------------------------------------------------------

func on_report_started() -> void:
	if not hostile:
		_set_state("reporting")
		_show_alert("((o))", Color(1, 0.85, 0.2), 0.8)


func on_report_finished() -> void:
	if state == "reporting":
		_set_state("idle")


# --- Diegetic labels ------------------------------------------------------------------------------

func _make_label(pos: Vector3, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.0045
	l.font_size = font_size
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.0, 0.1)
	l.position = pos
	l.render_priority = 5
	add_child(l)
	return l


func _build_shield_display() -> void:
	var top := 2.25 + (FLY_HEIGHT if flying else 0.0)
	_shield_icon = FXSprite.play_at(self, "shield", global_position + Vector3(-0.22, top, 0), 1.7, 1.2)
	if _shield_icon:
		_shield_icon.loop = true
		_shield_icon.position = Vector3(-0.22, top, 0)
		_shield_icon.no_depth_test = true
		_shield_icon.render_priority = 6
	_shield_label = _make_label(Vector3(-0.22, top - 0.02, 0.01), 44, Color(1, 1, 1))
	_weak_label = _make_label(Vector3(0.35, top, 0), 28, Color(0.75, 0.95, 1.0))
	_weak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_refresh_shield()
	_set_shield_visible(false)


func _refresh_shield() -> void:
	if _shield_label == null:
		return
	_shield_label.text = str(shield) if state != "broken" else "X"
	_shield_label.modulate = Color(1, 1, 1) if state != "broken" else Color(1.0, 0.6, 0.2)
	var tags: Array[String] = []
	for w in weak:
		tags.append(WEAK_TAGS.get(w, str(w).to_upper()) if Game.has_flag("weak_%s_%s" % [enemy_type, w]) else "??")
	_weak_label.text = " ".join(tags)


func _set_shield_visible(on: bool) -> void:
	if _shield_label:
		_shield_label.visible = on
		_weak_label.visible = on
	if _shield_icon:
		_shield_icon.visible = on


func _update_shield_visibility(dist: float) -> void:
	_set_shield_visible(state != "dead" and hostile and (dist < 9.0 or _targeted))
	if _shield_icon and _shield_icon.modulate.r > 1.25:
		_shield_icon.modulate = _shield_icon.modulate.lerp(Color(1.2, 1.2, 1.2), 0.15)
	if state == "broken" and _shield_label:
		_shield_label.text = "BREAK %d" % ceili(broken_time)


func _build_markers() -> void:
	for id in subsystems:
		var local: Vector3 = get_subsystem_position(id) - global_position
		var label := _make_label(local, 30, Color(0.4, 1.0, 1.0))
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
			label.position.y += 1.25
		else:
			label.text = ("[ %s ]" if id == _selected_sub else "%s") % s.get("label", id)
		var selected: bool = id == _selected_sub
		label.modulate = Color(1.0, 0.3, 0.9) if selected else Color(0.4, 1.0, 1.0)
		label.font_size = 36 if selected else 26


func _show_alert(text: String, color: Color, duration: float) -> void:
	_alert_label.text = text
	_alert_label.modulate = color
	_alert_label.visible = true
	var tw := create_tween()
	tw.tween_interval(maxf(duration, 0.3))
	tw.tween_callback(func(): if is_instance_valid(_alert_label): _alert_label.visible = false)
