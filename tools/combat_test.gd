extends SceneTree
## Combat sanity check (headless): every enemy type spawns and fights, only a few attack at once,
## every weapon hurts, the dash strike closes distance, riot shields block from the front, boom bots
## chain-explode, weapons unlock from items and start kits. Exit code = failures.
##   godot --headless --path . --script res://tools/combat_test.gd

var _step := 0
var _wait := 0
var _fails := 0
var _level: Node = null
var _player: Node = null
var _foes: Array = []
var _max_shooters := 0
var _max_attackers := 0
var _probe := {}


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _step == 3:
			_count_attackers()
		return false
	match _step:
		0:
			var tags := {"class": "working_poor", "age": "prime", "background": "bouncer", "personality": "hothead",
				"motivation": "revenge", "secret": "mob_debt"}
			var g = root.get_node("Game")
			g.new_game("Combat Tester", tags, 31337)
			_check(g.flags.get("weapons", {}).get("melee", []).has("hammer"), "a bouncer starts with the Repo Hammer")
			root.get_node("Router").params = {"planet_id": g.galaxy[0].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_step = 1
			_wait = 200
		1:
			_close()
			_level = current_scene
			_player = get_first_node_in_group("player")
			_player._iframes = 9999.0
			for e in get_nodes_in_group("enemy"):
				e.queue_free()
			_step = 2
			_wait = 5
		2:
			print("\n== every enemy type")
			var types: Array = root.get_node("DataDB").enemies.keys().filter(func(k): return not str(k).begins_with("_"))
			var i := 0
			for t in types:
				var a := TAU * float(i) / float(types.size())
				var e = _level.spawn_enemy(t, _player.global_position + Vector3(cos(a), 0, sin(a)) * 7.0, {"hostile": true})
				_foes.append(e)
				i += 1
			_check(_foes.size() >= 10, "%d enemy types spawn (%s)" % [_foes.size(), ", ".join(types)])
			# Pack four shooters around the player: tokens must keep it to one shooter at a time.
			for k in 4:
				var a := TAU * k / 4.0
				_foes.append(_level.spawn_enemy("paragon_officer", _player.global_position + Vector3(cos(a), 0, sin(a)) * 6.0, {"hostile": true}))
			_step = 3
			_wait = 360
		3:
			_check(_max_shooters <= 1, "never more than one shooter firing at once (max %d)" % _max_shooters)
			_check(_max_attackers <= 2 + 1, "attackers take turns (max %d at once)" % _max_attackers)
			var fought := 0
			for e in _foes:
				if is_instance_valid(e) and e.state != "idle":
					fought += 1
			_check(fought >= 8, "enemies engage (%d active)" % fought)
			for e in get_nodes_in_group("enemy"):
				e.free()
			_foes.clear()
			_step = 4
			_wait = 5
		4:
			_weapons_start()
			_step = 5
			_wait = 50
		5:
			_close()  # a story popup may have paused the tree mid-flight
			_step = 51
			_wait = 45
		51:
			_close()
			_weapons_check()
			_step = 6
			_wait = 2
		6:
			_dash_start()
			_step = 7
			_wait = 40
		7:
			_dash_check()
			_guard_test()
			_boom_start()
			_step = 8
			_wait = 30
		8:
			_boom_check()
			var g = root.get_node("Game")
			g.add_item("weapon_scatter", 1)
			_check(load("res://src/core/arsenal.gd").owns("scatter"), "picking up a weapon item unlocks it")
			print("\nCOMBAT TEST DONE - %d failures" % _fails)
			quit(_fails)
	return false


func _count_attackers() -> void:
	var shooters := 0
	var attackers := 0
	for e in get_nodes_in_group("enemy"):
		if e.state in ["windup", "attack"]:
			attackers += 1
			if e._is_ranged():
				shooters += 1
	_max_shooters = maxi(_max_shooters, shooters)
	_max_attackers = maxi(_max_attackers, attackers)


func _close() -> void:
	var hud = get_first_node_in_group("hud")
	for i in 8:
		if hud and hud._dialogue_open:
			hud._on_choice("")
	paused = false


func _check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1


func _dummy(type: String, offset: Vector3):
	var e = _level.spawn_enemy(type, _player.global_position + offset, {"hostile": false})
	e.max_hp = 9999.0
	e.hp = 9999.0
	e.set_physics_process(false)  # hold still: we only measure damage
	return e


func _weapons_start() -> void:
	print("\n== every weapon")
	var arsenal = load("res://src/core/arsenal.gd")
	var g = root.get_node("Game")
	g.flags["weapons"] = {"melee": arsenal.data().melee.keys(), "ranged": arsenal.data().ranged.keys()}
	_player.facing = Vector3(0, 0, -1)
	var origin: Vector3 = _player.global_position
	var x := -8.0
	for wid in arsenal.data().ranged:
		g.flags["equip"]["ranged"] = wid
		_player.global_position = origin
		var e = _dummy("pirate", Vector3(x, 0, -4.0))
		_player.global_position = e.global_position + Vector3(0, 0, 4.0)
		_player.target = e
		_player._fire_cd = 0.0
		_player.shoot(false)
		_probe[wid] = e
		x += 4.0
	g.flags["equip"]["ranged"] = "sidearm"
	for wid in arsenal.data().melee:
		g.flags["equip"]["melee"] = wid
		_player.global_position = origin
		var e = _dummy("pirate", Vector3(x, 0, -1.2))
		_player.global_position = e.global_position + Vector3(0, 0, 1.2)
		_player.target = e
		_player.facing = Vector3(0, 0, -1)
		_player._melee_hit({"fx": "slash_h", "dmg": 1.0, "push": 3.0, "shield": 1, "reach": 2.2})
		_probe["melee:" + wid] = e
		x += 4.0
	g.flags["equip"]["melee"] = "pipe"


func _weapons_check() -> void:
	for wid in _probe:
		var e = _probe[wid]
		var hurt: bool = is_instance_valid(e) and e.hp < 9999.0
		_check(hurt, "%s deals damage (%.0f)" % [wid, 9999.0 - e.hp if is_instance_valid(e) else 0.0])
	for e in get_nodes_in_group("enemy"):
		e.free()
	_probe.clear()


var _dash_foe: Node = null


func _dash_start() -> void:
	print("\n== dash strike")
	_dash_foe = _level.spawn_enemy("paragon_officer", _player.global_position + Vector3(0, 0, -7.0), {"hostile": true})
	_dash_foe.set_physics_process(false)
	_player.target = null
	_player.facing = Vector3(0, 0, -1)
	_player._dash_cd = 0.0
	_player.state = 0
	_player._melee_pressed()
	_check(_player.state == 7, "MELEE with a foe 7 m away starts a dash (state %d)" % _player.state)


func _dash_check() -> void:
	var d: float = _player.global_position.distance_to(_dash_foe.global_position) if is_instance_valid(_dash_foe) else 0.0
	_check(d < 3.0, "the dash closed the gap (now %.1f m)" % d)
	for e in get_nodes_in_group("enemy"):
		e.queue_free()


func _guard_test() -> void:
	print("\n== riot shield")
	var r = _level.spawn_enemy("riot_trooper", _player.global_position + Vector3(0, 0, -3.0), {"hostile": true})
	r.set_physics_process(false)
	r.hp = 500.0
	r._player = _player
	var before: float = r.hp
	r.take_hit({"damage": 10.0, "attacker": _player, "kind": "projectile", "position": r.global_position})
	var front: float = before - r.hp
	var behind := Node3D.new()
	_level.add_child(behind)
	behind.global_position = r.global_position + Vector3(0, 0, -3.0)
	before = r.hp
	r.take_hit({"damage": 10.0, "attacker": behind, "kind": "projectile", "position": r.global_position})
	var back: float = before - r.hp
	_check(front < back * 0.5, "shots from the front are blocked (%.1f vs %.1f from behind)" % [front, back])
	r.queue_free()
	behind.queue_free()


var _boom_neighbour: Node = null


func _boom_start() -> void:
	print("\n== boom bot")
	var b = _level.spawn_enemy("boom_bot", _player.global_position + Vector3(4.0, 0, -6.0), {"hostile": true})
	_boom_neighbour = _dummy("pirate", Vector3(5.2, 0, -6.0))
	b.take_hit({"damage": 999.0, "attacker": _player, "kind": "projectile", "position": b.global_position})


func _boom_check() -> void:
	var hurt: bool = is_instance_valid(_boom_neighbour) and _boom_neighbour.hp < 9999.0
	_check(hurt, "shooting a boom bot blows up the enemy next to it")
