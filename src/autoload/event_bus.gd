extends Node
## Global signal hub. Systems never reference each other's internals for
## notifications; they emit/listen here, which keeps them decoupled and lets
## new systems (achievements, analytics, quests...) hook in without edits.

# --- Causality ---------------------------------------------------------------
signal action_recorded(node: Dictionary)
signal action_status_changed(node: Dictionary, old_status: String)
signal witness_started(witness: Node, node_id: int)
signal witness_silenced(witness: Node, node_id: int)
signal news_broadcast(headline: String, node: Dictionary)

# --- Factions / economy --------------------------------------------------------
signal faction_rep_changed(faction_id: String, old_value: int, new_value: int, reason: String)
signal bounty_changed(faction_id: String, amount: int)
signal credits_changed(value: int, delta: int)
signal air_billed(cost: int, debt: int)
signal inventory_changed(item_id: String, count: int)

# --- Player / combat -------------------------------------------------------------
signal player_hp_changed(hp: float, max_hp: float)
signal player_died
signal player_parried(attacker: Node)
signal player_dodged
signal enemy_killed(enemy: Node, info: Dictionary)
signal subsystem_broken(enemy: Node, subsystem: String, effect: String)
signal target_changed(target: Node, subsystem: String)
signal overclock_changed(meter: float, active_time: float)
signal perfect_dodge
signal enemy_broken(enemy: Node)
signal enemy_shield_changed(enemy: Node, shield: int)

# --- Flaws & perks ---------------------------------------------------------------
signal mishap(kind: String, count: int)
signal flaw_offered(flaw_id: String, mishap_kind: String)
signal flaw_accepted(flaw_id: String)
signal perk_unlocked(perk_id: String)
signal skill_points_changed(value: int)
signal stats_changed

# --- Crew ----------------------------------------------------------------------------
signal crew_joined(member_id: String)
signal crew_left(member_id: String, reason: String)
signal crew_approval_changed(member_id: String, old_value: int, new_value: int)
signal crew_bark(member_id: String, text: String)
signal crew_betrayal(member_id: String, kind: String, text: String)

# --- World / UI ----------------------------------------------------------------------
signal ai_say(text: String, mood: String)
signal toast(text: String, color: Color)
signal encounter_started(encounter: Dictionary)
signal encounter_finished(encounter_id: String, choice_id: String)
signal interaction_done(verb_id: String, success: bool, npc: Node)
signal story_event(kind: String, info: Dictionary)
signal planet_entered(planet: Dictionary)
signal interact_prompt_changed(text: String)
## Ask the HUD to show a dialogue. choices: Array of {text, id, disabled?}.
## callback receives the chosen id ("" when closed without a choice).
signal dialogue_requested(speaker: String, text: String, choices: Array, callback: Callable)
signal shop_requested(vendor_name: String, faction_id: String, stock: Array)
signal game_loaded
signal cutscene_started
signal cutscene_ended
signal speech_bubble(speaker: Node, text: String)
## Something the player did that bystanders may see (NPC memory): "dance", "hurt", ...
signal player_act(kind: String, target: String)
signal input_device_changed(device: String)  # "touch" | "keyboard" | "gamepad"
