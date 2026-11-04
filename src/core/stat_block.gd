class_name StatBlock
extends RefCounted
## Player stats = BASE + flat adds, then x (1 + summed percents).
## Modifiers are grouped by "source" (tag:xxx, perk:xxx, flaw:xxx, synergy:xxx)
## so they can be removed/replaced cleanly and shown in the UI.
##
## Modifier dictionary format (same as the JSON data):
##   {"add": {"max_hp": 10}, "mul": {"air_cost_mult": -0.2}}

const BASE := {
	"max_hp": 100.0,
	"move_speed": 5.2,
	"roll_speed": 12.0,
	"roll_cooldown": 0.55,
	"roll_iframes": 0.32,
	"parry_window": 0.22,
	"stagger_time": 1.4,
	"damage": 10.0,
	"fire_rate": 4.0,
	"accuracy": 0.85,
	"air_cost_mult": 1.0,
	"price_mult": 1.0,
	"bribe_mult": 1.0,
	"witness_time_mult": 1.0,
	"crew_approval_mult": 1.0,
	"loot_mult": 1.0,
	"bug_damage_taken": 1.0,
	"explosion_damage": 1.0,
	"explosion_damage_taken": 1.0,
}

var _sources: Dictionary = {}  # source_id -> mods dictionary


func set_source(source_id: String, mods: Dictionary) -> void:
	if mods.is_empty():
		_sources.erase(source_id)
	else:
		_sources[source_id] = mods


func remove_source(source_id: String) -> void:
	_sources.erase(source_id)


func clear() -> void:
	_sources.clear()


func has_source(source_id: String) -> bool:
	return _sources.has(source_id)


func get_stat(stat: String) -> float:
	var base: float = BASE.get(stat, 0.0)
	var add := 0.0
	var mul := 0.0
	for mods in _sources.values():
		add += float(mods.get("add", {}).get(stat, 0.0))
		mul += float(mods.get("mul", {}).get(stat, 0.0))
	return (base + add) * maxf(0.05, 1.0 + mul)


## Human readable list of everything touching `stat` (for the status screen).
func breakdown(stat: String) -> Array[String]:
	var out: Array[String] = []
	for source_id in _sources:
		var mods: Dictionary = _sources[source_id]
		var a = mods.get("add", {}).get(stat)
		var m = mods.get("mul", {}).get(stat)
		if a != null:
			out.append("%s %+.2f" % [source_id, float(a)])
		if m != null:
			out.append("%s %+d%%" % [source_id, roundi(float(m) * 100.0)])
	return out


func to_save() -> Dictionary:
	return _sources.duplicate(true)


func from_save(data: Dictionary) -> void:
	_sources = data.duplicate(true)


## Short "+10 MAX HP, -20% AIR COST" style summary of a mods dictionary.
static func describe_mods(mods: Dictionary) -> String:
	var parts: Array[String] = []
	for stat in mods.get("add", {}):
		var v := float(mods["add"][stat])
		var num := ("%+d" % roundi(v)) if is_equal_approx(v, roundf(v)) else ("%+.2f" % v)
		parts.append("%s %s" % [num, _pretty(stat)])
	for stat in mods.get("mul", {}):
		parts.append("%+d%% %s" % [roundi(float(mods["mul"][stat]) * 100.0), _pretty(stat)])
	return ", ".join(parts)


static func _pretty(stat: String) -> String:
	return stat.replace("_mult", "").replace("_", " ").to_upper()
