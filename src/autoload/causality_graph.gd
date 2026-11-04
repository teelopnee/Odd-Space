extends Node
## "Causality" autoload - the Causality Graph Engine. The game's memory.
##
## Every meaningful action becomes a NODE:
##   {id, verb, label, actor, target, target_faction, location, location_name,
##    time, severity, witnesses[], status, causes[], effects[], moral{}, headline, note}
##
## Nodes link to each other (causes -> effects), e.g.
##   theft #3 --(witness saw it)--> murder #4 (you shot the witness) --> news #5 ...
##
## STATUS lifecycle:
##   secret     : nobody saw it. No world consequences (crew still judge you).
##   pending    : one or more witnesses are on the radio RIGHT NOW.
##   reported   : a witness finished the call (or it was public). Consequences fire:
##                rep loss, bounty, Lumen headline. Other places may hear about it.
##   suppressed : every witness was silenced (killed/bribed) before finishing.
##                "The news never spreads if you kill the witness before the radio call."

const STATUS_SECRET := "secret"
const STATUS_PENDING := "pending"
const STATUS_REPORTED := "reported"
const STATUS_SUPPRESSED := "suppressed"

## Verbs that count as crimes for infamy/NPC reactions.
const CRIME_VERBS := ["theft", "vandalism", "assault", "murder", "smuggle", "trespass", "bribe"]
## Reported nodes with severity >= this are galactic news (known everywhere).
const GALACTIC_SEVERITY := 4

var nodes: Array = []            # index == node id
var _pending: Dictionary = {}    # node_id -> Array[String] witness ids still calling
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func reset() -> void:
	nodes.clear()
	_pending.clear()


# --- Recording ------------------------------------------------------------------------

## Record an action. info keys (all optional):
##   target (String display name), target_faction, location, location_name,
##   causes (Array[int]), moral (Dictionary override), note,
##   public (bool: consequences fire immediately, e.g. encounter choices),
##   position (Vector3: run witness detection around this point),
##   exclude (Array[Node]: e.g. the victim can't witness their own murder).
## Returns the new node id.
func record(verb: String, info: Dictionary = {}) -> int:
	var rule: Dictionary = DataDB.consequences.get(verb, {})
	var node := {
		"id": nodes.size(),
		"verb": verb,
		"label": rule.get("label", verb.capitalize()),
		"actor": info.get("actor", "player"),
		"target": info.get("target", ""),
		"target_faction": info.get("target_faction", ""),
		"location": info.get("location", Game.location_id),
		"location_name": info.get("location_name", Game.location_name),
		"time": snappedf(Game.play_time, 0.1),
		"severity": int(rule.get("severity", 1)),
		"witnesses": [],
		"status": STATUS_SECRET,
		"causes": [],
		"effects": [],
		"moral": info.get("moral", rule.get("moral", {})),
		"headline": "",
		"note": info.get("note", ""),
	}
	nodes.append(node)
	for cause_id in info.get("causes", []):
		link(int(cause_id), node.id, false)

	if info.get("public", false):
		node.status = STATUS_REPORTED
	elif info.has("position"):
		var witnesses := _find_witnesses(info["position"], info.get("exclude", []))
		if not witnesses.is_empty():
			node.status = STATUS_PENDING
			_pending[node.id] = []
			for w in witnesses:
				node.witnesses.append(w.witness_id)
				_pending[node.id].append(w.witness_id)

	EventBus.action_recorded.emit(node)

	if node.status == STATUS_REPORTED:
		_apply_consequences(node)
	elif node.status == STATUS_PENDING:
		# Start the radio calls after the signal so UI shows the crime first.
		for w in _find_witness_nodes(node.witnesses):
			w.begin_report(node.id)
	return node.id


func link(cause_id: int, effect_id: int, emit: bool = true) -> void:
	if not _valid(cause_id) or not _valid(effect_id) or cause_id == effect_id:
		return
	if not nodes[effect_id].causes.has(cause_id):
		nodes[effect_id].causes.append(cause_id)
	if not nodes[cause_id].effects.has(effect_id):
		nodes[cause_id].effects.append(effect_id)
	if emit:
		EventBus.action_status_changed.emit(nodes[effect_id], nodes[effect_id].status)


# --- Witness callbacks (called by WitnessComponent) ------------------------------------

func witness_reported(node_id: int, witness_id: String) -> void:
	if not _valid(node_id):
		return
	var node: Dictionary = nodes[node_id]
	if node.status == STATUS_PENDING:
		_set_status(node, STATUS_REPORTED)
		_apply_consequences(node)
	_drop_pending(node_id, witness_id)


func witness_silenced(node_id: int, witness_id: String) -> void:
	if not _valid(node_id) or not _pending.has(node_id):
		return
	_drop_pending(node_id, witness_id)
	var node: Dictionary = nodes[node_id]
	if not _pending.has(node_id) and node.status == STATUS_PENDING:
		_set_status(node, STATUS_SUPPRESSED)


## Called when a level unloads: anyone still on the radio finishes the call
## after you leave. Running away does not un-ring the bell.
func flush_pending() -> void:
	for node_id in _pending.keys():
		var node: Dictionary = nodes[node_id]
		if node.status == STATUS_PENDING:
			_set_status(node, STATUS_REPORTED)
			_apply_consequences(node)
	_pending.clear()


func is_pending(node_id: int) -> bool:
	return _valid(node_id) and nodes[node_id].status == STATUS_PENDING


# --- Queries ------------------------------------------------------------------------------

func get_node_data(node_id: int) -> Dictionary:
	return nodes[node_id] if _valid(node_id) else {}


func query(verb: String = "", status: String = "", location: String = "") -> Array:
	var out := []
	for n in nodes:
		if verb != "" and n.verb != verb:
			continue
		if status != "" and n.status != status:
			continue
		if location != "" and n.location != location:
			continue
		out.append(n)
	return out


func count(verb: String, status: String = "") -> int:
	return query(verb, status).size()


func reported_count() -> int:
	return query("", STATUS_REPORTED).size()


## Reported crimes that people at `location_id` (controlled by `controller`) know about:
## local crimes, crimes against the local controller, and galactic headlines.
func known_crimes_at(location_id: String, controller: String = "") -> Array:
	var out := []
	for n in nodes:
		if n.status != STATUS_REPORTED or not CRIME_VERBS.has(n.verb):
			continue
		if n.location == location_id or n.severity >= GALACTIC_SEVERITY \
				or (controller != "" and n.target_faction == controller):
			out.append(n)
	return out


func infamy_at(location_id: String, controller: String = "") -> int:
	var total := 0
	for n in known_crimes_at(location_id, controller):
		total += int(n.severity)
	return total


func latest_headlines(max_count: int = 5) -> Array[String]:
	var out: Array[String] = []
	for i in range(nodes.size() - 1, -1, -1):
		var h: String = nodes[i].get("headline", "")
		if h != "":
			out.append(h)
			if out.size() >= max_count:
				break
	return out


## Walk causes upward: returns [root, ..., node].
func chain_to(node_id: int) -> Array:
	var out := []
	var guard := 0
	var current := node_id
	while _valid(current) and guard < 32:
		out.push_front(nodes[current])
		var causes: Array = nodes[current].causes
		if causes.is_empty():
			break
		current = int(causes[0])
		guard += 1
	return out


func describe(node: Dictionary) -> String:
	var s: String = "#%d %s" % [node.id, node.label]
	if node.target != "":
		s += " - " + str(node.target)
	if node.target_faction != "":
		s += " (%s)" % DataDB.faction_name(node.target_faction)
	s += " @ " + str(node.location_name)
	return s


# --- Persistence --------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"nodes": nodes.duplicate(true)}


func from_save(data: Dictionary) -> void:
	reset()
	for n in data.get("nodes", []):
		n["id"] = int(n["id"])
		n["severity"] = int(n.get("severity", 1))
		n["causes"] = n.get("causes", []).map(func(c): return int(c))
		n["effects"] = n.get("effects", []).map(func(c): return int(c))
		nodes.append(n)
	# Witnesses who were mid-call when we saved finished their calls "off screen".
	for n in nodes:
		if n.status == STATUS_PENDING:
			n.status = STATUS_REPORTED
			_apply_consequences(n)


# --- Internals ------------------------------------------------------------------------------

func _valid(node_id: int) -> bool:
	return node_id >= 0 and node_id < nodes.size()


func _set_status(node: Dictionary, status: String) -> void:
	var old: String = node.status
	if old == status:
		return
	node.status = status
	EventBus.action_status_changed.emit(node, old)


func _drop_pending(node_id: int, witness_id: String) -> void:
	if not _pending.has(node_id):
		return
	_pending[node_id].erase(witness_id)
	if _pending[node_id].is_empty():
		_pending.erase(node_id)


func _find_witnesses(pos: Vector3, exclude: Array) -> Array:
	var out := []
	for w in get_tree().get_nodes_in_group("witness"):
		if not is_instance_valid(w) or not w.has_method("can_witness"):
			continue
		if exclude.has(w.get_parent()) or exclude.has(w):
			continue
		if w.can_witness(pos):
			out.append(w)
	return out


func _find_witness_nodes(ids: Array) -> Array:
	var out := []
	for w in get_tree().get_nodes_in_group("witness"):
		if is_instance_valid(w) and ids.has(w.witness_id):
			out.append(w)
	return out


func _apply_consequences(node: Dictionary) -> void:
	var rule: Dictionary = DataDB.consequences.get(node.verb, {})
	var target_faction: String = node.target_faction
	var rep_rules: Dictionary = rule.get("rep", {})
	for key in rep_rules:
		var fid: String = target_faction if key == "$target" else key
		if fid != "":
			Factions.change_rep(fid, int(rep_rules[key]), node.label)
	var bounty := int(rule.get("bounty", 0))
	if bounty > 0:
		var bounty_faction := target_faction if DataDB.factions.has(target_faction) else "paragon"
		Factions.add_bounty(bounty_faction, bounty)
	var news: Array = rule.get("news", [])
	if not news.is_empty():
		var template: String = news[_rng.randi() % news.size()]
		var target_name: String = DataDB.faction_name(target_faction) if target_faction != "" else str(node.target)
		node.headline = template.format({"location": node.location_name, "target_name": target_name})
		EventBus.news_broadcast.emit(node.headline, node)
	if node.verb == "theft" and not node.witnesses.is_empty():
		FlawPerk.report_mishap("caught_stealing")
