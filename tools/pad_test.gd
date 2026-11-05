extends SceneTree
## Headless gamepad check: sends joypad events into real screens and reports
## what has GUI focus and whether A (button 0) activates it.
##   godot --headless --path . --script res://tools/pad_test.gd

var _step := 0
var _wait := 0
var _hits: Array = []


func _process(_d: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			change_scene_to_file("res://scenes/ui/title_screen.tscn")
			_next(20)
		1:
			_report("title")
			_pad_button(JOY_BUTTON_DPAD_DOWN)
			_next(3)
		2:
			_report("title after dpad down")
			_pad_axis(JOY_AXIS_LEFT_Y, 1.0)
			_next(3)
		3:
			_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
			_report("title after stick down")
			change_scene_to_file("res://scenes/ui/character_creation.tscn")
			_next(20)
		4:
			_report("creator")
			_pad_button(JOY_BUTTON_DPAD_RIGHT)
			_next(3)
		5:
			_report("creator after dpad right")
			_pad_button(JOY_BUTTON_A)
			_next(3)
		6:
			_report("creator after A")
			print("creator class selected: ", current_scene._selected.get("class", ""))
			var game = root.get_node("Game")
			game.new_game("Pad", {}, 77)
			root.get_node("Router").params = {"planet_id": game.galaxy[0].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_next(120)
		7:
			var hud = get_first_node_in_group("hud")
			for i in 8:
				if hud._dialogue_open:
					hud._on_choice("")
			root.get_node("EventBus").dialogue_requested.emit("Test", "Pick one", [{"id": "a", "text": "Alpha"}, {"id": "b", "text": "Beta"}], func(c): _hits.append(c))
			_next(5)
		8:
			_report("dialogue open")
			_pad_button(JOY_BUTTON_DPAD_DOWN)
			_next(3)
		9:
			_report("dialogue after dpad down")
			_pad_button(JOY_BUTTON_A)
			_next(5)
		10:
			print("dialogue callback got: ", _hits)
			_pad_button(JOY_BUTTON_START)
			_next(5)
		11:
			var hud = get_first_node_in_group("hud")
			print("pause menu open after START: ", hud._menu.visible)
			_report("pause menu")
			_pad_button(JOY_BUTTON_RIGHT_SHOULDER)
			_next(4)
		12:
			var hud = get_first_node_in_group("hud")
			print("menu tab after RB: ", hud._menu._tabs.current_tab)
			_report("pause menu after RB")
			_pad_button(JOY_BUTTON_B)
			_next(4)
		13:
			var hud = get_first_node_in_group("hud")
			print("pause menu open after B: ", hud._menu.visible, "  tree paused: ", paused)
			quit(0)
	return false


func _next(f: int) -> void:
	_step += 1
	_wait = f


func _report(tag: String) -> void:
	var f := root.get_viewport().gui_get_focus_owner()
	var txt := ""
	if f is Button:
		txt = (f as Button).text
	print("[%s] focus: %s %s   paused=%s" % [tag, f.get_class() if f else "<none>", txt, paused])


func _pad_button(b: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = b
		e.pressed = down
		Input.parse_input_event(e)


func _pad_axis(axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)
