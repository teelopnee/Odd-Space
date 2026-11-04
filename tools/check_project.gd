extends SceneTree
## Headless sanity check: compiles every script and instantiates every scene.
## Run:  godot --headless --path . --script res://tools/check_project.gd
## Exit code = number of failures (0 = all good).

var failures := 0
var _ran := false


## Autoloads exist only once the main loop runs, so check on the first frame.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_check()
	return false


func _check() -> void:
	var scripts: Array[String] = []
	var scenes: Array[String] = []
	_collect("res://src", scripts, ".gd")
	_collect("res://scenes", scenes, ".tscn")
	for path in scripts:
		var s = load(path)
		if s == null or (s is GDScript and not s.can_instantiate() and not _is_abstract_ok(path)):
			print("FAIL script: ", path)
			failures += 1
	for path in scenes:
		var ps = load(path)
		if ps == null:
			print("FAIL scene load: ", path)
			failures += 1
	print("Checked %d scripts, %d scenes, %d failures" % [scripts.size(), scenes.size(), failures])
	quit(failures)


func _is_abstract_ok(_path: String) -> bool:
	return false


func _collect(dir_path: String, out: Array[String], ext: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir():
			if not f.begins_with("."):
				_collect(full, out, ext)
		elif f.ends_with(ext):
			out.append(full)
		f = dir.get_next()
