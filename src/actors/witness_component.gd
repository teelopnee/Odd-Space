class_name WitnessComponent
extends Node3D
## Attach to any NPC/guard. When a crime happens within perception range AND
## line of sight, Causality calls begin_report(): the owner pulls out a radio
## and a progress bar floats above their head. If the call finishes, the crime
## becomes REPORTED (rep loss, bounty, news). Kill or bribe them first and the
## story dies with them (SUPPRESSED).
##
## Owner contract (optional methods on the parent):
##   is_alive() -> bool, on_report_started(), on_report_finished()

signal report_started(node_id: int)
signal report_finished(node_id: int)

static var _id_counter := 0

@export var perception_radius := 12.0
@export var base_report_time := 5.0
## Who they call. Only cosmetic ("CALLING PARAGON...").
@export var calls_faction := "paragon"

var witness_id := ""
var active := true
var reports: Array[int] = []
var progress := 0.0
var duration := 5.0
var _label: Label3D


func _ready() -> void:
	_id_counter += 1
	witness_id = "%s#%d" % [get_parent().name, _id_counter]
	add_to_group("witness")
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.006
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.85, 0.2)
	_label.outline_modulate = Color(0.1, 0.0, 0.1)
	_label.position = Vector3(0, 2.25, 0)
	_label.visible = false
	add_child(_label)
	EventBus.action_status_changed.connect(_on_status_changed)


## Would they phone it in? (In range, line of sight, and willing.)
func can_witness(pos: Vector3) -> bool:
	if not active:
		return false
	# Friends (and people you've bought) look the other way.
	var owner_node := get_parent()
	if owner_node.has_method("will_report") and not owner_node.will_report():
		return false
	return can_see(pos)


## Can they see it at all? (Memory and reactions work even for friends and bought witnesses.)
func can_see(pos: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var owner_node := get_parent()
	if owner_node.has_method("is_alive") and not owner_node.is_alive():
		return false
	var eye := global_position + Vector3(0, 1.5, 0)
	var target := pos + Vector3(0, 1.0, 0)
	if eye.distance_to(target) > perception_radius:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, 1)  # world layer only
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func begin_report(node_id: int) -> void:
	if reports.has(node_id):
		return
	reports.append(node_id)
	if reports.size() == 1:
		progress = 0.0
		duration = _compute_duration(node_id)
		_label.visible = true
		if get_parent().has_method("on_report_started"):
			get_parent().on_report_started()
	EventBus.witness_started.emit(self, node_id)
	report_started.emit(node_id)
	Audio.play_sfx("radio")


func is_reporting() -> bool:
	return not reports.is_empty()


## Kill/bribe/stun. how: "killed" disables future witnessing.
func silence(how: String = "killed") -> void:
	if how == "killed":
		active = false
	if reports.is_empty():
		return
	var ids := reports.duplicate()
	reports.clear()
	_label.visible = false
	for id in ids:
		EventBus.witness_silenced.emit(self, id)
		Causality.witness_silenced(id, witness_id)
	# The owner is off the phone: back to normal life (was stuck "reporting" forever).
	if get_parent().has_method("on_report_finished"):
		get_parent().on_report_finished()


func _process(delta: float) -> void:
	if reports.is_empty():
		return
	progress += delta / maxf(duration, 0.1)
	var pct := clampi(roundi(progress * 100.0), 0, 100)
	var bar := "|".repeat(pct / 10) + ".".repeat(10 - pct / 10)
	_label.text = "((o)) CALLING %s\n[%s] %d%%" % [calls_faction.to_upper(), bar, pct]
	if progress >= 1.0:
		_finish()


func _finish() -> void:
	var ids := reports.duplicate()
	reports.clear()
	_label.visible = false
	for id in ids:
		Causality.witness_reported(id, witness_id)
		report_finished.emit(id)
	if get_parent().has_method("on_report_finished"):
		get_parent().on_report_finished()


func _compute_duration(node_id: int) -> float:
	var t := base_report_time * Game.stat("witness_time_mult")
	var crisis := PlanetGenerator.layer(Game.current_planet, "crises") if not Game.current_planet.is_empty() else {}
	t *= float(crisis.get("witness_mult", 1.0))
	var node := Causality.get_node_data(node_id)
	if node.get("verb", "") == "theft" and Game.item_count("lockpick") > 0:
		t *= 1.3
	# Informants you've bought on this planet "lose signal" for a while.
	t *= 1.0 + float(Game.flags.get("informants_" + Game.location_id, 0.0))
	# People who like you dawdle on the phone; people you've wronged speed-dial.
	var att = get_parent().get("attitude")
	if att != null:
		t *= clampf(1.0 + float(att) / 60.0, 0.55, 1.75)
	return maxf(1.2, t)


func _on_status_changed(node: Dictionary, _old: String) -> void:
	# Someone else finished the call (or it got resolved) -> stop calling it in.
	if node.status != Causality.STATUS_PENDING and reports.has(int(node.id)):
		reports.erase(int(node.id))
		if reports.is_empty():
			_label.visible = false
			if get_parent().has_method("on_report_finished"):
				get_parent().on_report_finished()
