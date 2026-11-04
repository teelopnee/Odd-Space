extends Node
## "Crew" autoload - the Morality Engine.
## Up to 4 crew. Each has moral values (mercy / order / greed). Every recorded
## action carries a moral vector; approval change = dot(vector, values) * scale.
## Crew ALWAYS find out (they monitor your comms; QUACK gossips).
## Low approval -> grumbling -> DISLOYAL -> betrayal on the next warp:
##   steal_ship  : they run off with a chunk of your credits and items
##   leak_coords : they sell your position; next warp = forced ambush encounter
##   mutiny      : they turn on you in the next level (spawn as a hostile)
##   leave       : they simply walk out at the next port

const MAX_CREW := 4
const APPROVAL_SCALE := 6.0
const GRUMBLE_AT := -40
const DISLOYAL_AT := -65
const AXES := ["mercy", "order", "greed"]

var members: Dictionary = {}  # id -> {approval:int, joined_at:float}
var order: Array = []         # recruitment order
var pending_mutiny: Array = []  # member defs who will attack in the next level
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.action_recorded.connect(_on_action_recorded)


func reset() -> void:
	members.clear()
	order.clear()
	pending_mutiny.clear()


func def(id: String) -> Dictionary:
	return DataDB.crew.get("members", {}).get(id, {})


func size() -> int:
	return order.size()


func is_full() -> bool:
	return order.size() >= MAX_CREW


func has_member(id: String) -> bool:
	return members.has(id)


func available_recruits() -> Array:
	var out := []
	for id in DataDB.crew.get("members", {}):
		if not members.has(id):
			out.append(id)
	return out


func random_recruit_id() -> String:
	var pool := available_recruits()
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else ""


func recruit(id: String) -> bool:
	if id == "random":
		id = random_recruit_id()
	if id == "" or members.has(id) or is_full() or def(id).is_empty():
		return false
	members[id] = {"approval": 10, "joined_at": Game.play_time}
	order.append(id)
	EventBus.crew_joined.emit(id)
	EventBus.toast.emit("%s joined the crew" % def(id).get("name", id), Color(0.5, 1.0, 0.7))
	return true


func dismiss(id: String, reason: String = "dismissed") -> void:
	if not members.has(id):
		return
	members.erase(id)
	order.erase(id)
	EventBus.crew_left.emit(id, reason)


func approval(id: String) -> int:
	return int(members.get(id, {}).get("approval", 0))


func mood(id: String) -> String:
	var a := approval(id)
	if a <= DISLOYAL_AT:
		return "DISLOYAL"
	if a <= GRUMBLE_AT:
		return "GRUMBLING"
	if a < 20:
		return "WARY"
	if a < 60:
		return "LOYAL"
	return "DEVOTED"


func change_approval(id: String, delta: int, bark: bool = true) -> void:
	if not members.has(id) or delta == 0:
		return
	var old: int = members[id].approval
	var new_value := clampi(old + delta, -100, 100)
	members[id].approval = new_value
	EventBus.crew_approval_changed.emit(id, old, new_value)
	if bark and absi(delta) >= 3:
		var barks: Dictionary = def(id).get("barks", {})
		var key := "approve" if delta > 0 else "disapprove"
		if new_value <= DISLOYAL_AT:
			key = "disloyal"
		var lines: Array = barks.get(key, [])
		if not lines.is_empty():
			EventBus.crew_bark.emit(id, lines[_rng.randi() % lines.size()])
	if old > GRUMBLE_AT and new_value <= GRUMBLE_AT:
		ShipAI.say("on_crew_unhappy", {"member": def(id).get("name", id)}, true)


## The moral judgement: how much does `id` like an act with this moral vector?
func judge(id: String, moral: Dictionary) -> int:
	var values: Dictionary = def(id).get("values", {})
	var dot := 0.0
	for axis in AXES:
		dot += float(moral.get(axis, 0.0)) * float(values.get(axis, 0.0))
	return roundi(dot * APPROVAL_SCALE * Game.stat("crew_approval_mult"))


func _on_action_recorded(node: Dictionary) -> void:
	var moral: Dictionary = node.get("moral", {})
	if moral.is_empty():
		return
	for id in order.duplicate():
		change_approval(id, judge(id, moral))


## Called by the star map when warping. Returns an Array of betrayal events
## {member, kind, text} that the UI should show.
func check_betrayals() -> Array:
	var events := []
	for id in order.duplicate():
		if approval(id) > DISLOYAL_AT:
			continue
		# The lower the approval, the likelier the betrayal (40%..100%).
		var chance := remap(float(approval(id)), DISLOYAL_AT, -100.0, 0.4, 1.0)
		if _rng.randf() > chance:
			continue
		var d := def(id)
		var kind: String = d.get("betrayal", "leave")
		var text := _execute_betrayal(id, kind)
		events.append({"member": id, "kind": kind, "text": text})
		EventBus.crew_betrayal.emit(id, kind, text)
		ShipAI.say("on_betrayal", {}, true)
	return events


func _execute_betrayal(id: String, kind: String) -> String:
	var d := def(id)
	var who: String = d.get("name", id)
	match kind:
		"steal_ship":
			var stolen := roundi(Game.credits * 0.6)
			Game.add_credits(-stolen)
			for item_id in Game.inventory.keys():
				if _rng.randf() < 0.5:
					Game.add_item(item_id, -ceili(Game.item_count(item_id) / 2.0))
			dismiss(id, "betrayal")
			return "%s took the shuttle, %d credits and half your stuff. A note says: 'Nothing personal. Everything financial.'" % [who, stolen]
		"leak_coords":
			Encounters.force_next("bounty_hunter")
			Factions.add_bounty("paragon", 100)
			dismiss(id, "betrayal")
			return "%s sold your coordinates and jumped ship at the last buoy. Someone is coming." % who
		"mutiny":
			pending_mutiny.append(id)
			dismiss(id, "mutiny")
			return "%s has armed themselves and slipped off the ship. They'll be waiting for you on the next planet." % who
		_:
			dismiss(id, "left")
			return "%s packed a bag and left without a word. QUACK says they took the good mug." % who


func pop_mutineers() -> Array:
	var out := pending_mutiny.duplicate()
	pending_mutiny.clear()
	return out


func to_save() -> Dictionary:
	return {"members": members.duplicate(true), "order": order.duplicate(), "mutiny": pending_mutiny.duplicate()}


func from_save(data: Dictionary) -> void:
	reset()
	var m: Dictionary = data.get("members", {})
	for id in m:
		members[id] = {"approval": int(m[id].get("approval", 0)), "joined_at": float(m[id].get("joined_at", 0.0))}
	order = data.get("order", members.keys())
	pending_mutiny = data.get("mutiny", [])
