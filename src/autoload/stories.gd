extends Node
## "Stories" autoload - every planet has its own story, and the streets have theirs.
##
## LOCAL STORIES (data/stories.json "local", one template per crisis): on first
## landing a planet gets two generated characters - a LEADER of the people and a
## BOSS working for the planet's owner. Each offers choices (gated by who you
## are); a choice resolves instantly or sets a task (fight, retrieve, sabotage).
## The outcome changes the planet for the rest of the run (crisis resolved or
## worse, prices, air, even who controls it) and becomes a slide of your ending.
##
## STREET EVENTS ("street"): 1-2 random incidents each landing - muggings,
## repossessions, evictions, auctions of frozen people - with choices that depend
## on your class, age, background, personality and inventory.

const LOCAL_COLOR := Color(0.75, 0.5, 1.0)
const STREET_COLOR := Color(1.0, 0.55, 0.2)

var local: Dictionary = {}        # planet_id -> story state
var street_done: Dictionary = {}  # planet_id -> [event ids]
var _visit := {"planet": "", "events": []}
var _rng := RandomNumberGenerator.new()
var _pending_enemy: Node = null


func _ready() -> void:
	_rng.randomize()
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.action_recorded.connect(_on_action_recorded)


func reset() -> void:
	local.clear()
	street_done.clear()
	_visit = {"planet": "", "events": []}


func templates() -> Dictionary:
	return DataDB.stories.get("local", {})


# --- Local stories ------------------------------------------------------------------------------

func ensure_local(planet_id: String) -> Dictionary:
	if local.has(planet_id):
		return local[planet_id]
	var planet := Game.planet_by_id(planet_id)
	var crisis := str(planet.get("crisis", ""))
	var t: Dictionary = templates().get(crisis, {})
	if planet.is_empty() or t.is_empty():
		return {}
	var ctrl := str(planet.get("controller", ""))
	var leader := Saga.make_persona("local_leader", "", planet_id, str(t.get("leader", {}).get("style", "worker")))
	leader["job"] = t.get("leader", {}).get("job", leader.job)
	var boss_style := str(t.get("boss", {}).get("style", "corporate")).replace("{controller}", ctrl if ctrl != "" else "paragon")
	if ctrl == "" and boss_style.begins_with("corporate"):
		boss_style = "punk"
	var boss := Saga.make_persona("local_boss", ctrl, planet_id, boss_style)
	boss["job"] = t.get("boss", {}).get("job", boss.job)
	local[planet_id] = {"crisis": crisis, "status": "open", "leader": leader, "boss": boss,
		"title": str(t.get("title", "Local trouble")).replace("{planet}", str(planet.get("name", "?"))),
		"choice": "", "outcome": "", "task": {}, "progress": 0, "epilogue": ""}
	return local[planet_id]


func has_local(planet_id: String) -> bool:
	return local.has(planet_id) and local[planet_id].status != "done"


func local_info(planet_id: String) -> Dictionary:
	var s: Dictionary = local.get(planet_id, {})
	if s.is_empty():
		return {}
	return {"hint": templates().get(s.crisis, {}).get("hint", ""), "leader": s.leader.get("name", "?"), "title": s.title, "status": s.status}


func epilogue_lines() -> Array:
	var out := []
	for pid in local:
		if str(local[pid].get("epilogue", "")) != "":
			out.append(local[pid].epilogue)
	return out


## Journal / star map summary.
func summary_lines() -> Array:
	var out := []
	for pid in local:
		var s: Dictionary = local[pid]
		var pname: String = Game.planet_by_id(pid).get("name", "?")
		match str(s.status):
			"done":
				out.append("[s]%s[/s] (%s) - %s" % [s.title, pname, str(s.outcome).replace("_", " ")])
			"task":
				out.append("[b]%s[/b] (%s) - %s" % [s.title, pname, _task_text(s)])
			_:
				out.append("%s (%s) - talk to %s or %s" % [s.title, pname, s.leader.get("name", "?"), s.boss.get("name", "?")])
	return out


func _task_text(s: Dictionary) -> String:
	var t: Dictionary = s.get("task", {})
	match str(t.get("type", "")):
		"defeat":
			return "defeat %s" % t.get("name", "the enforcer")
		"defeat_leader":
			return "defeat %s" % s.leader.get("name", "the leader")
		"retrieve":
			return "recover %s" % t.get("label", "the goods")
		"sabotage":
			return "sabotage %d/%d ad screens or machines" % [int(s.progress), int(t.get("count", 2))]
	return "?"


# --- Street events --------------------------------------------------------------------------------

## Called once per landing: roll this visit's street incidents.
func begin_visit(planet_id: String) -> void:
	ensure_local(planet_id)
	var done: Array = street_done.get(planet_id, [])
	var pool := []
	for e in DataDB.stories.get("street", []):
		if not done.has(e.get("id", "")):
			pool.append(e)
	pool.shuffle()
	var picks := []
	for e in pool:
		if picks.size() >= 2:
			break
		picks.append(e.get("id", ""))
	_visit = {"planet": planet_id, "events": picks}


func _street_event(id: String) -> Dictionary:
	for e in DataDB.stories.get("street", []):
		if e.get("id", "") == id:
			return e
	return {}


# --- Spawning --------------------------------------------------------------------------------------

func spawns_for(planet_id: String) -> Array:
	var out := []
	var s: Dictionary = local.get(planet_id, {})
	if not s.is_empty() and s.status != "done":
		var t: Dictionary = s.get("task", {})
		var leader_fights: bool = s.status == "task" and t.get("type", "") == "defeat_leader"
		if not leader_fights:
			out.append({"kind": "story_npc", "key": "local:%s:leader" % planet_id, "story_id": "local:%s:leader" % planet_id, "persona": s.leader, "marker": "?" if s.status == "open" else "", "color": LOCAL_COLOR})
		out.append({"kind": "story_npc", "key": "local:%s:boss" % planet_id, "story_id": "local:%s:boss" % planet_id, "persona": s.boss, "marker": "?" if s.status == "open" else "", "color": LOCAL_COLOR})
		if s.status == "task":
			var tag := "story:" + planet_id
			match str(t.get("type", "")):
				"defeat":
					out.append({"kind": "elite", "tag": tag, "persona_id": "", "name": t.get("name", "Enforcer"), "enemy_type": t.get("enemy", "pirate"), "boss": false})
					out.append({"kind": "guards", "count": int(t.get("guards", 2)), "faction": Game.planet_by_id(planet_id).get("controller", ""), "key": "story_guards:" + planet_id})
				"defeat_leader":
					out.append({"kind": "elite", "tag": tag, "persona_id": "", "name": s.leader.get("name", "Leader"), "look": s.leader.get("look", {}), "enemy_type": "pirate", "boss": false})
					out.append({"kind": "guards", "count": 2, "faction": "", "key": "story_guards:" + planet_id})
				"retrieve":
					out.append({"kind": "quest_item", "tag": tag, "label": t.get("label", "the goods")})
					out.append({"kind": "guards", "count": int(t.get("guards", 2)), "faction": Game.planet_by_id(planet_id).get("controller", ""), "key": "story_guards:" + planet_id})
	if _visit.planet == planet_id:
		for eid in _visit.events:
			var e := _street_event(eid)
			if e.is_empty() or (street_done.get(planet_id, []) as Array).has(eid):
				continue
			out.append({"kind": "street", "key": "street:" + eid, "story_id": "street:" + eid, "event": e, "color": STREET_COLOR})
	return out


# --- Talking ---------------------------------------------------------------------------------------

func on_npc_talk(npc: Node) -> void:
	var sid: String = npc.story_id
	if sid.begins_with("street:"):
		_talk_street(npc, sid.substr(7))
		return
	var parts := sid.split(":")
	if parts.size() < 3:
		return
	var planet_id := parts[1]
	var who := parts[2]
	var s: Dictionary = local.get(planet_id, {})
	if s.is_empty():
		return
	var t: Dictionary = templates().get(s.crisis, {})
	var p: Dictionary = s.get(who, {})
	var head := Saga.persona_greeting(p) + "\n[color=#c07dff][b]%s[/b][/color]\n" % s.title
	match str(s.status):
		"open":
			var choices := []
			for ch in t.get("choices", []):
				if ch.get("who", "leader") == who and Saga.choice_ok(ch):
					choices.append({"id": ch.id, "text": _fill(str(ch.text), planet_id)})
			choices.append({"id": "later", "text": "\"Let me think about it.\""})
			var talk_text := _fill(str(t.get(who + "_talk", "...")), planet_id)
			EventBus.dialogue_requested.emit(p.get("name", "?"), head + talk_text, choices, _on_local_choice.bind(planet_id))
		"task":
			EventBus.dialogue_requested.emit(p.get("name", "?"), head + "\"Well? It's not going to %s itself.\"\n[color=#ffd23e]%s[/color]" % [_task_text(s).split(" ")[0], _task_text(s)], [], Callable())
		_:
			var o: Dictionary = t.get("outcomes", {}).get(s.outcome, {})
			EventBus.dialogue_requested.emit(p.get("name", "?"), head + "\"After what you did...\" " + _fill(str(o.get("text", "")), planet_id), [], Callable())


func _on_local_choice(choice: String, planet_id: String) -> void:
	if choice == "later":
		return
	var s: Dictionary = local.get(planet_id, {})
	var t: Dictionary = templates().get(s.get("crisis", ""), {})
	var ch: Dictionary = {}
	for c in t.get("choices", []):
		if c.get("id", "") == choice:
			ch = c
	if ch.is_empty():
		return
	s.choice = choice
	Encounters.apply_effects(ch.get("effects", {}))
	if ch.has("task"):
		s.status = "task"
		s.task = ch.task
		s.progress = 0
		s["pending_outcome"] = ch.get("outcome", "")
		Saga._log("PLANET: " + s.title, _fill(str(ch.text), planet_id))
		EventBus.toast.emit("LOCAL STORY: %s" % _task_text(s), LOCAL_COLOR)
		Saga.objective_changed.emit()
		get_tree().call_group("level", "refresh_quests")
		if str(ch.task.get("type", "")) == "defeat_leader":
			get_tree().call_group("story_npc", "story_left", "local:%s:leader" % planet_id)
	else:
		_resolve_local(planet_id, str(ch.get("outcome", "")))


func _resolve_local(planet_id: String, outcome_id: String) -> void:
	var s: Dictionary = local.get(planet_id, {})
	if s.is_empty() or s.status == "done":
		return
	var t: Dictionary = templates().get(s.crisis, {})
	var o: Dictionary = t.get("outcomes", {}).get(outcome_id, {})
	s.status = "done"
	s.outcome = outcome_id
	var planet := Game.planet_by_id(planet_id)
	var lines := Encounters.apply_effects(o.get("effects", {}))
	var ctrl := str(planet.get("controller", ""))
	var rep: Dictionary = o.get("rep", {})
	for k in rep:
		var fid := str(k).replace("{controller}", ctrl)
		if fid != "" and DataDB.factions.has(fid):
			Factions.change_rep(fid, int(rep[k]), "planet story")
			lines.append("%s %+d" % [DataDB.faction_name(fid), int(rep[k])])
	var ax: Dictionary = o.get("axes", {})
	for k in ax:
		Saga.axes[k] = float(Saga.axes.get(k, 0.0)) + float(ax[k])
	if o.has("followers"):
		Game.flags["followers"] = Saga.followers() + int(o.followers)
		lines.append("+%d followers" % int(o.followers))
	if o.has("fame"):
		Game.flags["fame"] = Saga.fame() + int(o.fame)
		lines.append("Fame +%d" % int(o.fame))
	var pc: Dictionary = o.get("planet", {})
	if pc.get("crisis_resolved", false):
		planet["crisis_state"] = "resolved"
	if pc.get("crisis_worse", false):
		planet["crisis_state"] = "worse"
	if pc.has("price_adjust"):
		planet["price_adjust"] = float(planet.get("price_adjust", 1.0)) * float(pc.price_adjust)
	if pc.has("air_mult"):
		planet["air_adjust"] = float(planet.get("air_adjust", 1.0)) * float(pc.air_mult)
	if pc.get("controller_lost", false):
		planet["former_controller"] = ctrl
		planet["controller"] = ""
		planet["liberated"] = true
	Causality.record("choice", {"target": s.title, "moral": {"mercy": ax.get("mercy", 0), "order": ax.get("order", 0), "greed": ax.get("greed", 0)}, "note": "planet:" + outcome_id, "public": true})
	s.epilogue = _fill(str(o.get("epilogue", "")), planet_id)
	Saga._log("PLANET: " + s.title, _fill(str(o.get("text", "")), planet_id))
	var text := "[color=#c07dff][b]%s[/b][/color]\n%s" % [s.title, _fill(str(o.get("text", "")), planet_id)]
	if not lines.is_empty():
		text += "\n[color=#ffd23e]" + "  ".join(PackedStringArray(lines)) + "[/color]"
	EventBus.dialogue_requested.emit(s.leader.get("name", "?") if outcome_id != "strike_broken" else s.boss.get("name", "?"), text, [], Callable())
	EventBus.story_event.emit("local_done", {"planet": planet_id, "outcome": outcome_id})
	Saga.objective_changed.emit()
	get_tree().call_group("level", "refresh_quests")


func _fill(text: String, planet_id: String) -> String:
	var planet := Game.planet_by_id(planet_id)
	return text.replace("{planet}", str(planet.get("name", "?"))).replace("{player}", Game.player_name)


func _talk_street(npc: Node, eid: String) -> void:
	var e := _street_event(eid)
	if e.is_empty():
		return
	var choices := []
	for ch in e.get("choices", []):
		if not Saga.choice_ok(ch):
			continue
		var text := str(ch.get("text", ch.id))
		if ch.has("chance"):
			text += "  [%d%%]" % roundi(_chance(ch) * 100.0)
		choices.append({"id": ch.id, "text": text})
	EventBus.dialogue_requested.emit(str(e.get("title", "!")), str(e.get("text", "")), choices, _on_street_choice.bind(npc, eid))


func _chance(ch: Dictionary) -> float:
	return Interactions.chance_of(ch, null) if ch.has("chance") else 1.0


func _on_street_choice(choice: String, npc: Node, eid: String) -> void:
	var e := _street_event(eid)
	var ch: Dictionary = {}
	for c in e.get("choices", []):
		if c.get("id", "") == choice:
			ch = c
	if ch.is_empty():
		return
	var success := _rng.randf() < _chance(ch)
	var o: Dictionary = ch.get("success" if success else "fail", ch.get("success", {}))
	var lines := Encounters.apply_effects(o.get("effects", {}))
	var ax: Dictionary = o.get("axes", {})
	for k in ax:
		Saga.axes[k] = float(Saga.axes.get(k, 0.0)) + float(ax[k])
	if o.has("followers"):
		Game.flags["followers"] = Saga.followers() + int(o.followers)
		lines.append("+%d followers" % int(o.followers))
	if o.has("fame"):
		Game.flags["fame"] = Saga.fame() + int(o.fame)
		lines.append("Fame +%d" % int(o.fame))
	var pos: Vector3 = (npc as Node3D).global_position if is_instance_valid(npc) else Vector3.ZERO
	if o.has("record"):
		var r: Dictionary = o.record
		Causality.record(str(r.get("verb", "comply")), {"target": str(e.get("title", "")), "target_faction": str(r.get("target_faction", Game.current_planet.get("controller", ""))), "position": pos})
	elif not ax.is_empty():
		Causality.record("choice", {"target": str(e.get("title", "")), "moral": {"mercy": ax.get("mercy", 0), "order": ax.get("order", 0), "greed": ax.get("greed", 0)}, "note": "street:" + eid, "public": false})
	var text := str(o.get("text", "..."))
	if o.get("rumor", false):
		text += "\n\n" + Interactions.rumor(null)
	if not lines.is_empty():
		text += "\n[color=#ffd23e]" + "  ".join(PackedStringArray(lines)) + "[/color]"
	var done: Array = street_done.get(Game.location_id, [])
	done.append(eid)
	street_done[Game.location_id] = done
	Saga._log("STREET: " + str(e.get("title", "")), text)
	EventBus.dialogue_requested.emit(str(e.get("title", "")), text, [], Callable())
	if o.has("spawn_hostile"):
		var sh: Dictionary = o.spawn_hostile
		get_tree().call_group("level", "spawn_story_hostiles", str(sh.get("type", "pirate")), int(sh.get("count", 1)), str(sh.get("name", "")), pos)
	get_tree().call_group("story_npc", "story_left", "street:" + eid)
	EventBus.story_event.emit("street_done", {"event": eid, "choice": choice})


# --- Task hooks ------------------------------------------------------------------------------------

func on_item_taken(tag: String) -> void:
	var planet_id := tag.substr(6)
	var s: Dictionary = local.get(planet_id, {})
	if s.is_empty() or s.status != "task":
		return
	_resolve_local(planet_id, str(s.get("pending_outcome", "")))


func on_surrender(enemy: Node, tag: String) -> void:
	_pending_enemy = enemy
	EventBus.dialogue_requested.emit(enemy.display_name, "\"Alright, alright! You win! Just... let me walk away from this.\"",
		[{"id": "kill", "text": "Finish them"}, {"id": "spare", "text": "Let them walk"}], _on_story_surrender.bind(tag))


func _on_story_surrender(choice: String, tag: String) -> void:
	Saga.axes["mercy"] = float(Saga.axes.get("mercy", 0.0)) + (-1.0 if choice == "kill" else 1.0)
	if is_instance_valid(_pending_enemy):
		_pending_enemy.set_meta("saga_resolved", true)
		_pending_enemy.resolve_surrender("kill" if choice == "kill" else "leave")
	_pending_enemy = null
	var planet_id := tag.substr(6)
	var s: Dictionary = local.get(planet_id, {})
	if not s.is_empty() and s.status == "task":
		_resolve_local(planet_id, str(s.get("pending_outcome", "")))


func _on_enemy_killed(enemy: Node, _info: Dictionary) -> void:
	var tag: String = enemy.get_meta("saga_tag", "") if enemy else ""
	if not tag.begins_with("story:") or enemy.get_meta("saga_resolved", false):
		return
	var planet_id := tag.substr(6)
	var s: Dictionary = local.get(planet_id, {})
	if not s.is_empty() and s.status == "task":
		Saga.axes["mercy"] = float(Saga.axes.get("mercy", 0.0)) - 0.5
		_resolve_local(planet_id, str(s.get("pending_outcome", "")))


func _on_action_recorded(node: Dictionary) -> void:
	if node.get("verb", "") != "vandalism":
		return
	var s: Dictionary = local.get(Game.location_id, {})
	if s.is_empty() or s.status != "task" or s.task.get("type", "") != "sabotage":
		return
	s.progress = int(s.progress) + 1
	EventBus.toast.emit("%s: %d/%d" % [s.title, s.progress, int(s.task.get("count", 2))], LOCAL_COLOR)
	if int(s.progress) >= int(s.task.get("count", 2)):
		_resolve_local(Game.location_id, str(s.get("pending_outcome", "")))


# --- Save ------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"local": local, "street_done": street_done}


func from_save(d: Dictionary) -> void:
	reset()
	local = d.get("local", {})
	street_done = d.get("street_done", {})
	for pid in local:
		local[pid]["progress"] = int(local[pid].get("progress", 0))
