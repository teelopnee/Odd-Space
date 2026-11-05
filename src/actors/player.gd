class_name Player
extends CharacterBody3D
## The drifter. Fast, juicy action combat:
##   MOVE      analog walk/run, 8-way sprite facing, footstep dust
##   ROLL      i-frames + afterimages; dodge at the last moment = PERFECT DODGE (slow-mo)
##   MELEE     3-hit energy-baton combo with lunges, hitstop, slash arcs (finisher knocks back)
##   SHOOT     tap = blaster bolt at the locked target's SUBSYSTEM, hold = CHARGE SHOT (pierces)
##   PARRY     tight window: melee attackers stagger + lose shield, bolts reflect x2
##   OVERCLOCK spend boost pips (earned by hits/parries/perfect dodges) for a power-up burst
## Enemy shields: hitting a WEAKNESS chips the shield; at 0 the enemy BREAKS (stunned, x2 damage).
## Inputs are InputMap actions, so keyboard, gamepad and the touch HUD all drive the same code.

enum State { NORMAL, ROLL, PARRY, MELEE, HURT, DEAD, LOCKED, DASH }

## Dash strike: press MELEE with a foe 3-9 m away and you close the gap in a blink (i-frames),
## then the combo starts on arrival. The answer to enemies who keep their distance.
const DASH_MIN := 3.0
const DASH_MAX := 9.0
const DASH_SPEED := 19.0

const GRAVITY := 24.0
const ACCEL := 48.0
const FRICTION := 38.0
const ROLL_TIME := 0.36
const PERFECT_WINDOW := 0.16
const PARRY_RECOVERY := 0.3
const AUTO_TARGET_RANGE := 15.0
const MISSES_PER_MISHAP := 8
const CHARGE_TIME := 0.6
const OVERCLOCK_PER_PIP := 33.4
const COMBO := [
	{"anim": "slash1", "fx": "slash_h", "time": 0.30, "hit": 0.10, "dmg": 1.0, "push": 3.0, "lunge": 5.0, "shield": 1, "reach": 2.2},
	{"anim": "slash2", "fx": "slash_rise", "time": 0.30, "hit": 0.10, "dmg": 1.15, "push": 3.5, "lunge": 5.5, "shield": 1, "reach": 2.2},
	{"anim": "slash3", "fx": "slash_down", "time": 0.46, "hit": 0.19, "dmg": 2.0, "push": 9.0, "lunge": 7.0, "shield": 2, "reach": 2.6},
]

@onready var sprite: BillboardSprite = $Sprite
@onready var muzzle: Marker3D = $Muzzle
@onready var interact_area: Area3D = $InteractArea
@onready var glow: OmniLight3D = $Glow

var state := State.NORMAL
var facing := Vector3(0, 0, 1)
var input_locked := false
var input_grace := 0.0  ## seconds of ignored action buttons after a menu/dialogue closes
var gravity_scale := 1.0

var target: Node3D = null
var target_subsystem := "core"

var overclock := 0.0          # 0..100 meter (3 pips)
var overclock_time := 0.0     # >0 while boosted
var overclock_pips := 0

var _roll_dir := Vector3.ZERO
var _roll_time := 0.0
var _roll_cd := 0.0
var _iframes := 0.0
var _parry_time := 0.0
var _parry_recover := 0.0
var _last_parry_whiff := -10.0
var _fire_cd := 0.0
var _shoot_pose := 0.0
var _charge := 0.0
var _hurt_time := 0.0
var _misses := 0
var _combo_step := -1
var _combo_time := 0.0
var _combo_hit_done := false
var _combo_queued := false
var _combo_grace := 0.0
var _lunge := Vector3.ZERO
var _step_dist := 0.0
var _ghost_timer := 0.0
var _rs_ready := true
var _was_on_floor := true
var _interactables: Array[Area3D] = []
var _current_interactable: Area3D = null
var _base_glow := 0.7
var _dash_target: Node3D = null
var _dash_time := 0.0
var _dash_cd := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	sprite.set_look(Game.player_look if not Game.player_look.is_empty() else CharacterLook.default_look())
	Game.hp = clampf(Game.hp, 1.0, Game.max_hp())
	EventBus.player_hp_changed.emit(Game.hp, Game.max_hp())
	interact_area.area_entered.connect(_on_interactable_entered)
	interact_area.area_exited.connect(_on_interactable_exited)
	_base_glow = glow.light_energy
	_emit_overclock()


func is_alive() -> bool:
	return state != State.DEAD


func is_invulnerable() -> bool:
	return _iframes > 0.0


func set_cutscene(on: bool) -> void:
	input_locked = on
	if on and state != State.DEAD:
		state = State.LOCKED
		velocity.x = 0.0
		velocity.z = 0.0
	elif not on and state == State.LOCKED:
		state = State.NORMAL


# --- Main loop ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	var input_vec := Vector2.ZERO
	if not input_locked and state != State.DEAD:
		input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Fixed-yaw HD-2D camera looks down -Z: screen axes map straight to world X/Z.
	var move_dir := Vector3(input_vec.x, 0.0, input_vec.y)
	var strength := minf(1.0, move_dir.length())

	match state:
		State.NORMAL:
			_normal_state(delta, move_dir, strength)
		State.ROLL:
			var k := 1.0 - (_roll_time / ROLL_TIME)
			var speed := Game.stat("roll_speed") * lerpf(1.15, 0.5, k) * _oc_mult(1.12)
			velocity.x = _roll_dir.x * speed
			velocity.z = _roll_dir.z * speed
			_ghost_timer -= delta
			if _ghost_timer <= 0.0:
				_ghost_timer = 0.035
				sprite.spawn_afterimage(Color(0.35, 0.95, 1.0, 0.55))
			if _roll_time <= 0.0:
				state = State.NORMAL
				sprite.squash(Vector2(1.15, 0.88))
				FX.dust(get_parent(), global_position, 0.8)
		State.PARRY:
			_brake(delta)
			if _parry_time <= 0.0:
				state = State.NORMAL
				_parry_recover = PARRY_RECOVERY
				_last_parry_whiff = Game.play_time
		State.MELEE:
			_melee_state(delta, move_dir)
		State.DASH:
			_dash_state(delta)
		State.HURT:
			_brake(delta, 0.4)
			if _hurt_time <= 0.0:
				state = State.NORMAL
		State.DEAD, State.LOCKED:
			_brake(delta)

	if is_on_floor():
		if not _was_on_floor:
			sprite.squash(Vector2(1.2, 0.85))
			FX.dust(get_parent(), global_position, 0.7)
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * gravity_scale * delta
	_was_on_floor = is_on_floor()
	move_and_slide()
	_footsteps(delta)
	_right_stick()
	_update_animation()
	_validate_target()
	_update_glow(delta)


func _tick_timers(delta: float) -> void:
	_roll_time -= delta
	_roll_cd -= delta
	_iframes -= delta
	_parry_time -= delta
	_parry_recover -= delta
	_fire_cd -= delta
	_shoot_pose -= delta
	_hurt_time -= delta
	_combo_grace -= delta
	_dash_time -= delta
	_dash_cd -= delta
	if overclock_time > 0.0:
		overclock_time -= delta
		_ghost_timer -= delta
		if _ghost_timer <= 0.0 and Vector2(velocity.x, velocity.z).length() > 1.0:
			_ghost_timer = 0.07
			sprite.spawn_afterimage(Color(1.0, 0.3, 0.85, 0.45), 0.22)
		if overclock_time <= 0.0:
			_emit_overclock()


func _brake(delta: float, mult: float = 1.0) -> void:
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * mult * delta)
	velocity.z = move_toward(velocity.z, 0.0, FRICTION * mult * delta)


func _normal_state(delta: float, move_dir: Vector3, strength: float) -> void:
	var run_speed := Game.stat("move_speed") * _oc_mult(1.15)
	var speed := run_speed if strength > 0.6 else run_speed * 0.5 * (strength / 0.6)
	if _charge > 0.25:
		speed *= 0.55  # slow down while charging
	var target_vel := move_dir.normalized() * speed if strength > 0.05 else Vector3.ZERO
	var rate := ACCEL if strength > 0.05 else FRICTION
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)
	if strength > 0.1:
		# Sharp turn at speed kicks up dust.
		if facing.dot(move_dir.normalized()) < -0.3 and Vector2(velocity.x, velocity.z).length() > 3.0:
			FX.dust(get_parent(), global_position, 0.6)
		facing = move_dir.normalized()
	if input_locked:
		return
	if input_grace > 0.0:
		input_grace -= delta
		return
	if Input.is_action_just_pressed("dodge") and _roll_cd <= 0.0:
		_start_roll(move_dir)
	elif Input.is_action_just_pressed("parry") and _parry_recover <= 0.0:
		_start_parry()
	elif Input.is_action_just_pressed("melee"):
		_melee_pressed()
	elif Input.is_action_just_pressed("swap_melee"):
		_swap("melee")
	elif Input.is_action_just_pressed("swap_ranged"):
		_swap("ranged")
	elif Input.is_action_just_pressed("overclock"):
		activate_overclock()
	_shooting(delta)
	if Input.is_action_just_pressed("interact"):
		interact()
	if Input.is_action_just_pressed("target_cycle"):
		cycle_target()
	if Input.is_action_just_pressed("subsystem_next"):
		cycle_subsystem()


# --- Shooting / charge ------------------------------------------------------------------------

func _shooting(delta: float) -> void:
	var w := Arsenal.stats("ranged")
	if not w.get("charge", false):
		# Non-charging guns: hold to keep firing at the weapon's rate.
		_charge = 0.0
		if Input.is_action_pressed("attack") and _fire_cd <= 0.0:
			shoot(false)
		return
	if Input.is_action_just_pressed("attack") and _fire_cd <= 0.0:
		shoot(false)
		_charge = 0.0001
	elif Input.is_action_pressed("attack") and _charge > 0.0:
		_charge += delta
		if _charge > 0.25:
			if int(_charge * 12.0) % 2 == 0:
				sprite.flash(Color(1.2, 2.6, 3.0), 0.04)
			if _charge >= CHARGE_TIME and _charge - delta < CHARGE_TIME:
				Audio.play_sfx("charge", 0.0, -4.0)
				FX.rumble(0.2, 0.0, 0.1)
	elif _charge > 0.0:
		if _charge >= CHARGE_TIME:
			shoot(true)
		_charge = 0.0


func shoot(charged: bool = false) -> void:
	var w := Arsenal.stats("ranged")
	_fire_cd = 1.0 / maxf(0.3, Game.stat("fire_rate") * float(w.get("rate", 1.0)) * _oc_mult(1.5))
	if target == null or not is_instance_valid(target):
		_auto_target()
	var from := muzzle.global_position
	var aim_point: Vector3
	var sub := ""
	if target != null and is_instance_valid(target):
		sub = target_subsystem
		aim_point = target.get_subsystem_position(sub) if target.has_method("get_subsystem_position") else target.global_position + Vector3.UP
		var acc := Game.stat("accuracy") + (0.15 if charged else 0.0)
		if target.has_method("subsystem_accuracy"):
			acc *= target.subsystem_accuracy(sub)
		acc *= clampf(1.15 - from.distance_to(aim_point) / 30.0, 0.5, 1.0)
		if randf() > acc:
			var side := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.8), 0).normalized()
			aim_point += side * randf_range(0.6, 1.0)
			sub = ""
		facing = Vector3(aim_point.x - from.x, 0, aim_point.z - from.z).normalized()
	else:
		aim_point = from + facing * 10.0
	var dir := (aim_point - from).normalized()
	var dmg := Game.stat("damage") * _oc_mult(1.0 + 0.25 * maxi(1, overclock_pips)) * (3.0 if charged else 1.0) * float(w.get("dmg", 1.0))
	match str(w.get("special", "")):
		"chain":
			_arc_shot(w, dmg)
			_shot_feedback(dir, from, false)
			return
		"grenade":
			var land: Vector3 = target.global_position if target != null and is_instance_valid(target) else global_position + facing * 7.0
			Grenade.throw(get_parent(), from, Vector3(land.x, 0.25, land.z), dmg, float(w.get("radius", 3.0)), self)
			_shot_feedback(dir, from, false)
			return
	var pellets := int(w.get("pellets", 1))
	var p: Projectile = null
	for i in pellets:
		var d := dir
		if pellets > 1:
			var ang := deg_to_rad(float(w.get("spread", 20)) * (float(i) / float(pellets - 1) - 0.5) + randf_range(-3.0, 3.0))
			d = dir.rotated(Vector3.UP, ang)
		p = Projectile.spawn(get_parent(), from + d * 0.45, d, 30.0 if charged else float(w.get("speed", 26.0)), dmg, "player", self,
			sub if pellets == 1 else "")
		p.life = 1.2 if charged else float(w.get("life", 1.6))
		if w.has("push"):
			p.push_force = float(w["push"])
		if str(w.get("special", "")) == "pull":
			p.pull = true
		if w.has("stun"):
			p.stun = float(w["stun"])
	if charged:
		p.make_charged()
		FX.shake(get_tree(), 0.25)
		FX.rumble(0.4, 0.6, 0.18)
		sprite.squash(Vector2(0.85, 1.12))
		Audio.play_sfx("charge_shot", 0.05)
	else:
		Audio.play_sfx("shoot", 0.1, -3.0)
	_shot_feedback(dir, from, charged)
	if pellets > 1:
		velocity -= Vector3(dir.x, 0, dir.z) * 3.0  # scatter kick


func _shot_feedback(dir: Vector3, from: Vector3, charged: bool) -> void:
	var col := Color.from_string(str(Arsenal.stats("ranged").get("color", "#fff0b0")), Color(1.0, 0.95, 0.7))
	FXSprite.play_at(get_parent(), "muzzle", from + dir * 0.55, 1.4 if charged else 0.9, 3.0, col, dir.x < 0)
	_shoot_pose = 0.28
	sprite.play("shoot", true)
	velocity -= Vector3(dir.x, 0, dir.z) * (4.0 if charged else 0.8)  # recoil


## Arc Thrower: instant lightning to the target, then jumps to the nearest others; stuns.
func _arc_shot(w: Dictionary, dmg: float) -> void:
	var rng := float(w.get("range", 10.0))
	var first: Node3D = null
	if target != null and is_instance_valid(target) and target.global_position.distance_to(global_position) <= rng:
		first = target
	else:
		var best := INF
		for e in get_tree().get_nodes_in_group("enemy"):
			var to: Vector3 = (e.global_position - global_position) * Vector3(1, 0, 1)
			if e.is_alive() and to.length() <= rng and facing.dot(to.normalized()) > 0.2 and to.length() < best:
				best = to.length()
				first = e
	var from := muzzle.global_position
	if first == null:
		_zap(from, from + facing * 5.0)
		Audio.play_sfx("shoot", 0.2, -2.0)
		return
	var chain: Array = [first]
	for i in int(w.get("chains", 2)):
		var cur: Node3D = chain[-1]
		var nxt: Node3D = null
		var best2 := 5.0
		for e in get_tree().get_nodes_in_group("enemy"):
			if chain.has(e) or not e.is_alive():
				continue
			var dd: float = e.global_position.distance_to(cur.global_position)
			if dd < best2:
				best2 = dd
				nxt = e
		if nxt == null:
			break
		chain.append(nxt)
	var a := from
	for e in chain:
		var b: Vector3 = e.global_position + Vector3(0, 1.0, 0)
		_zap(a, b)
		e.take_hit({"damage": dmg, "attacker": self, "kind": "projectile", "subsystem": "", "position": b,
			"stun": float(w.get("stun", 0.4)), "shield_damage": 1, "push": ((b - a) * Vector3(1, 0, 1)).normalized() * 1.0})
		a = b
		dmg *= 0.8
	Audio.play_sfx("charge_shot", 0.2, -6.0)


func _zap(a: Vector3, b: Vector3) -> void:
	var pts := [a]
	for i in 3:
		var t := float(i + 1) / 4.0
		pts.append(a.lerp(b, t) + Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.2), randf_range(-0.25, 0.25)))
	pts.append(b)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.95, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.9, 1.0)
	m.emission_energy_multiplier = 6.0
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, p0.distance_to(p1))
		bm.material = m
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(mi)
		mi.global_position = (p0 + p1) * 0.5
		if p0.distance_to(p1) > 0.01:
			mi.look_at(p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.99 else Vector3.RIGHT)
		get_tree().create_timer(0.12).timeout.connect(mi.queue_free)


func on_shot_missed() -> void:
	_misses += 1
	if _misses >= MISSES_PER_MISHAP:
		_misses = 0
		FlawPerk.report_mishap("missed_shots")


# --- Melee combo -------------------------------------------------------------------------------

func _melee_pressed() -> void:
	var foe := _dash_candidate()
	if foe != null:
		_dash_target = foe
		_dash_time = 0.5
		_dash_cd = 0.8
		_iframes = maxf(_iframes, 0.32)
		state = State.DASH
		var to := (foe.global_position - global_position) * Vector3(1, 0, 1)
		facing = to.normalized()
		sprite.play("run", true)
		sprite.squash(Vector2(1.25, 0.82))
		FX.dust(get_parent(), global_position, 0.9)
		Audio.play_sfx("roll", 0.1)
		return
	_start_combo(0)


## A hostile 3-9 m away: the locked target, else the nearest one roughly in front of you.
func _dash_candidate() -> Node3D:
	if _dash_cd > 0.0:
		return null
	var cand: Array = []
	if target != null and is_instance_valid(target) and target.is_in_group("enemy"):
		cand.append(target)
	var best: Node3D = null
	var best_d := INF
	for e in cand + get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.is_queued_for_deletion() or not e.is_alive() or not e.get("hostile"):
			continue
		var to: Vector3 = (e.global_position - global_position) * Vector3(1, 0, 1)
		var d := to.length()
		if d < DASH_MIN or d > DASH_MAX:
			continue
		if e == target:
			return e
		if facing.dot(to.normalized()) > 0.35 and d < best_d:
			best_d = d
			best = e
	return best


func _dash_state(delta: float) -> void:
	if _dash_target == null or not is_instance_valid(_dash_target) or not _dash_target.is_alive() or _dash_time <= 0.0:
		state = State.NORMAL
		_start_combo(0)
		return
	var to := (_dash_target.global_position - global_position) * Vector3(1, 0, 1)
	if to.length() < 1.7:
		velocity.x = 0.0
		velocity.z = 0.0
		_start_combo(0)
		return
	facing = to.normalized()
	velocity.x = facing.x * DASH_SPEED * _oc_mult(1.1)
	velocity.z = facing.z * DASH_SPEED * _oc_mult(1.1)
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.03
		sprite.spawn_afterimage(Color.from_string(str(Arsenal.stats("melee").get("color", "#9ff7ff")), Color(0.4, 1.0, 1.0)) * Color(1, 1, 1, 0.6))


func _swap(slot: String) -> void:
	var before := Arsenal.equipped(slot)
	var now := Arsenal.cycle(slot)
	if now == before:
		EventBus.toast.emit("Only one %s so far - find more in shops and on enemies." % ("blade" if slot == "melee" else "gun"), Color(0.8, 0.8, 0.8))
		return
	Audio.play_sfx("blip", 0.1)
	sprite.flash(Color.from_string(str(Arsenal.stats(slot).get("color", "#ffffff")), Color.WHITE) * 2.0, 0.12)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.4, 0), Arsenal.label(slot).to_upper(),
		Color.from_string(str(Arsenal.stats(slot).get("color", "#ffffff")), Color.WHITE))


func _start_combo(step: int) -> void:
	_combo_step = step
	_combo_time = 0.0
	_combo_hit_done = false
	_combo_queued = false
	state = State.MELEE
	var step_data: Dictionary = COMBO[step]
	# Soft lock: turn toward the nearest foe in front (or the locked target).
	var foe := _melee_target()
	if foe != null:
		var to := foe.global_position - global_position
		to.y = 0.0
		facing = to.normalized()
		_lunge = facing * (step_data.lunge if to.length() > 1.3 else 1.0)
	else:
		_lunge = facing * step_data.lunge * 0.6
	sprite.play(step_data.anim, true)
	sprite.speed_scale = 1.0 / maxf(0.5, float(Arsenal.stats("melee").get("speed", 1.0)))
	Audio.play_sfx("slash", 0.08, -2.0)


func _melee_target() -> Node3D:
	if target != null and is_instance_valid(target) and target.global_position.distance_to(global_position) < 4.5:
		return target
	var best: Node3D = null
	var best_score := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.is_alive():
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > 4.0:
			continue
		var score := d - facing.dot(to.normalized()) * 1.5
		if score < best_score:
			best_score = score
			best = e
	return best


func _melee_state(delta: float, move_dir: Vector3) -> void:
	var step: Dictionary = COMBO[_combo_step].duplicate()
	var wspeed := float(Arsenal.stats("melee").get("speed", 1.0))
	step["time"] = float(step["time"]) * wspeed
	step["hit"] = float(step["hit"]) * wspeed
	_combo_time += delta
	velocity.x = _lunge.x
	velocity.z = _lunge.z
	_lunge = _lunge.move_toward(Vector3.ZERO, 40.0 * delta)
	if Input.is_action_just_pressed("melee") and _combo_time > step.hit * 0.6:
		_combo_queued = true
	if Input.is_action_just_pressed("dodge") and _combo_hit_done:
		state = State.NORMAL  # roll-cancel after the hit lands
		_start_roll(move_dir)
		return
	if not _combo_hit_done and _combo_time >= step.hit:
		_combo_hit_done = true
		_melee_hit(step)
	if _combo_time >= step.time:
		if _combo_queued and _combo_step < COMBO.size() - 1:
			_start_combo(_combo_step + 1)
		else:
			state = State.NORMAL
			sprite.speed_scale = 1.0
			_combo_grace = 0.3


func _melee_hit(step: Dictionary) -> void:
	var w := Arsenal.stats("melee")
	var reach := float(step.reach) + float(w.get("reach", 0.0))
	var col := Color.from_string(str(w.get("color", "#9ff7ff")), Color(0.6, 1.0, 1.0))
	var center := global_position + facing * (1.0 + float(w.get("reach", 0.0)) * 0.5) + Vector3(0, 1.0, 0)
	FXSprite.play_at(get_parent(), step.fx, center, (1.5 if step.get("shield", 1) > 1 else 1.25) * (1.0 + float(w.get("reach", 0.0)) * 0.35), 2.6, col, facing.x < 0)
	var hits := 0
	var dmg: float = Game.stat("damage") * 1.25 * float(step.dmg) * float(w.get("dmg", 1.0)) * _oc_mult(1.0 + 0.25 * maxi(1, overclock_pips))
	var fin := _combo_step == COMBO.size() - 1
	for n in get_tree().get_nodes_in_group("damageable"):
		if n == self or not is_instance_valid(n) or not n is Node3D:
			continue
		var to: Vector3 = (n as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach or (d > 0.9 and facing.dot(to.normalized()) < float(w.get("arc", 0.15))):
			continue
		var sub := target_subsystem if n == target else ""
		var info := {"damage": dmg, "attacker": self, "kind": "melee", "subsystem": sub,
			"position": (n as Node3D).global_position + Vector3(0, 1.0, 0), "push": facing * float(step.push) * float(w.get("push", 1.0)),
			"shield_damage": int(step.shield) + int(w.get("shield", 0))}
		if float(w.get("stun", 0.0)) > 0.0:
			info["stun"] = float(w["stun"]) * (1.6 if fin else 1.0)
		if w.get("pierce", false):
			info["pierce"] = true
		n.take_hit(info)
		hits += 1
	if fin and str(w.get("finisher", "")) == "shockwave":
		# Repo Hammer: the last hit slams the ground - everything around you gets thrown back.
		FX.dust(get_parent(), global_position, 2.4)
		FXSprite.play_at(get_parent(), "explosion", global_position + Vector3(0, 0.3, 0), 2.6, 1.6, col)
		for e in get_tree().get_nodes_in_group("enemy"):
			var to2: Vector3 = (e.global_position - global_position) * Vector3(1, 0, 1)
			if e.is_alive() and to2.length() <= 3.0:
				e.take_hit({"damage": dmg * 0.6, "attacker": self, "kind": "explosion", "position": e.global_position + Vector3(0, 1.0, 0),
					"push": to2.normalized() * 8.0, "shield_damage": 1})
				hits += 1
	if hits > 0:
		FX.hitstop(get_tree(), 0.09 if fin else 0.05)
		FX.shake(get_tree(), 0.35 if fin else 0.15)
		FX.rumble(0.3, 0.5 if fin else 0.2, 0.12)
		add_overclock(5.0 * hits)
		Audio.play_sfx("melee_hit", 0.1)


# --- Roll / parry / overclock ---------------------------------------------------------------

func _start_roll(move_dir: Vector3) -> void:
	_roll_dir = move_dir.normalized() if move_dir.length() > 0.1 else facing
	facing = _roll_dir
	state = State.ROLL
	_roll_time = ROLL_TIME
	_roll_cd = Game.stat("roll_cooldown") + ROLL_TIME
	_iframes = Game.stat("roll_iframes")
	_charge = 0.0
	sprite.play("roll", true)
	sprite.squash(Vector2(0.8, 1.2))
	FX.dust(get_parent(), global_position, 0.9)
	Audio.play_sfx("roll")


func _start_parry() -> void:
	state = State.PARRY
	_parry_time = Game.stat("parry_window")
	sprite.play("guard", true)
	Audio.play_sfx("parry_swing", 0.05, -6.0)


func add_overclock(amount: float) -> void:
	if overclock_time > 0.0:
		return
	overclock = clampf(overclock + amount, 0.0, 100.0)
	_emit_overclock()


func activate_overclock() -> void:
	var pips := int(overclock / OVERCLOCK_PER_PIP)
	if pips <= 0 or overclock_time > 0.0:
		return
	overclock_pips = pips
	overclock_time = 2.5 * pips
	overclock = 0.0
	sprite.flash(Color(3.0, 1.0, 2.6), 0.25)
	FX.punch(get_tree(), 0.1, 0.3)
	FX.rumble(0.5, 0.5, 0.25)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.2, 0), "OVERCLOCK x%d" % pips, Color(1.0, 0.3, 0.9), true)
	Audio.play_sfx("overclock")
	_emit_overclock()


func _oc_mult(m: float) -> float:
	return m if overclock_time > 0.0 else 1.0


func _emit_overclock() -> void:
	if overclock_time <= 0.0:
		overclock_pips = 0
	EventBus.overclock_changed.emit(overclock, maxf(overclock_time, 0.0))


func _update_glow(delta: float) -> void:
	var goal := _base_glow
	var col := Color(1, 0.85, 0.75)
	if overclock_time > 0.0:
		goal = 2.2 + sin(Time.get_ticks_msec() / 80.0) * 0.4
		col = Color(1.0, 0.35, 0.9)
	elif _charge > 0.25:
		goal = 1.2 + _charge * 2.0
		col = Color(0.4, 0.95, 1.0)
	glow.light_energy = lerpf(glow.light_energy, goal, 1.0 - exp(-10.0 * delta))
	glow.light_color = glow.light_color.lerp(col, 1.0 - exp(-10.0 * delta))


# --- Animation / feel ---------------------------------------------------------------------------

var _idle_time := 0.0


func _near_dance_floor() -> bool:
	for sp in get_tree().get_nodes_in_group("life_spot"):
		if sp.get_meta("kind", "") == "dance" and (sp as Node3D).global_position.distance_to(global_position) < 4.5:
			return true
	return false


func _update_animation() -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	match state:
		State.ROLL:
			sprite.play("roll")
		State.PARRY:
			sprite.play("guard")
		State.MELEE:
			pass
		State.DASH:
			sprite.play("run")
		State.HURT:
			sprite.play("hurt")
		State.DEAD:
			sprite.play("dead")
		_:
			sprite.speed_scale = 1.0
			if _shoot_pose > 0.0:
				sprite.play("shoot")
			elif _charge > 0.25:
				sprite.play("charge")
			elif hspeed > 3.4:
				sprite.play("run")
				sprite.speed_scale = clampf(hspeed / 6.0, 0.7, 1.4)
			elif hspeed > 0.35:
				sprite.play("walk")
				sprite.speed_scale = clampf(hspeed / 2.6, 0.6, 1.4)
			else:
				# Stand around long enough and you check your wristpad (or dance near a hologram).
				_idle_time += get_physics_process_delta_time()
				if _idle_time > 9.0 and state == State.NORMAL and target == null:
					var dancing := _near_dance_floor()
					if dancing and sprite.current != "dance":
						EventBus.player_act.emit("dance", "")
					sprite.play("dance" if dancing else "phone")
				else:
					sprite.play("idle")
			if hspeed > 0.35 or _shoot_pose > 0.0 or _charge > 0.0:
				_idle_time = 0.0
	var face_dir := facing
	if target != null and is_instance_valid(target) and state == State.NORMAL and (hspeed < 0.5 or _shoot_pose > 0.0):
		face_dir = target.global_position - global_position
	sprite.set_facing(face_dir)


func _footsteps(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if state != State.NORMAL or not is_on_floor() or hspeed < 0.5:
		return
	_step_dist += hspeed * delta
	var stride := 1.5 if hspeed > 3.4 else 1.1
	if _step_dist >= stride:
		_step_dist = 0.0
		Audio.play_sfx("step", 0.15, -14.0 if hspeed < 3.4 else -9.0)
		if hspeed > 3.4 and randf() < 0.5:
			FX.dust(get_parent(), global_position - facing * 0.3, 0.45)


## Right stick flick: X = switch target, Y = switch subsystem.
func _right_stick() -> void:
	var v := Vector2.ZERO
	for id in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
		if s.length() > v.length():
			v = s
	if v.length() < 0.3:
		_rs_ready = true
		return
	if not _rs_ready or v.length() < 0.75 or input_locked:
		return
	_rs_ready = false
	if absf(v.x) > absf(v.y):
		cycle_target(1 if v.x > 0 else -1)
	else:
		cycle_subsystem(1 if v.y > 0 else -1)


func interact() -> void:
	if _current_interactable != null and is_instance_valid(_current_interactable):
		_current_interactable.interact(self)


# --- Targeting -------------------------------------------------------------------------------

func _enemies_in_range() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.is_alive() and e.global_position.distance_to(global_position) <= AUTO_TARGET_RANGE:
			out.append(e)
	out.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	return out


func _auto_target() -> void:
	var best: Node3D = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.is_alive() and e.hostile:
			var d: float = e.global_position.distance_to(global_position)
			if d < AUTO_TARGET_RANGE and d < best_d:
				best_d = d
				best = e
	if best != null:
		set_target(best, "core")


func cycle_target(dir: int = 1) -> void:
	var list := _enemies_in_range()
	if list.is_empty():
		set_target(null)
		return
	var idx := list.find(target)
	if idx < 0:
		list.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
		set_target(list[0], "core")
		return
	set_target(list[posmod(idx + dir, list.size())], "core")
	Audio.play_sfx("blip", 0.05, -8.0)


func cycle_subsystem(dir: int = 1) -> void:
	if target == null or not is_instance_valid(target):
		_auto_target()
		return
	var subs: Array = target.subsystem_ids(true)
	if subs.is_empty():
		return
	var idx := subs.find(target_subsystem)
	set_target(target, subs[posmod(idx + dir, subs.size())])
	Audio.play_sfx("blip", 0.05, -8.0)


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


# --- Taking hits ---------------------------------------------------------------------------------

## Returns "parried" | "dodged" | "hit" | "ignored".
func receive_attack(info: Dictionary) -> String:
	if state == State.DEAD or state == State.LOCKED:
		return "ignored"
	var kind: String = info.get("kind", "melee")
	var attacker = info.get("attacker")
	if state == State.PARRY and kind != "explosion":
		_on_parry_success(attacker, kind)
		return "parried"
	if _iframes > 0.0:
		if state == State.ROLL and ROLL_TIME - _roll_time < PERFECT_WINDOW + 0.06 and kind != "explosion":
			_perfect_dodge()
		EventBus.player_dodged.emit()
		return "dodged"
	var dmg := float(info.get("damage", 5.0))
	if kind == "explosion":
		dmg *= Game.stat("explosion_damage_taken")
		FlawPerk.report_mishap("took_explosion")
	if info.get("bug", false):
		dmg *= Game.stat("bug_damage_taken")
		FlawPerk.report_mishap("bitten")
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


func _perfect_dodge() -> void:
	if Engine.time_scale < 0.9:
		return
	_iframes = maxf(_iframes, 0.5)
	add_overclock(20.0)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.2, 0), "PERFECT!", Color(0.4, 1.0, 1.0), true)
	sprite.flash(Color(1.0, 3.0, 3.0), 0.12)
	Audio.play_sfx("perfect")
	FX.rumble(0.3, 0.0, 0.15)
	EventBus.perfect_dodge.emit()
	FX.slowmo(get_tree(), 0.3, 0.55)


func _on_parry_success(attacker, kind: String) -> void:
	_parry_time = 0.0
	state = State.NORMAL
	_parry_recover = 0.05
	_iframes = 0.3
	sprite.flash(Color(0.6, 3.0, 3.0), 0.12)
	sprite.squash(Vector2(1.15, 0.9))
	Audio.play_sfx("parry", 0.05)
	FX.spark(get_parent(), global_position + facing * 0.6 + Vector3(0, 1.0, 0), Color(0.5, 1.0, 1.0), 24)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.3, 0), "PARRY!", Color(0.4, 1.0, 1.0), true)
	FX.punch(get_tree(), 0.14, 0.3)
	FX.rumble(0.6, 0.8, 0.15)
	add_overclock(18.0)
	if kind == "melee" and attacker != null and is_instance_valid(attacker) and attacker.has_method("on_parried"):
		attacker.on_parried(self)
	EventBus.player_parried.emit(attacker)
	FX.hitstop(get_tree(), 0.12, 0.08)


func _apply_damage(dmg: float, push_dir: Vector3) -> void:
	var was_ok := Game.hp >= Game.max_hp() * 0.35
	Game.hp = maxf(0.0, Game.hp - dmg)
	if was_ok and Game.hp > 0.0 and Game.hp < Game.max_hp() * 0.35:
		EventBus.player_act.emit("hurt", "")  # bystanders notice you bleeding
	EventBus.player_hp_changed.emit(Game.hp, Game.max_hp())
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.9, 0), str(roundi(dmg)), Color(1.0, 0.3, 0.4))
	sprite.flash(Color(3.0, 0.6, 0.6), 0.12)
	Audio.play_sfx("hurt")
	FX.shake(get_tree(), 0.3)
	FX.rumble(0.4, 0.7, 0.2)
	FX.hitstop(get_tree(), 0.05, 0.1)
	_charge = 0.0
	if Game.hp <= 0.0:
		_die()
		return
	state = State.HURT
	_hurt_time = 0.22
	velocity.x = push_dir.x * 7.0
	velocity.z = push_dir.z * 7.0


func take_hit(info: Dictionary) -> void:
	receive_attack(info)


func _die() -> void:
	state = State.DEAD
	set_target(null)
	sprite.play("dead", true)
	FX.slowmo(get_tree(), 0.3, 0.8)
	EventBus.player_died.emit()


# --- Interaction ------------------------------------------------------------------------------

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
