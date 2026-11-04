class_name PlanetGenerator
extends RefCounted
## Procedural Planet Matrix: every planet is 4 stacked layers rolled from a seed:
##   1. environment  (look, palette, props, air multiplier)
##   2. controller   (one of the 5 Consortium factions, or "lawless")
##   3. crisis       (economic situation: prices, air, enemy density)
##   4. anomaly      (local weirdness: gravity, fog, ad ghosts, reverse rain...)
## Same seed -> same planet, so saves only need the dictionary below.

const LAWLESS := ""


static func generate_galaxy(galaxy_seed: int, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed
	var out := []
	var used_names := {}
	for i in count:
		var p := generate(rng.randi(), i)
		while used_names.has(p.name):
			p.name += " II"
		used_names[p.name] = true
		# Lay planets out left -> right on the star map with some vertical jitter.
		var x := (float(i) + 0.5) / float(count)
		p["map_pos"] = [x + rng.randf_range(-0.04, 0.04), rng.randf_range(0.18, 0.82)]
		p["difficulty"] = 1 + int(i * 3 / float(count))
		out.append(p)
	return out


static func generate(planet_seed: int, index: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed
	var data: Dictionary = DataDB.planets
	var env: Dictionary = _pick(rng, data.get("environments", []))
	var crisis: Dictionary = _pick(rng, data.get("crises", []))
	var anomaly: Dictionary = _pick(rng, data.get("anomalies", []))
	var controllers: Array = DataDB.faction_ids().duplicate()
	controllers.append(LAWLESS)
	var controller: String = controllers[rng.randi() % controllers.size()]
	# Crises lean toward their favoured faction being in charge (60%).
	var favored: String = crisis.get("favored_faction", "")
	if favored != "" and rng.randf() < 0.6:
		controller = favored
	var planet := {
		"id": "planet_%d_%d" % [index, planet_seed % 100000],
		"seed": planet_seed,
		"name": _make_name(rng, data.get("names", {})),
		"environment": env.get("id", ""),
		"controller": controller,
		"crisis": crisis.get("id", ""),
		"anomaly": anomaly.get("id", ""),
		"air_mult": float(env.get("air_mult", 1.0)) * float(crisis.get("air_mult", 1.0)),
		"visited": false,
	}
	return planet


static func layer(planet: Dictionary, kind: String) -> Dictionary:
	## kind: "environments" | "crises" | "anomalies"
	var key := {"environments": "environment", "crises": "crisis", "anomalies": "anomaly"}[kind] as String
	for entry in DataDB.planets.get(kind, []):
		if entry.get("id", "") == planet.get(key, ""):
			return entry
	return {}


static func controller_name(planet: Dictionary) -> String:
	var c: String = planet.get("controller", "")
	return "Lawless Zone" if c == LAWLESS else DataDB.faction_name(c)


static func describe(planet: Dictionary) -> String:
	var env := layer(planet, "environments")
	var crisis := layer(planet, "crises")
	var anomaly := layer(planet, "anomalies")
	return "[b]%s[/b]\n%s\n\n[color=#ffd23e]CONTROL:[/color] %s\n[color=#ff3ec8]CRISIS:[/color] %s - %s\n[color=#3ee6ff]ANOMALY:[/color] %s - %s" % [
		env.get("name", "?"), env.get("desc", ""),
		controller_name(planet),
		crisis.get("name", "?"), crisis.get("desc", ""),
		anomaly.get("name", "?"), anomaly.get("desc", ""),
	]


static func _pick(rng: RandomNumberGenerator, entries: Array) -> Dictionary:
	if entries.is_empty():
		return {}
	var weights := PackedFloat32Array()
	for e in entries:
		weights.append(float(e.get("weight", 1)))
	return entries[rng.rand_weighted(weights)]


static func _make_name(rng: RandomNumberGenerator, names: Dictionary) -> String:
	var pre: Array = names.get("prefix", ["Nova"])
	var mid: Array = names.get("middle", [""])
	var suf: Array = names.get("suffix", ["prime"])
	var brand: Array = names.get("brand", [])
	var core: String = pre[rng.randi() % pre.size()] + mid[rng.randi() % mid.size()] + suf[rng.randi() % suf.size()]
	core = core.capitalize().replace(" ", "")
	if not brand.is_empty() and rng.randf() < 0.6:
		return "%s '%s'" % [core, brand[rng.randi() % brand.size()]]
	return "%s-%d" % [core, rng.randi_range(2, 99)]
