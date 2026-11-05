class_name Arsenal
extends RefCounted
## The player's weapons (data/weapons.json): one BLADE (melee) and one GUN (ranged) equipped,
## more unlocked by picking up "weapon_<id>" items (shops, enemy drops, background start kit).
## Owned/equipped state lives in Game.flags so it saves with everything else.

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
		_data = parsed if parsed is Dictionary else {"melee": {}, "ranged": {}}
	return _data


static func slot_of(id: String) -> String:
	return "melee" if data().get("melee", {}).has(id) else ("ranged" if data().get("ranged", {}).has(id) else "")


static func owned(slot: String) -> Array:
	var o: Dictionary = Game.flags.get("weapons", {})
	var list: Array = o.get(slot, [])
	if list.is_empty():
		list = ["pipe"] if slot == "melee" else ["sidearm"]
	return list


static func owns(id: String) -> bool:
	return owned(slot_of(id)).has(id)


static func equipped(slot: String) -> String:
	var e: Dictionary = Game.flags.get("equip", {})
	var id := str(e.get(slot, ""))
	return id if owned(slot).has(id) else str(owned(slot)[0])


static func stats(slot: String) -> Dictionary:
	return data().get(slot, {}).get(equipped(slot), {})


static func unlock(id: String, equip: bool = true) -> bool:
	var slot := slot_of(id)
	if slot == "" or owns(id):
		return false
	var o: Dictionary = Game.flags.get("weapons", {})
	var list: Array = owned(slot).duplicate()
	list.append(id)
	o[slot] = list
	Game.flags["weapons"] = o
	if equip:
		_equip(slot, id)
	Tips.show("weapons")
	EventBus.toast.emit("NEW WEAPON: %s - %s" % [str(data()[slot][id].get("name", id)).to_upper(), data()[slot][id].get("desc", "")],
		Color(1.0, 0.85, 0.3))
	return true


static func cycle(slot: String) -> String:
	var list := owned(slot)
	var i := list.find(equipped(slot))
	var next := str(list[(i + 1) % list.size()])
	_equip(slot, next)
	return next


static func _equip(slot: String, id: String) -> void:
	var e: Dictionary = Game.flags.get("equip", {})
	e[slot] = id
	Game.flags["equip"] = e
	EventBus.weapon_changed.emit(slot, id)


static func label(slot: String) -> String:
	return str(stats(slot).get("name", equipped(slot)))


## New life: the default pair, plus whatever your background brought along.
static func start_kit(tags: Dictionary) -> void:
	Game.flags["weapons"] = {"melee": ["pipe"], "ranged": ["sidearm"]}
	Game.flags["equip"] = {"melee": "pipe", "ranged": "sidearm"}
	var extra := str(data().get("start_kit", {}).get(str(tags.get("background", "")), ""))
	if extra != "":
		var slot := slot_of(extra)
		var o: Dictionary = Game.flags["weapons"]
		o[slot] = (o[slot] as Array) + [extra]
		Game.flags["equip"][slot] = extra
