extends SceneTree
## Counts how many DISTINCT endings the data can compose (Saga.compose_ending).
##   godot --headless --path . --script res://tools/count_endings.gd
## An ending = resolution slide x antagonist fate x lieutenant fate x ally fate x
## personal outcome (per Motivation) x legacy title, plus optional planet-story and
## class/age coda slides. Gated options (heir / hacker / preacher...) are counted
## because SOME character can reach them; not every character can reach every one.


func _initialize() -> void:
	var saga: Dictionary = _json("res://data/saga.json")
	var stories: Dictionary = _json("res://data/stories.json")
	var tags: Dictionary = _json("res://data/tags.json")
	var motivations: Array = tags.get("motivation", {}).keys()
	var finale: Array = saga.get("finale", [])
	var normal_finales := 0
	var defector_finales := 0
	for f in finale:
		var defector_only: bool = f.get("requires_state", {}).get("defected", false)
		if defector_only:
			defector_finales += 1
		else:
			normal_finales += 1
		if f.id in ["leverage", "walk_away", "personal_use"]:
			defector_finales += 1
	var ant_fates := _fates(saga.get("surrender", {}).get("antagonist", []))
	var lt_fates := _fates(saga.get("surrender", {}).get("lieutenant", []))
	var ally_fates := _fates(saga.get("twist_choices", []))
	var legacy: int = saga.get("legacy", []).size()
	var personal_outcomes := 3
	var early: int = saga.get("early", {}).size()
	var per_motivation := normal_finales * ant_fates * lt_fates * ally_fates * personal_outcomes * legacy
	var defector := defector_finales * 1 * lt_fates * 1 * personal_outcomes * legacy
	var early_paths := 1 * (lt_fates + 1) * (ally_fates + 1) * 2 * legacy
	var total := motivations.size() * (per_motivation + defector) + early * early_paths
	var conservative := motivations.size() * normal_finales * ant_fates * ally_fates * personal_outcomes
	var local: Dictionary = stories.get("local", {})
	var planet_outcomes := 0
	for k in local:
		planet_outcomes += local[k].get("outcomes", {}).size()
	var origins := 1
	for cat in ["class", "age", "background", "personality", "motivation", "secret"]:
		origins *= tags.get(cat, {}).size()
	print("=== ODD-SPACE ending space ===")
	print("motivations: %d   finales: %d (+%d defector)   antagonist fates: %d   lieutenant fates: %d   ally fates: %d" % [
		motivations.size(), normal_finales, defector_finales, ant_fates, lt_fates, ally_fates])
	print("personal outcomes: %d per motivation   legacy titles: %d   early endings: %d" % [personal_outcomes, legacy, early])
	print("distinct composed endings: %d" % total)
	print("conservative (resolution x antagonist x ally x personal, per motivation only): %d" % conservative)
	print("planet-story outcomes: %d (each visited planet adds its own slide)   street events: %d" % [planet_outcomes, stories.get("street", []).size()])
	print("character origins (6 tags): %d   x 8 starts = %d" % [origins, origins * 8])
	quit(0)


func _fates(list: Array) -> int:
	var seen := {}
	for c in list:
		seen[str(c.get("fate", c.get("id", "")))] = true
	return seen.size()


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
