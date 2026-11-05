extends SceneTree
## Headless runtime smoke test: plays through every scene and pokes the core
## systems. Any SCRIPT ERROR in the output = failure.
## Run:  godot --headless --path . --script res://tools/smoke_test.gd

var _step := 0
var _wait := 0
var _planet_index := 0
var _log: Array[String] = []
var _saga_steps := 0
const LIVES := 6
var _life := 0
var _endings := {}
var _arng := RandomNumberGenerator.new()
var _random_answers := false


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
				_step = 20
				return false
			var b: Dictionary = saga.current()
			_saga_steps += 1
			print("  beat %d/%d %s (%s) on %s: %s" % [saga.index + 1, saga.beats.size(), b.get("id", "?"), b.get("type", "?"), saga.objective_planet(), saga.objective_text().left(90)])
			print("    spawns there: ", saga.spawns_for(saga.objective_planet()).map(func(sp): return sp.kind))
			_play_beat(saga, b, false)
			_wait = 6
		20:
			# LIFE PATHS: random characters through interactions, street events,
			# planet stories and the branching saga, each to its own ending.
			if _life >= LIVES:
				print("  distinct endings in %d lives: %d" % [LIVES, _endings.size()])
				_step = 11
				return false
			_new_life()
			_step = 21
			_wait = 5
		21:
			var saga = root.get_node("Saga")
			if saga.is_complete() or _saga_steps > 40:
				print("    -> ENDING: %s\n       id: %s" % [saga.ending_title, saga.ending])
				_endings[saga.ending] = true
				_life += 1
				_step = 20
				return false
			_saga_steps += 1
			_play_beat(saga, saga.current(), true)
			_wait = 8
		11:
			var game = root.get_node("Game")
			print("save ok: ", game.save_game(3), "  load ok: ", game.load_game(3))
			print("SMOKE TEST DONE")
			quit(0)
	return false


## Answers every dialogue with its first (or a random) enabled choice.
func _auto_answer(_speaker: String, _text: String, choices: Array, callback: Callable) -> void:
	var pick := ""
	var enabled := choices.filter(func(c): return not c.get("disabled", false))
	if not enabled.is_empty():
		pick = str((enabled[_arng.randi() % enabled.size()] if _random_answers else enabled[0]).get("id", ""))
	if callback.is_valid():
		callback.call_deferred(pick)


func _play_beat(saga, b: Dictionary, surrender: bool) -> void:
	match str(saga._beat_type(b)):
		"talk":
			saga.on_persona_talk(saga.cast.get(b.get("who", ""), ""))
		"retrieve":
			saga.on_item_taken(b.id)
		"defeat":
			if surrender:
				saga.on_surrender(_dummy_enemy(), b.id)
			else:
				var dummy := Node.new()
				dummy.set_meta("saga_tag", b.id)
				root.get_node("EventBus").enemy_killed.emit(dummy, {})
				dummy.free()


## A stand-in for a beaten elite that has surrendered.
func _dummy_enemy() -> Node:
	var sc := GDScript.new()
	sc.source_code = "extends Node\nvar display_name := \"Elite\"\nfunc resolve_surrender(_o: String) -> void:\n\tqueue_free()\n"
	sc.reload()
	var n := Node.new()
	n.set_script(sc)
	root.add_child(n)
	return n


func _new_life() -> void:
	_random_answers = true
	_saga_steps = 0
	_arng.seed = 7000 + _life * 13
	var game = root.get_node("Game")
	var origin = root.get_node("Origin")
	var tags: Dictionary = origin.random_tags(_arng)
	var age: int = origin.random_age(tags.age, _arng)
	var look: Dictionary = load("res://src/core/character_look.gd").call("random_look", _arng, "hero")
	var universe := 100000 + _life * 7919
	var galaxy: Array = load("res://src/core/planet_generator.gd").call("generate_galaxy", universe, 7)
	var start: String = "" if _arng.randf() < 0.4 else str(galaxy[_arng.randi() % galaxy.size()].id)
	game.new_game("Life %d" % _life, tags, universe, look, start, age)
	print(">>> LIFE %d: %s (%s)  start: %s" % [_life, origin.persona_line(), tags.motivation + "/" + tags.secret, "cryo" if start == "" else start])
	game.credits += _arng.randi_range(0, 3000)  # some lives get rich along the way
	# Talk to people the way this character can.
	var npc_scene: PackedScene = load("res://scenes/actors/npc.tscn")
	var interactions = root.get_node("Interactions")
	var used := []
	for i in 3:
		var npc = npc_scene.instantiate()
		npc.traits.assign([["poor", "worker", "artsy", "corporate", "rebel", "weird"][_arng.randi() % 6]])
		root.add_child(npc)
		var options: Array = interactions.choices_for(npc, "civilian") + interactions.choices_for(npc, "witness")
		for o in options.slice(0, 3):
			interactions.resolve(npc, str(o.id).substr(4))
			used.append(str(o.id).substr(4))
		npc.queue_free()
	print("    interactions used: ", used)
	# Planet stories + street events on a few worlds.
	var stories = root.get_node("Stories")
	for p in game.galaxy.slice(0, 4):
		var s: Dictionary = stories.ensure_local(p.id)
		if s.is_empty():
			continue
		var t: Dictionary = stories.templates().get(s.crisis, {})
		var ok := (t.get("choices", []) as Array).filter(func(c): return root.get_node("Saga").choice_ok(c))
		if ok.is_empty():
			continue
		var c: Dictionary = ok[_arng.randi() % ok.size()]
		stories._on_local_choice(str(c.id), p.id)
		if stories.local[p.id].status == "task":
			stories._resolve_local(p.id, str(stories.local[p.id].get("pending_outcome", "")))
		print("    planet %s: %s -> %s" % [p.name, c.id, stories.local[p.id].outcome])
	var events: Array = root.get_node("DataDB").stories.get("street", [])
	game.location_id = game.galaxy[0].id
	for k in 3:
		var e: Dictionary = events[_arng.randi() % events.size()]
		var ch := (e.get("choices", []) as Array).filter(func(c): return root.get_node("Saga").choice_ok(c))
		if not ch.is_empty():
			stories._on_street_choice(str(ch[_arng.randi() % ch.size()].id), null, str(e.id))
	# Walk into every venue and try everything this character is allowed to do.
	var venues: Dictionary = root.get_node("DataDB").venues.get("venues", {})
	var tried := 0
	for vid in venues:
		interactions._venue_ctx = {"id": vid, "sign": "TEST", "faction": ""}
		for o in venues[vid].get("options", []):
			if root.get_node("Saga").choice_ok(o):
				interactions._venue_ctx = {"id": vid, "sign": "TEST", "faction": ""}
				interactions._on_venue_choice(str(o.id))
				tried += 1
	print("    venue options tried: %d   fame %d  followers %d" % [tried, int(game.flags.get("fame", 0)), int(game.flags.get("followers", 0))])
	var early: Dictionary = root.get_node("Saga").early_ending_available()
	if not early.is_empty():
		print("    early ending available: ", early.get("text", ""))


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
