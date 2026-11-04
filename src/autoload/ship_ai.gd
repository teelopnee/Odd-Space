extends Node
## "ShipAI" autoload - Q.U.A.C.K., the Odd Duck's sarcastic ship AI.
## Listens to the EventBus and comments. Lines live in data/ai_lines.json.
## Uses per-key and global cooldowns so it stays funny instead of spammy.

const GLOBAL_COOLDOWN := 6.0
const KEY_COOLDOWN := 25.0
const IDLE_MIN := 70.0
const IDLE_MAX := 120.0

var enabled := true
var _cooldowns: Dictionary = {}  # key -> time remaining
var _global := 0.0
var _idle_timer := 90.0
var _rng := RandomNumberGenerator.new()
var _last_line := ""


func _ready() -> void:
	_rng.randomize()
	EventBus.action_recorded.connect(_on_action_recorded)
	EventBus.action_status_changed.connect(_on_status_changed)
	EventBus.player_parried.connect(func(_a): say("on_parry"))
	EventBus.subsystem_broken.connect(_on_subsystem_broken)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.player_died.connect(func(): say("on_death", {}, true))
	EventBus.planet_entered.connect(_on_planet_entered)


func _process(delta: float) -> void:
	_global = maxf(0.0, _global - delta)
	for k in _cooldowns.keys():
		_cooldowns[k] -= delta
		if _cooldowns[k] <= 0.0:
			_cooldowns.erase(k)
	if Game.has_active_run and Game.air_billing_active and not get_tree().paused:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = _rng.randf_range(IDLE_MIN, IDLE_MAX)
			say("idle")


## Say a random line for `key`. vars fill {tokens}. force ignores cooldowns.
func say(key: String, vars: Dictionary = {}, force: bool = false) -> void:
	if not enabled:
		return
	if not force and (_global > 0.0 or _cooldowns.has(key)):
		return
	var lines: Array = DataDB.ai_lines.get(key, [])
	if lines.is_empty():
		return
	var line: String = lines[_rng.randi() % lines.size()]
	if lines.size() > 1 and line == _last_line:
		line = lines[(lines.find(line) + 1) % lines.size()]
	_last_line = line
	var all_vars := {"name": Game.player_name, "planet": Game.location_name}
	all_vars.merge(vars, true)
	_global = GLOBAL_COOLDOWN
	_cooldowns[key] = KEY_COOLDOWN
	_idle_timer = maxf(_idle_timer, 30.0)
	EventBus.ai_say.emit(line.format(all_vars), key)


func _on_action_recorded(node: Dictionary) -> void:
	if node.status == Causality.STATUS_PENDING:
		say("on_witness", {}, true)
		return
	match node.verb:
		"theft":
			say("on_theft")
		"murder":
			say("on_murder", {}, true)
		"assault":
			say("on_assault")
		"vandalism":
			say("on_vandalism")
	if node.status == Causality.STATUS_SECRET and int(node.severity) >= 2:
		say("on_secret")


func _on_status_changed(node: Dictionary, _old: String) -> void:
	match node.status:
		Causality.STATUS_REPORTED:
			say("on_reported", {}, true)
		Causality.STATUS_SUPPRESSED:
			say("on_suppressed", {}, true)


func _on_subsystem_broken(_enemy: Node, _sub: String, effect: String) -> void:
	match effect:
		"explode":
			say("on_jetpack_boom", {}, true)
		"crippled":
			say("on_legs_broken")


func _on_enemy_killed(_enemy: Node, _info: Dictionary) -> void:
	if _rng.randf() < 0.3:
		say("on_kill")


func _on_hp_changed(hp: float, max_hp: float) -> void:
	if hp > 0.0 and hp < max_hp * 0.3:
		say("on_low_hp")


func _on_planet_entered(planet: Dictionary) -> void:
	var crisis_name := ""
	for c in DataDB.planets.get("crises", []):
		if c.get("id", "") == planet.get("crisis", ""):
			crisis_name = c.get("name", "")
	say("on_land", {"planet": planet.get("name", "?"), "crisis": crisis_name}, true)
