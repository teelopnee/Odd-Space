extends SceneTree
## Headless runtime smoke test: plays through every scene and pokes the core
## systems. Any SCRIPT ERROR in the output = failure.
## Run:  godot --headless --path . --script res://tools/smoke_test.gd

var _step := 0
var _wait := 0
var _planet_index := 0
var _log: Array[String] = []
var _saga_steps := 0


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			_say("title")
			change_scene_to_file("res://scenes/ui/title_screen.tscn")
			_next(30)
		1:
			_say("character creation")
			change_scene_to_file("res://scenes/ui/character_creation.tscn")
			_next(30)
		2:
			_say("new game -> station")
			var game = root.get_node("Game")
			game.new_game("Smoke Tester", {"background": "street_medic", "motivation": "burn_consortium", "secret": "kleptomaniac"}, 1234)
			change_scene_to_file("res://scenes/world/station_prologue.tscn")
			_next(90)
		3:
			_say("combat + crimes in station")
			_combat_and_crime()
			_next(240)
		4:
			_report_state()
			_say("exit to ship")
			current_scene.exit_to_ship()
			_next(120)
		5:
			_say("star map: %s" % current_scene.name)
			_next(10)
		6:
			var game = root.get_node("Game")
			if _planet_index >= game.galaxy.size():
				_step = 8
				return false
			var p: Dictionary = game.galaxy[_planet_index]
			_say("planet %d: %s [%s / %s / %s / %s]" % [_planet_index, p.name, p.environment, p.controller, p.crisis, p.anomaly])
			root.get_node("Router").params = {"planet_id": p.id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_next(150)
		7:
			_combat_and_crime()
			# Build every pause-menu tab (journal portraits, crew, causality...) once per planet.
			var hud = get_first_node_in_group("hud")
			if hud:
				hud._menu.open("journal")
				hud._menu.visible = false
			_planet_index += 1
			_step = 6
			_wait = 120
		8:
			_say("encounters")
			var enc = root.get_node("Encounters")
			for e in root.get_node("DataDB").encounters.list:
				for ch in e.choices:
					enc.resolve(e, ch)
			_say("save/load")
			var game = root.get_node("Game")
			print("save ok: ", game.save_game(2))
			print("load ok: ", game.load_game(2))
			_report_state()
			_say("native start (random look, universe 4321)")
			var rng := RandomNumberGenerator.new()
			rng.seed = 99
			var look: Dictionary = load("res://src/core/character_look.gd").call("random_look", rng, "hero")
			game.new_game("Native Tester", {"background": "street_medic", "motivation": "find_sibling", "secret": "sleeper_agent"}, 4321, look, "")
			var home: Dictionary = game.galaxy[2]
			game.new_game("Native Tester", {"background": "street_medic", "motivation": "find_sibling", "secret": "sleeper_agent"}, 4321, look, home.id)
			print("  home: %s  native_of=%s  credits=%d  look=%s" % [home.name, game.flags.get("native_of", ""), game.credits, look.variant])
			root.get_node("Router").params = {"planet_id": home.id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_next(150)
		9:
			_say("saga: play every beat")
			change_scene_to_file("res://scenes/ui/star_map.tscn")
			var bus = root.get_node("EventBus")
			bus.dialogue_requested.connect(_auto_answer)
			_next(20)
		10:
			var saga = root.get_node("Saga")
			if saga.is_complete() or _saga_steps > 12:
				print("  saga ending: %s  twist: %s  journal: %d entries" % [saga.ending, saga.twist_choice, saga.journal.size()])
				_step = 11
				return false
			var b: Dictionary = saga.current()
			_saga_steps += 1
			print("  beat %d/%d %s (%s) on %s: %s" % [saga.index + 1, saga.beats.size(), b.get("id", "?"), b.get("type", "?"), saga.objective_planet(), saga.objective_text().left(90)])
			print("    spawns there: ", saga.spawns_for(saga.objective_planet()).map(func(sp): return sp.kind))
			match str(b.get("type", "")):
				"talk":
					saga.on_persona_talk(saga.cast.get(b.get("who", ""), ""))
				"retrieve":
					saga.on_item_taken(b.id)
				"defeat":
					var dummy := Node.new()
					dummy.set_meta("saga_tag", b.id)
					root.get_node("EventBus").enemy_killed.emit(dummy, {})
					dummy.free()
			_wait = 6
		11:
			print("SMOKE TEST DONE")
			quit(0)
	return false


## Answers every dialogue with its first enabled choice, like an impatient player.
func _auto_answer(_speaker: String, _text: String, choices: Array, callback: Callable) -> void:
	var pick := ""
	for c in choices:
		if not c.get("disabled", false):
			pick = str(c.get("id", ""))
			break
	if callback.is_valid():
		callback.call_deferred(pick)


func _next(frames: int) -> void:
	_step += 1
	_wait = frames


func _say(text: String) -> void:
	print(">>> ", text)


func _combat_and_crime() -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		print("!! no player")
		return
	# Shoot at the nearest enemy, roll, parry.
	player.cycle_target()
	player.cycle_subsystem()
	for i in 3:
		player.shoot()
	Input.action_press("dodge")
	Input.action_release("dodge")
	# Hit every enemy's jetpack/legs directly to exercise subsystem effects.
	for e in get_nodes_in_group("enemy"):
		for sub in e.subsystem_ids(true):
			e.take_hit({"damage": 15.0, "attacker": player, "subsystem": sub, "kind": "projectile"})
		break
	# Crime next to an NPC so a witness starts reporting.
	var npcs = get_nodes_in_group("npc")
	if not npcs.is_empty():
		var n = npcs[0]
		root.get_node("Causality").record("theft", {"target": "Test crate", "target_faction": "oxy", "position": n.global_position + Vector3(1, 0, 0)})
		n.take_hit({"damage": 100.0, "attacker": player})
	# Explosive props / ads.
	for prop in get_nodes_in_group("damageable"):
		if _class_of(prop) == "ShootableProp":
			prop.take_hit({"damage": 50.0, "attacker": player})
			break
	# Use every interactable once (dialogues auto-queue in the HUD).
	var hud = get_first_node_in_group("hud")
	for it in _find_interactables(current_scene):
		if it.kind != "dock" and it.kind != "terminal":
			it.interact(player)
	if hud:
		# Close all modals by picking the first choice repeatedly.
		for i in 12:
			if hud._dialogue_open:
				hud._on_choice("")
		if hud._shop_panel.visible:
			hud._shop_panel.visible = false
			hud._after_modal_closed()
		hud.open_menu("causality")
		hud._close_menu()
	paused = false


func _find_interactables(node: Node) -> Array:
	var out := []
	for c in node.get_children():
		if _class_of(c) == "PropInteractable":
			out.append(c)
		out.append_array(_find_interactables(c))
	return out


## Compare by global class name so this tool never compiles game classes before
## the autoloads exist (which would poison the script cache).
func _class_of(n: Object) -> String:
	var sc = n.get_script()
	return sc.get_global_name() if sc != null else ""


func _report_state() -> void:
	var c = root.get_node("Causality")
	var f = root.get_node("Factions")
	var g = root.get_node("Game")
	print("  causality nodes: ", c.nodes.size(), "  reported: ", c.reported_count(), "  headlines: ", c.latest_headlines(2))
	print("  rep: ", f.rep, "  bounty: ", f.total_bounty())
	print("  credits: ", g.credits, "  hp: ", g.hp, "  air debt: ", g.air_debt, "  items: ", g.inventory)
