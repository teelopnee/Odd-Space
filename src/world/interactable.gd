class_name Interactable
extends Area3D
## Something the player can use: steal from, talk to, buy from, board...
## The player's InteractArea detects these (physics layer 6 "interact").
## Connect `interacted` or subclass and override _on_interact().

signal interacted(player: Node)

const LAYER_INTERACT := 32

@export var prompt := "Interact"
@export var radius := 1.4
@export var enabled := true:
	set(value):
		enabled = value
		if is_inside_tree():
			set_deferred("monitorable", value)
		_notify_players()
@export var one_shot := false

var _prompt_label: Label3D


func _ready() -> void:
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	monitoring = false
	monitorable = enabled
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)


func get_prompt() -> String:
	return prompt


func interact(player: Node) -> void:
	if not enabled:
		return
	_on_interact(player)
	interacted.emit(player)
	if one_shot:
		enabled = false


func _on_interact(_player: Node) -> void:
	pass


func _notify_players() -> void:
	if not is_inside_tree():
		return
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("refresh_interaction"):
			p.call_deferred("refresh_interaction")
