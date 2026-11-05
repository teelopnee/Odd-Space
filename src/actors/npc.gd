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
## What they saw you do (NPCVoice): [{kind, stance, target, t}], newest first.
var memories: Array = []
var tic := ""  ## personal verbal tic ("Swear on my lungs.") - see NPCVoice.say
## Consequences of what you did to them (see "Impact" below).
var owes_favour := false
var grudge := false
var repossessed := false
var scared_until := 0.0
var _favour_wait := 0.0
var _grudge_wait := 0.0
var _mood_bark := 0.0
var _leaving := false
static var _act_seen := {}  # "frame:kind" -> how many bystanders already reacted out loud


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
	EventBus.interaction_done.connect(_on_interaction_seen)
	EventBus.action_recorded.connect(_on_action_seen)
	EventBus.enemy_killed.connect(_on_kill_seen)
	EventBus.perfect_dodge.connect(func(): witness_act("skill", "a bullet"))
	EventBus.player_parried.connect(func(a): witness_act("skill", str(a.get("display_name")) if a and is_instance_valid(a) and "display_name" in a else "someone"))
	EventBus.player_act.connect(func(k, t): witness_act(k, t))
	EventBus.enemy_killed.connect(func(_e, _i): _on_combat_nearby())
	EventBus.subsystem_broken.connect(func(_e, _s, _f): _on_combat_nearby())
	if role != "recruit":
		Interactions.setup_npc(self, _rng)
	tic = Copy.make("tic", _rng) if _rng.randf() < 0.7 else ""
	name_label.text = npc_name + ("\n<TRADER>" if role == "merchant" else ("\n<LOOKING FOR WORK>" if role == "recruit" else ""))
	_update_prompt()
	refresh_label()


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
			if role != "merchant" or activity == "kneel":
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
		"kneel":
			return "surrender"
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


## Witness contract: friends and people you've bought won't pick up the phone.
func will_report() -> bool:
	return not loyal and attitude < 45


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
	var text := "\"Stay back! I'm on with %s right now. They're putting me through to a supervisor!\"" % witness.calls_faction.capitalize()
	text += "\n[color=#ffd23e]> The call is %d%% done. Win them over (pay, charm, scare...) and it dies; botch it and they talk faster.[/color]" % roundi(witness.progress * 100.0)
	for l in Interactions._other_callers(self):
		text += "\n> " + l
	EventBus.dialogue_requested.emit(npc_name, text, choices, _on_witness_choice)


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
				scared_until = Game.play_time + 150.0
				attitude = mini(attitude, -20)
				EventBus.dialogue_requested.emit(npc_name, "\"...Line's dead. Must be static. I didn't see anything. I don't even have eyes.\"" + _call_footer(true), [], Callable())
				flee_from_player()
			else:
				# Botched threat: they talk faster.
				witness.progress = minf(0.95, witness.progress + 0.35)
				attitude = mini(attitude, -30)
				EventBus.dialogue_requested.emit(npc_name, "\"Are you THREATENING me? Supervisor, are you getting this?!\"" + _call_footer(false), [], Callable())
	refresh_label()
	_update_prompt()


func _silence_by_bribe(method: String) -> void:
	witness.silence("bribed")
	Causality.record("bribe", {"target": npc_name, "target_faction": faction, "note": method})
	make_loyal()
	attitude = maxi(attitude, 10)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.6, 0), "CALL CUT", Color(0.5, 1.0, 0.6), true)
	EventBus.dialogue_requested.emit(npc_name, "\"Sorry, Paragon, wrong number. Just ordering a pizza.\" They pocket the cash and look away." + _call_footer(true), [], Callable())


## Result block for the stop-the-call dialogue: did it work, who else is still calling.
func _call_footer(cut: bool) -> String:
	var t := "\n\n[color=#9adfff]> "
	if cut:
		t += "[color=#7dff4a]CALL CUT - %s hangs up and won't report you.[/color]" % npc_name
	else:
		t += "[color=#ff5a5a]That made it worse - %d%% through the call.[/color]" % roundi(witness.progress * 100.0)
	for l in Interactions._other_callers(self):
		t += "\n> " + l
	return t + "[/color]"


func _talk_merchant() -> void:
	if not Factions.will_trade(faction):
		EventBus.dialogue_requested.emit(npc_name, "\"%s policy: I don't serve your kind. 'Your kind' being people with your credit rating.\"" % DataDB.faction_name(faction), [], Callable())
		return
	var choices := [{"id": "shop", "text": "Browse the goods%s" % ("  (-%d%%)" % roundi(discount * 100) if discount > 0.01 else ("  (+%d%%)" % roundi(-discount * 100) if discount < -0.01 else ""))}]
	choices.append_array(Interactions.choices_for(self, "merchant"))
	choices.append({"id": "leave", "text": "Leave"})
	EventBus.dialogue_requested.emit(npc_name, _opening_line() + "\n" + Copy.expand("\"#merchant_ask#\"", _rng), choices, _on_merchant_choice)


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
		lines.append(_opening_line())
		if _rng.randf() < 0.55:
			lines.append(NPCVoice.remark(self, _rng))
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


## First thing they say: what they saw you do, what the street says about you, or who you are.
func _opening_line() -> String:
	if not memories.is_empty() and _rng.randf() < 0.85:
		return NPCVoice.recall(self, memories[0], _rng)
	if not NPCVoice.street_memory().is_empty() and _rng.randf() < 0.35:
		return NPCVoice.gossip(self, _rng)
	return Interactions.greeting(self) if _rng.randf() < 0.4 else NPCVoice.remark(self, _rng)


# --- Eyes and memory -------------------------------------------------------------------------

## Something the player did. If it happened in this NPC's line of sight they remember it,
## change their opinion by their stance, and the first couple of bystanders say so out loud.
func witness_act(kind: String, target: String = "", victim: Node = null) -> void:
	if kind == "" or state == "dead" or not is_inside_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var me := victim == self
	if not me and not witness.can_see(_player.global_position):
		return
	if not memories.is_empty() and memories[0]["kind"] == kind and absf(float(memories[0]["t"]) - Game.play_time) < 0.5:
		return  # same act reported twice (verb + Causality record)
	var st := NPCVoice.stance_for(self, kind)
	var stamp := "%d:%s" % [Engine.get_process_frames(), kind]
	if not _act_seen.has(stamp):
		_act_seen = {stamp: 0}
		NPCVoice.add_street_memory(kind)
	memories.push_front({"kind": kind, "stance": st, "target": "me" if me else target, "t": Game.play_time})
	if memories.size() > NPCVoice.MAX_MEMORIES:
		memories.resize(NPCVoice.MAX_MEMORIES)
	var shift: int = {"approve": 6, "amused": 3, "disapprove": -8, "fear": -5}.get(st, 0)
	attitude = clampi(attitude + shift, -100, 100)
	if st == "fear" and kind in ["murder", "kill_cop", "fight", "threat"]:
		scared_until = maxf(scared_until, Game.play_time + 90.0)
	refresh_label()
	if me or state != "idle" or int(_act_seen[stamp]) >= 2:
		return
	_act_seen[stamp] = int(_act_seen[stamp]) + 1
	var line := NPCVoice.react_now(self, kind, st, target, _rng)
	var t := get_tree().create_timer(_rng.randf_range(0.25, 1.1) + 0.9 * float(_act_seen[stamp] - 1))
	t.timeout.connect(func():
		if is_instance_valid(self) and state != "dead":
			say(line, 2.8))
	if st == "approve" and _rng.randf() < 0.5:
		react_cheer()


func _on_interaction_seen(verb_id: String, success: bool, target: Node) -> void:
	var kinds: Dictionary = NPCVoice.reactions().get("verb_kind", {})
	if verb_id.begins_with("venue:"):
		var vid := verb_id.split(":")[1]
		var vk := str(NPCVoice.reactions().get("venue_kind", {}).get(vid, ""))
		witness_act(vk, str(Interactions._venue_ctx.get("sign", "that place")).capitalize())
		return
	var kind := str(kinds.get(verb_id, "talk"))
	if kind == "talk" or (not success and kind in ["charity", "show", "deal"]):
		return
	if target != null and is_instance_valid(target):
		witness_act(kind, str(target.npc_name), target)


func _on_action_seen(node: Dictionary) -> void:
	if str(node.get("actor", "player")) != "player":
		return
	var kind := str(NPCVoice.reactions().get("record_kind", {}).get(str(node.get("verb", "")), ""))
	if kind != "":
		var tgt := str(node.get("target", "someone"))
		witness_act(kind, tgt, self if tgt == npc_name else null)


func _on_kill_seen(enemy: Node, info: Dictionary) -> void:
	if not info.get("by_player", false) or enemy == null or not is_instance_valid(enemy):
		return
	var kmap: Dictionary = NPCVoice.reactions().get("kill_kind", {})
	var kind := str(kmap.get(str(enemy.get("faction")), kmap.get("default", "kill_other")))
	witness_act(kind, str(enemy.get("display_name")))


## Bought, charmed or scared into loyalty: they stop reporting you.
func make_loyal() -> void:
	loyal = true
	if witness.is_reporting():
		witness.silence("talked")
	witness.active = false
	_update_prompt()
	refresh_label()


# --- Impact: what you did to them shows, and changes how they live ---------------------------

func is_scared() -> bool:
	return scared_until > Game.play_time


## The relationship tag over their head (empty = nothing special).
func relation_label() -> String:
	if name_label and name_label.text.contains("INFORMANT"):
		return "YOUR INFORMANT"
	if repossessed:
		return "REPOSSESSED"
	if is_scared():
		return "SCARED OF YOU"
	if attitude >= 45:
		return "DEVOTED TO YOU"
	if owes_favour:
		return "OWES YOU ONE"
	if attitude >= 15:
		return "FRIENDLY"
	if attitude <= -40:
		return "FURIOUS"
	if attitude <= -15:
		return "DISLIKES YOU"
	if loyal:
		return "KEEPS QUIET"
	return ""


const REL_COLORS := {"YOUR INFORMANT": Color(0.6, 0.9, 1.0), "REPOSSESSED": Color(0.7, 0.7, 0.75),
	"SCARED OF YOU": Color(0.75, 0.55, 1.0), "DEVOTED TO YOU": Color(1.0, 0.85, 0.3), "OWES YOU ONE": Color(0.5, 1.0, 0.6),
	"FRIENDLY": Color(0.5, 1.0, 0.6), "FURIOUS": Color(1.0, 0.3, 0.3), "DISLIKES YOU": Color(1.0, 0.6, 0.45),
	"KEEPS QUIET": Color(0.75, 0.85, 0.9)}


func refresh_label() -> void:
	if name_label == null or story_id != "" or persona_id != "":
		return
	var base := npc_name + ("\n<TRADER>" if role == "merchant" else ("\n<LOOKING FOR WORK>" if role == "recruit" else ""))
	var rel := relation_label()
	if rel == "YOUR INFORMANT":
		return
	name_label.text = base + ("\n<%s>" % rel if rel != "" else "")
	name_label.modulate = REL_COLORS.get(rel, Color.WHITE)


## Called by Interactions after a verb resolves: show it, and set up what happens next.
func after_interaction(before_rel: String, before_att: int) -> String:
	refresh_label()
	var rel := relation_label()
	var d := attitude - before_att
	var col: Color = REL_COLORS.get(rel, Color(1, 1, 1))
	if rel != before_rel and rel != "":
		FX.damage_number(get_parent(), global_position + Vector3(0, 2.6, 0), rel, col, true)
	elif d != 0:
		FX.damage_number(get_parent(), global_position + Vector3(0, 2.6, 0), "%+d" % d, Color(0.5, 1, 0.6) if d > 0 else Color(1, 0.4, 0.4))
	if rel != before_rel:
		return "%s: %s -> %s" % [npc_name, before_rel.capitalize() if before_rel != "" else "Neutral", rel.capitalize() if rel != "" else "Neutral"]
	return ""


## Behaviour reactions requested by interaction effects ("react" key in data/interactions.json).
## Returns a line describing the consequence for the dialogue.
func react(kind: String) -> String:
	match kind:
		"grateful":
			owes_favour = true
			_favour_wait = _rng.randf_range(15.0, 35.0)
			react_cheer()
			if (traits as Array).has("poor") and _rng.randf() < 0.7:
				_go_spend()
				return "They head straight for the food stall. First real meal in a while. They owe you one."
			return "They won't forget this. They owe you one."
		"scared":
			scared_until = Game.play_time + 150.0
			flee_from_player()
			return "They're scared of you now. They'll keep their distance."
		"bow":
			_kneel(1.4)
			return "They know exactly who your family is. They'll keep quiet - and give you the family discount."
		"leave":
			_kneel(1.2)
			_leaving = true
			return "Served. They pack up and leave the street for good."
		"repossessed":
			repossessed = true
			_strip_look()
			_kneel(3.0)
			grudge = true
			_grudge_wait = _rng.randf_range(8.0, 14.0)
			return "Repossessed. They're left with nothing - and they look like they're about to call Paragon."
		"grudge":
			grudge = true
			_grudge_wait = _rng.randf_range(5.0, 10.0)
			return "They're furious. Looks like they're about to file a complaint about you."
		"smitten":
			react_cheer()
			return "They're blushing. Somebody has a crush."
	return ""


func _kneel(t: float) -> void:
	end_activity()
	state = "idle"
	activity = "kneel"
	_act_target = global_position
	_act_time = t
	_act_face = (_player.global_position - global_position) * Vector3(1, 0, 1) if _player and is_instance_valid(_player) else Vector3.BACK


## Spend the money you gave them: walk to the nearest food stall queue.
func _go_spend() -> void:
	var best: Node3D = null
	var best_d := 40.0
	for sp in get_tree().get_nodes_in_group("life_spot"):
		if str(sp.get_meta("kind", "")) != "queue" or sp.get_meta("taken", false):
			continue
		var dd: float = (sp as Node3D).global_position.distance_to(global_position)
		if dd < best_d:
			best = sp
			best_d = dd
	if best == null:
		return
	end_activity()
	_act_spot = best
	best.set_meta("taken", true)
	activity = "queue"
	_act_target = best.global_position
	_act_face = best.get_meta("face", Vector3.BACK)
	_act_time = -1.0


## Repo men took the good clothes: grey, threadbare, coatless.
func _strip_look() -> void:
	var l: Dictionary = look.duplicate(true)
	var cols: Dictionary = l.get("colors", {})
	for slot in ["coat", "top", "accent", "gear", "boots"]:
		if cols.has(slot):
			cols[slot] = ["#5a5a60", "#6a6a6e", "#4a4a50"][_rng.randi() % 3]
	l["colors"] = cols
	look = l
	sprite.set_look(look)


## Ongoing consequences, ticked from _life().
func _impact_tick(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or state == "dead":
		return
	var d := global_position.distance_to(_player.global_position)
	_mood_bark -= delta
	# A favour, returned.
	if owes_favour and state == "idle":
		_favour_wait -= delta
		if _favour_wait <= 0.0 and d < 6.0:
			_give_favour()
	# A grudge becomes a complaint to Paragon (a real report: stop them or eat the bounty).
	if grudge and not loyal:
		_grudge_wait -= delta
		if _grudge_wait <= 0.0 and state == "idle":
			grudge = false
			if attitude <= -15:
				say(Copy.expand("#grudge_call#", _rng), 2.6)
				EventBus.toast.emit("%s is filing a complaint about you with Paragon!" % npc_name, Color(1.0, 0.6, 0.3))
				witness.active = true
				Causality.record("complaint", {"target": npc_name, "target_faction": "paragon", "position": global_position})
	# Fear and fury show in how they act around you.
	if is_scared() and d < 3.2 and state == "idle" and _talking <= 0.0 and _mood_bark <= 0.0:
		_mood_bark = 8.0
		say(Copy.expand("#scared_bark#", _rng), 2.0)
		flee_from_player()
	elif attitude <= -40 and d < 5.0 and state == "idle" and _mood_bark <= 0.0:
		_mood_bark = 14.0
		say(Copy.expand("#furious_bark#", _rng, {"name": Game.player_name}), 2.6)
	elif attitude >= 45 and d < 5.0 and state == "idle" and _mood_bark <= 0.0 and _rng.randf() < 0.02:
		_mood_bark = 25.0
		say(Copy.expand("#devoted_bark#", _rng, {"name": Game.player_name}), 2.4)
	# Served papers: walk off and never come back.
	if _leaving and activity != "kneel":
		_leaving = false
		flee_from_player()
		var tw := create_tween()
		tw.tween_interval(3.5)
		tw.tween_callback(sprite.fade_to.bind(0.0, 0.8))
		tw.tween_interval(0.8)
		tw.tween_callback(queue_free)


func _give_favour() -> void:
	owes_favour = false
	_act_face = (_player.global_position - global_position) * Vector3(1, 0, 1)
	var key := NPCVoice.voice(self)
	var what := ""
	match key:
		"corporate":
			Game.add_credits(30)
			what = "+30 CR"
		"worker", "merchant":
			Game.add_credits(15)
			what = "+15 CR"
		"artsy":
			Game.flags["fame"] = int(Game.flags.get("fame", 0)) + 2
			what = "FAME +2 (they wrote a song about you)"
		"rebel":
			Game.flags["followers"] = int(Game.flags.get("followers", 0)) + 1
			what = "+1 FOLLOWER"
		"robot":
			Game.add_item("medkit", 1)
			what = "+1 MEDKIT"
		"weird":
			Game.add_item(["lockpick", "loaded_dice", "antihistamine"][_rng.randi() % 3], 1)
			what = "A strange gift"
		_:
			Game.add_item("paste_ration", 1)
			what = "+1 PASTE RATION + a tip"
			EventBus.toast.emit(Interactions.rumor(self), Color(0.9, 0.9, 0.7))
	say(Copy.expand("#favour_line#", _rng, {"name": Game.player_name}), 3.0)
	FX.damage_number(get_parent(), global_position + Vector3(0, 2.6, 0), "GIFT!", Color(0.5, 1.0, 0.6), true)
	EventBus.toast.emit("%s returns the favour: %s" % [npc_name, what], Color(0.5, 1.0, 0.6))
	attitude = mini(100, attitude + 5)
	refresh_label()


## Bought, charmed or scared into loyalty: they stop reporting you.


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
	_impact_tick(delta)
	_bark_timer -= delta
	if _player != null and is_instance_valid(_player) and name_label:
		# Only nearby or important people show their name - keeps crowds readable.
		var important: bool = story_id != "" or persona_id != "" or role != "civilian" or state == "reporting" \
			or name_label.text.contains("<")
		name_label.visible = important or global_position.distance_squared_to(_player.global_position) < 30.0
	if not _waved and _player != null and state == "idle" and attitude >= 20 and activity in ["", "phone"] \
			and global_position.distance_to(_player.global_position) < 5.0:
		_waved = true
		activity = "wave"
		_act_face = (_player.global_position - global_position) * Vector3(1, 0, 1)
		_act_time = 2.2
		say(Copy.expand("#wave_hi#", _rng, {"name": Game.player_name}), 2.2)
	if _bark_timer > 0.0 or state != "idle" or _player == null:
		return
	_bark_timer = _rng.randf_range(9.0, 22.0)
	var d := global_position.distance_to(_player.global_position)
	if d > 11.0:
		return
	# Muttering about you as you pass: who you are, what you did.
	if d < 6.5 and role == "civilian" and _rng.randf() < 0.3:
		if not memories.is_empty() and _rng.randf() < 0.5:
			say(NPCVoice.aside(self, memories[0], _rng))
		else:
			say(NPCVoice.remark(self, _rng, true))
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
		if not pool.is_empty():
			_converse(str(pool[_rng.randi() % pool.size()]), _partner)
			return
	elif not Game.current_planet.is_empty() and _rng.randf() < 0.3:
		pool = b.get("crisis:" + str(Game.current_planet.get("crisis", "")), [])
	elif Game.current_planet.is_empty() and _rng.randf() < 0.3:
		pool = b.get("station", [])
	else:
		pool = _reactive_barks(b)
	if pool.is_empty() and role == "civilian" and _rng.randf() < 0.55:
		# Fresh small talk every time: the copywriter knows the shows, the teams, the prices.
		say(Copy.make("chatter", _rng))
		if _partner != null and is_instance_valid(_partner):
			_partner.reply_later(_rng.randf_range(1.6, 2.4))
		return
	if pool.is_empty():
		pool = b.get(role, b.get("civilian", []))
	if not pool.is_empty():
		say(str(pool[_rng.randi() % pool.size()]))
		if _partner != null and is_instance_valid(_partner) and _rng.randf() < 0.4:
			_partner.reply_later(_rng.randf_range(1.8, 2.6))


## A scripted exchange "A -- B -- C": lines alternate between this NPC and the partner.
## Grammar is expanded once up front so both speakers talk about the same show / dish / team.
func _converse(line: String, partner: Node) -> void:
	var parts := Copy.expand(line, _rng, {"name": Game.player_name}).split(" -- ")
	var at := 0.0
	for i in parts.size():
		var who: Node = self if i % 2 == 0 else partner
		var text := parts[i].strip_edges()
		if i == 0:
			say(text, 2.4)
		else:
			who.reply_later(at, text)
		at += clampf(1.2 + text.length() * 0.035, 1.6, 3.2)
	_talking = at + 1.0
	_bark_timer = maxf(_bark_timer, at + 4.0)


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


## Answer whatever the neighbour just said (two-sided street conversations).
func reply_later(delay: float, text: String = "") -> void:
	_talking = delay + 2.5
	_bark_timer = maxf(_bark_timer, delay + 5.0)
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func():
		if is_instance_valid(self) and state == "idle":
			say(text if text != "" else Copy.make("reply", _rng), 2.6))


func say(text: String, duration: float = 3.4) -> void:
	if text.contains("#") or text.contains("{"):
		text = Copy.expand(text, _rng, {"name": Game.player_name})
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
			say(str(lines[_rng.randi() % lines.size()]), 2.0)
		end_activity()
		state = "flee"
		_timer = 2.5
		_flee_from = _player.global_position
