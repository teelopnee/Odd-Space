class_name Tips
extends RefCounted
## Just-in-time teaching: each tip appears once, the first time its situation happens, as a
## small banner that never pauses the game (data/tips.json). Seen tips are remembered across
## lives in the device settings, and the whole thing can be switched off in Settings.

static var _data: Dictionary = {}
static var _shown_this_run: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var path := "res://data/tips.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_data = parsed
	return _data


static func show(id: String) -> void:
	if str(Game.settings.get("tips", "on")) == "off" or _shown_this_run.has(id):
		return
	var seen: Array = Game.settings.get("tips_seen", [])
	if seen.has(id):
		return
	var t: Dictionary = data().get(id, {})
	if t.is_empty():
		return
	_shown_this_run[id] = true
	seen.append(id)
	Game.settings["tips_seen"] = seen
	Game.save_settings()
	var dev := "touch"
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node("Router"):
		dev = str(tree.root.get_node("Router").input_device)
	var key := "touch" if dev == "touch" else ("pad" if dev == "gamepad" else "key")
	EventBus.tip_shown.emit(str(t.get("title", "")), str(t.get(key, t.get("key", ""))))


## Forget every seen tip (Settings > "Show tips again").
static func reset() -> void:
	Game.settings["tips_seen"] = []
	_shown_this_run.clear()
	Game.save_settings()
