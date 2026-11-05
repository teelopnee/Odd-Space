extends Node
## "Saga" autoload - the procedural story director (v2: branching).
##
## At new game it rolls a story nobody else will get:
##   * an ANTAGONIST (Consortium exec: name, title, faction, scheme, look) - for
##     Consortium heirs it is often someone from your own family's company
##   * an ALLY with a job, two personality traits and a verbal quirk
##   * a MACGUFFIN, a CLUE, a LIEUTENANT, and a PERSONAL thread from your
##     Motivation tag (12 kinds), a TWIST from your Secret tag (12 kinds)
##   * 7 beats across 3 acts, scattered over random planets of your galaxy
## Every beat branches: approaches (gated by who you are), surrenders (kill /
## spare / arrest / recruit / expose...), twist choices, a MacGuffin finale with
## up to 18 fates, and early endings when your Motivation is fulfilled sooner.
## The ending is COMPOSED from slides (resolution x antagonist x lieutenant x
## ally x personal outcome x legacy x class/age codas x planet stories) - see
## tools/count_endings.gd for the number of distinct endings.
## Every planet also rolls 1-2 SIDE QUESTS (bounty / lost item / sabotage).
## Data: data/saga.json. Levels ask spawns_for(planet_id) what to place.

signal objective_changed

const AXES := ["mercy", "order", "greed", "truth"]

var seed_value := 0
var personas: Dictionary = {}   # id -> persona
var cast: Dictionary = {}       # role -> persona id
var world: Dictionary = {}      # macguffin, scheme, clue, twist, faction...
var beats: Array = []
var index := 0
var journal: Array = []
var side: Dictionary = {}       # planet_id -> Array of side quests
var ending := ""                # composed ending id
var ending_title := ""
var twist_choice := ""
var state: Dictionary = {}      # ally_trust, intel, personal, fates, flags set by choices
var axes: Dictionary = {}       # mercy / order / greed / truth
var start_wealth := 0
var _rng := RandomNumberGenerator.new()
var _data: Dictionary = {}
var _pending_enemy: Node = null
var _slides: Array = []


func _ready() -> void:
	reset()
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
	ending_title = ""
	twist_choice = ""
	state = {"ally_trust": 0, "intel": 0, "personal": 0, "evidence": 0,
		"ally_fate": "unknown", "lieutenant_fate": "unknown", "antagonist_fate": "untouched", "finale": ""}
	axes = {"mercy": 0.0, "order": 0.0, "greed": 0.0, "truth": 0.0}
	start_wealth = 0
	_pending_enemy = null


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
	start_wealth = Origin.wealth()
	var d := data()
	var motivation: String = Game.tags.get("motivation", "burn_consortium")
	var secret: String = Game.tags.get("secret", "wanted_alias")
	var faction_by_motive := {"pay_debt": "halcyon", "get_famous": "lumen", "buy_a_planet": "oxy", "find_sibling": "gristle",
		"find_cure": "halcyon", "protect_family": "halcyon", "escape_sprawl": "paragon", "find_love": "lumen"}
	var faction: String = faction_by_motive.get(motivation, _pick(["paragon", "lumen", "halcyon", "oxy", "gristle"]))
	# Heirs: more often than not, the villain is family business.
	var heir := Origin.heir_of()
	if heir != "" and _rng.randf() < 0.6:
		faction = heir
		world["family_feud"] = true
	var mac: Dictionary = _pick(d.get("macguffins", [{"name": "the Thing", "desc": "a thing"}]))
	world.merge({
		"faction": faction,
		"faction_name": DataDB.faction_name(faction),
		"macguffin": mac.get("name", "the Thing"),
		"macguffin_desc": mac.get("desc", ""),
		"scheme": _pick(d.get("schemes", ["ruin everything"])),
		"clue": _pick(d.get("clues", ["a clue"])),
		"antagonist_title": _pick(d.get("antagonist_titles", ["VP"])),
	}, true)
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
	var stops := []
	for k in [0, 1, 2, 3, 3, 4, 5]:
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
	var pf: Dictionary = d.get("personal_finale", {}).get(motivation, {})
	world["personal_finale_text"] = str(pf.get("text", "Use it for yourself"))
	world["personal_finale_slide"] = str(pf.get("slide", "You use it. It works. Mostly."))
	if world.get("family_feud", false):
		world["scheme"] = str(world["scheme"]) + " - with your family's name on the paperwork"
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
		"age": Game.age,
		"heir": DataDB.faction_name(Origin.heir_of()),
	}
	for k in world:
		vars[k] = str(world[k])
	var planet_id: String = beat.get("planet", "")
	vars["planet"] = Game.planet_by_id(planet_id).get("name", "the station") if planet_id != "" else "?"
	if index + 1 < beats.size():
		vars["next_planet"] = Game.planet_by_id(beats[index + 1].get("planet", "")).get("name", "?")
	# Two passes so tokens inside world texts (twist, personal intro) resolve too.
	return text.format(vars).format(vars)


# --- Conditions -------------------------------------------------------------------------------

func fame() -> int:
	return int(Game.flags.get("fame", 0))


func followers() -> int:
	return int(Game.flags.get("followers", 0))


## Player requirements (same keys as data/interactions.json) plus story keys.
func cond_ok(c: Dictionary) -> bool:
	if c.is_empty():
		return true
	if not Interactions.requirements_met({"requires": c}, null):
		return false
	if c.has("min_fame") and fame() < int(c["min_fame"]):
		return false
	if c.has("min_followers") and followers() < int(c["min_followers"]):
		return false
	if c.has("min_intel") and int(state.get("intel", 0)) < int(c["min_intel"]):
		return false
	if c.has("min_ally_trust") and int(state.get("ally_trust", 0)) < int(c["min_ally_trust"]):
		return false
	if c.has("state"):
		for k in c["state"]:
			if state.get(k) != c["state"][k]:
				return false
	if c.has("min_axis"):
		for k in c["min_axis"]:
			if float(axes.get(k, 0.0)) < float(c["min_axis"][k]):
				return false
	if c.has("max_axis"):
		for k in c["max_axis"]:
			if float(axes.get(k, 0.0)) > float(c["max_axis"][k]):
				return false
	if c.has("finale_in") and not (c["finale_in"] as Array).has(state.get("finale", "")):
		return false
	if c.has("max_air_debt") and Game.air_debt > int(c["max_air_debt"]):
		return false
	if c.has("min_bounty") and Factions.total_bounty() < int(c["min_bounty"]):
		return false
	if c.has("max_reported") and Causality.reported_count() > int(c["max_reported"]):
		return false
	if c.has("min_visited"):
		var visited := Game.galaxy.filter(func(p): return p.get("visited", false)).size()
		if visited < int(c["min_visited"]):
			return false
	if c.has("min_max_rep"):
		var best := -100
		for fid in Factions.ids():
			best = maxi(best, Factions.get_rep(fid))
		if best < int(c["min_max_rep"]):
			return false
	return true


func choice_ok(ch: Dictionary) -> bool:
	if not cond_ok(ch.get("requires", {})):
		return false
	if ch.has("requires_any"):
		var any := false
		for alt in ch["requires_any"]:
			if cond_ok(alt):
				any = true
				break
		if not any:
			return false
	if ch.has("requires_state"):
		for k in ch["requires_state"]:
			if state.get(k) != ch["requires_state"][k]:
				return false
	if ch.has("requires_state_any"):
		for k in ch["requires_state_any"]:
			if not (ch["requires_state_any"][k] as Array).has(state.get(k)):
				return false
	return true


func _choices_from(list: Array, beat: Dictionary = {}) -> Array:
	var out := []
	for ch in list:
		if choice_ok(ch):
			out.append({"id": ch.id, "text": fill(str(ch.get("text", ch.id)), beat)})
	return out


func _find(list: Array, id: String) -> Dictionary:
	for ch in list:
		if ch.get("id", "") == id:
			return ch
	return {}


## Apply a story choice: effects, morality axes, state changes. Returns its reply text.
func apply_choice(ch: Dictionary, beat: Dictionary = {}) -> String:
	var lines := Encounters.apply_effects(ch.get("effects", {}))
	var ax: Dictionary = ch.get("axes", {})
	for k in ax:
		axes[k] = float(axes.get(k, 0.0)) + float(ax[k])
	for k in ch.get("set", {}):
		state[k] = ch["set"][k]
	for k in ch.get("add", {}):
		if k == "fame":
			Game.flags["fame"] = fame() + int(ch["add"][k])
		else:
			state[k] = int(state.get(k, 0)) + int(ch["add"][k])
	if ch.has("rep_faction"):
		Factions.change_rep(world.get("faction", "paragon"), int(ch["rep_faction"]), "story choice")
	if not ax.is_empty():
		Causality.record("choice", {"target": str(ch.get("id", "")), "moral": {"mercy": ax.get("mercy", 0), "order": ax.get("order", 0), "greed": ax.get("greed", 0)},
			"note": "saga:%s" % ch.get("id", ""), "public": false})
	var reply := fill(str(ch.get("reply", "")), beat)
	if not lines.is_empty():
		reply += "\n[color=#ffd23e]" + "  ".join(PackedStringArray(lines)) + "[/color]"
	return reply


# --- Queries ---------------------------------------------------------------------------------

func current() -> Dictionary:
	return beats[index] if index < beats.size() else {}


func is_complete() -> bool:
	return index >= beats.size()


func objective_planet() -> String:
	return current().get("planet", "")


func objective_text() -> String:
	if is_complete():
		return ("THE END: %s - the Sprawl is yours to wander" % ending_title) if ending != "" else ""
	var b := current()
	var pname: String = Game.planet_by_id(b.get("planet", "")).get("name", "?")
	var here: bool = Game.location_id == b.get("planet", "")
	var what := ""
	match _beat_type(b):
		"talk":
			what = "Find %s" % personas.get(cast.get(b.get("who", ""), ""), {}).get("name", "your contact")
		"retrieve":
			what = "Recover %s" % world.get(b.get("item", ""), b.get("item", "it"))
		"defeat":
			what = "Take down %s" % personas.get(cast.get(b.get("who", ""), ""), {}).get("name", "the target")
	return "ACT %d - %s: %s%s" % [int(b.get("act", 1)), b.get("title", ""), what, "" if here else "  (travel to %s)" % pname]


## Defectors meet the antagonist as a boss, not a target.
func _beat_type(b: Dictionary) -> String:
	if b.get("id", "") == "finale" and state.get("defected", false):
		return "talk"
	return str(b.get("type", ""))


func side_quests_at(planet_id: String) -> Array:
	return side.get(planet_id, [])


# --- Spawning ------------------------------------------------------------------------------------

## What a planet level should place for the story and its side quests.
func spawns_for(planet_id: String) -> Array:
	var out := []
	var b := current()
	if not b.is_empty() and b.get("planet", "") == planet_id:
		match _beat_type(b):
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
	for planet_id in side:
		for q in side[planet_id]:
			if q.giver == persona_id and q.status != "done":
				_talk_side(q, p)
				return
	var b := current()
	if b.is_empty() or _beat_type(b) != "talk" or cast.get(b.get("who", ""), "") != persona_id:
		EventBus.dialogue_requested.emit(p.get("name", "?"), "%s\n\n\"Not now. They're watching. They're always watching.\"" % persona_greeting(p), [], Callable())
		return
	var text := persona_greeting(p) + "\n\n" + fill(b.get("talk", "..."), b)
	match str(b.id):
		"twist":
			var choices := _choices_from(data().get("twist_choices", []), b)
			EventBus.dialogue_requested.emit(p.get("name", "?"), "[color=#ff3ec8][b]TWIST[/b][/color]\n" + text, choices, _on_twist_choice)
		"finale":
			# Defected: you meet your new boss instead of fighting them.
			state["antagonist_fate"] = "victorious"
			EventBus.dialogue_requested.emit(p.get("name", "?"), persona_greeting(p) + "\n\n\"So. You brought it. Loyalty is so rare these days. Hand it over.\"",
				_finale_choices(), _on_finale_choice)
		_:
			var ap: Array = data().get("approaches", {}).get(b.id, [])
			if ap.is_empty():
				EventBus.dialogue_requested.emit(p.get("name", "?"), text, [], func(_c): _advance())
			else:
				EventBus.dialogue_requested.emit(p.get("name", "?"), text, _choices_from(ap, b), _on_approach.bind(b.id))


func _on_approach(choice: String, beat_id: String) -> void:
	var b := current()
	var ch := _find(data().get("approaches", {}).get(beat_id, []), choice)
	var reply := apply_choice(ch, b) if not ch.is_empty() else ""
	_log("%s: %s" % [b.get("title", ""), fill(str(ch.get("text", choice)), b)], reply)
	if reply.strip_edges() == "":
		_advance()
	else:
		EventBus.dialogue_requested.emit(Game.player_name, reply, [], func(_c): _advance())


func _on_twist_choice(choice: String) -> void:
	twist_choice = choice
	var b := current()
	var ch := _find(data().get("twist_choices", []), choice)
	if not ch.is_empty():
		state["ally_fate"] = ch.get("fate", "unknown")
		apply_choice(ch, b)
	_log("TWIST: " + fill(str(ch.get("text", choice)), b), "")
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
	axes["mercy"] = float(axes.get("mercy", 0.0)) + 0.5
	Causality.record("mercy", {"target": p.get("name", ""), "note": "side quest"})
	EventBus.dialogue_requested.emit(p.get("name", "?"), text + "\n\n[color=#ffd23e]+%d cr[/color]" % q.reward, [], Callable())
	_log("SIDE DONE: " + str(q.title), "Paid %d cr." % q.reward)
	objective_changed.emit()


func on_item_taken(tag: String) -> void:
	if tag.begins_with("story:"):
		Stories.on_item_taken(tag)
		return
	var b := current()
	if not b.is_empty() and b.id == tag:
		var ap: Array = data().get("approaches", {}).get(b.id, [])
		var text := fill(b.get("done", "Got it."), b)
		if ap.is_empty():
			EventBus.dialogue_requested.emit("FOUND", text, [], func(_c): _advance())
		else:
			EventBus.dialogue_requested.emit("FOUND", text + "\n\n[color=#3ee6ff]What now?[/color]", _choices_from(ap, b), _on_approach.bind(b.id))
		return
	_mark_side_ready(tag)


## An elite story target gave up (Enemy._surrender).
func on_surrender(enemy: Node, tag: String) -> void:
	var b := current()
	_pending_enemy = enemy
	if b.is_empty() or b.id != tag or not (b.id in ["lieutenant", "finale"]):
		# Side-quest bounty: quick mercy choice.
		EventBus.dialogue_requested.emit(enemy.display_name, "\"Okay! OKAY! I yield! I've got credits - take them, just let me walk!\"",
			[{"id": "kill", "text": "Finish the job"}, {"id": "spare", "text": "Take the credits and let them go"}], _on_bounty_surrender.bind(tag))
		return
	var role := "antagonist" if b.id == "finale" else "lieutenant"
	var who: String = persona_by_role(role).get("name", "They")
	var plea := "\"Wait - WAIT. You don't understand what you're doing. We can make a deal. Everyone makes a deal.\"" if role == "antagonist" \
		else "\"Enough! I yield! I'm just the help - you want %s, not me!\"" % persona_by_role("antagonist").get("name", "the boss")
	EventBus.dialogue_requested.emit(who, plea, _choices_from(data().get("surrender", {}).get(role, []), b), _on_surrender_choice.bind(role))


func _on_bounty_surrender(choice: String, tag: String) -> void:
	if is_instance_valid(_pending_enemy):
		_pending_enemy.set_meta("saga_resolved", true)
		_pending_enemy.resolve_surrender("kill" if choice == "kill" else "leave")
	if choice == "spare":
		Game.add_credits(roundi(40 * Game.stat("loot_mult")))
		axes["mercy"] = float(axes.get("mercy", 0.0)) + 1.0
		Causality.record("mercy", {"target": "bounty target", "note": "spared"})
	_mark_side_ready(tag)
	_pending_enemy = null


func _on_surrender_choice(choice: String, role: String) -> void:
	var b := current()
	var ch := _find(data().get("surrender", {}).get(role, []), choice)
	state[role + "_fate"] = ch.get("fate", "killed")
	var reply := apply_choice(ch, b)
	_log("%s: %s" % [b.get("title", ""), fill(str(ch.get("text", choice)), b)], reply)
	if is_instance_valid(_pending_enemy):
		_pending_enemy.set_meta("saga_resolved", true)
		_pending_enemy.resolve_surrender("kill" if choice == "kill" else "leave")
	_pending_enemy = null
	if role == "antagonist":
		EventBus.dialogue_requested.emit(Game.player_name, reply, [], func(_c): _finale(b))
	else:
		EventBus.dialogue_requested.emit("Q.U.A.C.K.", reply + "\n\n" + fill(b.get("done", "Done."), b), [], func(_c): _advance())


func _on_enemy_killed(enemy: Node, _info: Dictionary) -> void:
	var tag: String = enemy.get_meta("saga_tag", "") if enemy else ""
	if tag == "" or tag.begins_with("story:") or enemy.get_meta("saga_resolved", false):
		return
	var b := current()
	if not b.is_empty() and b.id == tag:
		if b.id == "finale":
			state["antagonist_fate"] = "killed"
			_finale(b)
		else:
			if b.id == "lieutenant":
				state["lieutenant_fate"] = "killed"
			EventBus.dialogue_requested.emit("Q.U.A.C.K.", fill(b.get("done", "Done."), b), [], func(_c): _advance())
		return
	_mark_side_ready(tag)


func _on_action_recorded(node: Dictionary) -> void:
	# Every remembered act nudges your legacy a little (saga choices are counted separately).
	if node.get("verb", "") != "choice":
		var m: Dictionary = node.get("moral", {})
		for k in ["mercy", "order", "greed"]:
			axes[k] = float(axes.get(k, 0.0)) + float(m.get(k, 0.0)) * 0.2
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


# --- Finale & endings ---------------------------------------------------------------------------

func _finale_choices() -> Array:
	var out := []
	for ch in data().get("finale", []):
		if not choice_ok(ch):
			continue
		# Defectors get a short list; everyone else can't "serve".
		if state.get("defected", false) and not (ch.id in ["serve", "double_cross", "leverage", "walk_away", "personal_use"]):
			continue
		out.append({"id": ch.id, "text": fill(str(ch.get("text", ch.id)), current())})
	return out


func _finale(b: Dictionary) -> void:
	EventBus.dialogue_requested.emit("THE END?", fill(b.get("done", ""), b) + "\n\n[color=#3ee6ff]What happens to %s?[/color]" % world.get("macguffin", "it"),
		_finale_choices(), _on_finale_choice)


func _on_finale_choice(choice: String) -> void:
	var ch := _find(data().get("finale", []), choice)
	state["finale"] = choice
	apply_choice(ch, current())
	if ch.has("faction"):
		Factions.change_rep(str(ch["faction"]), 20, "bought the MacGuffin")
	_compose_and_play(choice, false)


## Endings reachable before the finale, when your Motivation comes true early.
func early_ending_available() -> Dictionary:
	if is_complete() or ending != "":
		return {}
	var e: Dictionary = data().get("early", {}).get(Game.tags.get("motivation", ""), {})
	if e.is_empty() or not cond_ok(e.get("when", {})):
		return {}
	return e


func take_early_ending() -> void:
	var e := early_ending_available()
	if e.is_empty():
		return
	state["finale"] = "early_" + str(Game.tags.get("motivation", ""))
	world["early_slide"] = str(e.get("slide", ""))
	_compose_and_play(state.finale, true)


## Same as take_early_ending, but returns the ending for UIs without a HUD (star map).
func commit_early_ending() -> Dictionary:
	var e := early_ending_available()
	if e.is_empty():
		return {}
	state["finale"] = "early_" + str(Game.tags.get("motivation", ""))
	world["early_slide"] = str(e.get("slide", ""))
	var out := commit_ending(state.finale, true)
	index = beats.size()
	objective_changed.emit()
	return out


## Build the ending from independent slides. Returns {id, title, slides}.
func compose_ending(finale_id: String, early: bool) -> Dictionary:
	var d := data()
	var b := current()
	var motivation: String = Game.tags.get("motivation", "")
	var slides: Array = []
	# 1. Resolution.
	if early:
		slides.append(fill(str(world.get("early_slide", "")), b))
	else:
		slides.append(fill(str(_find(d.get("finale", []), finale_id).get("slide", "")), b))
	var sl: Dictionary = d.get("slides", {})
	# 2-4. Fates of the antagonist, lieutenant and ally.
	slides.append(fill(str(sl.get("antagonist", {}).get(state.get("antagonist_fate", "untouched"), "")), b))
	slides.append(fill(str(sl.get("lieutenant", {}).get(state.get("lieutenant_fate", "unknown"), "")), b))
	slides.append(fill(str(sl.get("ally", {}).get(state.get("ally_fate", "unknown"), "")), b))
	# 5. Personal thread: earned through the personal beat + how the ending serves your Motivation.
	var outcome := personal_outcome(finale_id, early)
	var ptexts: Array = sl.get("personal", {}).get(motivation, [])
	if outcome < ptexts.size():
		slides.append(fill(str(ptexts[outcome]), b))
	# 6. Planet stories you changed.
	for line in Stories.epilogue_lines():
		slides.append(line)
	# 7. Crew.
	if Crew.size() > 0:
		slides.append("Your crew of %d stays aboard the Odd Duck. Q.U.A.C.K. bills them for air out of habit and forgives the debt out of something it refuses to call love." % Crew.size())
	# 8. Legacy + who you were.
	var legacy := legacy_for(finale_id)
	slides.append("[b]%s[/b]\n%s\n\n%s" % [legacy.get("title", "THE SURVIVOR"), fill(str(legacy.get("text", "")), b), _codas()])
	var outcome_names := ["fulfilled", "bittersweet", "failed"]
	var id := "%s|%s|%s|%s|%s:%s|%s" % [finale_id, state.get("antagonist_fate", "untouched"), state.get("lieutenant_fate", "unknown"),
		state.get("ally_fate", "unknown"), motivation, outcome_names[outcome], legacy.get("id", "survivor")]
	var title := "%s - %s" % [legacy.get("title", "THE SURVIVOR"), _finale_tag(finale_id)]
	return {"id": id, "title": title, "slides": slides.filter(func(s): return str(s).strip_edges() != "")}


## 0 = fulfilled, 1 = bittersweet, 2 = failed.
func personal_outcome(finale_id: String, early: bool) -> int:
	var score := int(state.get("personal", 0))
	score += int(data().get("affinity", {}).get(Game.tags.get("motivation", ""), {}).get(finale_id, 0))
	if finale_id == "personal_use" or early:
		score += 3
	if state.get("personal_lied", false):
		score -= 1
	return 0 if score >= 3 else (1 if score >= 1 else 2)


func _finale_tag(finale_id: String) -> String:
	var tags := {"broadcast": "WHO TOLD THE TRUTH", "seize_company": "WHO TOOK THE THRONE", "destroy": "WHO BURNED IT ALL",
		"sell_paragon": "WHO SOLD IT TO THE LAW", "sell_halcyon": "WHO SOLD IT TO THE BANK", "sell_gristle": "WHO SOLD IT TO THE KITCHEN",
		"sell_oxy": "WHO SOLD THE AIR", "sell_lumen": "WHO SOLD THE STORY", "give_ally": "WHO TRUSTED A FRIEND",
		"give_people": "WHO GAVE IT AWAY", "personal_use": "WHO CHOSE THEMSELF", "leverage": "WHO KEPT THE KEY",
		"upload_self": "WHO BECAME THE MACHINE", "walk_away": "WHO WALKED AWAY", "ransom": "WHO NAMED A PRICE",
		"serve": "WHO SERVED THE CROWN", "double_cross": "WHO LAUGHED LAST"}
	if finale_id.begins_with("early_"):
		return "WHO GOT OUT EARLY"
	return tags.get(finale_id, "OF THE SPRAWL")


func legacy_for(finale_id: String) -> Dictionary:
	var prev: String = state.get("finale", "")
	state["finale"] = finale_id
	var found := {"id": "survivor", "title": "THE SURVIVOR", "text": "You made it."}
	for l in data().get("legacy", []):
		var w: Dictionary = (l.get("when", {}) as Dictionary).duplicate()
		var min_cr := int(w.get("min_credits", -1))
		w.erase("min_credits")
		if min_cr >= 0 and Game.credits < min_cr:
			continue
		if cond_ok(w):
			found = l
			break
	state["finale"] = prev if prev != "" else finale_id
	return found


func _codas() -> String:
	var d := data()
	var w_now := 0
	if Game.credits >= 5000:
		w_now = 5
	elif Game.credits >= 1500:
		w_now = 4
	elif Game.credits >= 600:
		w_now = 3
	elif Game.credits >= 150:
		w_now = 2
	elif Game.credits >= 30:
		w_now = 1
	var change := "same"
	if w_now > start_wealth:
		change = "up"
	elif w_now < start_wealth:
		change = "down"
	var cc := str(d.get("class_coda", {}).get(str(start_wealth), "")).replace("{wealth_change}", str(d.get("wealth_change", {}).get(change, "")))
	var ac := str(d.get("age_coda", {}).get(Game.tags.get("age", "young"), ""))
	return fill(cc) + " " + fill(ac)


func commit_ending(finale_id: String, early: bool) -> Dictionary:
	var e := compose_ending(finale_id, early)
	ending = e.id
	ending_title = e.title
	Game.flags["saga_complete"] = true
	Game.flags["ending_id"] = e.id
	var seen: Array = Game.flags.get("endings_seen", [])
	if not seen.has(e.id):
		seen.append(e.id)
	Game.flags["endings_seen"] = seen
	for line in e.slides:
		_log("EPILOGUE", line)
	return e


func _compose_and_play(finale_id: String, early: bool) -> void:
	var e := commit_ending(finale_id, early)
	_slides = e.slides.duplicate()
	get_tree().call_group("hud", "title_card", e.title, "an ending composed from your choices", 3.0)
	_next_slide()


func _next_slide() -> void:
	if _slides.is_empty():
		index = beats.size()
		get_tree().call_group("hud", "title_card", "THE END", ending_title, 3.5)
		objective_changed.emit()
		get_tree().call_group("level", "refresh_quests")
		return
	var s: String = _slides.pop_front()
	EventBus.dialogue_requested.emit("EPILOGUE", s, [], func(_c): _next_slide())


func _advance() -> void:
	var prev_act := ""
	if index < beats.size():
		beats[index].status = "done"
		prev_act = str(int(float(beats[index].get("act", 0))))
		_log("DONE: " + str(beats[index].title), "")
	index += 1
	if index < beats.size():
		var b: Dictionary = beats[index]
		b.status = "active"
		var intro := fill(b.get("intro", ""), b)
		_log(b.title, intro)
		EventBus.toast.emit("NEW OBJECTIVE: %s" % b.title, Color(1.0, 0.82, 0.24))
		EventBus.ai_say.emit(intro, "saga")
		var act := str(int(float(b.get("act", 0))))
		if prev_act != "" and act != prev_act:
			play_bookend("close", prev_act)
			play_bookend("open", act)
	objective_changed.emit()
	get_tree().call_group("level", "refresh_quests")


# --- Bookends: hand-written act openings and closings (data/bookends.json) --------------------
# The procedural saga is the middle; these are the authored anchors around it, written around
# who the player is (motivation, wealth) and what they did (dominant moral axis, crew).

var _bookends: Dictionary = {}


func bookends() -> Dictionary:
	if _bookends.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/bookends.json"))
		_bookends = parsed if parsed is Dictionary else {}
	return _bookends


func play_bookend(kind: String, act: String) -> void:
	var flag := "bookend_%s_%s" % [kind, act]
	if Game.flags.get(flag, false):
		return
	var d: Dictionary = bookends().get(kind, {}).get(act, {})
	if d.is_empty():
		return
	Game.flags[flag] = true
	var beat: Dictionary = beats[index] if index < beats.size() else {}
	var parts: Array[String] = [fill(str(d.get("frame", "")), beat)]
	if kind == "open":
		var mot := str(Game.tags.get("motivation", ""))
		if d.get("motivation", {}).has(mot):
			parts.append(fill(str(d.motivation[mot]), beat))
		var w := Origin.wealth()
		var band := "rich" if w >= 4 else ("poor" if w <= 1 else "middle")
		parts.append(fill(str(d.get("wealth", {}).get(band, "")), beat))
	else:
		parts.append(fill(str(d.get("axis", {}).get(dominant_axis(), "")), beat))
		if not Crew.members.is_empty():
			var crew_name := str(Crew.def(str(Crew.members.keys()[0])).get("name", "your crew"))
			parts.append(fill(str(d.get("crew", "")), beat).replace("{crew}", crew_name))
	var text := "\n\n".join(parts.filter(func(p): return p != ""))
	_log(str(d.get("title", "")), text)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("title_card"):
		hud.title_card(str(d.get("title", "")), "", 2.0)
	EventBus.dialogue_requested.emit(str(d.get("title", "")), text, [], Callable())


## The moral axis the player has leaned into most so far ("none" if they haven't).
func dominant_axis() -> String:
	var best := "none"
	var best_v := 1.0
	for k in ["mercy", "order", "greed", "truth"]:
		var v := float(axes.get(k, 0.0))
		if v > best_v:
			best_v = v
			best = k
	return best


func _log(title: String, text: String) -> void:
	journal.append({"title": title, "text": text, "where": Game.location_name, "time": snappedf(Game.play_time, 1.0)})


# --- Save ------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"seed": seed_value, "personas": personas, "cast": cast, "world": world, "beats": beats, "index": index,
		"journal": journal, "side": side, "ending": ending, "ending_title": ending_title, "twist_choice": twist_choice,
		"state": state, "axes": axes, "start_wealth": start_wealth}


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
	ending_title = d.get("ending_title", "")
	twist_choice = d.get("twist_choice", "")
	state.merge(d.get("state", {}), true)
	axes.merge(d.get("axes", {}), true)
	start_wealth = int(d.get("start_wealth", 1))
	for pid in side:
		for q in side[pid]:
			q["progress"] = int(q.get("progress", 0))
			q["reward"] = int(q.get("reward", 50))
