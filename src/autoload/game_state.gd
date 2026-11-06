extends Node
## "Game" autoload: the player's persistent run state + save/load.
## Every other system with persistent state implements reset() / to_save() /
## from_save(data) and is wired into _systems() below.

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 2  ## 2: weapons/equip + keepers/street flags (older saves load with defaults)
const AIR_TICK_SECONDS := 10.0
const AIR_BASE_COST := 1.0
const AUTOSAVE_SLOT := 0
const SETTINGS_PATH := "user://settings.json"

var player_name := "Drifter"
var tags := {"class": "", "age": "", "background": "", "personality": "", "motivation": "", "secret": ""}
var shop_discount := 0.0  ## per-conversation merchant discount (Interactions)
var age := 30  ## exact age in years (inside the age tag's bracket)
## Player appearance: {"variant": "h00", "colors": {...}} (see CharacterLook).
var player_look: Dictionary = {}
var credits := 0
var air_debt := 0
var hp := 100.0
var inventory: Dictionary = {}  # item_id -> count
var skill_points := 0
var perks: Array = []
var flaws: Array = []
var flags: Dictionary = {}
var world_seed := 0
var galaxy: Array = []  # planet dictionaries (see PlanetGenerator)
var location_id := "station_lot47"
var location_name := "Cold Storage Lot 47"
var current_planet: Dictionary = {}  # empty while on the station / ship
var play_time := 0.0
var stats := StatBlock.new()
var has_active_run := false
## Per-device settings (not part of save slots).
var settings := {"dof_mode": "tilt_shift", "touch": "auto", "music_db": -8.0, "sfx_db": -4.0,
	"difficulty": "normal", "graphics": "medium" if OS.has_feature("mobile") else "high", "ui_scale": 1.0,
	"followups": "sometimes", "tips": "on", "tips_seen": [], "hud_fade": "on"}

## Levels switch this on: you only pay for air while breathing it.
var air_billing_active := false
var _air_timer := 0.0
var _air_debt_mishap_marker := 0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary:
			settings.merge(parsed, true)


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))


func _process(delta: float) -> void:
	if not has_active_run or get_tree().paused:
		return
	play_time += delta
	if air_billing_active:
		_air_timer += delta
		if _air_timer >= AIR_TICK_SECONDS:
			_air_timer = 0.0
			_bill_air()


# --- New game / reset -------------------------------------------------------------

## start_planet_id: "" = thaw in Cold Storage Lot 47; otherwise you're a native of that planet.
func new_game(p_name: String, p_tags: Dictionary, seed_value: int = -1, look: Dictionary = {}, start_planet_id: String = "", p_age: int = -1) -> void:
	reset_all()
	player_name = p_name if p_name.strip_edges() != "" else "Drifter"
	tags = p_tags.duplicate()
	for cat in Origin.CATEGORIES:
		if not tags.has(cat) or str(tags[cat]) == "":
			tags[cat] = _default_tag(cat)
	var bracket := Origin.age_range(tags.get("age", "young"))
	age = clampi(p_age, bracket.x, bracket.y) if p_age > 0 else Origin.random_age(tags.get("age", "young"))
	player_look = look.duplicate(true)
	world_seed = seed_value if seed_value >= 0 else randi()
	Origin.apply_new_game(tags)
	Arsenal.start_kit(tags)
	FirstDay.start()
	hp = max_hp()
	galaxy = PlanetGenerator.generate_galaxy(world_seed, 7)
	location_id = "station_lot47"
	location_name = "Cold Storage Lot 47"
	if start_planet_id != "":
		# Native start: no cryo prologue, locals know your face, a little pocket money.
		flags["native_of"] = start_planet_id
		flags["prologue_woke"] = true
		var home := planet_by_id(start_planet_id)
		if not home.is_empty():
			home["visited"] = true
			var ctrl := str(home.get("controller", ""))
			if ctrl != "":
				Factions.change_rep(ctrl, 12, "hometown", false)
		credits += 40
	Saga.generate(world_seed, start_planet_id)
	has_active_run = true
	EventBus.stats_changed.emit()


## Older saves / callers that only pass the original 3 tags get neutral defaults.
func _default_tag(cat: String) -> String:
	return {"class": "working_poor", "age": "young", "personality": "cynic", "background": "cryo_debtor", "motivation": "pay_debt", "secret": "wanted_alias"}.get(cat, "")


func reset_all() -> void:
	player_name = "Drifter"
	tags = {"class": "", "age": "", "background": "", "personality": "", "motivation": "", "secret": ""}
	age = 30
	player_look = {}
	credits = 0
	air_debt = 0
	inventory = {}
	skill_points = 0
	perks = []
	flaws = []
	flags = {}
	galaxy = []
	current_planet = {}
	play_time = 0.0
	stats = StatBlock.new()
	_air_timer = 0.0
	_air_debt_mishap_marker = 0
	for system in _systems():
		system.reset()


func _systems() -> Array:
	return [Factions, Causality, Crew, FlawPerk, Encounters, Saga, Stories]


# --- Stats helpers -------------------------------------------------------------------

func max_hp() -> float:
	return stats.get_stat("max_hp")


func stat(stat_name: String) -> float:
	return stats.get_stat(stat_name)


func heal(amount: float) -> void:
	hp = clampf(hp + amount, 0.0, max_hp())
	EventBus.player_hp_changed.emit(hp, max_hp())


func has_flag(flag_name: String) -> bool:
	return bool(flags.get(flag_name, false))


# --- Economy ---------------------------------------------------------------------------

func add_credits(amount: int) -> void:
	var old := credits
	credits = maxi(0, credits + amount)
	EventBus.credits_changed.emit(credits, credits - old)


func can_afford(amount: int) -> bool:
	return credits >= amount


## Pays what it can; returns true when the full amount was paid.
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if credits < amount:
		return false
	add_credits(-amount)
	return true


## Shop price after faction standing, perks/flaws and the local economic crisis.
func price_of(item_id: String, seller_faction: String = "") -> int:
	var base := float(DataDB.items.get(item_id, {}).get("price", 10))
	var mult := Factions.price_multiplier(seller_faction) if seller_faction != "" else stat("price_mult")
	if not current_planet.is_empty():
		mult *= float(PlanetGenerator.layer(current_planet, "crises").get("price_mult", 1.0))
		mult *= float(current_planet.get("price_adjust", 1.0))  # set by planet story outcomes
	mult *= 1.0 - shop_discount  # the merchant you're talking to likes (or hates) you
	return maxi(1, roundi(base * mult))


func sell_price_of(item_id: String) -> int:
	return maxi(1, roundi(float(DataDB.items.get(item_id, {}).get("price", 2)) * 0.5))


func add_air_debt(amount: int) -> void:
	air_debt = maxi(0, air_debt + amount)
	EventBus.air_billed.emit(0, air_debt)


func _bill_air() -> void:
	Tips.show("air")
	var mult := stat("air_cost_mult")
	if not current_planet.is_empty():
		mult *= float(current_planet.get("air_mult", 1.0))
		mult *= float(current_planet.get("air_adjust", 1.0))  # planet story outcomes
	var cost := maxi(1, roundi(AIR_BASE_COST * mult))
	if credits >= cost:
		add_credits(-cost)
	else:
		var was_clean := air_debt == 0
		air_debt += cost - credits
		add_credits(-credits)
		if was_clean:
			ShipAI.say("on_air_debt")
		# every 20 credits of fresh debt counts as one 'air_debt' mishap
		if air_debt - _air_debt_mishap_marker >= 20:
			_air_debt_mishap_marker = air_debt
			FlawPerk.report_mishap("air_debt")
	EventBus.air_billed.emit(cost, air_debt)


# --- Inventory -------------------------------------------------------------------------

func add_item(item_id: String, count: int = 1) -> void:
	# Weapons aren't carried as items: picking one up unlocks it in the arsenal.
	var wid := str(DataDB.items.get(item_id, {}).get("weapon", ""))
	if wid != "" and count > 0:
		if not Arsenal.unlock(wid):
			add_credits(roundi(float(DataDB.items[item_id].get("price", 40)) * 0.4))  # a duplicate: sold for parts
		return
	var n: int = int(inventory.get(item_id, 0)) + count
	if n <= 0:
		inventory.erase(item_id)
		n = 0
	else:
		inventory[item_id] = n
	EventBus.inventory_changed.emit(item_id, n)


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func use_item(item_id: String) -> bool:
	if item_count(item_id) <= 0:
		return false
	var def: Dictionary = DataDB.items.get(item_id, {})
	var use: Dictionary = def.get("use", {})
	if use.is_empty():
		return false
	if use.has("heal"):
		heal(float(use["heal"]))
	if use.has("air_debt"):
		add_air_debt(int(use["air_debt"]))
	add_item(item_id, -1)
	EventBus.toast.emit("Used %s" % DataDB.item_name(item_id), Color(0.5, 1, 0.8))
	return true


# --- Location ---------------------------------------------------------------------------

func enter_planet(planet: Dictionary) -> void:
	current_planet = planet
	location_id = planet.get("id", "unknown")
	location_name = planet.get("name", "Unknown")
	EventBus.planet_entered.emit(planet)


func enter_station() -> void:
	current_planet = {}
	location_id = "station_lot47"
	location_name = "Cold Storage Lot 47"


func enter_ship() -> void:
	current_planet = {}
	location_id = "odd_duck"
	location_name = "The Odd Duck"


func planet_by_id(planet_id: String) -> Dictionary:
	for p in galaxy:
		if p.get("id", "") == planet_id:
			return p
	return {}


# --- Save / load --------------------------------------------------------------------------

func save_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


func has_save(slot: int = AUTOSAVE_SLOT) -> bool:
	return FileAccess.file_exists(save_path(slot))


func save_game(slot: int = AUTOSAVE_SLOT) -> bool:
	if not has_active_run:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game": {
			"player_name": player_name, "tags": tags, "age": age, "look": player_look, "credits": credits, "air_debt": air_debt,
			"hp": hp, "inventory": inventory, "skill_points": skill_points, "perks": perks,
			"flaws": flaws, "flags": flags, "world_seed": world_seed, "galaxy": galaxy,
			"location_id": location_id, "location_name": location_name,
			"current_planet": current_planet, "play_time": play_time, "stats": stats.to_save(),
		},
		"factions": Factions.to_save(),
		"causality": Causality.to_save(),
		"crew": Crew.to_save(),
		"flawperk": FlawPerk.to_save(),
		"encounters": Encounters.to_save(),
		"saga": Saga.to_save(),
		"stories": Stories.to_save(),
	}
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func load_game(slot: int = AUTOSAVE_SLOT) -> bool:
	if not has_save(slot):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
	if not parsed is Dictionary:
		push_error("Save file corrupted: %s" % save_path(slot))
		return false
	var data: Dictionary = parsed
	reset_all()
	var g: Dictionary = data.get("game", {})
	player_name = g.get("player_name", "Drifter")
	tags = g.get("tags", tags)
	for cat in Origin.CATEGORIES:
		if not tags.has(cat) or str(tags[cat]) == "":
			tags[cat] = _default_tag(cat)
	age = int(g.get("age", 30))
	player_look = g.get("look", {})
	credits = int(g.get("credits", 0))
	air_debt = int(g.get("air_debt", 0))
	hp = float(g.get("hp", 100.0))
	inventory = g.get("inventory", {})
	for k in inventory.keys():
		inventory[k] = int(inventory[k])
	skill_points = int(g.get("skill_points", 0))
	perks = g.get("perks", [])
	flaws = g.get("flaws", [])
	flags = g.get("flags", {})
	world_seed = int(g.get("world_seed", 0))
	galaxy = g.get("galaxy", [])
	location_id = g.get("location_id", "station_lot47")
	location_name = g.get("location_name", "")
	current_planet = g.get("current_planet", {})
	play_time = float(g.get("play_time", 0.0))
	stats.from_save(g.get("stats", {}))
	Factions.from_save(data.get("factions", {}))
	Causality.from_save(data.get("causality", {}))
	Crew.from_save(data.get("crew", {}))
	FlawPerk.from_save(data.get("flawperk", {}))
	Encounters.from_save(data.get("encounters", {}))
	Saga.from_save(data.get("saga", {}))
	Stories.from_save(data.get("stories", {}))
	has_active_run = true
	EventBus.game_loaded.emit()
	EventBus.stats_changed.emit()
	return true


func save_summary(slot: int) -> String:
	if not has_save(slot):
		return "- empty -"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
	if not parsed is Dictionary:
		return "- corrupted -"
	var g: Dictionary = parsed.get("game", {})
	return "%s  |  %s  |  %d cr  |  %s" % [
		g.get("player_name", "?"), g.get("location_name", "?"),
		int(g.get("credits", 0)), pretty_time(str(parsed.get("saved_at", "")))]


## "2026-11-06T12:35:49" -> "6 Nov, 12:35" (a raw ISO stamp on the title screen looked unfinished).
static func pretty_time(iso: String) -> String:
	var parts := iso.split("T")
	if parts.size() != 2:
		return iso
	var d := parts[0].split("-")
	if d.size() != 3:
		return iso
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s, %s" % [int(d[2]), months[clampi(int(d[1]) - 1, 0, 11)], parts[1].left(5)]
