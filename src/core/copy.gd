class_name Copy
extends RefCounted
## Procedural copywriter: expands the grammar in data/copy.json into ads, slogans,
## shop and street names, news, flyers, graffiti, menus, PA announcements and NPC
## small talk - so the Sprawl never says the same thing twice.
##   Copy.make("slogan")                       -> "TRUST THE PASTE"
##   Copy.make("news", rng, {"planet": "Toraka"})
## Grammar: "#sym#" picks a random alternative (recursively), "#sym.cap#", "#sym.upper#",
## "#sym.lower#", "#sym.a#" (a/an); "{planet}" "{player}" "{faction}" are filled from vars / the game.

static var _rules: Dictionary = {}
static var _re: RegEx
static var _tidy_re: RegEx
static var _rng := RandomNumberGenerator.new()


## Grammar files, merged in order (later files may extend a symbol: alternatives are appended).
const FILES := ["res://data/copy.json", "res://data/copy_people.json", "res://data/copy_reactions.json"]


static func rules() -> Dictionary:
	if _rules.is_empty():
		for path in FILES:
			if not FileAccess.file_exists(path):
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not parsed is Dictionary:
				push_error("Copy: bad JSON in %s" % path)
				continue
			var more: Dictionary = parsed.get("rules", {})
			for k in more:
				if _rules.has(k):
					(_rules[k] as Array).append_array(more[k])
				else:
					_rules[k] = (more[k] as Array).duplicate()
		_rng.randomize()
	return _rules


static func has(symbol: String) -> bool:
	return rules().has(symbol)


static func make(symbol: String, rng: RandomNumberGenerator = null, vars: Dictionary = {}) -> String:
	return expand("#%s#" % symbol, rng, vars)


static func expand(text: String, rng: RandomNumberGenerator = null, vars: Dictionary = {}) -> String:
	return _tidy(_expand(text, rng, vars))


static func _expand(text: String, rng: RandomNumberGenerator, vars: Dictionary) -> String:
	var r := rules()
	if rng == null:
		rng = _rng
	if _re == null:
		_re = RegEx.new()
		_re.compile("#([a-z_]+)(?:\\.([a-z]+))?#")
	var out := text
	var guard := 0
	while guard < 60:
		guard += 1
		var m := _re.search(out)
		if m == null:
			break
		var alts: Array = r.get(m.get_string(1), [])
		var pick: String = str(alts[rng.randi() % alts.size()]) if not alts.is_empty() else m.get_string(1)
		pick = _expand(pick, rng, vars) if pick.contains("#") else pick
		match m.get_string(2):
			"cap":
				pick = pick.substr(0, 1).to_upper() + pick.substr(1)
			"upper":
				pick = pick.to_upper()
			"lower":
				pick = pick.to_lower()
			"a":
				pick = ("an " if pick.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + pick
		out = out.substr(0, m.get_start()) + pick + out.substr(m.get_end())
	return _fill(out, vars)


## Typography after expansion: "..", "!." and "?." collapse (an ellipsis survives), and each
## line starts with a capital even when it opens on "the Forever Loan".
static func _tidy(text: String) -> String:
	if _tidy_re == null:
		_tidy_re = RegEx.new()
		_tidy_re.compile("(?<!\\.)\\.\\.(?!\\.)")
	var out := _tidy_re.sub(text, ".", true).replace("!.", "!").replace("?.", "?")
	var lines := out.split("\n")
	for i in lines.size():
		var l: String = lines[i]
		var j := 0
		while j < l.length() and l[j] in ["\"", "'", " ", "("]:
			j += 1
		if j < l.length() and l[j] != l[j].to_upper():
			lines[i] = l.substr(0, j) + l[j].to_upper() + l.substr(j + 1)
	return "\n".join(lines)


static func _fill(text: String, vars: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var v := vars.duplicate()
	var game: Node = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node("Game"):
		game = tree.root.get_node("Game")
	if not v.has("planet"):
		var loc := str(game.location_name) if game else ""
		v["planet"] = loc if loc != "" else "the Sprawl"
	if not v.has("player"):
		var pn := str(game.player_name) if game else ""
		v["player"] = pn if pn != "" else "you"
	if not v.has("name"):
		v["name"] = v["player"]
	for k in v:
		text = text.replace("{%s}" % k, str(v[k])).replace("{%s}" % str(k).to_upper(), str(v[k]).to_upper())
	return text
