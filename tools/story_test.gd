extends SceneTree
## Hand-written act bookends: for several very different lives, play every opening/closing and
## check the text is complete (no {tokens} left). Prints one full sample. Exit code = failures.
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
		{"class": "heir_halcyon", "age": "young", "motivation": "become_ceo", "background": "corp_lawyer"},
		{"class": "street_beggar", "age": "elder", "motivation": "find_sibling", "background": "street_medic"},
		{"class": "middle_manager", "age": "prime", "motivation": "revenge", "background": "ex_auditor"},
		{"class": "collateral", "age": "teen", "motivation": "escape_sprawl", "background": "clone_reject"},
	]
	var saga = root.get_node("Saga")
	var re := RegEx.create_from_string("\\{[a-z_]+\\}")
	for tags in lives:
		root.get_node("Game").new_game("Story Tester", tags, 7 + _fails)
		texts.clear()
		saga.play_bookend("open", "1")
		saga.axes["mercy"] = 3.0
		var guard := 0
		while saga.index < saga.beats.size() - 1 and guard < 20:
			saga._advance()
			guard += 1
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
				if str(t[0]).begins_with("ACT II"):
					print("\n--- sample: ", t[0], "\n", t[1], "\n---")
	print("STORY TEST DONE - %d failures" % _fails)
	quit(_fails)
	return false
