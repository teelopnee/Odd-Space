extends SceneTree
## Renders key scenes and saves PNG screenshots (needs a real renderer, not --headless).
## Run (Linux, no GPU):  xvfb-run -s "-screen 0 1280x800x24" godot --path . \
##                        --script res://tools/capture_screens.gd -- <out_dir> [--dof=off|physical|tilt_shift]
## (Don't pass --rendering-driver: it silently switches the renderer to Forward+.)

var _out := "user://screens"
var _step := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			change_scene_to_file("res://scenes/ui/title_screen.tscn")
			_next(40)
		1:
			_shot("01_title")
			change_scene_to_file("res://scenes/ui/character_creation.tscn")
			_next(30)
		2:
			_shot("02_character_creation")
			root.get_node("Game").new_game("Rex Vantablack", {"background": "cryo_debtor", "motivation": "burn_consortium", "secret": "kleptomaniac"}, 4242)
			change_scene_to_file("res://scenes/world/station_prologue.tscn")
			_next(60)
		3:
			# Walk the player into the concourse so there is something to see.
			var p = get_first_node_in_group("player")
			p.global_position = Vector3(25, 0.2, 19)
			# Keep enemies passive so the screenshot isn't a flaw popup.
			for e in get_nodes_in_group("enemy"):
				e.hostile = false
				e.def["hostility"] = "rep"
				e.def["hostile_below"] = -999
			_next(90)
		4:
			_shot("03_station_concourse")
			var args := OS.get_cmdline_user_args()
			for a in args:
				if a.begins_with("--dof="):
					get_first_node_in_group("camera_rig").set_dof_mode(a.split("=")[1])
					_wait = 3
					_step = 40
					return false
			var p = get_first_node_in_group("player")
			for e in get_nodes_in_group("enemy"):
				e.hostile = true
			p.cycle_target()
			p.cycle_subsystem()
			p.shoot()
			_next(8)
		5:
			_shot("04_station_combat")
			root.get_node("Game").enter_ship()
			change_scene_to_file("res://scenes/ui/star_map.tscn")
			_next(40)
		6:
			var sm = current_scene
			sm._select(root.get_node("Game").galaxy[3])
			_next(10)
		7:
			_shot("05_star_map")
			var g = root.get_node("Game")
			root.get_node("Router").params = {"planet_id": g.galaxy[3].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_next(120)
		8:
			_shot("06_planet_a")
			var g = root.get_node("Game")
			root.get_node("Router").params = {"planet_id": g.galaxy[2].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_next(120)
		9:
			_shot("07_planet_b")
			quit(0)
		40:
			_shot("03b_station_dof_variant")
			quit(0)
	return false


func _next(frames: int) -> void:
	_step += 1
	_wait = frames


func _shot(shot_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out, shot_name]
	img.save_png(path)
	print("saved ", path)
