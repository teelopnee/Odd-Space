extends Node
## Loads every JSON design file in res://data/ once at boot.
## Designers edit the JSON (works fine in the Android editor's script/text view),
## code only reads it. Call reload() after editing at runtime (debug).

const DATA_DIR := "res://data/"

var factions: Dictionary = {}
var tags: Dictionary = {}
var consequences: Dictionary = {}
var planets: Dictionary = {}
var encounters: Dictionary = {}
var crew: Dictionary = {}
var flaws_perks: Dictionary = {}
var ai_lines: Dictionary = {}
var ads: Dictionary = {}
var enemies: Dictionary = {}
var items: Dictionary = {}
var interactions: Dictionary = {}
var stories: Dictionary = {}
var venues: Dictionary = {}
var counters: Dictionary = {}  ## NPC counter-moves + approaches (data/counters.json)


func _ready() -> void:
	reload()


func reload() -> void:
	factions = _load("factions.json")
	tags = _load("tags.json")
	consequences = _load("consequences.json")
	planets = _load("planets.json")
	encounters = _load("encounters.json")
	crew = _load("crew.json")
	flaws_perks = _load("flaws_perks.json")
	ai_lines = _load("ai_lines.json")
	ads = _load("ads.json")
	enemies = _load("enemies.json")
	items = _load("items.json")
	interactions = _load("interactions.json")
	stories = _load("stories.json")
	venues = _load("venues.json")
	counters = _load("counters.json")


func faction_ids() -> Array:
	return factions.keys()


func faction_name(id: String) -> String:
	if factions.has(id):
		return factions[id].get("name", id)
	return "Unaffiliated"


func faction_color(id: String) -> Color:
	if factions.has(id):
		return Color.from_string(factions[id].get("color", "#ffffff"), Color.WHITE)
	return Color(0.8, 0.8, 0.8)


func item_name(id: String) -> String:
	return items.get(id, {}).get("name", id.capitalize())


func _load(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("DataDB: missing %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("DataDB: %s is not a JSON object (syntax error?)" % path)
	return {}
