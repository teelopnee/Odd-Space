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

var _layer: CanvasLayer
var _rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.color = Color(0.06, 0.0, 0.1, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_rect)


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
