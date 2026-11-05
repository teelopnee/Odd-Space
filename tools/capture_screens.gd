extends SceneTree
## Renders key scenes and saves PNG screenshots (needs a real renderer, not --headless).
## Run (Linux, no GPU):  xvfb-run -s "-screen 0 1280x800x24" godot --path . \
##                        --script res://tools/capture_screens.gd -- <out_dir> [--quick] [--biome=<env id>] [--creator] [--dof=off|physical|tilt_shift]
## (Don't pass --rendering-driver: it silently switches the renderer to Forward+.)

var _out := "user://screens"
var _step := 0
var _wait := 0
var _queue: Array = []
var _current := ""
var _quick := false  ## --quick: creator + one shot per biome, skip the station/star map


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_quick = args.has("--quick")
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
			if OS.get_cmdline_user_args().has("--creator"):
				var cc = current_scene
				cc._show_category("background")
				_step = 30
				_wait = 10
				return false
			if _quick:
				root.get_node("Game").new_game("Rex Vantablack", {"background": "cryo_debtor", "motivation": "burn_consortium", "secret": "kleptomaniac"}, 4242)
				_step = 9
				_wait = 5
				return false
			root.get_node("Game").new_game("Rex Vantablack", {"background": "cryo_debtor", "motivation": "burn_consortium", "secret": "kleptomaniac"}, 4242)
			change_scene_to_file("res://scenes/world/station_prologue.tscn")
			_next(150)
		3:
			_shot("03_intro_cutscene")
			var hud = get_first_node_in_group("hud")
			for i in 6:
				if hud._dialogue_open:
					hud._on_choice("")
			paused = false
			# Skip the rest of the intro: release control.
			hud.cinematic(false)
			var p = get_first_node_in_group("player")
			p.set_cutscene(false)
			var rig = get_first_node_in_group("camera_rig")
			rig.target = p
			rig.configure(36.0, 14.5, 31.0)
			p.global_position = Vector3(25, 0.2, 19)
			for e in get_nodes_in_group("enemy"):
				e.hostile = false
				e.def["hostility"] = "rep"
				e.def["hostile_below"] = -999
			_next(90)
		4:
			var hud = get_first_node_in_group("hud")
			for i in 6:
				if hud._dialogue_open:
					hud._on_choice("")
			paused = false
			_shot("04_station")
			var p = get_first_node_in_group("player")
			for e in get_nodes_in_group("enemy"):
				e.hostile = true
			p.cycle_target()
			p._start_combo(0)
			_next(7)
		5:
			_shot("05_station_combat")
			root.get_node("Game").enter_ship()
			change_scene_to_file("res://scenes/ui/star_map.tscn")
			_next(40)
		6:
			var sm = current_scene
			sm._select(root.get_node("Game").galaxy[3])
			_next(10)
		7:
			_shot("06_star_map")
			var g = root.get_node("Game")
			root.get_node("Router").params = {"planet_id": g.galaxy[3].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_next(150)
		8:
			_shot("07_planet_landing")
			_next(260)
		9:
			if not _quick:
				_shot("08_planet_a")
			# One shot per distinct biome in this universe (dense random worlds).
			var g = root.get_node("Game")
			var seen := {}
			var only := ""
			for a in OS.get_cmdline_user_args():
				if str(a).begins_with("--biome="):
					only = str(a).substr(8)
			for pl in g.galaxy:
				if only != "" and pl.environment != only:
					continue
				if not seen.has(pl.environment):
					seen[pl.environment] = true
					_queue.append(pl)
			_next(1)
		10:
			if _queue.is_empty():
				quit(0)
				return false
			var pl: Dictionary = _queue.pop_front()
			_current = "09_world_%s" % pl.environment
			root.get_node("Router").params = {"planet_id": pl.id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_step = 40
			_wait = 45
		40:
			_shot(_current + "_wide")
			_step = 11
			_wait = 330
		11:
			var hud = get_first_node_in_group("hud")
			if hud and hud._dialogue_open:
				hud._on_choice("")
			paused = false
			_shot(_current)
			_step = 10
			if OS.get_cmdline_user_args().has("--street"):
				_step = 12
				_wait = 2
		12:
			# Walk the hero up to a shop front: signs, flyers, graffiti, menus, queues.
			_step = 13
			_wait = 120
			var pl = get_first_node_in_group("player")
			var spots: Array = []
			for n in current_scene.find_children("*", "", true, false):
				if "venue_id" in n and str(n.venue_id) != "":
					spots.append(n)
			if pl and not spots.is_empty():
				var best = spots[0]
				for v in spots:
					if v.global_position.distance_to(pl.global_position) < best.global_position.distance_to(pl.global_position):
						best = v
				pl.global_position = best.global_position + Vector3(0, 0.2, 2.2)
		13:
			_shot(_current + "_street")
			_step = 10
		30:
			_shot("02b_character_creation_background")
			current_scene._show_category("age")
			_step = 31
			_wait = 10
		31:
			_shot("02c_character_creation_age")
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
