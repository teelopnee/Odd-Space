extends Node
## "Encounters" autoload - Space Encounters rolled while warping.
## Encounters are pure data (data/encounters.json). This class picks one based
## on context (bounty, debt, crew, reported crimes), formats its text, checks
## which choices are available, rolls chances and applies effects.

var history: Array = []   # encounter ids seen, newest last
var _forced_next := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func reset() -> void:
	history.clear()
	_forced_next = ""


func force_next(encounter_id: String) -> void:
	_forced_next = encounter_id


func get_encounter(id: String) -> Dictionary:
	for e in DataDB.encounters.get("list", []):
		if e.get("id", "") == id:
			return e
	return {}


## Returns an encounter Dictionary, or {} for a quiet warp.
func roll_warp_encounter() -> Dictionary:
	if _forced_next != "":
		var forced := get_encounter(_forced_next)
		_forced_next = ""
		if not forced.is_empty():
			return forced
	if _rng.randf() > float(DataDB.encounters.get("chance_per_warp", 0.7)):
		return {}
	var pool := []
	var weights := []
	for e in DataDB.encounters.get("list", []):
		if not _requirements_met(e.get("requires", {})):
			continue
		var w := float(e.get("weight", 1))
		w += float(e.get("weight_bounty", 0.0)) * Factions.total_bounty()
		if not history.is_empty() and history[-1] == e.get("id", ""):
			w *= 0.2  # avoid back-to-back repeats
		pool.append(e)
		weights.append(w)
	if pool.is_empty():
		return {}
	return pool[_rng.rand_weighted(PackedFloat32Array(weights))]


func _requirements_met(req: Dictionary) -> bool:
	if req.has("min_bounty") and Factions.total_bounty() < int(req["min_bounty"]):
		return false
	if req.has("min_air_debt") and Game.air_debt < int(req["min_air_debt"]):
		return false
	if req.has("min_reported") and Causality.reported_count() < int(req["min_reported"]):
		return false
	if req.has("max_crew") and Crew.size() > int(req["max_crew"]):
		return false
	if req.has("crew_size_min") and Crew.size() < int(req["crew_size_min"]):
		return false
	if req.has("min_credits") and Game.credits < int(req["min_credits"]):
		return false
	if req.has("flag") and not Game.has_flag(req["flag"]):
		return false
	if req.has("has_item") and Game.item_count(req["has_item"]) <= 0:
		return false
	return true


func tokens() -> Dictionary:
	return {
		"bounty": Factions.total_bounty(),
		"credits": Game.credits,
		"air_debt": Game.air_debt,
		"bribe": roundi(60 * Game.stat("bribe_mult")),
		"name": Game.player_name,
	}


func format_text(text: String) -> String:
	return text.format(tokens())


func choice_cost(choice: Dictionary) -> int:
	if choice.get("cost_bounty", false):
		return Factions.total_bounty()
	if choice.get("cost_air_debt", false):
		return Game.air_debt
	var cost := int(choice.get("cost", 0))
	if choice.get("bribe", false):
		cost = roundi(cost * Game.stat("bribe_mult"))
	return cost


func choice_available(choice: Dictionary) -> bool:
	if not _requirements_met(choice.get("requires", {})):
		return false
	return Game.credits >= choice_cost(choice)


func choice_chance(choice: Dictionary) -> float:
	if not choice.has("chance"):
		return 1.0
	var c := float(choice["chance"])
	var mods: Dictionary = choice.get("chance_mods", {})
	for key in mods:
		var k: String = key
		if k.begins_with("flag:") and Game.has_flag(k.substr(5)):
			c += float(mods[key])
		elif k.begins_with("perk:") and Game.perks.has(k.substr(5)):
			c += float(mods[key])
		elif k.begins_with("tag:") and Origin.has_tag(k.substr(4)):
			c += float(mods[key])
	return clampf(c, 0.02, 0.98)


## Resolve the chosen option. Returns {text, lines(Array[String]), success(bool)}.
func resolve(encounter: Dictionary, choice: Dictionary) -> Dictionary:
	history.append(encounter.get("id", ""))
	var cost := choice_cost(choice)
	if cost > 0:
		Game.spend(cost)
	var outcome: Dictionary
	var success := true
	if choice.has("chance"):
		success = _rng.randf() < choice_chance(choice)
		outcome = choice.get("success" if success else "fail", {})
	else:
		outcome = choice.get("result", {})
	var lines := apply_effects(outcome.get("effects", {}))
	EventBus.encounter_finished.emit(encounter.get("id", ""), choice.get("id", ""))
	return {"text": format_text(outcome.get("text", "...")), "lines": lines, "success": success}


## Applies an effects dictionary. Returns human-readable result lines.
func apply_effects(effects: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if effects.has("credits"):
		var amount := int(effects["credits"])
		if amount > 0:
			amount = roundi(amount * Game.stat("loot_mult"))
		Game.add_credits(amount)
		lines.append("%+d credits" % amount)
	if effects.has("credits_pct"):
		var amount := roundi(Game.credits * float(effects["credits_pct"]))
		Game.add_credits(amount)
		lines.append("%+d credits" % amount)
	if effects.has("hp"):
		Game.heal(float(effects["hp"]))
		Game.hp = maxf(Game.hp, 1.0)  # space encounters hurt, but never kill
		lines.append("%+d HP" % int(effects["hp"]))
	var rep: Dictionary = effects.get("rep", {})
	for fid in rep:
		Factions.change_rep(fid, int(rep[fid]), "encounter")
		lines.append("%s %+d" % [DataDB.faction_name(fid), int(rep[fid])])
	var bounty: Dictionary = effects.get("bounty", {})
	for fid in bounty:
		Factions.add_bounty(fid, int(bounty[fid]))
		lines.append("Bounty (%s) %+d" % [DataDB.faction_name(fid), int(bounty[fid])])
	if effects.get("clear_bounty", false):
		Factions.clear_bounties()
		lines.append("All bounties cleared")
	var items: Dictionary = effects.get("items", {})
	for item_id in items:
		Game.add_item(item_id, int(items[item_id]))
		lines.append("%+d %s" % [int(items[item_id]), DataDB.item_name(item_id)])
	if effects.has("air_debt"):
		var before := Game.air_debt
		Game.add_air_debt(int(effects["air_debt"]))
		lines.append("Air debt %+d" % (Game.air_debt - before))
	if effects.has("skill_points"):
		FlawPerk.add_skill_points(int(effects["skill_points"]))
		lines.append("%+d skill points" % int(effects["skill_points"]))
	if effects.has("recruit"):
		var id: String = effects["recruit"]
		if id == "random":
			id = Crew.random_recruit_id()
		if Crew.recruit(id):
			lines.append("%s joined the crew" % Crew.def(id).get("name", id))
		elif Crew.is_full():
			lines.append("(Crew is full - they wave goodbye)")
	var flags: Dictionary = effects.get("flag", {})
	for k in flags:
		Game.flags[k] = flags[k]
	if effects.has("record"):
		var r: Dictionary = effects["record"]
		Causality.record(r.get("verb", "comply"), {
			"target_faction": r.get("target_faction", ""),
			"public": r.get("public", true),
			"location": "deep_space",
			"location_name": "Deep Space",
		})
	if effects.has("mishap"):
		FlawPerk.report_mishap(effects["mishap"])
	if effects.has("ai"):
		ShipAI.say(effects["ai"], {}, true)
	return lines


func to_save() -> Dictionary:
	return {"history": history.duplicate(), "forced": _forced_next}


func from_save(data: Dictionary) -> void:
	reset()
	history = data.get("history", [])
	_forced_next = data.get("forced", "")
