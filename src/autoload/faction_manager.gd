extends Node
## "Factions" autoload: reputation (-100..+100) and bounties for the five
## Consortium powers. Rep affects prices, whether guards are hostile, and how
## often bounty hunters show up during warp.

const MIN_REP := -100
const MAX_REP := 100
const RIVAL_SPILLOVER := 0.25  # helping/hurting X affects X's rivals/allies by 25%

const STANDINGS := [
	[-80, "ENEMY OF THE BRAND"],
	[-50, "HOSTILE"],
	[-20, "DISTRUSTED"],
	[20, "NEUTRAL"],
	[50, "VALUED CUSTOMER"],
	[80, "PREFERRED SHAREHOLDER"],
	[101, "BOARD MEMBER"],
]

var rep: Dictionary = {}     # faction_id -> int
var bounty: Dictionary = {}  # faction_id -> int (credits)


func _ready() -> void:
	reset()


func reset() -> void:
	rep.clear()
	bounty.clear()
	for id in DataDB.factions:
		rep[id] = int(DataDB.factions[id].get("start_rep", 0))
		bounty[id] = 0


func ids() -> Array:
	return DataDB.factions.keys()


func get_rep(id: String) -> int:
	return int(rep.get(id, 0))


func change_rep(id: String, delta: int, reason: String = "", spill: bool = true) -> void:
	if not rep.has(id) or delta == 0:
		return
	var old: int = rep[id]
	var new_value := clampi(old + delta, MIN_REP, MAX_REP)
	rep[id] = new_value
	EventBus.faction_rep_changed.emit(id, old, new_value, reason)
	if old > -50 and new_value <= -50:
		ShipAI.say("on_rep_crash", {"faction": DataDB.faction_name(id)})
	if spill:
		var spill_amount := roundi(delta * RIVAL_SPILLOVER)
		if spill_amount != 0:
			var def: Dictionary = DataDB.factions[id]
			for rival in def.get("rivals", []):
				change_rep(rival, -spill_amount, "rivalry with %s" % id, false)
			for ally in def.get("allies", []):
				change_rep(ally, spill_amount, "alliance with %s" % id, false)


func standing(id: String) -> String:
	var r := get_rep(id)
	for entry in STANDINGS:
		if r < entry[0]:
			return entry[1]
	return "BOARD MEMBER"


## Shop price multiplier for goods sold by `id` (rep -100 -> x1.75, +100 -> x0.7).
func price_multiplier(id: String) -> float:
	var r := float(get_rep(id))
	var m := 1.0
	if r < 0.0:
		m = lerpf(1.0, 1.75, -r / 100.0)
	else:
		m = lerpf(1.0, 0.7, r / 100.0)
	return m * Game.stat("price_mult")


func will_trade(id: String) -> bool:
	return id == "" or get_rep(id) > -60


## Should guards of this faction attack on sight?
func is_hostile(id: String, threshold: int = -30) -> bool:
	if id == "" or not rep.has(id):
		return false
	return get_rep(id) <= threshold or get_bounty(id) >= 200


func get_bounty(id: String) -> int:
	return int(bounty.get(id, 0))


func total_bounty() -> int:
	var total := 0
	for id in bounty:
		total += int(bounty[id])
	return total


func add_bounty(id: String, amount: int) -> void:
	if not bounty.has(id) or amount == 0:
		return
	var was_zero := total_bounty() == 0
	bounty[id] = maxi(0, int(bounty[id]) + amount)
	EventBus.bounty_changed.emit(id, bounty[id])
	if was_zero and total_bounty() > 0:
		ShipAI.say("on_bounty")


func clear_bounties() -> void:
	for id in bounty:
		bounty[id] = 0
		EventBus.bounty_changed.emit(id, 0)


## 0..1-ish: how much heat the player is under (drives hunter encounters).
func heat() -> float:
	var worst := 0
	for id in rep:
		worst = mini(worst, int(rep[id]))
	return clampf(total_bounty() / 600.0 + absf(worst) / 200.0, 0.0, 1.5)


func to_save() -> Dictionary:
	return {"rep": rep.duplicate(), "bounty": bounty.duplicate()}


func from_save(data: Dictionary) -> void:
	reset()
	for id in data.get("rep", {}):
		rep[id] = int(data["rep"][id])
	for id in data.get("bounty", {}):
		bounty[id] = int(data["bounty"][id])
