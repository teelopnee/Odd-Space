extends Node
## "Router" autoload - scene changes with a synthwave-magenta fade.
## Router.goto("res://scenes/world/planet_surface.tscn", {"planet_id": "p3"})
## The destination reads Router.params in its _ready().

const TITLE := "res://scenes/ui/title_screen.tscn"
const CREATOR := "res://scenes/ui/character_creation.tscn"
const STATION := "res://scenes/world/station_prologue.tscn"
const PLANET := "res://scenes/world/planet_surface.tscn"
const STAR_MAP := "res://scenes/ui/star_map.tscn"

var params: Dictionary = {}
var busy := false
## Last input device used: "touch" | "keyboard" | "gamepad". Drives HUD prompts/touch UI.
var input_device := "keyboard"

const GLYPHS := {
	"gamepad": {"interact": "Y", "melee": "X", "attack": "RT", "dodge": "A", "parry": "RB", "overclock": "B",
		"target_cycle": "LB", "subsystem_next": "LT", "pause": "START", "log": "BACK"},
	"keyboard": {"interact": "F", "melee": "J", "attack": "K", "dodge": "SPACE", "parry": "L", "overclock": "R",
		"target_cycle": "TAB", "subsystem_next": "Q", "pause": "ESC", "log": "C"},
}

var _layer: CanvasLayer
var _rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_gamepad_ui()
	get_tree().root.content_scale_factor = float(Game.settings.get("ui_scale", 1.0))
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or str(Game.settings.get("touch", "auto")) == "on":
		input_device = "touch"  # touch controls forced on = touch prompts ("press F" on a touch screen read as a lazy port)
	if not Input.get_connected_joypads().is_empty():
		input_device = "gamepad"
	Input.joy_connection_changed.connect(_on_joy_changed)
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.color = Color(0.06, 0.0, 0.1, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_rect)


func _input(event: InputEvent) -> void:
	var dev := ""
	if event is InputEventJoypadButton and event.pressed:
		dev = "gamepad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		dev = "gamepad"
	elif event is InputEventScreenTouch and event.pressed:
		dev = "touch"
	elif event is InputEventKey and event.pressed:
		dev = "keyboard"
	if dev != "" and dev != input_device:
		input_device = dev
		EventBus.input_device_changed.emit(dev)


## Button name for an action on the current device ("" on touch).
func glyph(action: String) -> String:
	return GLYPHS.get(input_device, {}).get(action, "")


func goto(path: String, new_params: Dictionary = {}, fade: float = 0.35) -> void:
	if busy:
		return
	busy = true
	params = new_params
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, fade)
	await tw.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Router: cannot open %s (%s)" % [path, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_rect, "color:a", 0.0, fade)
	await tw2.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false


## Continue a loaded save at the right place.
func continue_run() -> void:
	if not Game.current_planet.is_empty():
		goto(PLANET, {"planet_id": Game.current_planet.get("id", "")})
	elif Game.location_id == "station_lot47":
		goto(STATION)
	else:
		goto(STAR_MAP)


func _on_joy_changed(_device: int, connected: bool) -> void:
	if connected:
		input_device = "gamepad"
		EventBus.input_device_changed.emit("gamepad")
		EventBus.toast.emit("Controller connected - ready to play!", Color(0.5, 1.0, 0.7))
	elif Input.get_connected_joypads().is_empty() and (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		input_device = "touch"
		EventBus.input_device_changed.emit("touch")


## Godot 4.7's built-in ui_accept / ui_cancel carry no gamepad buttons (and a joypad
## event added to ui_accept in project.godot is dropped on load), so menus could be
## navigated with the D-pad but nothing could be confirmed. Bind them at runtime:
## A = confirm, B = back, plus Start as an extra confirm on title-like screens.
static func ensure_gamepad_ui() -> void:
	var binds := {"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B]}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in binds[action]:
			var have := false
			for e in InputMap.action_get_events(action):
				if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == b:
					have = true
			if not have:
				var ev := InputEventJoypadButton.new()
				ev.device = -1
				ev.button_index = b
				InputMap.action_add_event(action, ev)


## Phones and tablets: the system Back button closes what's open (or opens the menu) instead of
## killing the game, and leaving the app pauses + autosaves (Android may close us in the background).
func _notification(what: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if hud == null:
				get_tree().quit()
				return
			var ev := InputEventAction.new()
			ev.action = "ui_cancel" if hud.get("_modal") and hud._modal.visible else "pause"
			ev.pressed = true
			Input.parse_input_event(ev)
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if hud != null and Game.has_active_run and not (hud.get("_modal") and hud._modal.visible):
				hud.open_menu()
			if what == NOTIFICATION_APPLICATION_PAUSED and Game.has_active_run:
				Game.save_game()


## PC: F11 or Alt+Enter toggles fullscreen.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
