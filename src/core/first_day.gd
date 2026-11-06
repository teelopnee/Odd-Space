class_name FirstDay
extends RefCounted
## "First day in the Sprawl": a four-step checklist for a new life that teaches the game by doing
## (talk -> shop -> fight -> change someone's mind), one small reward per step. Shown above the
## objective in the HUD until done. State in Game.flags["first_day"] (saved with the life).

const STEPS := [
	{"id": "talk", "text": "Talk to someone on the street", "reward": 15},
	{"id": "shop", "text": "Step into a shop or a stall", "reward": 15},
	{"id": "fight", "text": "Win a fight (MELEE from a distance = DASH STRIKE)", "reward": 20},
	{"id": "change", "text": "Change how someone feels about you", "reward": 20},
]


static func start() -> void:
	Game.flags["first_day"] = []


static func active() -> bool:
	return Game.flags.has("first_day") and (Game.flags["first_day"] as Array).size() < STEPS.size()


static func next_text() -> String:
	if not active():
		return ""
	var done: Array = Game.flags["first_day"]
	for s in STEPS:
		if not done.has(s.id):
			return "FIRST DAY %d/%d: %s" % [done.size() + 1, STEPS.size(), s.text]
	return ""


static func done(id: String) -> void:
	if not active():
		return
	var list: Array = Game.flags["first_day"]
	if list.has(id):
		return
	var step: Dictionary = {}
	for s in STEPS:
		if s.id == id:
			step = s
	if step.is_empty():
		return
	list.append(id)
	Game.flags["first_day"] = list
	Game.add_credits(int(step.reward))
	EventBus.toast.emit("FIRST DAY: %s  +%d CR" % [str(step.text).split(" (")[0], int(step.reward)], Color(0.5, 1.0, 0.7))
	if list.size() >= STEPS.size():
		Game.add_item("medkit", 1)
		EventBus.toast.emit("FIRST DAY COMPLETE  +1 MEDKIT", Color(1.0, 0.85, 0.3))
		EventBus.ai_say.emit("You survived a whole day in the Sprawl, captain. That's above the median. I'm almost proud.", "saga")
	EventBus.stats_changed.emit()
