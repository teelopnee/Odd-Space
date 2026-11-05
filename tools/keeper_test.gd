extends SceneTree
## Shop owners: spawned at every door, greet you by relationship, price by mood, react to every
## shop option (success + fail) with a counter-move, can ban you, close when killed, and are the
## same person (same mood) when you come back. Exit code = failures.
##   godot --headless --path . --script res://tools/keeper_test.gd

var _step := 0
var _wait := 0
var _fails := 0
var _last: Array = []
var _planet := {}
var _remember := {}


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			var tags := {"class": "heir_gristle", "age": "middle", "background": "bouncer", "personality": "hothead",
				"motivation": "revenge", "secret": "kleptomaniac"}
			var g = root.get_node("Game")
			g.new_game("Shop Tester", tags, 2024)
			for p in g.galaxy:
				if p.environment == "neon_sprawl":
					_planet = p
					break
			if _planet.is_empty():
				_planet = g.galaxy[0]
			_enter()
			_step = 1
		1:
			root.get_node("EventBus").dialogue_requested.connect(func(s, t, c, cb): _last = [s, t, c, cb])
			_close()
			_run_shops()
			_step = 2
		2:
			_enter()  # come back to the same planet
			_step = 3
		3:
			_close()
			_check_memory()
			print("\nKEEPER TEST DONE - %d failures" % _fails)
			quit(_fails)
	return false


func _enter() -> void:
	root.get_node("Router").params = {"planet_id": _planet.id}
	change_scene_to_file("res://scenes/world/planet_surface.tscn")
	_wait = 200


func _close() -> void:
	var hud = get_first_node_in_group("hud")
	for i in 16:
		if hud and hud._dialogue_open:
			hud._on_choice("")
	paused = false


func _check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1


func _doors() -> Array:
	return current_scene.find_children("*", "", true, false).filter(func(n): return "venue_id" in n and str(n.get("venue_id")) != "" and n.has_meta("keeper"))


func _run_shops() -> void:
	var inter = root.get_node("Interactions")
	var game = root.get_node("Game")
	var player = get_first_node_in_group("player")
	var doors := _doors()
	print("== %d shops with an owner on %s" % [doors.size(), _planet.name])
	_check(doors.size() >= 3, "owners stand at the shop doors")
	if doors.is_empty():
		return
	# Greeting + personal prices.
	var d0 = doors[0]
	var k0 = d0.get_meta("keeper")
	player.global_position = d0.global_position + Vector3(0, -0.7, 1.0)
	_last = []
	inter.open_venue(d0.venue_id, d0.venue_sign, d0.owner_faction, d0)
	_check(not _last.is_empty() and str(_last[0]).contains(k0.npc_name), "the owner greets you by name (%s)" % (str(_last[0]) if not _last.is_empty() else "-"))
	print("    | " + str(_last[1]).replace("\n", "\n    | ") if not _last.is_empty() else "")
	_close()
	k0.attitude = 60
	var cheap: float = k0.price_mult()
	k0.attitude = -50
	var dear: float = k0.price_mult()
	_check(cheap < 1.0 and dear > 1.0, "prices follow their mood (friend x%.2f, enemy x%.2f)" % [cheap, dear])
	k0.attitude = 0
	# Every option of every shop type, both outcomes -> the owner reacts and answers back.
	var seen := {}
	var no_counter := []
	var played := 0
	var vi := 0
	for vid in root.get_node("DataDB").venues.venues:
		# Every shop type, each run by one of this city's owners.
		var d = doors[vi % doors.size()]
		vi += 1
		seen[vid] = true
		var k = d.get_meta("keeper")
		var opts: Array = root.get_node("DataDB").venues.venues[vid].options
		for o in opts:
			for outcome in [true, false]:
				if not outcome and not o.has("fail"):
					continue
				if not is_instance_valid(k):
					break
				game.credits = 9999
				k.banned = false
				k.attitude = 0
				k.state = "idle"
				game.inventory["scrap"] = 3
				game.inventory["pre_war_coin"] = 1
				player.global_position = d.global_position + Vector3(0, -0.7, 1.0)
				inter.open_venue(vid, d.venue_sign, d.owner_faction, d)
				_close()
				inter.force_outcome = outcome
				_last = []
				inter._on_venue_choice(str(o.id))
				inter.force_outcome = null
				played += 1
				if _last.is_empty() or (_last[2] as Array).size() < 2:
					var shop_flow: bool = o.get("success", {}).has("shop")
					if not shop_flow:
						no_counter.append("%s:%s/%s" % [vid, o.id, "ok" if outcome else "fail"])
				_close()
	print("  shop options played: %d (%d shop types)" % [played, seen.size()])
	_check(no_counter.is_empty(), "the owner answers back after every shop option %s" % str(no_counter))
	# Every venue counter choice.
	var n := 0
	var t: Dictionary = root.get_node("DataDB").counters.get("venue", {})
	for key in t:
		for tpl in t[key]:
			for i in (tpl.choices as Array).size():
				for outcome in [true, false]:
					var k = doors[n % doors.size()].get_meta("keeper")
					if not is_instance_valid(k):
						continue
					game.credits = 9999
					inter.force_outcome = outcome
					_last = []
					inter._on_counter_choice("c%d" % i, k, tpl)
					inter.force_outcome = null
					if _last.is_empty():
						_check(false, "venue/%s choice %d produced nothing" % [key, i])
					n += 1
					_close()
	print("  owner counter choices played: %d" % n)
	# Banned.
	var d1 = doors[1 % doors.size()]
	var k1 = d1.get_meta("keeper")
	k1.react("banned")
	_last = []
	inter.open_venue(d1.venue_id, d1.venue_sign, d1.owner_faction, d1)
	_check(not _last.is_empty() and str(_last[1]).to_lower().contains("ban") or str(_last[1]).contains("welcome") or str(_last[1]).contains("Not you") or str(_last[1]).contains("Turn around"),
		"a banned customer gets turned away (%s)" % (str(_last[1]).substr(0, 60) if not _last.is_empty() else "-"))
	_close()
	_remember = {"key": k1.keeper_key, "name": k1.npc_name, "banned": true}
	# A dead owner leaves a dark shop.
	var d2 = doors[2 % doors.size()]
	var k2 = d2.get_meta("keeper")
	k2._die(true)
	_close()
	_last = []
	inter.open_venue(d2.venue_id, d2.venue_sign, d2.owner_faction, d2)
	_check(not _last.is_empty() and str(_last[1]).contains("shutters"), "the shop is dark after its owner dies")
	_close()


func _check_memory() -> void:
	print("\n== coming back")
	var found := false
	for d in _doors():
		var k = d.get_meta("keeper")
		if k.keeper_key == _remember.get("key", ""):
			found = true
			_check(k.npc_name == _remember.name, "same owner as last time (%s)" % k.npc_name)
			_check(k.is_banned(), "they still remember banning you")
	_check(found, "the owner is back at their shop")
