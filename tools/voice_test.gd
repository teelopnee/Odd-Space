extends SceneTree
## Headless check of NPC eyes, memory and voices:
##   godot --headless --path . --script res://tools/voice_test.gd [-- <class> <age> <background>]
## Starts a life, lands on a planet, does things in front of NPCs and prints what they say:
## bystander reactions, remarks about who you are, memories, gossip, memory-driven verbs.

var _step := 0
var _wait := 0
var _voice: GDScript


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			_voice = load("res://src/core/npc_voice.gd")
			var a := OS.get_cmdline_user_args()
			var tags := {"class": a[0] if a.size() > 0 else "heir_halcyon", "age": a[1] if a.size() > 1 else "elder",
				"background": a[2] if a.size() > 2 else "jingle_composer", "personality": "honest", "motivation": "find_sibling",
				"secret": "sleeper_agent"}
			root.get_node("Game").new_game("Vox Tester", tags, 777)
			var g = root.get_node("Game")
			var pl: Dictionary = g.galaxy[0]
			root.get_node("Router").params = {"planet_id": pl.id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_step = 1
			_wait = 200
		1:
			var hud = get_first_node_in_group("hud")
			if hud and hud._dialogue_open:
				hud._on_choice("")
			paused = false
			_run()
			quit(0)
	return false


func _run() -> void:
	var player = get_first_node_in_group("player")
	var npcs := get_nodes_in_group("npc").filter(func(n): return n.role == "civilian" and n.state != "dead")
	print("VOICE: %d civilians, player %s" % [npcs.size(), player != null])
	if npcs.is_empty() or player == null:
		return
	var a = npcs[0]
	var b = npcs[1] if npcs.size() > 1 else npcs[0]
	player.global_position = a.global_position + Vector3(1.5, 0, 0)
	b.global_position = a.global_position + Vector3(-1.5, 0, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	print("\n== who they think you are (%s, voice %s, mood %s)" % [a.npc_name, _voice.voice(a), _voice.mood(a)])
	for i in 6:
		print("  ", _voice.remark(a, rng))
	print("\n== bubbles")
	for i in 3:
		print("  ", _voice.remark(b, rng, true))
	print("\n== acts in front of them")
	for kind in ["charity", "threat", "theft", "kill_cop", "skill", "dance", "hurt", "vice"]:
		var st: String = _voice.stance_for(a, kind)
		print("  [%s/%s] %s" % [kind, st, _voice.react_now(a, kind, st, "Old Ines", rng)])
	a.witness_act("charity", "Old Ines")
	a.witness_act("kill_cop", "Paragon Officer")
	b.witness_act("skill", "a bullet")
	print("\n== memories: %s" % str(a.memories.map(func(m): return "%s/%s" % [m.kind, m.stance])))
	print("  recall: ", _voice.recall(a, a.memories[0], rng))
	print("  recall: ", _voice.recall(a, a.memories[1], rng))
	print("  aside:  ", _voice.aside(b, b.memories[0], rng))
	print("  gossip: ", _voice.gossip(b, rng))
	print("  street: ", _voice.street_rep(a, rng))
	print("  opening line: ", a._opening_line())
	print("\n== choices now")
	for c in root.get_node("Interactions").choices_for(a, "civilian"):
		print("  - ", c.text)
	print("\n== memory verbs")
	for v in ["explain_yourself", "spread_the_word", "ask_reputation", "teach_moves"]:
		var ok: bool = root.get_node("Interactions").requirements_met(root.get_node("Interactions").verbs()[v], a if v != "teach_moves" else b)
		print("  %s available: %s" % [v, ok])
	print("  afterword: ", _voice.afterword(a, "give_credits", true, rng))
	print("  afterword: ", _voice.afterword(a, "threaten", false, rng))
	root.get_node("Interactions").resolve(a, "explain_yourself")
	# Every verb once (requirements ignored) so no outcome line or effect can crash at runtime.
	var inter = root.get_node("Interactions")
	root.get_node("Game").credits = 99999
	var texts: Array = []
	root.get_node("EventBus").dialogue_requested.connect(func(_s, t, _c, _cb): texts.append(t))
	var n := 0
	for id in inter.verbs():
		var who = npcs[n % npcs.size()]
		if is_instance_valid(who):
			inter.resolve(who, id)
		n += 1
	print("resolved %d verbs" % n)
	var re := RegEx.create_from_string("\\{[a-z_]+\\}|#[a-z_]+#")
	for t in texts:
		if re.search(str(t)):
			print("  UNFILLED: ", str(t).replace("\n", " | "))
	print("\nVOICE TEST DONE")
