extends SceneTree
## Hand-written act bookends: for several very different lives, play every opening/closing and
## check the text is complete (no {tokens} left), then the authored meetings (ally, lieutenant, the
## antagonist's call, the face-off): complete and different for different lives. Exit code = failures.
##   godot --headless --path . --script res://tools/story_test.gd

var _f := 0
var _fails := 0


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var texts: Array = []
	root.get_node("EventBus").dialogue_requested.connect(func(s, t, _c, _cb): texts.append([s, t]))
	var lives := [
		{"class": "heir_halcyon", "age": "young", "motivation": "become_ceo", "background": "corp_lawyer", "personality": "charming"},
		{"class": "street_beggar", "age": "elder", "motivation": "find_sibling", "background": "street_medic", "personality": "honest"},
		{"class": "middle_manager", "age": "prime", "motivation": "revenge", "background": "ex_auditor", "personality": "hothead"},
		{"class": "collateral", "age": "teen", "motivation": "escape_sprawl", "background": "clone_reject", "personality": "joker"},
	]
	var saga = root.get_node("Saga")
	var meetings: Array = []
	var re := RegEx.create_from_string("\\{[a-z_]+\\}")
	for tags in lives:
		root.get_node("Game").new_game("Story Tester", tags, 7 + _fails)
		texts.clear()
		saga.play_bookend("open", "1")
		saga.axes["mercy"] = 3.0
		saga.play_meet("ally")
		saga.play_meet("lieutenant")
		saga.state["lieutenant_fate"] = ["killed", "spared", "recruited", "exposed"][lives.find(tags)]
		var guard := 0
		while saga.index < saga.beats.size() - 1 and guard < 20:
			saga._advance()
			guard += 1
		saga.state["ally_fate"] = ["loyal", "betrayed", "partner", "dead"][lives.find(tags)]
		saga.play_meet("faceoff")
		var titles_j: Array = saga.journal.map(func(j): return str(j.title))
		var met: bool = titles_j.has("FIRST CONTACT") and titles_j.has("THE FIXER") and titles_j.has("INCOMING CALL") and titles_j.has("FACE TO FACE")
		print(("  PASS  " if met else "  FAIL  ") + "meetings played: ally, lieutenant, call (auto on the MacGuffin beat), face-off")
		if not met:
			_fails += 1
		meetings.append(saga.meet_text("ally") + saga.meet_text("call") + saga.meet_text("faceoff"))
		var again: bool = saga.play_meet("ally")
		_check_t(not again, "a meeting plays once per life")
		_check_t(not saga.idle_line("ally").contains("{"), "idle line filled: " + saga.idle_line("ally"))
		for t in texts:
			if re.search(str(t[1])):
				print("  FAIL unfilled token in ", t[0], ": ", re.search(str(t[1])).get_string())
				_fails += 1
		var titles := texts.map(func(t): return str(t[0]))
		var ok: bool = titles.has("ACT I - THE STATIC") and titles.has("END OF ACT I") and titles.has("ACT II - THE LEDGER") \
			and titles.has("ACT III - THE FINE PRINT")
		print(("  PASS  " if ok else "  FAIL  ") + "%s / %s: %s" % [tags.class, tags.motivation, ", ".join(titles.filter(func(x): return x.begins_with("ACT") or x.begins_with("END")))])
		if not ok:
			_fails += 1
		if tags.class == "street_beggar":
			for t in texts:
				if str(t[0]).begins_with("ACT II") or str(t[0]).ends_with("INCOMING CALL"):
					print("\n--- sample: ", t[0], "\n", t[1], "\n---")
	var distinct := {}
	for m in meetings:
		distinct[m] = true
	_check_t(distinct.size() == meetings.size(), "%d lives -> %d different meeting texts" % [meetings.size(), distinct.size()])
	# First day checklist: four steps, rewards, done.
	var g = root.get_node("Game")
	g.new_game("First Day", {"class": "gig_worker"}, 3)
	var fd = load("res://src/core/first_day.gd")
	var cr: int = g.credits
	var shown: String = fd.next_text()
	for id in ["talk", "shop", "fight", "change"]:
		fd.done(id)
	var ok2: bool = shown.begins_with("FIRST DAY 1/4") and not fd.active() and g.credits - cr == 70 and g.item_count("medkit") >= 1
	print(("  PASS  " if ok2 else "  FAIL  ") + "first day checklist: '%s' -> done, +%d CR" % [shown, g.credits - cr])
	if not ok2:
		_fails += 1
	print("STORY TEST DONE - %d failures" % _fails)
	quit(_fails)
	return false


func _check_t(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1
