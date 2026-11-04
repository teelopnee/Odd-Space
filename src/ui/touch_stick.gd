class_name TouchStick
extends Control
## Floating multi-touch joystick: touch anywhere inside this control's rect and
## the stick appears under your thumb. Feeds the move_* InputMap actions with
## analog strength, so gameplay code just uses Input.get_vector().

@export var radius := 110.0
@export var dead_zone := 0.12
@export var base_color := Color(0.24, 0.9, 1.0, 0.18)
@export var knob_color := Color(1.0, 0.24, 0.78, 0.55)

var output := Vector2.ZERO
var _index := -99
var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed and _index == -99 and get_global_rect().has_point(t.position):
			_index = t.index
			_center = t.position
			_move_to(t.position)
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _index:
			release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _index:
			_move_to(d.position)
			get_viewport().set_input_as_handled()


func _move_to(pos: Vector2) -> void:
	var delta := pos - _center
	if delta.length() > radius:
		# Drag the base along so the stick never "runs out".
		_center = pos - delta.normalized() * radius
		delta = pos - _center
	_knob = delta
	output = delta / radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	_apply()
	queue_redraw()


func release() -> void:
	_index = -99
	output = Vector2.ZERO
	_knob = Vector2.ZERO
	_apply()
	queue_redraw()


func _apply() -> void:
	_set_axis("move_left", "move_right", output.x)
	_set_axis("move_up", "move_down", output.y)


func _set_axis(neg: String, pos: String, value: float) -> void:
	if value < 0.0:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.0:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _draw() -> void:
	if _index == -99:
		# Idle hint in the lower-left corner of the zone.
		var hint := Vector2(radius + 40.0, size.y - radius - 40.0)
		draw_arc(hint, radius, 0.0, TAU, 48, base_color, 3.0, true)
		draw_circle(hint, radius * 0.35, Color(base_color, 0.12))
		return
	var c := _center - global_position
	draw_circle(c, radius, Color(base_color, 0.1))
	draw_arc(c, radius, 0.0, TAU, 48, base_color, 3.0, true)
	draw_circle(c + _knob, radius * 0.38, knob_color)
	draw_arc(c + _knob, radius * 0.38, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0, true)
