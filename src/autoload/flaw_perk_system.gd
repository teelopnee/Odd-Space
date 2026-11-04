extends Node
## "FlawPerk" autoload - Flaw & Perk system.
## Repeated mishaps (failed parries, bug bites, missed shots...) are counted.
## At the threshold the game OFFERS a flaw: accept -> permanent drawback +
## free skill points. Decline -> counter resets, threshold grows by 50%.
## Skill points buy perks.

var counts: Dictionary = {}     # mishap kind -> int
var declines: Dictionary = {}   # flaw id -> times declined
var pending_offer := ""         # flaw id waiting for the player's decision
var _pending_mishap := ""


func reset() -> void:
	counts.clear()
	declines.clear()
	pending_offer = ""
	_pending_mishap = ""


func flaw_def(id: String) -> Dictionary:
	return DataDB.flaws_perks.get("flaws", {}).get(id, {})


func perk_def(id: String) -> Dictionary:
	return DataDB.flaws_perks.get("perks", {}).get(id, {})


func threshold_for(kind: String) -> int:
	var rule: Dictionary = DataDB.flaws_perks.get("mishaps", {}).get(kind, {})
	var base := int(rule.get("threshold", 999))
	var flaw_id: String = rule.get("flaw", "")
	return ceili(base * pow(1.5, int(declines.get(flaw_id, 0))))


func report_mishap(kind: String) -> void:
	var rule: Dictionary = DataDB.flaws_perks.get("mishaps", {}).get(kind, {})
	if rule.is_empty():
		return
	var flaw_id: String = rule.get("flaw", "")
	if Game.flaws.has(flaw_id):
		return  # already living with it
	counts[kind] = int(counts.get(kind, 0)) + 1
	EventBus.mishap.emit(kind, counts[kind])
	if pending_offer == "" and counts[kind] >= threshold_for(kind):
		pending_offer = flaw_id
		_pending_mishap = kind
		EventBus.flaw_offered.emit(flaw_id, kind)


func accept_offer() -> void:
	if pending_offer == "":
		return
	var id := pending_offer
	var d := flaw_def(id)
	Game.flaws.append(id)
	Game.stats.set_source("flaw:" + id, d.get("mods", {}))
	add_skill_points(int(d.get("skill_points", 1)))
	counts[_pending_mishap] = 0
	pending_offer = ""
	_pending_mishap = ""
	EventBus.flaw_accepted.emit(id)
	EventBus.stats_changed.emit()
	ShipAI.say("on_flaw", {}, true)


func decline_offer() -> void:
	if pending_offer == "":
		return
	declines[pending_offer] = int(declines.get(pending_offer, 0)) + 1
	counts[_pending_mishap] = 0
	pending_offer = ""
	_pending_mishap = ""


func add_skill_points(amount: int) -> void:
	Game.skill_points = maxi(0, Game.skill_points + amount)
	EventBus.skill_points_changed.emit(Game.skill_points)


func can_buy_perk(id: String) -> bool:
	var d := perk_def(id)
	return not d.is_empty() and not Game.perks.has(id) and Game.skill_points >= int(d.get("cost", 1))


func buy_perk(id: String) -> bool:
	if not can_buy_perk(id):
		return false
	var d := perk_def(id)
	add_skill_points(-int(d.get("cost", 1)))
	Game.perks.append(id)
	Game.stats.set_source("perk:" + id, d.get("mods", {}))
	EventBus.perk_unlocked.emit(id)
	EventBus.stats_changed.emit()
	ShipAI.say("on_perk", {}, true)
	return true


func to_save() -> Dictionary:
	return {"counts": counts.duplicate(), "declines": declines.duplicate()}


func from_save(data: Dictionary) -> void:
	reset()
	for k in data.get("counts", {}):
		counts[k] = int(data["counts"][k])
	for k in data.get("declines", {}):
		declines[k] = int(data["declines"][k])
