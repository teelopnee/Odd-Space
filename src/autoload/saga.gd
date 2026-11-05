extends Node
## "Saga" autoload - the procedural story director.
##
## At new game it rolls a story nobody else will get:
##   * an ANTAGONIST (Consortium exec: name, title, faction, scheme, look)
##   * an ALLY with a job, two personality traits and a verbal quirk
##   * a MACGUFFIN, a CLUE, a LIEUTENANT, and a PERSONAL thread from your
##     Motivation tag (lost sibling, debt collector, resistance, rival, deed broker)
##   * a TWIST from your Secret tag (alias, allergy, liar, sleeper, kleptomaniac)
##   * 7 beats across 3 acts, scattered over random planets of your galaxy
## Every planet also rolls 1-2 SIDE QUESTS (bounty / lost item / sabotage) with
## their own generated characters. Choices feed the Causality Graph and crew.
## Data: data/saga.json. Levels ask spawns_for(planet_id) what to place.

signal objective_changed

var seed_value := 0
var personas: Dictionary = {}   # id -> persona
var cast: Dictionary = {}       # role -> persona id
var world: Dictionary = {}      # macguffin, scheme, clue, twist, faction...
var beats: Array = []
var index := 0
var journal: Array = []
var side: Dictionary = {}       # planet_id -> Array of side quests
var ending := ""
var twist_choice := ""
var _rng := RandomNumberGenerator.new()
var _data: Dictionary = {}


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.action_recorded.connect(_on_action_recorded)


func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/saga.json"))
		_data = parsed if parsed is Dictionary else {}
	return _data


func reset() -> void:
	personas.clear()
	cast.clear()
	world.clear()
	beats.clear()
	side.clear()
	journal.clear()
	index = 0
	ending = ""
	twist_choice = ""


# --- Generation -----------------------------------------------------------------------------

func _pick(list: Array):
	return list[_rng.randi() % list.size()] if not list.is_empty() else null


## Roll a named character with personality and a look.
func make_persona(role: String, faction: String = "", planet_id: String = "", style: String = "civilian") -> Dictionary:
	var d := data()
	var n: Dictionary = d.get("names", {})
	var first: String = _pick(n.get("first", ["Juno"]))
	var last: String = _pick(n.get("last", ["Vance"]))
	var nick: String = _pick(n.get("nick", ["Static"]))
	var traits: Array = d.get("traits", ["blunt"]).duplicate()
	var t1: String = _pick(traits)
	traits.erase(t1)
	var p := {
		"id": "p%d_%d" % [personas.size(), _rng.randi() % 100000],
		"role": role,
		"first": first,
		"name": "%s '%s' %s" % [first, nick, last] if _rng.randf() < 0.55 else "%s %s" % [first, last],
		"job": _pick(d.get("jobs", ["drifter"])),
		"faction": faction,
		"traits": [t1, _pick(traits)],
		"quirk": _pick(d.get("quirks", ["sighs a lot"])),
		"planet": planet_id,
		"look": CharacterLook.random_look(_rng, style),
	}
	personas[p.id] = p
	return p


func generate(seed_in: int, start_planet_id: String = "") -> void:
	reset()
	seed_value = seed_in
	_rng.seed = seed_in * 7 + 13
	var d := data()
	var motivation: String = Game.tags.get("motivation", "burn_consortium")
	var secret: String = Game.tags.get("secret", "wanted_alias")
	var faction_by_motive := {"pay_debt": "halcyon", "get_famous": "lumen", "buy_a_planet": "oxy", "find_sibling": "gristle"}
	var faction: String = faction_by_motive.get(motivation, _pick(["paragon", "lumen", "halcyon", "oxy", "gristle"]))
	var mac: Dictionary = _pick(d.get("macguffins", [{"name": "the Thing", "desc": "a thing"}]))
	world = {
		"faction": faction,
		"faction_name": DataDB.faction_name(faction),
		"macguffin": mac.get("name", "the Thing"),
		"macguffin_desc": mac.get("desc", ""),
		"scheme": _pick(d.get("schemes", ["ruin everything"])),
		"clue": _pick(d.get("clues", ["a clue"])),
		"antagonist_title": _pick(d.get("antagonist_titles", ["VP"])),
	}
	# Planets for the beats: a shuffled tour of the galaxy.
	var ids: Array = []
	for p in Game.galaxy:
		ids.append(p.get("id", ""))
	for i in range(ids.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	if start_planet_id != "" and ids.has(start_planet_id):
		ids.erase(start_planet_id)
		ids.push_front(start_planet_id)
	var stops := []  # planet per beat index
	var plan := [0, 1, 2, 3, 3, 4, 5]
	for k in plan:
		stops.append(ids[k % maxi(1, ids.size())] if not ids.is_empty() else "")
	var ant := make_persona("antagonist", faction, stops[6], "corporate:" + faction)
	var ally := make_persona("ally", "", stops[0], "hero")
	var lieut := make_persona("lieutenant", faction, stops[3], "heavy:" + faction)
	var pdef: Dictionary = d.get("personal", {}).get(motivation, d.get("personal", {}).get("burn_consortium", {}))
	var personal := make_persona(str(pdef.get("role", "contact")), "", stops[2], "hero")
	cast = {"antagonist": ant.id, "ally": ally.id, "lieutenant": lieut.id, "personal": personal.id}
	world["twist"] = str(d.get("twists", {}).get(secret, "{ally} was never who they said."))
	world["personal_intro"] = str(pdef.get("intro", "{personal} is waiting on {planet}."))
	world["personal_met"] = str(pdef.get("met", "{personal} nods."))
	world["personal_label"] = str(pdef.get("label", "an old friend"))
	var templates: Array = d.get("beats", [])
	for i in templates.size():
		var b: Dictionary = templates[i].duplicate(true)
		b["planet"] = stops[mini(i, stops.size() - 1)]
		b["status"] = "locked"
		beats.append(b)
	index = 0
	if not beats.is_empty():
		beats[0].status = "active"
		_log(beats[0].title, fill(beats[0].intro, beats[0]))


func persona_by_role(role: String) -> Dictionary:
	return personas.get(cast.get(role, ""), {})


## Fill {tokens} in story text.
func fill(text: String, beat: Dictionary = {}) -> String:
	var vars := {
		"player": Game.player_name,
		"ally": persona_by_role("ally").get("name", "?"),
		"ally_job": persona_by_role("ally").get("job", "?"),
		"antagonist": persona_by_role("antagonist").get("name", "?"),
		"lieutenant": persona_by_role("lieutenant").get("name", "?"),
		"personal": persona_by_role("personal").get("name", "?"),
		"faction": world.get("faction_name", "?"),
	}
	for k in world:
		vars[k] = str(world[k])
	var planet_id: String = beat.get("planet", "")
	vars["planet"] = Game.planet_by_id(planet_id).get("name", "the station") if planet_id != "" else "?"
	if index + 1 < beats.size():
		vars["next_planet"] = Game.planet_by_id(beats[index + 1].get("planet", "")).get("name", "?")
	# Two passes so tokens inside world texts (twist, personal intro) resolve too.
	return text.format(vars).format(vars)


# --- Queries ---------------------------------------------------------------------------------

func current() -> Dictionary:
	return beats[index] if index < beats.size() else {}


func is_complete() -> bool:
	return index >= beats.size()


func objective_planet() -> String:
	return current().get("planet", "")


func objective_text() -> String:
	if is_complete():
		return "THE END - the Sprawl is yours to wander" if ending != "" else ""
	var b := current()
	var pname: String = Game.planet_by_id(b.get("planet", "")).get("name", "?")
	var here: bool = Game.location_id == b.get("planet", "")
	var what := ""
	match b.get("type", ""):
		"talk":
			what = "Find %s" % personas.get(cast.get(b.get("who", ""), ""), {}).get("name", "your contact")
		"retrieve":
			what = "Recover %s" % world.get(b.get("item", ""), b.get("item", "it"))
		"defeat":
			what = "Take down %s" % personas.get(cast.get(b.get("who", ""), ""), {}).get("name", "the target")
	return "ACT %d - %s: %s%s" % [int(b.get("act", 1)), b.get("title", ""), what, "" if here else "  (travel to %s)" % pname]


func side_quests_at(planet_id: String) -> Array:
	return side.get(planet_id, [])


# --- Spawning ------------------------------------------------------------------------------------

## What a planet level should place for the story and its side quests.
func spawns_for(planet_id: String) -> Array:
	var out := []
	var b := current()
	if not b.is_empty() and b.get("planet", "") == planet_id:
		match b.get("type", ""):
			"talk":
				out.append({"kind": "persona", "persona_id": cast.get(b.get("who", ""), ""), "quest": "main"})
			"retrieve":
				out.append({"kind": "quest_item", "tag": b.id, "label": world.get(b.get("item", ""), "the item")})
				out.append({"kind": "guards", "count": 3, "faction": world.get("faction", "")})
			"defeat":
				var p: Dictionary = personas.get(cast.get(b.get("who", ""), ""), {})
				var boss: bool = b.get("who", "") == "antagonist"
				out.append({"kind": "elite", "tag": b.id, "persona_id": p.get("id", ""), "boss": boss,
					"enemy_type": "debt_brute" if boss or world.get("faction", "") == "halcyon" else "paragon_officer"})
				out.append({"kind": "guards", "count": 4 if boss else 2, "faction": world.get("faction", "")})
	if not side.has(planet_id):
		_generate_side(planet_id)
	for q in side.get(planet_id, []):
		if q.status == "done":
			continue
		out.append({"kind": "persona", "persona_id": q.giver, "quest": "side", "qid": q.id})
		if q.status == "active" and not q.get("ready", false):
			match q.type:
				"bounty":
					out.append({"kind": "elite", "tag": q.id, "persona_id": q.target, "boss": false, "enemy_type": q.get("enemy_type", "pirate")})
				"fetch":
					out.append({"kind": "quest_item", "tag": q.id, "label": q.item})
	return out


func _generate_side(planet_id: String) -> void:
	var planet := Game.planet_by_id(planet_id)
	if planet.is_empty():
		return
	var d: Dictionary = data().get("side", {})
	var list := []
	var count := 1 + (_rng.randi() % 2)
	var controller: String = planet.get("controller", "")
	for i in count:
		var kind: String = _pick(["bounty", "fetch", "sabotage"])
		var giver := make_persona("giver", controller, planet_id, "civilian")
		var q := {"id": "q%d_%s" % [i, planet_id], "type": kind, "giver": giver.id, "status": "offered",
			"planet": planet_id, "reward": 40 + _rng.randi() % 90, "progress": 0}
		match kind:
			"bounty":
				var tgt := make_persona("target", controller, planet_id, "punk")
				q["target"] = tgt.id
				q["enemy_type"] = "pirate" if controller == "" else _pick(["pirate", "debt_brute"])
				q["title"] = str(d.get("bounty", {}).get("title", "Bounty")).format({"target": tgt.name})
			"fetch":
				q["item"] = _pick(data().get("side_items", ["a keepsake"]))
				q["title"] = str(d.get("fetch", {}).get("title", "Lost item")).format({"item": q.item})
			"sabotage":
				q["count"] = 2 + _rng.randi() % 2
				q["title"] = str(d.get("sabotage", {}).get("title", "Sabotage"))
		list.append(q)
	side[planet_id] = list


# --- Runtime hooks -----------------------------------------------------------------------------

func persona_greeting(p: Dictionary) -> String:
	var tr_a: String = p.get("traits", ["calm"])[0]
	return "[i](%s, %s - %s, %s)[/i]" % [p.get("name", "?"), p.get("job", "?"), tr_a, p.get("quirk", "")]


## Talking to a story/side character (called by NPC).
func on_persona_talk(persona_id: String) -> void:
	var p: Dictionary = personas.get(persona_id, {})
	# Side quest giver?
	for planet_id in side:
		for q in side[planet_id]:
			if q.giver == persona_id and q.status != "done":
				_talk_side(q, p)
				return
	var b := current()
	if b.is_empty() or b.get("type", "") != "talk" or cast.get(b.get("who", ""), "") != persona_id:
		EventBus.dialogue_requested.emit(p.get("name", "?"), "%s\n\n\"Not now. They're watching. They're always watching.\"" % persona_greeting(p), [], Callable())
		return
	var text := persona_greeting(p) + "\n\n" + fill(b.get("talk", "..."), b)
	if b.id == "twist":
		var choices := []
		for c in data().get("twist_choices", []):
			choices.append({"id": c.id, "text": fill(c.text, b)})
		EventBus.dialogue_requested.emit(p.get("name", "?"), "[color=#ff3ec8][b]TWIST[/b][/color]\n" + text, choices, _on_twist_choice)
		return
	EventBus.dialogue_requested.emit(p.get("name", "?"), text, [], func(_c): _advance())


func _on_twist_choice(choice: String) -> void:
	twist_choice = choice
	for c in data().get("twist_choices", []):
		if c.id == choice:
			Causality.record("comply" if choice == "forgive" else "desert", {"target": persona_by_role("ally").get("name", ""), "moral": c.get("moral", {}), "note": "twist:" + choice})
	if choice == "sell_out":
		Factions.change_rep(world.get("faction", "paragon"), 15, "sold out an ally")
		Game.add_credits(150)
	_advance()


func _talk_side(q: Dictionary, p: Dictionary) -> void:
	var d: Dictionary = data().get("side", {}).get(q.type, {})
	var vars := {"target": personas.get(q.get("target", ""), {}).get("name", "them"), "item": q.get("item", "it"), "count": q.get("count", 2)}
	match q.status:
		"offered":
			EventBus.dialogue_requested.emit(p.get("name", "?"), persona_greeting(p) + "\n\n" + str(d.get("offer", "")).format(vars) + "\n\n[color=#ffd23e]Reward: %d cr[/color]" % q.reward,
				[{"id": "accept", "text": "I'll do it."}, {"id": "no", "text": "Not now."}], func(c: String): _accept_side(q, c))
		"active":
			if q.get("ready", false):
				_complete_side(q, p, str(d.get("done", "Thanks.")).format(vars))
			else:
				EventBus.dialogue_requested.emit(p.get("name", "?"), "\"Still waiting on that job. %s\"" % q.title, [], Callable())


func _accept_side(q: Dictionary, choice: String) -> void:
	if choice != "accept":
		return
	q.status = "active"
	_log("SIDE: " + str(q.title), "Accepted on %s." % Game.location_name)
	EventBus.toast.emit("SIDE QUEST: %s" % q.title, Color(1.0, 0.82, 0.24))
	objective_changed.emit()
	get_tree().call_group("level", "refresh_quests")


func _complete_side(q: Dictionary, p: Dictionary, text: String) -> void:
	q.status = "done"
	Game.add_credits(int(q.reward))
	if p.get("faction", "") != "":
		Factions.change_rep(p.faction, 5, "helped a local")
	Causality.record("mercy", {"target": p.get("name", ""), "note": "side quest"})
	EventBus.dialogue_requested.emit(p.get("name", "?"), text + "\n\n[color=#ffd23e]+%d cr[/color]" % q.reward, [], Callable())
	_log("SIDE DONE: " + str(q.title), "Paid %d cr." % q.reward)
	objective_changed.emit()


func on_item_taken(tag: String) -> void:
	var b := current()
	if not b.is_empty() and b.id == tag:
		EventBus.dialogue_requested.emit("FOUND", fill(b.get("done", "Got it."), b), [], func(_c): _advance())
		return
	_mark_side_ready(tag)


func _on_enemy_killed(enemy: Node, _info: Dictionary) -> void:
	var tag: String = enemy.get_meta("saga_tag", "") if enemy else ""
	if tag == "":
		return
	var b := current()
	if not b.is_empty() and b.id == tag:
		if b.id == "finale":
			_finale(b)
		else:
			EventBus.dialogue_requested.emit("Q.U.A.C.K.", fill(b.get("done", "Done."), b), [], func(_c): _advance())
		return
	_mark_side_ready(tag)


func _on_action_recorded(node: Dictionary) -> void:
	if node.get("verb", "") != "vandalism":
		return
	for q in side.get(Game.location_id, []):
		if q.type == "sabotage" and q.status == "active" and not q.get("ready", false):
			q.progress = int(q.progress) + 1
			EventBus.toast.emit("%s: %d/%d" % [q.title, q.progress, q.count], Color(1.0, 0.82, 0.24))
			if q.progress >= int(q.count):
				_mark_side_ready(q.id)


func _mark_side_ready(qid: String) -> void:
	for planet_id in side:
		for q in side[planet_id]:
			if q.id == qid and q.status == "active":
				q["ready"] = true
				EventBus.toast.emit("Return to %s for your reward" % personas.get(q.giver, {}).get("name", "the client"), Color(1.0, 0.82, 0.24))
				objective_changed.emit()
				get_tree().call_group("level", "refresh_quests")


func _finale(b: Dictionary) -> void:
	var choices := []
	for e in data().get("endings", []):
		choices.append({"id": e.id, "text": fill(e.text, b)})
	EventBus.dialogue_requested.emit("THE END?", fill(b.get("done", ""), b), choices, _on_ending)


func _on_ending(choice: String) -> void:
	ending = choice
	var epi := ""
	for e in data().get("endings", []):
		if e.id == choice:
			epi = fill(e.epilogue, current())
	var stats := "\n\n[color=#3ee6ff]Your story:[/color] %d events remembered, %d crimes reported, %d covered up, %d crew aboard. Twist choice: %s." % [
		Causality.nodes.size(), Causality.reported_count(), Causality.query("", Causality.STATUS_SUPPRESSED).size(), Crew.size(), twist_choice if twist_choice != "" else "none"]
	_log("EPILOGUE", epi)
	Game.flags["saga_complete"] = true
	EventBus.dialogue_requested.emit("EPILOGUE", epi + stats, [], func(_c): _advance())


func _advance() -> void:
	if index < beats.size():
		beats[index].status = "done"
		_log("DONE: " + str(beats[index].title), "")
	index += 1
	if index < beats.size():
		var b: Dictionary = beats[index]
		b.status = "active"
		var intro := fill(b.get("intro", ""), b)
		_log(b.title, intro)
		EventBus.toast.emit("NEW OBJECTIVE: %s" % b.title, Color(1.0, 0.82, 0.24))
		EventBus.ai_say.emit(intro, "saga")
	else:
		get_tree().call_group("hud", "title_card", "THE END", "...of this story. The Sprawl keeps going.", 3.5)
	objective_changed.emit()
	get_tree().call_group("level", "refresh_quests")


func _log(title: String, text: String) -> void:
	journal.append({"title": title, "text": text, "where": Game.location_name, "time": snappedf(Game.play_time, 1.0)})


# --- Save ------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"seed": seed_value, "personas": personas, "cast": cast, "world": world, "beats": beats, "index": index,
		"journal": journal, "side": side, "ending": ending, "twist_choice": twist_choice}


func from_save(d: Dictionary) -> void:
	reset()
	seed_value = int(d.get("seed", 0))
	_rng.seed = seed_value * 7 + 13 + int(d.get("index", 0)) * 101
	personas = d.get("personas", {})
	cast = d.get("cast", {})
	world = d.get("world", {})
	beats = d.get("beats", [])
	index = int(d.get("index", 0))
	journal = d.get("journal", [])
	side = d.get("side", {})
	ending = d.get("ending", "")
	twist_choice = d.get("twist_choice", "")
	for pid in side:
		for q in side[pid]:
			q["progress"] = int(q.get("progress", 0))
			q["reward"] = int(q.get("reward", 50))
