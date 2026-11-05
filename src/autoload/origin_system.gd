extends Node
## "Origin" autoload - Dynamic Origin & Tag Engine.
## No classes. The player combines 6 tags: class (wealth / standing, incl. Consortium
## heirs), age, background, personality, motivation, secret - over two million combos.
## Tags decide: spawn point, starting credits/debt & items, stat mods, starting rep
## and bounties, story flags, how NPCs react, and which interactions you get
## (data/interactions.json reads the same flags).

const CATEGORIES := ["class", "age", "background", "personality", "motivation", "secret"]
const TITLES := {"class": "CLASS // money & standing", "age": "AGE // how long you've survived", "background": "BACKGROUND // who you were",
	"personality": "PERSONALITY // how you deal", "motivation": "MOTIVATION // what you want", "secret": "SECRET // what they don't know"}


func list(category: String) -> Array:
	var out := []
	var group: Dictionary = DataDB.tags.get(category, {})
	for id in group:
		var t: Dictionary = group[id].duplicate()
		t["id"] = id
		out.append(t)
	return out


func get_tag(category: String, id: String) -> Dictionary:
	return DataDB.tags.get(category, {}).get(id, {})


func random_tags(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var out := {}
	for cat in CATEGORIES:
		var ids: Array = DataDB.tags.get(cat, {}).keys()
		out[cat] = ids[rng.randi() % ids.size()] if not ids.is_empty() else ""
	return out


## Exact age inside an age bracket.
func random_age(bracket: String, rng: RandomNumberGenerator = null) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var r: Array = get_tag("age", bracket).get("range", [25, 35])
	return rng.randi_range(int(r[0]), int(r[1]))


func age_range(bracket: String) -> Vector2i:
	var r: Array = get_tag("age", bracket).get("range", [20, 29])
	return Vector2i(int(r[0]), int(r[1]))


func wealth(tag_set: Dictionary = {}) -> int:
	var ts := tag_set if not tag_set.is_empty() else Game.tags
	return int(get_tag("class", ts.get("class", "")).get("wealth", 1))


func heir_of(tag_set: Dictionary = {}) -> String:
	var ts := tag_set if not tag_set.is_empty() else Game.tags
	return str(get_tag("class", ts.get("class", "")).get("heir_of", ""))


## Short "who you are" line, e.g. "a 67-year-old Paragon Heir street medic".
func persona_line(tag_set: Dictionary = {}, age: int = -1) -> String:
	var ts := tag_set if not tag_set.is_empty() else Game.tags
	var a := age if age >= 0 else Game.age
	return "%d-year-old %s %s, %s" % [a, get_tag("class", ts.get("class", "")).get("name", "?"),
		get_tag("background", ts.get("background", "")).get("name", "?"), str(get_tag("personality", ts.get("personality", "")).get("name", "?")).to_lower()]


## Synergies unlocked by a tag combination.
func synergies_for(tag_set: Dictionary) -> Array:
	var chosen := tag_set.values()
	var out := []
	for syn in DataDB.tags.get("synergies", []):
		var ok := true
		for t in syn.get("tags", []):
			if not chosen.has(t):
				ok = false
				break
		if ok:
			out.append(syn)
	return out


func apply_new_game(tag_set: Dictionary) -> void:
	for cat in CATEGORIES:
		var id: String = tag_set.get(cat, "")
		var t := get_tag(cat, id)
		if t.is_empty():
			continue
		Game.add_credits(int(t.get("credits", 0)))
		if int(t.get("air_debt", 0)) > 0:
			Game.add_air_debt(int(t["air_debt"]))
		var items: Dictionary = t.get("items", {})
		for item_id in items:
			Game.add_item(item_id, int(items[item_id]))
		Game.stats.set_source("tag:" + id, t.get("mods", {}))
		var rep: Dictionary = t.get("rep", {})
		for fid in rep:
			Factions.change_rep(fid, int(rep[fid]), "origin", false)
		var bounty: Dictionary = t.get("bounty", {})
		for fid in bounty:
			Factions.add_bounty(fid, int(bounty[fid]))
		var flags: Dictionary = t.get("flags", {})
		for k in flags:
			Game.flags[k] = flags[k]
	for syn in synergies_for(tag_set):
		Game.stats.set_source("synergy:" + str(syn.get("name", "?")), syn.get("mods", {}))
		Game.flags["synergy_" + str(syn.get("name", "")).to_snake_case()] = true


func spawn_point() -> String:
	return get_tag("background", Game.tags.get("background", "")).get("spawn", "cryo_bay")


func has_tag(id: String) -> bool:
	return Game.tags.values().has(id)


## How much a given NPC likes the player because of who they are (-50..50).
## npc_traits: e.g. ["poor", "worker"]; faction: the NPC's employer.
func npc_reaction(faction: String, npc_traits: Array) -> int:
	var total := 0
	for cat in CATEGORIES:
		var t := get_tag(cat, Game.tags.get(cat, ""))
		var reactions: Dictionary = t.get("reactions", {})
		if faction != "" and reactions.has("faction:" + faction):
			total += int(reactions["faction:" + faction])
		for tr_name in npc_traits:
			if reactions.has("trait:" + str(tr_name)):
				total += int(reactions["trait:" + str(tr_name)])
	return clampi(total, -50, 50)


func origin_story(tag_set: Dictionary = {}) -> String:
	var ts := tag_set if not tag_set.is_empty() else Game.tags
	var parts: Array[String] = []
	var a: int = int(ts.get("age_years", Game.age))
	for cat in CATEGORIES:
		var story: String = get_tag(cat, ts.get(cat, "")).get("story", "")
		if story != "":
			parts.append(story.replace("{age}", str(a)))
	for syn in synergies_for(ts):
		parts.append(str(syn.get("text", "")))
	return " ".join(parts)


func preview(tag_set: Dictionary) -> Dictionary:
	## Summary for the character creator: credits, items, rep, mods text.
	var credits := 0
	var air_debt := 0
	var items := {}
	var rep := {}
	var mods_text: Array[String] = []
	var bounty := 0
	for cat in CATEGORIES:
		var t := get_tag(cat, tag_set.get(cat, ""))
		credits += int(t.get("credits", 0))
		air_debt += int(t.get("air_debt", 0))
		var t_items: Dictionary = t.get("items", {})
		for item_id in t_items:
			items[item_id] = int(items.get(item_id, 0)) + int(t_items[item_id])
		var t_rep: Dictionary = t.get("rep", {})
		for fid in t_rep:
			rep[fid] = int(rep.get(fid, 0)) + int(t_rep[fid])
		var t_bounty: Dictionary = t.get("bounty", {})
		for fid in t_bounty:
			bounty += int(t_bounty[fid])
		var m := StatBlock.describe_mods(t.get("mods", {}))
		if m != "":
			mods_text.append(m)
	var syn_names: Array[String] = []
	for syn in synergies_for(tag_set):
		syn_names.append(str(syn.get("name", "")))
		var m := StatBlock.describe_mods(syn.get("mods", {}))
		if m != "":
			mods_text.append(m)
	return {
		"credits": credits, "air_debt": air_debt, "items": items, "rep": rep, "bounty": bounty,
		"mods": ", ".join(mods_text), "synergies": syn_names,
		"spawn": get_tag("background", tag_set.get("background", "")).get("spawn", "cryo_bay"),
	}
