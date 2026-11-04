extends SceneTree
## One-shot tool: writes the default input map into project.godot.
## Run:  godot --headless --path . --script res://tools/setup_input_map.gd
## Safe to re-run; it overwrites only the actions listed below.
## NOTE: mouse buttons are intentionally NOT bound to gameplay actions, because on
## tablets every touch is also emulated as a left-click (would fire on every tap).

const DEADZONE := 0.25

func _init() -> void:
	var actions := {
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0), _btn(JOY_BUTTON_DPAD_LEFT)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0), _btn(JOY_BUTTON_DPAD_RIGHT)],
		"move_up": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0), _btn(JOY_BUTTON_DPAD_UP)],
		"move_down": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0), _btn(JOY_BUTTON_DPAD_DOWN)],
		# Gamepad layout (Xbox names; PlayStation: A=Cross, B=Circle, X=Square, Y=Triangle)
		"melee": [_key(KEY_J), _btn(JOY_BUTTON_X)],
		"attack": [_key(KEY_K), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"dodge": [_key(KEY_SPACE), _btn(JOY_BUTTON_A)],
		"parry": [_key(KEY_L), _btn(JOY_BUTTON_RIGHT_SHOULDER)],
		"overclock": [_key(KEY_R), _btn(JOY_BUTTON_B)],
		"interact": [_key(KEY_F), _key(KEY_E), _btn(JOY_BUTTON_Y)],
		"target_cycle": [_key(KEY_TAB), _btn(JOY_BUTTON_LEFT_SHOULDER)],
		"subsystem_next": [_key(KEY_Q), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"pause": [_key(KEY_ESCAPE), _key(KEY_P), _btn(JOY_BUTTON_START)],
		"log": [_key(KEY_C), _btn(JOY_BUTTON_BACK)],
	}
	for action_name in actions:
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": DEADZONE,
			"events": actions[action_name],
		})
	var err := ProjectSettings.save()
	print("Input map written: ", error_string(err))
	quit()


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.device = -1  # all devices
	return e


func _btn(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e
