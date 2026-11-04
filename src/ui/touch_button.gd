class_name TouchButton
extends Control
## Round holographic multi-touch button. Either holds an InputMap action
## (action = "attack" -> pressed while the finger is down) or fires `tapped`.

signal tapped

@export var action := ""
@export var text := "A"
@export var color := Color(0.24, 0.9, 1.0)
@export var font_size := 20

var pressed := false
var _index := -99


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed and _index == -99 and _hit(t.position):
			_index = t.index
			_set_pressed(true)
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _index:
			_set_pressed(false)
			get_viewport().set_input_as_handled()


func _hit(pos: Vector2) -> bool:
	var r := minf(size.x, size.y) * 0.5
	return (pos - (global_position + size * 0.5)).length() <= r * 1.15


func _set_pressed(on: bool) -> void:
	if pressed == on:
		return
	pressed = on
	if not on:
		_index = -99
	if action != "":
		if on:
			Input.action_press(action)
		else:
			Input.action_release(action)
	elif on:
		tapped.emit()
	queue_redraw()


func release() -> void:
	_set_pressed(false)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, Color(color, 0.42 if pressed else 0.16))
	draw_arc(c, r - 1.5, 0.0, TAU, 40, Color(color, 0.9), 3.0, true)
	draw_arc(c, r * 0.78, 0.0, TAU, 40, Color(color, 0.25), 1.5, true)
	var font := get_theme_default_font()
	var fs := font_size
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
