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
	npc.attitude = clampi(att + rng.randi_range(-8, 8), -60, 60)


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
		if not d.get("roles", ["civilian"]).has(role):
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
	var success := _rng.randf() < chance_of(d, npc)
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
	EventBus.interaction_done.emit(verb_id, success, npc)
	EventBus.dialogue_requested.emit(npc.npc_name, text, [], Callable())
	return success


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


func open_venue(venue_id: String, sign_text: String, faction: String) -> void:
	var v: Dictionary = DataDB.venues.get("venues", {}).get(venue_id, {})
	if v.is_empty():
		return
	_venue_ctx = {"id": venue_id, "sign": sign_text, "faction": faction}
	var greet: Array = v.get("greet", ["..."])
	var title := "%s  //  %s" % [sign_text, v.get("name", "")]
	var choices := []
	for o in v.get("options", []):
		if not Saga.choice_ok(o) or (o.get("once", false) and _venue_used(venue_id, str(o.id))):
			continue
		var text := str(o.get("text", o.id))
		var cost := int(o.get("cost", 0))
		if o.has("chance"):
			text += "  [%d%%]" % roundi(chance_of(o, null) * 100.0)
		choices.append({"id": o.id, "text": text, "disabled": cost > 0 and not Game.can_afford(cost)})
	choices.append({"id": "leave", "text": "Leave"})
	EventBus.dialogue_requested.emit(title, Copy.expand(str(greet[_rng.randi() % greet.size()]), _rng), choices, _on_venue_choice)


func _venue_used(venue_id: String, opt: String) -> bool:
	var used: Dictionary = Game.flags.get("venue_once", {})
	return used.has("%s:%s:%s" % [Game.location_id, venue_id, opt])


func _on_venue_choice(choice: String) -> void:
	if choice == "leave" or _venue_ctx.is_empty():
		return
	var vid: String = _venue_ctx.id
	var v: Dictionary = DataDB.venues.get("venues", {}).get(vid, {})
	var o: Dictionary = {}
	for x in v.get("options", []):
		if x.get("id", "") == choice:
			o = x
	if o.is_empty():
		return
	var cost := int(o.get("cost", 0))
	if cost > 0 and not Game.spend(cost):
		return
	if o.get("once", false):
		var used: Dictionary = Game.flags.get("venue_once", {})
		used["%s:%s:%s" % [Game.location_id, vid, choice]] = true
		Game.flags["venue_once"] = used
	var success := _rng.randf() < chance_of(o, null)
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
		Game.shop_discount = 0.0
		EventBus.shop_requested.emit(str(_venue_ctx.sign), str(_venue_ctx.faction), r.shop)
		return
	EventBus.dialogue_requested.emit(str(_venue_ctx.sign), text, [], Callable())


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
