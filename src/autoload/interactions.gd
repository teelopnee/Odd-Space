extends Node
## "Interactions" autoload - what YOU can do to people, decided by who you are.
## Verbs live in data/interactions.json. Each conversation offers the verbs
## your class / age / background / personality / secret / motivation unlock, with
## success chances shaped by the NPC's traits, faction, mood and your reputation.
## Outcomes apply the shared effect DSL (Encounters.apply_effects) plus NPC
## effects (mood, flee, silence, informant...) and are recorded in the
## Causality Graph, so the world remembers how you treat people.

const MAX_CHOICES := 7

var _rng := RandomNumberGenerator.new()
var force_outcome = null  ## tests: true / false forces a verb's success roll (null = roll normally)


func _ready() -> void:
	_rng.randomize()


func verbs() -> Dictionary:
	return DataDB.interactions.get("verbs", {})


func npc_text() -> Dictionary:
	return DataDB.interactions.get("npc", {})


# --- Persona generation -----------------------------------------------------------------

## Gives a civilian a job, a need and a starting attitude toward the player.
func setup_npc(npc: Node, rng: RandomNumberGenerator) -> void:
	var tr_list: Array = npc.traits
	var key: String = tr_list[0] if not tr_list.is_empty() else "poor"
	var jobs: Array = npc_text().get("jobs", {}).get(key, ["drifter"])
	var needs: Array = npc_text().get("needs", {}).get(key, ["Air"])
	npc.job = jobs[rng.randi() % jobs.size()]
	npc.need = needs[rng.randi() % needs.size()]
	var att := Origin.npc_reaction(npc.faction, tr_list)
	if npc.faction != "":
		att += roundi(Factions.get_rep(npc.faction) * 0.3)
	# Wealth gap: the poor distrust the rich, the corporate distrust the poor.
	var w := Origin.wealth()
	if tr_list.has("poor") or tr_list.has("worker"):
		att += (2 - w) * 4
	if tr_list.has("corporate"):
		att += (w - 2) * 5
	att += int(Game.flags.get("followers", 0)) * 2 if tr_list.has("poor") else 0
	# The planet remembers you: what the street saw you do colours how strangers greet you.
	att += NPCVoice.street_bias(npc)
	npc.attitude = clampi(att + rng.randi_range(-8, 8), -60, 60)
	if NPCVoice.street_feared(npc) and rng.randf() < 0.5:
		npc.scared_until = Game.play_time + 600.0


## Greeting line that reacts to your class, age, notoriety and the NPC's mood.
func greeting(npc: Node) -> String:
	var t := npc_text()
	var lines: Array[String] = []
	var heir := DataDB.faction_name(Origin.heir_of())
	var w := Origin.wealth()
	var by_w: Array = t.get("greet_by_wealth", {}).get(str(w), [])
	if not by_w.is_empty() and _rng.randf() < 0.55:
		lines.append(fill(by_w[_rng.randi() % by_w.size()], npc).replace("{heir}", heir))
	else:
		var mood := "warm" if npc.attitude >= 15 else ("cold" if npc.attitude <= -15 else "neutral")
		var pool: Array = t.get("greet_by_trait_reaction", {}).get(mood, ["\"...\""])
		lines.append(fill(pool[_rng.randi() % pool.size()], npc))
	var by_age: Array = t.get("greet_by_age", {}).get(Game.tags.get("age", ""), [])
	if not by_age.is_empty() and _rng.randf() < 0.5:
		lines.append(by_age[_rng.randi() % by_age.size()])
	if int(Game.flags.get("fame", 0)) >= 20 and _rng.randf() < 0.6:
		lines.append("\"Wait - you're %s! From the feeds! Can I get a selfie? It's 3 credits, I'll pay.\"" % Game.player_name)
	return "\n".join(lines)


func fill(text: String, npc: Node = null) -> String:
	var vars := {
		"name": Game.player_name, "age": Game.age, "heir": DataDB.faction_name(Origin.heir_of()),
		"npc": npc.npc_name if npc else "they", "job": npc.job if npc else "", "need": npc.need if npc else "",
		"faction": DataDB.faction_name(npc.faction) if npc else "",
	}
	var out := text.format(vars)
	return Copy.expand(out, _rng) if out.contains("#") or out.contains("{") else out


# --- Availability -------------------------------------------------------------------------

## Choice dictionaries for a conversation: {"id": "act:<verb>", "text", "disabled"}.
func choices_for(npc: Node, role: String) -> Array:
	var gated := []
	var generic := []
	var used: Array = npc.get_meta("used_verbs", [])
	for id in verbs():
		var d: Dictionary = verbs()[id]
		var roles: Array = d.get("roles", ["civilian"])
		if not roles.has(role):
			# Mid-call you can try anything social on a witness: talk, pay, charm, scare.
			var k := str(NPCVoice.reactions().get("verb_kind", {}).get(id, "talk"))
			if not (role == "witness" and roles.has("civilian") and k in ["charity", "threat", "deal", "show", "beg", "weird"]):
				continue
		if d.get("once", false) and used.has(id):
			continue
		if not requirements_met(d, npc):
			continue
		var cost := cost_of(d)
		var text := fill(str(d.get("text", id)), npc).replace("{cost}", str(cost))
		if d.has("chance"):
			text += "  [%d%%]" % roundi(chance_of(d, npc) * 100.0)
		var entry := {"id": "act:" + id, "text": text, "disabled": cost > 0 and not Game.can_afford(cost)}
		if d.has("requires") or d.has("requires_item_any"):
			gated.append(entry)
		else:
			generic.append(entry)
	# Who-you-are verbs first; they're the interesting ones.
	gated.shuffle()
	var out := gated.slice(0, MAX_CHOICES)
	for g in generic:
		if out.size() >= MAX_CHOICES:
			break
		out.append(g)
	return out


func requirements_met(d: Dictionary, npc: Node) -> bool:
	var req: Dictionary = d.get("requires", {})
	if req.has("flag") and not Game.has_flag(req["flag"]):
		return false
	if req.has("not_flag") and Game.has_flag(req["not_flag"]):
		return false
	if req.has("any_flag"):
		var ok := false
		for f in req["any_flag"]:
			if Game.has_flag(f):
				ok = true
		if not ok:
			return false
	if req.has("tag"):
		var ok2 := false
		for t in req["tag"]:
			if Origin.has_tag(t):
				ok2 = true
		if not ok2:
			return false
	if req.has("age") and not (req["age"] as Array).has(Game.tags.get("age", "")):
		return false
	if req.has("goal") and str(Game.flags.get("goal", "")) != str(req["goal"]):
		return false
	if req.has("item") and Game.item_count(req["item"]) <= 0:
		return false
	if req.has("min_credits") and Game.credits < int(req["min_credits"]):
		return false
	if req.get("not_crew_full", false) and Crew.is_full():
		return false
	if req.has("min_air_debt") and Game.air_debt < int(req["min_air_debt"]):
		return false
	if req.has("min_wealth") and Origin.wealth() < int(req["min_wealth"]):
		return false
	if req.has("max_wealth") and Origin.wealth() > int(req["max_wealth"]):
		return false
	if req.has("npc_trait") and npc != null:
		var ok3 := false
		for t in req["npc_trait"]:
			if (npc.traits as Array).has(t):
				ok3 = true
		if not ok3:
			return false
	# Memory: what this NPC saw you do / what the planet says / how they feel (NPCVoice).
	if req.has("npc_saw") and npc != null:
		var ok5 := false
		for m in npc.memories:
			if (req["npc_saw"] as Array).has(str(m.get("kind", ""))):
				ok5 = true
		if not ok5:
			return false
	if req.has("npc_heard"):
		var street := NPCVoice.street_memory()
		var ok6 := false
		for k in req["npc_heard"]:
			if int(street.get(k, 0)) > 0:
				ok6 = true
		if not ok6:
			return false
	if req.has("npc_mood") and npc != null and not (req["npc_mood"] as Array).has(NPCVoice.mood(npc)):
		return false
	if d.has("requires_item_any"):
		var ok4 := false
		for it in d["requires_item_any"]:
			if Game.item_count(it) > 0:
				ok4 = true
		if not ok4:
			return false
	return true


func cost_of(d: Dictionary) -> int:
	var c := int(d.get("cost", 0))
	if c > 0 and d.get("verb", "") == "bribe":
		c = roundi(c * Game.stat("bribe_mult"))
	return c


func chance_of(d: Dictionary, npc: Node) -> float:
	if not d.has("chance"):
		return 1.0
	var c := float(d["chance"])
	var mods: Dictionary = d.get("chance_mods", {})
	for key in mods:
		var k: String = key
		var m := float(mods[key])
		if k.begins_with("npc:") and npc != null and (npc.traits as Array).has(k.substr(4)):
			c += m
		elif k.begins_with("faction:") and npc != null and npc.faction == k.substr(8):
			c += m
		elif k.begins_with("flag:") and Game.has_flag(k.substr(5)):
			c += m
		elif k.begins_with("tag:") and Origin.has_tag(k.substr(4)):
			c += m
		elif k.begins_with("age:") and Game.tags.get("age", "") == k.substr(4):
			c += m
		elif k.begins_with("item:") and Game.item_count(k.substr(5)) > 0:
			c += m
		elif k == "attitude" and npc != null:
			c += m * float(npc.attitude)
		elif k == "rep" and npc != null and npc.faction != "":
			c += m * float(Factions.get_rep(npc.faction))
		elif k == "infamy" and npc != null:
			c += m * float(Causality.infamy_at(Game.location_id, npc.faction))
	return clampf(c, 0.03, 0.97)


# --- Resolution ---------------------------------------------------------------------------

## Runs a verb against an NPC and shows the outcome. Returns true on success.
func resolve(npc: Node, verb_id: String) -> bool:
	var d: Dictionary = verbs().get(verb_id, {})
	if d.is_empty() or not is_instance_valid(npc):
		return false
	var used: Array = npc.get_meta("used_verbs", [])
	used.append(verb_id)
	npc.set_meta("used_verbs", used)
	var cost := cost_of(d)
	if cost > 0 and not Game.spend(cost):
		return false
	var was_reporting: bool = npc.state == "reporting"
	var was_loyal: bool = npc.loyal
	var before_rel: String = npc.relation_label() if npc.has_method("relation_label") else ""
	var before_att: int = int(npc.attitude)
	var success := _rng.randf() < chance_of(d, npc)
	if force_outcome != null and d.has("fail"):
		success = bool(force_outcome)
	var outcome: Dictionary = d.get("success" if success else "fail", d.get("success", {}))
	var lines: Array = outcome.get("lines", ["..."])
	var text := fill(str(lines[_rng.randi() % lines.size()]), npc)
	var effects: Dictionary = outcome.get("effects", {})
	var result_lines := Encounters.apply_effects(_dsl_only(effects))
	var extra := _apply_npc_effects(npc, effects)
	text += extra
	if _rng.randf() < 0.6:
		var after := NPCVoice.afterword(npc, verb_id, success, _rng)
		if after != "":
			text += "\n" + after
	var record_on := str(d.get("record_on", "success"))
	if d.has("verb") and (record_on == "always" or (record_on == "success" and success) or (record_on == "fail" and not success)):
		var info := {"target": npc.npc_name, "target_faction": npc.faction, "position": (npc as Node3D).global_position}
		if str(d["verb"]) in ["theft", "assault", "intimidate"] and not success:
			info["exclude"] = []  # the victim themself saw it
		Causality.record(str(d["verb"]), info)
	if not result_lines.is_empty():
		text += "\n[color=#ffd23e]" + "  ".join(PackedStringArray(result_lines)) + "[/color]"
	var impact: Array[String] = []
	if was_reporting and is_instance_valid(npc):
		impact.append(_witness_outcome(npc, verb_id, success))
	EventBus.interaction_done.emit(verb_id, success, npc)  # bystanders see it now
	FirstDay.done("talk")
	var kind := str(NPCVoice.reactions().get("verb_kind", {}).get(verb_id, "talk"))
	if is_instance_valid(npc):
		# Every outcome leaves a mark: the verb's own reaction, or the default for its kind.
		var react_kind := str(effects.get("react", default_react(kind, success)))
		if npc.has_method("react") and react_kind != "":
			var r := str(npc.react(react_kind))
			if r != "":
				impact.append(r)
		if npc.has_method("after_interaction"):
			var change := str(npc.after_interaction(before_rel, before_att))
			if change != "":
				impact.append(change)
		if npc.loyal and not was_loyal:
			impact.append("They won't report anything you do now.")
		impact.append_array(_bystander_lines(npc))
		if was_reporting or not success:
			impact.append_array(_other_callers(npc))
	if not impact.is_empty():
		text += "\n\n" + _impact_block(impact)
		Tips.show("choices")
	# ...and they answer back: a counter-move you can respond to. Big moments always; small talk
	# only sometimes (Settings: "NPC follow-ups"), and less often from someone who already did.
	if is_instance_valid(npc) and npc.state != "dead":
		var key := "served" if npc.get("_leaving") else "%s_%s" % [kind, "ok" if success else "fail"]
		if should_counter(npc, key) and present_counter(npc, key, text):
			npc.set_meta("countered", int(npc.get_meta("countered", 0)) + 1)
			return success
	EventBus.dialogue_requested.emit(npc.npc_name, text, [], Callable())
	return success


## The "what changed" block: at most three lines - the call, the relationship, the biggest consequence.
func _impact_block(impact: Array) -> String:
	return "[color=#9adfff]" + "\n".join(PackedStringArray(impact.slice(0, 3).map(func(l): return "> " + str(l)))) + "[/color]"


## Always for moments that matter (caught stealing, a threat that failed, a fight, being evicted);
## otherwise a roll set by the player's "NPC follow-ups" setting.
const ALWAYS_COUNTER := ["served", "theft_fail", "threat_fail", "fight_ok", "fight_fail", "keeper_fight_ok", "keeper_fight_fail",
	"keeper_theft_fail", "keeper_banned"]


func should_counter(npc: Node, key: String) -> bool:
	if force_outcome != null or ALWAYS_COUNTER.has(key):
		return true
	var base: float = {"often": 0.75, "sometimes": 0.4, "rare": 0.15}.get(str(Game.settings.get("followups", "sometimes")), 0.4)
	return _rng.randf() < base / (1.0 + float(npc.get_meta("countered", 0)))


## Lasting reaction when the verb data doesn't name one (data/reactions.json "default_react").
func default_react(kind: String, success: bool) -> String:
	var row: Dictionary = NPCVoice.reactions().get("default_react", {}).get(kind, {})
	return str(row.get("ok" if success else "fail", ""))


# --- Counter-moves: the NPC answers back ----------------------------------------------------

func counters() -> Dictionary:
	return DataDB.counters


func _pick_text(v, npc: Node) -> String:
	var t: String = str(v[_rng.randi() % v.size()]) if v is Array else str(v)
	return fill(t, npc)


## Shows `header` plus the NPC's counter-move from data/counters.json (`table` = "counters" or
## "approach"), with choices. Returns false if there is no counter for this key.
func present_counter(npc: Node, key: String, header: String = "", table: String = "counters") -> bool:
	var pool: Array = counters().get(table, {}).get(key, [])
	if pool.is_empty():
		return false
	var tpl: Dictionary = pool[_rng.randi() % pool.size()]
	var ask := _pick_text(tpl.get("ask", "..."), npc)
	var text := (header + "\n\n" if header != "" else "") + "[color=#ffe9a8]" + NPCVoice.say(ask, npc, {}, _rng) + "[/color]"
	var choices := []
	var i := 0
	for c in tpl.get("choices", []):
		var cost := int(c.get("cost", 0))
		var ct := _pick_text(c.get("text", "..."), npc).replace("{cost}", str(cost))
		if c.has("chance"):
			ct += "  [%d%%]" % roundi(chance_of(c, npc) * 100.0)
		var ok := Saga.choice_ok(c) if c.has("requires") else true
		if ok:
			choices.append({"id": "c%d" % i, "text": ct, "disabled": cost > 0 and not Game.can_afford(cost)})
		i += 1
	choices.append({"id": "leave", "text": _pick_text(tpl.get("leave", ["Walk away", "Leave it there", "Say nothing and go"]), npc)})
	EventBus.dialogue_requested.emit(npc.npc_name, text, choices, _on_counter_choice.bind(npc, tpl))
	return true


func _on_counter_choice(choice_id: String, npc: Node, tpl: Dictionary) -> void:
	if not is_instance_valid(npc) or not choice_id.begins_with("c"):
		if is_instance_valid(npc) and tpl.has("leave_effects"):
			_apply_counter_effects(npc, tpl["leave_effects"])
		return
	var list: Array = tpl.get("choices", [])
	var idx := int(choice_id.substr(1))
	if idx < 0 or idx >= list.size():
		return
	var c: Dictionary = list[idx]
	var cost := int(c.get("cost", 0))
	if cost > 0 and not Game.spend(cost):
		return
	var before_rel: String = npc.relation_label()
	var before_att: int = int(npc.attitude)
	var success := _rng.randf() < chance_of(c, npc) if c.has("chance") else true
	if force_outcome != null and c.has("chance"):
		success = bool(force_outcome)
	var reply = c.get("reply", ["..."]) if success else c.get("fail_reply", c.get("reply", ["..."]))
	var effects: Dictionary = c.get("effects", {}) if success else c.get("fail_effects", {})
	var text := NPCVoice.say(_pick_text(reply, npc), npc, {}, _rng)
	var result_lines := Encounters.apply_effects(_dsl_only(effects))
	text += _apply_counter_effects(npc, effects)
	if c.has("verb") and success:
		Causality.record(str(c["verb"]), {"target": npc.npc_name, "target_faction": npc.faction, "position": (npc as Node3D).global_position})
	if not result_lines.is_empty():
		text += "\n[color=#ffd23e]" + "  ".join(PackedStringArray(result_lines)) + "[/color]"
	var impact: Array[String] = []
	if is_instance_valid(npc):
		if effects.has("react"):
			var r := str(npc.react(str(effects["react"])))
			if r != "":
				impact.append(r)
		var change := str(npc.after_interaction(before_rel, before_att))
		if change != "":
			impact.append(change)
	if not impact.is_empty():
		text += "\n\n" + _impact_block(impact)
	EventBus.interaction_done.emit("counter", success, npc)
	EventBus.dialogue_requested.emit(npc.npc_name, text, [], Callable())


## NPC-side effects shared by counters and approaches (plus "grudge": "now"/"clear").
func _apply_counter_effects(npc: Node, effects: Dictionary) -> String:
	var extra := _apply_npc_effects(npc, effects)
	match str(effects.get("grudge", "")):
		"now":
			npc.grudge = true
			npc._grudge_wait = 0.5
			npc.attitude = mini(int(npc.attitude), -20)
		"clear":
			npc.grudge = false
	if effects.has("owes"):
		npc.owes_favour = bool(effects["owes"])
		npc._favour_wait = _rng.randf_range(20.0, 40.0)
	if effects.get("stay", false):
		npc._leaving = false
	if effects.get("unban", false):
		npc.banned = false
		npc.attitude = maxi(int(npc.attitude), -30)
	if effects.get("unrob", false):
		npc.robbed = false
	if effects.get("unspook", false):
		npc.spooked_until = 0.0
	return extra


## A verb tried on someone who is on the phone to Paragon: win them over and the call dies,
## botch it and they talk faster.
func _witness_outcome(npc: Node, verb_id: String, success: bool) -> String:
	if npc.state != "reporting":
		return "[color=#7dff4a]CALL CUT - %s hangs up.[/color]" % npc.npc_name
	var kind := str(NPCVoice.reactions().get("verb_kind", {}).get(verb_id, "talk"))
	if success and kind not in ["theft", "fight"]:
		npc.witness.silence("talked")
		if kind in ["charity", "deal"]:
			npc.make_loyal()
		elif kind == "threat":
			npc.scared_until = Game.play_time + 150.0
		return "[color=#7dff4a]CALL CUT - %s hangs up and won't report you.[/color]" % npc.npc_name
	npc.witness.progress = minf(0.95, npc.witness.progress + 0.3)
	return "[color=#ff5a5a]That made it worse - they talk faster (%d%% through the call).[/color]" % roundi(npc.witness.progress * 100.0)


## Who saw that, and how they took it.
func _bystander_lines(npc: Node) -> Array[String]:
	var tally := {}
	var n := 0
	for o in get_tree().get_nodes_in_group("npc"):
		if o == npc or not ("memories" in o) or o.memories.is_empty():
			continue
		var m: Dictionary = o.memories[0]
		if str(m.get("target", "")) == str(npc.npc_name) and absf(float(m.get("t", -99.0)) - Game.play_time) < 0.6:
			n += 1
			tally[m.stance] = int(tally.get(m.stance, 0)) + 1
	if n == 0:
		return []
	var parts: Array[String] = []
	for st in ["approve", "amused", "disapprove", "fear"]:
		if tally.has(st):
			parts.append("%d %s" % [tally[st], {"approve": "approve", "amused": "amused", "disapprove": "disapprove", "fear": "scared"}[st]])
	return ["Seen by %d %s: %s. Word will spread on %s." % [n, "person" if n == 1 else "people", ", ".join(parts), Game.location_name]]


## Everyone else still on the phone about you.
func _other_callers(npc: Node) -> Array[String]:
	var others: Array[String] = []
	for w in get_tree().get_nodes_in_group("witness"):
		if is_instance_valid(w) and w.is_reporting() and w.get_parent() != npc:
			others.append("%s (%d%%)" % [str(w.get_parent().get("npc_name") if w.get_parent().get("npc_name") else w.get_parent().name), roundi(w.progress * 100.0)])
	if others.is_empty():
		return []
	return ["[color=#ffd23e]Still calling it in: %s[/color]" % ", ".join(others)]


func _dsl_only(effects: Dictionary) -> Dictionary:
	var out := {}
	for k in ["credits", "hp", "rep", "bounty", "items", "air_debt", "flag", "skill_points", "mishap", "ai"]:
		if effects.has(k):
			out[k] = effects[k]
	# Items with 0 (placeholder) are dropped; negative counts never go below zero.
	if out.has("items"):
		var items := {}
		for it in out["items"]:
			var n := int(out["items"][it])
			if n > 0 or (n < 0 and Game.item_count(it) > 0):
				items[it] = n
		out["items"] = items
	return out


func _apply_npc_effects(npc: Node, e: Dictionary) -> String:
	var extra := ""
	if e.has("attitude"):
		npc.attitude = clampi(int(npc.attitude) + int(e["attitude"]), -100, 100)
	if e.has("discount"):
		npc.discount = clampf(float(npc.discount) + float(e["discount"]), -0.5, 0.6)
	if e.has("fame"):
		Game.flags["fame"] = int(Game.flags.get("fame", 0)) + int(e["fame"])
		extra += "\n[color=#ff3ec8]Fame %+d (now %d)[/color]" % [int(e["fame"]), int(Game.flags["fame"])]
	if e.has("followers"):
		Game.flags["followers"] = int(Game.flags.get("followers", 0)) + int(e["followers"])
		extra += "\n[color=#7dff4a]A follower joins your cause (%d)[/color]" % int(Game.flags["followers"])
	if e.has("witness_slow"):
		var key := "informants_" + Game.location_id
		Game.flags[key] = minf(1.5, float(Game.flags.get(key, 0.0)) + float(e["witness_slow"]))
	if e.get("rumor", false):
		extra += "\n\n" + rumor(npc)
	if e.get("rumor2", false):
		extra += "\n" + rumor(npc)
	if e.get("street_rep", false):
		extra += "\n\n" + NPCVoice.street_rep(npc, _rng)
	if e.has("forget"):
		# They let go of what they saw ("forget" = kinds, or "all").
		var keep: Array = []
		for m in npc.memories:
			if str(e["forget"]) != "all" and not (e["forget"] as Array).has(str(m.get("kind", ""))):
				keep.append(m)
		npc.memories = keep
	if e.get("need_hint", false):
		extra += "\n[i](They'd remember anyone who helped with that.)[/i]"
	match str(e.get("npc", "")):
		"silenced":
			npc.make_loyal()
		"informant":
			npc.make_loyal()
			npc.name_label.text = npc.npc_name + "\n<YOUR INFORMANT>"
		"flee":
			npc.flee_from_player()
		"angry":
			npc.attitude = mini(int(npc.attitude), -30)
	return extra


# --- Rumours ------------------------------------------------------------------------------

func rumor(npc: Node = null) -> String:
	var r: Dictionary = npc_text().get("rumors", {})
	var pools := ["planet", "tips"]
	if Saga.index < Saga.beats.size():
		pools += ["saga", "saga"]
	if Stories.has_local(Game.location_id):
		pools += ["local", "local"]
	var goal := str(Game.flags.get("goal", ""))
	if goal == "sibling":
		pools.append("personal_sibling")
	if goal == "love":
		pools.append("personal_love")
	var heads := Causality.latest_headlines(1)
	if not heads.is_empty() and _rng.randf() < 0.25:
		return "\"Lumen keeps running this: '%s'\"" % heads[0]
	if _rng.randf() < 0.2:
		var n := Copy.make("news", _rng).to_lower()
		return "\"Did you hear? %s. %s\"" % [n.substr(0, 1).to_upper() + n.substr(1), ["Unbelievable.", "Classic.", "Of course they did.", "Lumen says it's fine.", "I'm not even surprised."][_rng.randi() % 5]]
	var pool: Array = r.get(pools[_rng.randi() % pools.size()], r.get("tips", ["\"Nothing ever happens here.\""]))
	var line: String = pool[_rng.randi() % pool.size()]
	return line.format(_rumor_vars())


func _rumor_vars() -> Dictionary:
	var vars := {}
	var ally := Saga.persona_by_role("ally")
	var ant := Saga.persona_by_role("antagonist")
	var lt := Saga.persona_by_role("lieutenant")
	vars["ally"] = ally.get("name", "someone")
	vars["antagonist"] = ant.get("name", "somebody important")
	vars["antagonist_title"] = Saga.world.get("antagonist_title", "VP of Something")
	vars["lieutenant"] = lt.get("name", "a fixer")
	vars["macguffin"] = Saga.world.get("macguffin", "something valuable")
	vars["scheme"] = Saga.world.get("scheme", "buy the sky")
	vars["objective_planet"] = Game.planet_by_id(Saga.objective_planet()).get("name", "somewhere")
	var others := Game.galaxy.filter(func(p): return p.get("id", "") != Game.location_id)
	if not others.is_empty():
		var o: Dictionary = others[_rng.randi() % others.size()]
		vars["other_planet"] = o.get("name", "?")
		vars["other_crisis"] = str(PlanetGenerator.layer(o, "crises").get("name", "trouble")).to_lower()
		var ctrl := str(o.get("controller", ""))
		vars["other_controller"] = DataDB.faction_name(ctrl) if ctrl != "" else "nobody (lawless)"
	var local := Stories.local_info(Game.location_id)
	vars["local_hint"] = local.get("hint", "Something about the bills.")
	vars["local_name"] = local.get("leader", "the locals")
	return vars


# --- Venues (shops, bars, clinics... behind every sign) ------------------------------------

var _venue_ctx := {}


func venue_for_sign(sign_text: String) -> String:
	var signs: Dictionary = DataDB.venues.get("signs", {})
	if signs.has(sign_text):
		return signs[sign_text]
	# Corporate storefronts show the owner's short name.
	for fid in DataDB.factions:
		if str(DataDB.factions[fid].get("short", "")) == sign_text:
			return "corp_store"
	return ""


func open_venue(venue_id: String, sign_text: String, faction: String, door: Node = null) -> void:
	var v: Dictionary = DataDB.venues.get("venues", {}).get(venue_id, {})
	if v.is_empty():
		return
	Tips.show("shops")
	FirstDay.done("shop")
	var keeper: Node = door.get_meta("keeper") if door and door.has_meta("keeper") else null
	if keeper != null and (not is_instance_valid(keeper) or keeper.state == "dead"):
		keeper = null
	_venue_ctx = {"id": venue_id, "sign": sign_text, "faction": faction, "keeper": keeper}
	var title := "%s  //  %s" % [sign_text, v.get("name", "")]
	var greet: Array = v.get("greet", ["..."])
	var scene := Copy.expand(str(greet[_rng.randi() % greet.size()]), _rng).split("\n")[0]
	if keeper == null and _keeper_dead(venue_id, sign_text):
		_closed_shop(sign_text)
		return
	if keeper != null:
		title = "%s  //  %s" % [sign_text, keeper.npc_name]
		if keeper.state == "reporting":
			keeper._talk_witness()
			return
		if keeper.is_banned():
			present_counter(keeper, "keeper_banned", scene, "venue")
			return
		keeper.visits += 1
		keeper.refresh_label()
	var mult := float(keeper.price_mult()) if keeper else 1.0
	var text := scene + "\n" + (_keeper_opening(keeper, venue_id) if keeper else Copy.expand("#%s_keeper#" % venue_id, _rng))
	if keeper and absf(mult - 1.0) >= 0.03:
		var why := "they like you" if mult < 1.0 else "they don't like you"
		if keeper.is_scared():
			why = "they're scared of you"
		elif keeper.visits >= 3 and mult < 1.0:
			why = "you're a regular"
		text += "\n[color=#ffd23e]> Your prices here: %+d%% (%s)[/color]" % [roundi((mult - 1.0) * 100.0), why]
	var choices := []
	for o in v.get("options", []):
		if not Saga.choice_ok(o) or (o.get("once", false) and _venue_used(venue_id, str(o.id))):
			continue
		var t := str(o.get("text", o.id))
		var base := int(o.get("cost", 0))
		var cost := _venue_cost(o)
		if base > 0 and cost != base:
			t = t.replace("%d cr" % base, "%d cr" % cost).replace("bet %d" % base, "bet %d" % cost)
		if o.has("chance"):
			t += "  [%d%%]" % roundi(chance_of(o, keeper) * 100.0)
		choices.append({"id": o.id, "text": t, "disabled": cost > 0 and not Game.can_afford(cost)})
	if keeper:
		# Deal with the owner themself: haggle, charm, lean on them, pull rank...
		var verbs_here := choices_for(keeper, "merchant").filter(func(c): return not c.get("disabled", false))
		for c in verbs_here.slice(0, 3):
			c["text"] = "(%s) %s" % [keeper.npc_name, c["text"]]
			choices.append(c)
	choices.append({"id": "leave", "text": "Leave"})
	EventBus.dialogue_requested.emit(title, text, choices, _on_venue_choice)


## What the owner says when you walk in: what they saw you do, how they feel, whether you're a regular.
func _keeper_opening(keeper: Node, venue_id: String) -> String:
	if not keeper.memories.is_empty() and _rng.randf() < 0.6:
		return NPCVoice.recall(keeper, keeper.memories[0], _rng)
	var sym := "keeper_greet_" + NPCVoice.mood(keeper)
	if keeper.fan:
		sym = "keeper_fan"
	elif keeper.partner:
		sym = "keeper_partner"
	elif keeper.visits >= 3 and keeper.attitude >= 0:
		sym = "keeper_regular"
	elif NPCVoice.mood(keeper) == "neutral" and _rng.randf() < 0.5 and Copy.has(venue_id + "_keeper"):
		return NPCVoice.say("#%s_keeper#" % venue_id, keeper, {}, _rng)  # already written as a scene line
	return "\"%s\"" % NPCVoice.say("#%s#" % sym, keeper, {}, _rng)


func _venue_cost(o: Dictionary) -> int:
	var base := int(o.get("cost", 0))
	var keeper = _venue_ctx.get("keeper")
	if base <= 0 or keeper == null or not is_instance_valid(keeper):
		return base
	return maxi(1, roundi(base * float(keeper.price_mult())))


func _keeper_dead(venue_id: String, sign_text: String) -> bool:
	var store: Dictionary = Game.flags.get("keepers_" + Game.location_id, {})
	return store.get("%s|%s" % [venue_id, sign_text], {}).get("dead", false)


## The owner is gone: the shop is dark, and what you do with that says something about you.
func _closed_shop(sign_text: String) -> void:
	var store: Dictionary = Game.flags.get("keepers_" + Game.location_id, {})
	var who := str(store.get("%s|%s" % [_venue_ctx.id, sign_text], {}).get("name", "the owner"))
	var text := "The shutters of %s are half down. Nobody's behind the counter any more. Someone has left flowers and a photo of %s by the door." % [sign_text, who]
	var choices := [{"id": "loot", "text": "Empty the till"}, {"id": "flowers", "text": "Leave something for the family (10 cr)", "disabled": not Game.can_afford(10)},
		{"id": "leave", "text": "Leave"}]
	EventBus.dialogue_requested.emit(sign_text, text, choices, _on_closed_choice)


func _on_closed_choice(choice: String) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	match choice:
		"loot":
			var cr := _rng.randi_range(30, 90)
			Game.add_credits(cr)
			Causality.record("theft", {"target": str(_venue_ctx.sign), "position": p.global_position if p else Vector3.ZERO})
			EventBus.dialogue_requested.emit(str(_venue_ctx.sign), "The till sticks, then gives. %d credits. The photo by the door watches you.\n[color=#ffd23e]+%d credits[/color]" % [cr, cr], [], Callable())
		"flowers":
			if Game.spend(10):
				NPCVoice.add_street_memory("charity")
				Saga.axes["mercy"] = float(Saga.axes.get("mercy", 0.0)) + 0.5
				EventBus.dialogue_requested.emit(str(_venue_ctx.sign), "You leave credits under the photo. Later, someone on the street says your name kindly.\n[color=#9adfff]> The street will remember this.[/color]", [], Callable())


func _venue_used(venue_id: String, opt: String) -> bool:
	var used: Dictionary = Game.flags.get("venue_once", {})
	return used.has("%s:%s:%s" % [Game.location_id, venue_id, opt])


func _on_venue_choice(choice: String) -> void:
	if choice == "leave" or _venue_ctx.is_empty():
		return
	var keeper = _venue_ctx.get("keeper")
	if keeper != null and not is_instance_valid(keeper):
		keeper = null
	if choice.begins_with("act:"):
		if keeper:
			resolve(keeper, choice.substr(4))
		return
	var vid: String = _venue_ctx.id
	var v: Dictionary = DataDB.venues.get("venues", {}).get(vid, {})
	var o: Dictionary = {}
	for x in v.get("options", []):
		if x.get("id", "") == choice:
			o = x
	if o.is_empty():
		return
	var cost := _venue_cost(o)
	if cost > 0 and not Game.spend(cost):
		return
	if o.get("once", false):
		var used: Dictionary = Game.flags.get("venue_once", {})
		used["%s:%s:%s" % [Game.location_id, vid, choice]] = true
		Game.flags["venue_once"] = used
	var success := _rng.randf() < chance_of(o, keeper)
	if force_outcome != null and o.has("fail"):
		success = bool(force_outcome)
	var r: Dictionary = o.get("success" if success else "fail", o.get("success", {}))
	var text := Saga.fill(str(r.get("text", "...")))
	var lines := Encounters.apply_effects(r.get("effects", {}))
	var ax: Dictionary = r.get("axes", {})
	for k in ax:
		Saga.axes[k] = float(Saga.axes.get(k, 0.0)) + float(ax[k])
	if r.has("fame"):
		Game.flags["fame"] = Saga.fame() + int(r.fame)
		lines.append("Fame +%d" % int(r.fame))
	if r.has("followers"):
		Game.flags["followers"] = Saga.followers() + int(r.followers)
		lines.append("+%d follower%s" % [int(r.followers), "" if int(r.followers) == 1 else "s"])
	if r.has("record"):
		var p := get_tree().get_first_node_in_group("player") as Node3D
		Causality.record(str(r.record), {"target": str(_venue_ctx.sign), "target_faction": str(_venue_ctx.faction), "position": p.global_position if p else Vector3.ZERO})
	for i in int(r.get("rumor", 0)):
		text += "\n\n" + rumor(null)
	if r.get("fortune", false):
		text += "\n\n[color=#c07dff]" + fortune() + "[/color]"
	if r.get("music", false):
		Audio.play_music(["odd_duck_theme", "neon_city", "bog_hymn", "glacier_static", "rust_run", "crystal_lull"][_rng.randi() % 6])
	if not lines.is_empty():
		text += "\n[color=#ffd23e]" + "  ".join(PackedStringArray(lines)) + "[/color]"
	if r.get("save", false):
		Game.save_game()
		text += "\n[color=#7dff4a]Progress saved.[/color]"
	EventBus.interaction_done.emit("venue:" + vid + ":" + choice, success, null)
	if r.has("shop"):
		Game.shop_discount = (1.0 - float(keeper.price_mult())) if keeper else 0.0
		EventBus.shop_requested.emit(str(_venue_ctx.sign), str(_venue_ctx.faction), r.shop)
		return
	if keeper and keeper.state != "dead":
		_keeper_reacts(keeper, vid, choice, success, text)
		return
	EventBus.dialogue_requested.emit(str(_venue_ctx.sign), text, [], Callable())


## The owner was watching: their mood, prices, memory and next move all follow from what you just did.
func _keeper_reacts(keeper: Node, vid: String, choice: String, success: bool, text: String) -> void:
	var rx := NPCVoice.reactions()
	var kind := str(rx.get("venue_option_kind", {}).get("%s:%s" % [vid, choice], "deal"))
	var ok := "ok" if success else "fail"
	var before_rel: String = keeper.relation_label()
	var before_att: int = int(keeper.attitude)
	var row: Dictionary = rx.get("keeper", {}).get(kind, {})
	keeper.attitude = clampi(int(keeper.attitude) + int(row.get(ok + "_attitude", 0)), -100, 100)
	keeper.witness_act(kind, "me", keeper)
	var impact: Array[String] = []
	var react_kind := str(row.get(ok, ""))
	if react_kind != "":
		var r := str(keeper.react(react_kind))
		if r != "":
			impact.append(r)
	var after := NPCVoice.say("#after_%s_%s#" % [kind, ok], keeper, {}, _rng) if Copy.has("after_%s_%s" % [kind, ok]) else ""
	if after != "":
		text += "\n\"%s\"" % after
	var change := str(keeper.after_interaction(before_rel, before_att))
	if change != "":
		impact.append(change)
	var mult := float(keeper.price_mult())
	if absf(mult - 1.0) >= 0.03:
		impact.append("Your prices at %s: %+d%%" % [str(_venue_ctx.sign), roundi((mult - 1.0) * 100.0)])
	if not impact.is_empty():
		text += "\n\n" + _impact_block(impact)
	var key := "keeper_%s_%s" % [kind, ok]
	if should_counter(keeper, key):
		keeper.set_meta("countered", int(keeper.get_meta("countered", 0)) + 1)
		if present_counter(keeper, key, text, "venue"):
			return
		if present_counter(keeper, "%s_%s" % [kind, ok], text):
			return
	EventBus.dialogue_requested.emit(keeper.npc_name, text, [], Callable())


## Cryptic but true: hints about where the story goes and how it could end.
func fortune() -> String:
	var pool := []
	if not Saga.is_complete():
		var b := Saga.current()
		var pname: String = Game.planet_by_id(Saga.objective_planet()).get("name", "?")
		pool.append("\"Your road bends toward %s. Something waits there: %s.\"" % [pname, str(b.get("title", "a door")).to_lower()])
		if int(Saga.state.get("ally_trust", 0)) <= 0 and Saga.index < 5:
			pool.append("\"The one who found you... their smile hides an invoice. Ask them what they owe, before they ask you.\"")
		if Saga.index < 6:
			pool.append("\"At the end, a thing in your hands. Burn it, sell it, give it, keep it - the cards don't care. The cards are watching anyway.\"")
	var e: Dictionary = Saga.data().get("early", {}).get(Game.tags.get("motivation", ""), {})
	if not e.is_empty():
		pool.append("\"There is a shorter road to what you want. It looks like this: '%s'. Few take it.\"" % Saga.fill(str(e.get("text", ""))))
	var ax := Saga.axes
	if float(ax.get("mercy", 0)) >= 3:
		pool.append("\"The gutters already sing about you. Keep going, saint.\"")
	elif float(ax.get("mercy", 0)) <= -3:
		pool.append("\"I see blood on the ledger. Yours will come due.\"")
	if pool.is_empty():
		pool.append("\"I see... a debt. I always see a debt.\"")
	return pool[_rng.randi() % pool.size()]
