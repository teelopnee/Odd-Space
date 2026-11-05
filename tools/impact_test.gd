extends SceneTree
## Headless check that interactions have real, lasting consequences:
##   godot --headless --path . --script res://tools/impact_test.gd
## 1. a crime -> witness calls -> talking + bribing / threatening / charming CUTS the call and the
##    witness goes back to normal life (used to stay "reporting" forever);
## 2. give credits / call the lawyer / repossess / pull rank change labels, behaviour and the street.

var _step := 0
var _wait := 0
var _fails := 0


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			var tags := {"class": "heir_halcyon", "age": "prime", "background": "repo_agent", "personality": "ruthless",
				"motivation": "become_ceo", "secret": "secret_heir"}
			root.get_node("Game").new_game("Impact Tester", tags, 4242)
			var g = root.get_node("Game")
			root.get_node("Router").params = {"planet_id": g.galaxy[0].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_step = 1
			_wait = 200
		1:
			_close_dialogue()
			_witness_test()
			_step = 2
			_wait = 30
		2:
			_close_dialogue()
			_verb_test()
			_step = 3
			_wait = 120
		3:
			_close_dialogue()
			_followup_test()
			print("\nIMPACT TEST DONE - %d failures" % _fails)
			quit(_fails)
	return false


func _close_dialogue() -> void:
	var hud = get_first_node_in_group("hud")
	for i in 12:
		if hud and hud._dialogue_open:
			hud._on_choice("")
	paused = false


func _check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1


func _civilians() -> Array:
	return get_nodes_in_group("npc").filter(func(n): return n.role == "civilian" and n.state != "dead" and n.story_id == "" and n.persona_id == "")


func _witness_test() -> void:
	print("\n== witness: stop the call")
	var player = get_first_node_in_group("player")
	var npcs := _civilians()
	var w = npcs[0]
	player.global_position = w.global_position + Vector3(2.0, 0, 0)
	var causality = root.get_node("Causality")
	var game = root.get_node("Game")
	game.credits = 5000
	for method in ["bribe", "threaten", "act"]:
		w.loyal = false
		w.witness.active = true
		w.attitude = 0
		var id: int = causality.record("theft", {"target": "a parked hover-car", "position": player.global_position})
		if not w.witness.is_reporting():
			w.witness.begin_report(id)
		_check(w.state == "reporting", "%s: witness is on the phone" % method)
		if method == "act":
			# A social verb mid-call: charm (forced success via high attitude-independent verb: write a cheque)
			var inter = root.get_node("Interactions")
			inter.resolve(w, "write_cheque")
		else:
			for tries in 14:
				if w.state != "reporting":
					break
				w._on_witness_choice(method)
				_close_dialogue()
				if method == "threaten" and w.state == "reporting":
					w.witness.progress = 0.0
		_check(not w.witness.is_reporting(), "%s: call cut" % method)
		_check(w.state != "reporting", "%s: witness back to normal life (state=%s)" % [method, w.state])
		_close_dialogue()
		w.state = "idle"


func _verb_test() -> void:
	print("\n== verbs with consequences")
	var inter = root.get_node("Interactions")
	var player = get_first_node_in_group("player")
	var npcs := _civilians()
	var game = root.get_node("Game")
	game.credits = 5000
	var cases := [["give_credits", "OWES YOU ONE"], ["repo_their_stuff", "REPOSSESSED"], ["pull_rank", ""], ["call_lawyer", ""]]
	var i := 1
	for c in cases:
		var n = npcs[i % npcs.size()]
		i += 1
		player.global_position = n.global_position + Vector3(1.5, 0, 0)
		n.attitude = 0
		var before: String = n.relation_label()
		var cr: int = game.credits
		var texts: Array = []
		var cb := func(_s, t, _c, _cb): texts.append(t)
		root.get_node("EventBus").dialogue_requested.connect(cb)
		var ok: bool = inter.resolve(n, c[0])
		root.get_node("EventBus").dialogue_requested.disconnect(cb)
		var after: String = n.relation_label() if is_instance_valid(n) else "(gone)"
		print("  %s ok=%s  label: '%s' -> '%s'  credits %+d" % [c[0], ok, before, after, game.credits - cr])
		if not texts.is_empty():
			print("    | " + str(texts[-1]).replace("\n", "\n    | "))
		if ok and c[1] != "":
			_check(after == c[1], "%s sets <%s>" % [c[0], c[1]])
		if ok:
			_check(before != after or c[0] == "pull_rank", "%s changes how they relate to you" % c[0])
		n.set_meta("case", c[0])
		if c[0] == "give_credits":
			_check(n.state != "reporting", "nobody phones Paragon about a gift")
	_close_dialogue()
	# Fast-forward the consequences: favours come due, grudges become complaints.
	for n in npcs:
		if is_instance_valid(n) and n.owes_favour:
			n.end_activity()  # don't let them wander off to the food stall mid-test
			n.witness.silence("test")  # nor be busy phoning in a later test crime
			n.state = "idle"  # nor still running from the test's other scuffles
			n.scared_until = 0.0
			n.spooked_until = 0.0
			n._favour_wait = 0.05
			player.global_position = n.global_position + Vector3(1.5, 0, 0)
			_favour_npc = n
		if is_instance_valid(n) and n.grudge:
			n.witness.silence("test")  # finish any earlier call so the grudge can act
			n.state = "idle"
			n.attitude = mini(n.attitude, -30)
			n._grudge_wait = 0.05
	_credits_before = game.credits
	_items_before = game.inventory.duplicate()
	_fame_before = int(game.flags.get("fame", 0))


var _favour_npc: Node = null
var _credits_before := 0
var _items_before := {}
var _fame_before := 0


func _followup_test() -> void:
	print("\n== what happens next")
	var game = root.get_node("Game")
	for n in _civilians():
		var c := str(n.get_meta("case", ""))
		if c == "":
			continue
		print("  %s: state=%s activity=%s owes=%s grudge=%s scared=%s leaving=%s label=%s" % [c, n.state, n.activity, n.owes_favour,
			n.grudge, n.is_scared(), n._leaving, n.relation_label()])
	if _favour_npc and is_instance_valid(_favour_npc):
		var gained: bool = game.credits != _credits_before or game.inventory != _items_before or int(game.flags.get("fame", 0)) != _fame_before \
			or int(game.flags.get("followers", 0)) > 0
		_check(not _favour_npc.owes_favour and gained, "a grateful NPC came back with a gift (owes=%s state=%s act=%s d=%.1f appr=%s)" % [
			_favour_npc.owes_favour, _favour_npc.state, _favour_npc.activity,
			_favour_npc.global_position.distance_to(get_first_node_in_group("player").global_position), _favour_npc._approach_kind])
	var complaints: Array = root.get_node("Causality").query("complaint")
	_check(not complaints.is_empty(), "a wronged NPC files a complaint with Paragon (%d, status %s)" % [complaints.size(),
		complaints[0].status if not complaints.is_empty() else "-"])
	var street: Dictionary = game.flags.get("street_" + game.location_id, {})
	print("  street memory: ", street)
	_check(not street.is_empty(), "the street remembers what you did")
