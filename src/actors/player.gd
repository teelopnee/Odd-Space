class_name Player
extends CharacterBody3D
## The drifter. Fast-paced action combat:
##   * DODGE ROLL - burst of speed with i-frames (projectiles pass through)
##   * PARRY      - short window: melee attackers get staggered, bolts reflect x2
##   * SHOOT      - auto-aims at the locked target's selected SUBSYSTEM
##                  (legs = cripple, jetpack = explode, weapon = disarm, ...)
## Input works with keyboard/gamepad (InputMap) and the touch HUD (which
## presses the same actions), so this script doesn't care where input comes from.

enum State { NORMAL, ROLL, PARRY, HURT, DEAD }

const GRAVITY := 24.0
const ACCEL := 40.0
const FRICTION := 30.0
const ROLL_TIME := 0.38
const PARRY_RECOVERY := 0.3
const AUTO_TARGET_RANGE := 15.0
const MISSES_PER_MISHAP := 8

@onready var sprite: BillboardSprite = $Sprite
@onready var muzzle: Marker3D = $Muzzle
@onready var interact_area: Area3D = $InteractArea

var state := State.NORMAL
var facing := Vector3.RIGHT
var input_locked := false
var gravity_scale := 1.0

var target: Node3D = null
var target_subsystem := "core"

var _roll_dir := Vector3.ZERO
var _roll_time := 0.0
var _roll_cd := 0.0
var _iframes := 0.0
var _parry_time := 0.0
var _parry_recover := 0.0
var _last_parry_whiff := -10.0
var _fire_cd := 0.0
var _hurt_time := 0.0
var _misses := 0
var _interactables: Array[Area3D] = []
var _current_interactable: Area3D = null


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	Game.hp = clampf(Game.hp, 1.0, Game.max_hp())
	EventBus.player_hp_changed.emit(Game.hp, Game.max_hp())
	interact_area.area_entered.connect(_on_interactable_entered)
	interact_area.area_exited.connect(_on_interactable_exited)


func is_alive() -> bool:
	return state != State.DEAD


func is_invulnerable() -> bool:
	return _iframes > 0.0


# --- Main loop --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	var input_vec := Vector2.ZERO
	if not input_locked and state != State.DEAD:
		input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Fixed-yaw HD-2D camera looks down -Z, so screen axes map straight to world X/Z.
	var move_dir := Vector3(input_vec.x, 0.0, input_vec.y)
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	match state:
		State.NORMAL:
			_normal_state(delta, move_dir)
		State.ROLL:
			var t := 1.0 - (_roll_time / ROLL_TIME)
			var speed := Game.stat("roll_speed") * lerpf(1.0, 0.45, t)
			velocity.x = _roll_dir.x * speed
			velocity.z = _roll_dir.z * speed
			if _roll_time <= 0.0:
				state = State.NORMAL
		State.PARRY:
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
			if _parry_time <= 0.0:
				# Window closed without blocking anything: a whiff.
				state = State.NORMAL
				_parry_recover = PARRY_RECOVERY
				_last_parry_whiff = Game.play_time
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta * 0.5)
			velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta * 0.5)
			if _hurt_time <= 0.0:
				state = State.NORMAL
		State.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0

	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * gravity_scale * delta
	move_and_slide()
	_update_animation()
	_validate_target()


func _tick_timers(delta: float) -> void:
	_roll_time -= delta
	_roll_cd -= delta
	_iframes -= delta
	_parry_time -= delta
	_parry_recover -= delta
	_fire_cd -= delta
	_hurt_time -= delta


func _normal_state(delta: float, move_dir: Vector3) -> void:
	var speed := Game.stat("move_speed")
	var target_vel := move_dir * speed
	var rate := ACCEL if move_dir.length() > 0.05 else FRICTION
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)
	if move_dir.length() > 0.1:
		facing = move_dir.normalized()
	if input_locked:
		return
	if Input.is_action_just_pressed("dodge") and _roll_cd <= 0.0:
		_start_roll(move_dir)
	elif Input.is_action_just_pressed("parry") and _parry_recover <= 0.0:
		_start_parry()
	elif Input.is_action_pressed("attack") and _fire_cd <= 0.0:
		shoot()
	if Input.is_action_just_pressed("interact"):
		interact()
	if Input.is_action_just_pressed("target_cycle"):
		cycle_target()
	if Input.is_action_just_pressed("subsystem_next"):
		cycle_subsystem()


func _update_animation() -> void:
	match state:
		State.ROLL:
			sprite.play("roll")
		State.PARRY:
			sprite.play("guard")
		State.HURT:
			sprite.play("hurt")
		State.DEAD:
			sprite.play("dead")
		_:
			if _fire_cd > 0.0 and sprite.current == "attack" and not sprite.finished:
				pass
			elif Vector2(velocity.x, velocity.z).length() > 0.4:
				sprite.play("walk")
			else:
				sprite.play("idle")
	# Face the target while fighting, otherwise the movement direction.
	if target != null and is_instance_valid(target) and state != State.ROLL:
		sprite.face(target.global_position.x - global_position.x)
	else:
		sprite.face(facing.x)


# --- Actions -----------------------------------------------------------------------------

func _start_roll(move_dir: Vector3) -> void:
	_roll_dir = move_dir.normalized() if move_dir.length() > 0.1 else facing
	state = State.ROLL
	_roll_time = ROLL_TIME
	_roll_cd = Game.stat("roll_cooldown") + ROLL_TIME
	_iframes = Game.stat("roll_iframes")
	sprite.play("roll", true)
	Audio.play_sfx("roll")


func _start_parry() -> void:
	state = State.PARRY
	_parry_time = Game.stat("parry_window")
	sprite.play("guard", true)
	Audio.play_sfx("parry_swing", 0.05, -6.0)


func shoot() -> void:
	_fire_cd = 1.0 / maxf(0.5, Game.stat("fire_rate"))
	if target == null or not is_instance_valid(target):
		_auto_target()
	var from := muzzle.global_position
	var aim_point: Vector3
	var sub := ""
	if target != null and is_instance_valid(target):
		sub = target_subsystem
		aim_point = target.get_subsystem_position(sub) if target.has_method("get_subsystem_position") else target.global_position + Vector3.UP
		# Hit chance: player accuracy x subsystem difficulty x distance falloff.
		var acc := Game.stat("accuracy")
		if target.has_method("subsystem_accuracy"):
			acc *= target.subsystem_accuracy(sub)
		acc *= clampf(1.15 - from.distance_to(aim_point) / 30.0, 0.5, 1.0)
		if randf() > acc:
			# Visible miss: nudge the aim off the subsystem.
			var side := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.8), 0).normalized()
			aim_point += side * randf_range(0.6, 1.0)
			sub = ""
		facing = Vector3(aim_point.x - from.x, 0, aim_point.z - from.z).normalized()
	else:
		aim_point = from + facing * 10.0
	var dir := (aim_point - from).normalized()
	Projectile.spawn(get_parent(), from + dir * 0.4, dir, 26.0, Game.stat("damage"), "player", self, sub)
	sprite.play("attack", true)
	Audio.play_sfx("shoot", 0.1, -3.0)


func on_shot_missed() -> void:
	_misses += 1
	if _misses >= MISSES_PER_MISHAP:
		_misses = 0
		FlawPerk.report_mishap("missed_shots")


func interact() -> void:
	if _current_interactable != null and is_instance_valid(_current_interactable):
		_current_interactable.interact(self)


# --- Targeting -------------------------------------------------------------------------

func _enemies_in_range() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.is_alive() and e.global_position.distance_to(global_position) <= AUTO_TARGET_RANGE:
			out.append(e)
	out.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	return out


func _auto_target() -> void:
	# Prefer hostile enemies; never auto-lock onto peaceful guards.
	for e in _enemies_in_range():
		if e.hostile:
			set_target(e, "core")
			return


func cycle_target() -> void:
	var list := _enemies_in_range()
	if list.is_empty():
		set_target(null)
		return
	var idx := list.find(target)
	set_target(list[(idx + 1) % list.size()], "core")


func cycle_subsystem() -> void:
	if target == null or not is_instance_valid(target):
		_auto_target()
		return
	var subs: Array = target.subsystem_ids(true)
	if subs.is_empty():
		return
	var idx := subs.find(target_subsystem)
	set_target(target, subs[(idx + 1) % subs.size()])


func set_target(new_target: Node3D, sub: String = "core") -> void:
	if target != null and is_instance_valid(target) and target != new_target and target.has_method("set_targeted"):
		target.set_targeted(false, "")
	target = new_target
	target_subsystem = sub
	if target != null and target.has_method("set_targeted"):
		target.set_targeted(true, sub)
	EventBus.target_changed.emit(target, target_subsystem)


func _validate_target() -> void:
	if target == null:
		return
	if not is_instance_valid(target) or not target.is_alive() \
			or target.global_position.distance_to(global_position) > AUTO_TARGET_RANGE * 1.5:
		set_target(null)
	elif not target.subsystem_ids(true).has(target_subsystem):
		set_target(target, "core")


# --- Taking hits -------------------------------------------------------------------------

## Returns "parried" | "dodged" | "hit" | "ignored".
func receive_attack(info: Dictionary) -> String:
	if state == State.DEAD:
		return "ignored"
	var kind: String = info.get("kind", "melee")
	var attacker = info.get("attacker")
	if state == State.PARRY and kind != "explosion":
		_on_parry_success(attacker, kind)
		return "parried"
	if _iframes > 0.0:
		EventBus.player_dodged.emit()
		return "dodged"
	var dmg := float(info.get("damage", 5.0))
	if kind == "explosion":
		dmg *= Game.stat("explosion_damage_taken")
		FlawPerk.report_mishap("took_explosion")
	if info.get("bug", false):
		dmg *= Game.stat("bug_damage_taken")
		FlawPerk.report_mishap("bitten")
	# Mishap bookkeeping for the Flaw & Perk system.
	if Game.play_time - _last_parry_whiff < 0.7:
		FlawPerk.report_mishap("failed_parry")
	var src_pos: Vector3 = info.get("position", global_position)
	if attacker != null and is_instance_valid(attacker) and attacker is Node3D:
		src_pos = (attacker as Node3D).global_position
	var to_src := Vector3(src_pos.x - global_position.x, 0, src_pos.z - global_position.z).normalized()
	if to_src.dot(facing) < -0.5 and kind == "projectile":
		FlawPerk.report_mishap("shot_in_back")
	_apply_damage(dmg, -to_src)
	return "hit"


func _on_parry_success(attacker, kind: String) -> void:
	_parry_time = 0.0
	state = State.NORMAL
	_parry_recover = 0.05
	_iframes = 0.25
	sprite.flash(Color(0.6, 3.0, 3.0), 0.12)
	Audio.play_sfx("parry", 0.05)
	FX.spark(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.5, 1.0, 1.0), 20)
	if kind == "melee" and attacker != null and is_instance_valid(attacker) and attacker.has_method("on_parried"):
		attacker.on_parried(self)
	EventBus.player_parried.emit(attacker)
	_hitstop(0.09)


func _apply_damage(dmg: float, push_dir: Vector3) -> void:
	Game.hp = maxf(0.0, Game.hp - dmg)
	EventBus.player_hp_changed.emit(Game.hp, Game.max_hp())
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.8, 0), str(roundi(dmg)), Color(1.0, 0.3, 0.4))
	sprite.flash(Color(3.0, 0.6, 0.6), 0.1)
	Audio.play_sfx("hurt")
	for cam in get_tree().get_nodes_in_group("camera_rig"):
		cam.shake(0.25)
	if Game.hp <= 0.0:
		_die()
		return
	state = State.HURT
	_hurt_time = 0.22
	velocity.x = push_dir.x * 6.0
	velocity.z = push_dir.z * 6.0


func take_hit(info: Dictionary) -> void:
	# Explosions route here through FX.explode_damage fallback - treat as attacks.
	receive_attack(info)


func _die() -> void:
	state = State.DEAD
	set_target(null)
	sprite.play("dead", true)
	EventBus.player_died.emit()


func _hitstop(duration: float) -> void:
	Engine.time_scale = 0.15
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


# --- Interaction -------------------------------------------------------------------------

func _on_interactable_entered(area: Area3D) -> void:
	if area.has_method("interact") and not _interactables.has(area):
		_interactables.append(area)
	_refresh_interactable()


func _on_interactable_exited(area: Area3D) -> void:
	_interactables.erase(area)
	_refresh_interactable()


func _refresh_interactable() -> void:
	_interactables = _interactables.filter(func(a): return is_instance_valid(a) and a.enabled)
	var best: Area3D = null
	var best_d := INF
	for a in _interactables:
		var d := a.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = a
	_current_interactable = best
	EventBus.interact_prompt_changed.emit(best.get_prompt() if best != null else "")


func refresh_interaction() -> void:
	_refresh_interactable()
