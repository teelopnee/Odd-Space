class_name NPC
extends CharacterBody3D
## Civilians, merchants and recruitable crew. All of them are WITNESSES.
## Talk to a witness mid-radio-call to bribe or threaten them into silence.
## Their greeting changes with: your origin tags, faction standing, and what
## the Causality Graph says this place has heard about you.

const GRAVITY := 24.0

@export var npc_name := "Scavenger"
@export var faction := ""
@export_enum("civilian", "merchant", "recruit") var role := "civilian"
@export var recruit_id := ""
@export var traits: Array[String] = ["poor"]
@export var sprite_name := "civilian_a"
var look: Dictionary = {}
var persona_id := ""
var story_id := ""     ## planet-story / street-event character (Stories autoload)
var job := ""
var need := ""
var attitude := 0      ## -100..100, how much they like the player (Interactions)
var discount := 0.0    ## merchant price discount earned through interactions
var loyal := false     ## won't report you any more
var activity := ""     ## sit | phone | queue | dance | wave | cheer ("" = wander)
var _act_target := Vector3.ZERO
var _act_time := 0.0
var _act_face := Vector3.ZERO
var _act_spot: Node3D = null
var _act_check := 0.0
var _waved := false
var _seated := false

@onready var sprite: BillboardSprite = $Sprite
@onready var witness: WitnessComponent = $Witness
@onready var talk: Interactable = $Talk
@onready var name_label: Label3D = $NameLabel

var hp := 25.0
var state := "idle"  # idle | reporting | flee | dead
var gravity_scale := 1.0
var _assault_node := -1
var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _timer := 0.0
var _flee_from := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _talking := 0.0
var _bark_timer := 0.0
var _bubble: Label3D
var _player: Node3D
var _partner: Node3D = null
static var _barks: Dictionary = {}


func _ready() -> void:
	add_to_group("npc")
	add_to_group("damageable")
	_rng.randomize()
	if role == "recruit" and recruit_id != "":
		var d := Crew.def(recruit_id)
		npc_name = d.get("name", npc_name)
		if d.has("look"):
			look = d["look"]
	if look.is_empty():
		var lrng := RandomNumberGenerator.new()
		lrng.randomize()
		look = CharacterLook.random_look(lrng, "civilian")
	sprite.set_look(look)
	_home = global_position
	_wander_target = _home
	witness.calls_faction = faction if faction != "" else "paragon"
	talk.interacted.connect(_on_talk)
	_bark_timer = _rng.randf_range(3.0, 14.0)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.pixel_size = 0.0042
	_bubble.font_size = 36
	_bubble.outline_size = 12
	_bubble.modulate = Color(1.0, 1.0, 0.92)
	_bubble.outline_modulate = Color(0.08, 0.04, 0.14, 0.95)
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.width = 520
	_bubble.position = Vector3(0, 2.55, 0)
	_bubble.render_priority = 4
	_bubble.visible = false
	add_child(_bubble)
	_act_check = _rng.randf_range(0.5, 6.0)
	EventBus.story_event.connect(func(_k, _i): react_cheer())
	EventBus.interaction_done.connect(func(_v, ok, _n): if ok and _rng.randf() < 0.4: react_cheer())
	EventBus.enemy_killed.connect(func(_e, _i): _on_combat_nearby())
	EventBus.subsystem_broken.connect(func(_e, _s, _f): _on_combat_nearby())
	if role != "recruit":
		Interactions.setup_npc(self, _rng)
	name_label.text = npc_name + ("\n<TRADER>" if role == "merchant" else ("\n<LOOKING FOR WORK>" if role == "recruit" else ""))
	_update_prompt()


func is_alive() -> bool:
	return state != "dead"


func _physics_process(delta: float) -> void:
	if state == "dead":
		return
	_timer -= delta
	_talking -= delta
	_life(delta)
	var move := Vector3.ZERO
	match state:
		"idle":
			if role != "merchant":
				move = _activity(delta) if activity != "" else _wander()
				if activity == "" and story_id == "" and persona_id == "":
					_act_check -= delta
					if _act_check <= 0.0:
						_act_check = _rng.randf_range(6.0, 14.0)
						_pick_activity()
		"flee":
			var away := global_position - _flee_from
			away.y = 0.0
			move = away.normalized()
			if _timer <= 0.0:
				state = "idle"
				_home = global_position
	var speed := 4.2 if state == "flee" else 1.4
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * gravity_scale * delta
	move_and_slide()
	if move.length() > 0.1:
		sprite.set_facing(move)
	elif activity != "" and _act_time > 0.0 and _act_face != Vector3.ZERO:
		sprite.set_facing(_act_face)
	elif _partner != null and is_instance_valid(_partner):
		sprite.set_facing(_partner.global_position - global_position)
	elif _player != null and global_position.distance_to(_player.global_position) < 3.5:
		sprite.set_facing(_player.global_position - global_position)
	if state == "flee":
		sprite.play("run")
	elif move.length() > 0.1:
		sprite.play("walk")
	elif state == "reporting" or _talking > 0.0:
		sprite.play("talk")
	elif activity != "" and _act_time > 0.0:
		sprite.play(_activity_anim())
	else:
		sprite.play("idle")


# --- Daily life: benches, phones, food queues, dancing near holograms ----------------------

func _pick_activity() -> void:
	var roll := _rng.randf()
	var spots := get_tree().get_nodes_in_group("life_spot")
	var best: Node3D = null
	var best_d := 14.0
	for sp in spots:
		var d: float = (sp as Node3D).global_position.distance_to(global_position)
		if d < best_d and not sp.get_meta("taken", false) and _rng.randf() < 0.7:
			best = sp
			best_d = d
	if best != null and roll < 0.65:
		_act_spot = best
		best.set_meta("taken", true)
		activity = str(best.get_meta("kind", "sit"))
		_act_target = best.global_position
		_act_face = best.get_meta("face", Vector3.BACK)
		_act_time = -1.0  # walking there first
		return
	if roll < 0.85:
		activity = "phone"
		_act_target = global_position
		_act_face = Vector3(_rng.randf_range(-1, 1), 0, 1).normalized()
		_act_time = _rng.randf_range(6.0, 16.0)


func _activity(delta: float) -> Vector3:
	if _act_time < 0.0:
		var to := _act_target - global_position
		to.y = 0.0
		if to.length() > 0.35:
			return to.normalized()
		global_position.x = _act_target.x
		global_position.z = _act_target.z
		_act_time = _rng.randf_range(12.0, 35.0)
		if activity == "sit":
			# Shift the sprite back onto the bench seat (the body stays clear of its collider).
			sprite.position += -_act_face * 0.42
			sprite.y_offset = 0.2
			_seated = true
		return Vector3.ZERO
	_act_time -= delta
	if _act_time <= 0.0:
		end_activity()
	return Vector3.ZERO


func _activity_anim() -> String:
	match activity:
		"sit":
			return "sit"
		"phone":
			return "phone"
		"dance":
			return "dance"
		"cheer":
			return "cheer"
		"wave":
			return "wave"
		"queue":
			return "talk" if fmod(_act_time, 7.0) < 2.0 else "idle"
	return "idle"


func end_activity() -> void:
	if _seated:
		sprite.position -= -_act_face * 0.42
		sprite.y_offset = 0.0
		_seated = false
	if _act_spot != null and is_instance_valid(_act_spot):
		_act_spot.set_meta("taken", false)
	_act_spot = null
	activity = ""
	_act_time = 0.0
	_home = global_position
	_wander_target = _home


## Something good just happened nearby: the crowd cheers.
func react_cheer() -> void:
	if state != "idle" or _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > 12.0 or attitude < -10:
		return
	if activity != "" and activity != "phone":
		return
	activity = "cheer"
	_act_face = (_player.global_position - global_position) * Vector3(1, 0, 1)
	_act_time = _rng.randf_range(2.0, 3.5)
	if _rng.randf() < 0.4:
		say(["WOOO!", "Legend!", "Did you see that?!", "Finally, someone did something!", "Put it on Lumen!"][_rng.randi() % 5], 2.0)


func _wander() -> Vector3:
	if _timer > 0.0:
		return Vector3.ZERO
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 0.4 or _timer < -5.0:
		_timer = _rng.randf_range(1.5, 4.0)
		_wander_target = _home + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
		return Vector3.ZERO
	return to.normalized()


# --- Witness hooks ----------------------------------------------------------------------

func on_report_started() -> void:
	state = "reporting"
	_update_prompt()


func on_report_finished() -> void:
	if state == "reporting":
		state = "idle"
	_update_prompt()


func _update_prompt() -> void:
	if not is_instance_valid(talk):
		return
	if state == "reporting":
		talk.prompt = "STOP %s'S CALL" % npc_name.to_upper()
	elif role == "merchant":
		talk.prompt = "Trade with %s" % npc_name
	elif role == "recruit":
		talk.prompt = "Talk to %s" % npc_name
	else:
		talk.prompt = "Talk to %s" % npc_name
	talk.enabled = state != "dead"


# --- Damage -------------------------------------------------------------------------------

func take_hit(info: Dictionary) -> void:
	if state == "dead":
		return
	var attacker = info.get("attacker")
	var by_player: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	if by_player and _assault_node < 0:
		_assault_node = Causality.record("assault", {"target": npc_name, "target_faction": faction,
			"position": global_position, "exclude": [self]})
	hp -= float(info.get("damage", 1.0))
	sprite.flash()
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.9, 0), str(roundi(float(info.get("damage", 1.0)))), Color(1, 0.8, 0.8))
	if hp <= 0.0:
		_die(by_player)
		return
	if state != "reporting":
		state = "flee"
		_timer = 3.0
		_flee_from = attacker.global_position if by_player else global_position


func receive_attack(info: Dictionary) -> String:
	take_hit(info)
	return "hit"


func _die(by_player: bool) -> void:
	state = "dead"
	remove_from_group("damageable")
	collision_layer = 0
	witness.silence("killed")
	talk.enabled = false
	name_label.visible = false
	sprite.play("dead", true)
	if by_player:
		var info := {"target": npc_name, "target_faction": faction, "position": global_position, "exclude": [self]}
		if _assault_node >= 0:
			info["causes"] = [_assault_node]
		Causality.record("murder", info)
	Audio.play_sfx("enemy_die")
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(sprite.fade_to.bind(0.0, 0.8))
	tw.tween_interval(0.8)
	tw.tween_callback(queue_free)


# --- Dialogue -------------------------------------------------------------------------------

func _on_talk(_player: Node) -> void:
	if story_id != "" and state != "reporting":
		_talking = 3.0
		Stories.on_npc_talk(self)
		return
	if persona_id != "" and state != "reporting":
		_talking = 3.0
		Saga.on_persona_talk(persona_id)
		return
	if state == "reporting":
		_talk_witness()
	elif role == "merchant":
		_talk_merchant()
	elif role == "recruit":
		_talk_recruit()
	else:
		_talk_civilian()


func bribe_cost() -> int:
	var sev := 0
	for id in witness.reports:
		sev += int(Causality.get_node_data(id).get("severity", 1))
	return roundi((30 + sev * 15) * Game.stat("bribe_mult"))


func _talk_witness() -> void:
	var cost := bribe_cost()
	var choices := [
		{"id": "bribe", "text": "Bribe them (%d cr)" % cost, "disabled": not Game.can_afford(cost)},
		{"id": "voucher", "text": "Hand over a Bribe Voucher", "disabled": Game.item_count("bribe_voucher") <= 0},
		{"id": "threaten", "text": "Threaten them (%d%% chance)" % roundi(_threaten_chance() * 100)},
	]
	choices.append_array(Interactions.choices_for(self, "witness").slice(0, 4))
	choices.append({"id": "leave", "text": "Let them finish the call"})
	EventBus.dialogue_requested.emit(npc_name, "\"Stay back! I'm on with %s right now. They're putting me through to a supervisor!\"" % witness.calls_faction.capitalize(), choices, _on_witness_choice)


func _threaten_chance() -> float:
	var c := 0.4
	if Game.has_flag("sleeper") or Game.has_flag("has_alias"):
		c += 0.15
	c += clampf(Causality.infamy_at(Game.location_id, faction) * 0.03, 0.0, 0.3)  # a known killer is scarier
	return clampf(c, 0.05, 0.9)


func _on_witness_choice(choice: String) -> void:
	if choice.begins_with("act:"):
		Interactions.resolve(self, choice.substr(4))
		_update_prompt()
		return
	match choice:
		"bribe":
			if Game.spend(bribe_cost()):
				_silence_by_bribe("bribe")
		"voucher":
			if Game.item_count("bribe_voucher") > 0:
				Game.add_item("bribe_voucher", -1)
				_silence_by_bribe("voucher")
		"threaten":
			if _rng.randf() < _threaten_chance():
				witness.silence("threatened")
				Causality.record("intimidate", {"target": npc_name, "target_faction": faction})
				EventBus.dialogue_requested.emit(npc_name, "\"...Line's dead. Must be static. I didn't see anything. I don't even have eyes.\"", [], Callable())
				state = "flee"
				_timer = 4.0
				_flee_from = global_position
			else:
				# Botched threat: they talk faster.
				witness.progress = minf(0.95, witness.progress + 0.35)
				EventBus.dialogue_requested.emit(npc_name, "\"Are you THREATENING me? Supervisor, are you getting this?!\"", [], Callable())
	_update_prompt()


func _silence_by_bribe(method: String) -> void:
	witness.silence("bribed")
	Causality.record("bribe", {"target": npc_name, "target_faction": faction, "note": method})
	EventBus.dialogue_requested.emit(npc_name, "\"Sorry, Paragon, wrong number. Just ordering a pizza.\" They pocket the cash and look away.", [], Callable())


func _talk_merchant() -> void:
	if not Factions.will_trade(faction):
		EventBus.dialogue_requested.emit(npc_name, "\"%s policy: I don't serve your kind. 'Your kind' being people with your credit rating.\"" % DataDB.faction_name(faction), [], Callable())
		return
	var choices := [{"id": "shop", "text": "Browse the goods%s" % ("  (-%d%%)" % roundi(discount * 100) if discount > 0.01 else ("  (+%d%%)" % roundi(-discount * 100) if discount < -0.01 else ""))}]
	choices.append_array(Interactions.choices_for(self, "merchant"))
	choices.append({"id": "leave", "text": "Leave"})
	EventBus.dialogue_requested.emit(npc_name, Interactions.greeting(self) + "\n\"Buying, selling, or wasting my billable time?\"", choices, _on_merchant_choice)


func _on_merchant_choice(choice: String) -> void:
	if choice.begins_with("act:"):
		Interactions.resolve(self, choice.substr(4))
		return
	if choice == "shop":
		open_shop()


func open_shop() -> void:
	Game.shop_discount = discount
	EventBus.shop_requested.emit(npc_name, faction, ["medkit", "air_canister", "antihistamine", "bribe_voucher", "lockpick", "painkillers", "paste_ration", "cyberdeck", "loaded_dice"])


func _talk_recruit() -> void:
	var d := Crew.def(recruit_id)
	if d.is_empty() or Crew.has_member(recruit_id):
		_talk_civilian()
		return
	var text := "[b]%s[/b] - %s\n%s\n\n\"%s\"" % [d.get("name", ""), d.get("title", ""), d.get("bio", ""), d.get("recruit_line", "")]
	var choices := [
		{"id": "join", "text": "Join the Odd Duck", "disabled": Crew.is_full()},
		{"id": "no", "text": "Not right now"},
	]
	EventBus.dialogue_requested.emit(npc_name, text, choices, _on_recruit_choice)


func _on_recruit_choice(choice: String) -> void:
	if choice == "join" and Crew.recruit(recruit_id):
		EventBus.dialogue_requested.emit(npc_name, "\"Let's go make some bad decisions together, captain.\"", [], Callable())
		witness.active = false
		talk.enabled = false
		var tw := create_tween()
		tw.tween_callback(sprite.fade_to.bind(0.0, 0.8))
		tw.tween_interval(0.8)
		tw.tween_callback(queue_free)


func _talk_civilian() -> void:
	var lines: Array[String] = []
	var known := Causality.known_crimes_at(Game.location_id, faction)
	if not known.is_empty():
		var worst: Dictionary = known[0]
		for n in known:
			if int(n.severity) > int(worst.severity):
				worst = n
		lines.append("\"Wait... you're the one from the news! The %s at %s!\"" % [str(worst.label).to_lower(), worst.location_name])
		attitude -= 10
	else:
		lines.append(Interactions.greeting(self))
	if job != "":
		lines.append("[i](%s - %s, %s)[/i]" % [npc_name, job, "friendly" if attitude >= 15 else ("hostile" if attitude <= -15 else "wary")])
	var crisis := PlanetGenerator.layer(Game.current_planet, "crises") if not Game.current_planet.is_empty() else {}
	if not crisis.is_empty() and _rng.randf() < 0.35:
		lines.append("\"And with this %s going on... %s\"" % [str(crisis.get("name", "")).to_lower(), crisis.get("desc", "")])
	var choices := Interactions.choices_for(self, "civilian")
	choices.append({"id": "rumor", "text": "Ask what people are saying"})
	choices.append({"id": "leave", "text": "Leave"})
	EventBus.dialogue_requested.emit(npc_name, "\n".join(lines), choices, _on_civilian_choice)


func _on_civilian_choice(choice: String) -> void:
	if choice.begins_with("act:"):
		Interactions.resolve(self, choice.substr(4))
		return
	if choice == "rumor":
		var text := Interactions.rumor(self) if attitude > -25 else "\"Rumours cost extra for people like you.\""
		EventBus.dialogue_requested.emit(npc_name, text, [], Callable())


## Bought, charmed or scared into loyalty: they stop reporting you.
func make_loyal() -> void:
	loyal = true
	if witness.is_reporting():
		witness.silence("talked")
	witness.active = false
	_update_prompt()


## A story/street character's part is over: drop the marker and go back to normal life.
func story_left(sid: String) -> void:
	if story_id != sid:
		return
	story_id = ""
	var m := get_node_or_null("QuestMarker")
	if m:
		m.queue_free()
	for c in get_children():
		if c is MeshInstance3D and c.mesh is QuadMesh:
			c.queue_free()  # the marker's light beam
	_update_prompt()


func flee_from_player() -> void:
	end_activity()
	state = "flee"
	_timer = 4.0
	_flee_from = _player.global_position if _player != null and is_instance_valid(_player) else global_position


func _pick(options: Array) -> String:
	return options[_rng.randi() % options.size()]


# --- Ambient life -----------------------------------------------------------------------------

static func barks() -> Dictionary:
	if _barks.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/barks.json"))
		_barks = parsed if parsed is Dictionary else {"civilian": ["..."]}
	return _barks


func _life(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_bark_timer -= delta
	if _player != null and is_instance_valid(_player) and name_label:
		# Only nearby or important people show their name - keeps crowds readable.
		var important: bool = story_id != "" or persona_id != "" or role != "civilian" or state == "reporting"
		name_label.visible = important or global_position.distance_squared_to(_player.global_position) < 30.0
	if not _waved and _player != null and state == "idle" and attitude >= 20 and activity in ["", "phone"] \
			and global_position.distance_to(_player.global_position) < 5.0:
		_waved = true
		activity = "wave"
		_act_face = (_player.global_position - global_position) * Vector3(1, 0, 1)
		_act_time = 2.2
		say(["Hey! It's you!", "Looking good, friend.", "Stay safe out there!", "Thanks for before!"][_rng.randi() % 4], 2.2)
	if _bark_timer > 0.0 or state != "idle" or _player == null:
		return
	_bark_timer = _rng.randf_range(9.0, 22.0)
	var d := global_position.distance_to(_player.global_position)
	if d > 11.0:
		return
	# Small talk with a neighbour?
	_partner = null
	for n in get_tree().get_nodes_in_group("npc"):
		if n != self and n.state == "idle" and n.global_position.distance_to(global_position) < 3.2:
			_partner = n
			break
	var pool: Array = []
	var b := barks()
	if not Causality.known_crimes_at(Game.location_id, faction).is_empty() and _rng.randf() < 0.6:
		pool = b.get("infamous", [])
	elif _partner != null and _rng.randf() < 0.6:
		pool = b.get("pair", [])
		_partner.call_deferred("hear_partner")
	elif not Game.current_planet.is_empty() and _rng.randf() < 0.3:
		pool = b.get("crisis:" + str(Game.current_planet.get("crisis", "")), [])
	elif Game.current_planet.is_empty() and _rng.randf() < 0.3:
		pool = b.get("station", [])
	else:
		pool = _reactive_barks(b)
	if pool.is_empty() and role == "civilian" and _rng.randf() < 0.55:
		# Fresh small talk every time: the copywriter knows the shows, the teams, the prices.
		say(Copy.make("chatter", _rng))
		return
	if pool.is_empty():
		pool = b.get(role, b.get("civilian", []))
	if not pool.is_empty():
		say(str(pool[_rng.randi() % pool.size()]).replace("{name}", Game.player_name))


## Lines about YOU and this place: fame, bounty, class, age, the planet's story outcome, the biome.
func _reactive_barks(b: Dictionary) -> Array:
	var options := []
	if int(Game.flags.get("fame", 0)) >= 15:
		options.append("famous")
	if Factions.total_bounty() >= 300:
		options.append("wanted")
	var w := Origin.wealth()
	if w >= 4:
		options.append("rich_player")
	elif w <= 0:
		options.append("poor_player")
	if Game.tags.get("age", "") in ["elder", "ancient"]:
		options.append("old_player")
	elif Game.tags.get("age", "") == "teen":
		options.append("young_player")
	if Game.current_planet.get("liberated", false):
		options.append("liberated")
	match str(Game.current_planet.get("crisis_state", "")):
		"resolved":
			options.append("story_good")
		"worse":
			options.append("story_bad")
	var env := str(Game.current_planet.get("environment", ""))
	if env != "":
		options.append("biome:" + env)
	if options.is_empty() or _rng.randf() < 0.35:
		return []
	return b.get(options[_rng.randi() % options.size()], [])


func hear_partner() -> void:
	_talking = 2.5
	_bark_timer = maxf(_bark_timer, 4.0)


func say(text: String, duration: float = 3.4) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	_talking = duration
	var tw := create_tween()
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(_bubble, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _bubble.visible = false)
	EventBus.speech_bubble.emit(self, text)


func _on_combat_nearby() -> void:
	if state != "idle" or _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) < 10.0 and _rng.randf() < 0.5:
		var lines: Array = barks().get("combat", [])
		if not lines.is_empty():
			say(lines[_rng.randi() % lines.size()], 2.0)
		end_activity()
		state = "flee"
		_timer = 2.5
		_flee_from = _player.global_position
