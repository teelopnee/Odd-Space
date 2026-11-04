class_name PropInteractable
extends Interactable
## Interactive level props. Stealing records THEFT in the Causality Graph at
## the player's position, so anyone who can see you becomes a witness.

@export_enum("stash", "vending", "terminal", "dock", "cryo", "medstation") var kind := "stash"
@export var owner_faction := "halcyon"

var _looted := false
var _player: Node = null
var _fee := 0
var _price := 0
var _missing := 0.0


func _on_interact(player: Node) -> void:
	match kind:
		"stash":
			_stash(player)
		"vending":
			_vending(player)
		"terminal":
			get_tree().call_group("hud", "open_menu", "causality")
		"dock":
			get_tree().call_group("level", "exit_to_ship")
		"cryo":
			_cryo()
		"medstation":
			_medstation()


func _owner_name() -> String:
	return DataDB.faction_name(owner_faction)


func _stash(player: Node) -> void:
	if _looted:
		EventBus.dialogue_requested.emit("Crate", "Empty. Someone (you) already relocated its contents.", [], Callable())
		return
	var fee := maxi(1, roundi(2 * Game.stat("price_mult")))
	var text := "PROPERTY OF %s.\nTouching fee: %d cr. Looking fee: pending.\nContents: [REDACTED - premium tier only]" % [_owner_name().to_upper(), fee]
	var choices := [
		{"id": "steal", "text": "Steal the contents"},
		{"id": "fee", "text": "Pay the touching fee (%d cr)" % fee, "disabled": not Game.can_afford(fee)},
		{"id": "leave", "text": "Walk away"},
	]
	_player = player
	_fee = fee
	EventBus.dialogue_requested.emit("Consortium Crate", text, choices, _on_stash_choice)


func _on_stash_choice(choice: String) -> void:
	match choice:
		"steal":
			_do_steal(_player)
		"fee":
			if Game.spend(_fee):
				Causality.record("comply", {"target": "Crate", "target_faction": owner_faction})
				EventBus.toast.emit("You paid to touch a box. The Consortium thanks you.", Color(1, 0.9, 0.4))


func _do_steal(player: Node) -> void:
	_looted = true
	var credits := roundi(randi_range(15, 45) * Game.stat("loot_mult"))
	Game.add_credits(credits)
	var loot_roll := randf()
	var item := "medkit" if loot_roll < 0.4 else ("scrap" if loot_roll < 0.8 else "bribe_voucher")
	Game.add_item(item, 1)
	EventBus.toast.emit("Stole %d cr + %s" % [credits, DataDB.item_name(item)], Color(1.0, 0.85, 0.3))
	Audio.play_sfx("pickup")
	var pos: Vector3 = (player as Node3D).global_position if player is Node3D else global_position
	Causality.record("theft", {"target": "Supply crate", "target_faction": owner_faction, "position": pos})
	prompt = "Empty crate"
	enabled = false


func _vending(player: Node) -> void:
	var price := Game.price_of("air_canister", owner_faction)
	var text := "AIR-O-MAT by OxyGenix(tm)\n\"Thank you for breathing responsibly!\"\nYour air debt: %d cr" % Game.air_debt
	var choices := [
		{"id": "buy", "text": "Buy Air Canister (%d cr)" % price, "disabled": not Game.can_afford(price)},
		{"id": "pay", "text": "Pay off air debt (%d cr)" % mini(Game.air_debt, Game.credits), "disabled": Game.air_debt <= 0 or Game.credits <= 0},
		{"id": "smash", "text": "Smash it open", "disabled": _looted},
		{"id": "leave", "text": "Leave"},
	]
	_player = player
	_price = price
	EventBus.dialogue_requested.emit("AIR-O-MAT", text, choices, _on_vending_choice)


func _on_vending_choice(choice: String) -> void:
	match choice:
		"buy":
			if Game.spend(_price):
				Game.add_item("air_canister", 1)
				Audio.play_sfx("coin")
		"pay":
			var amount := mini(Game.air_debt, Game.credits)
			Game.spend(amount)
			Game.add_air_debt(-amount)
			Audio.play_sfx("coin")
		"smash":
			_looted = true
			Game.add_item("air_canister", 2)
			Game.add_credits(roundi(12 * Game.stat("loot_mult")))
			Audio.play_sfx("break")
			var pos: Vector3 = (_player as Node3D).global_position if _player is Node3D else global_position
			var theft := Causality.record("theft", {"target": "AIR-O-MAT", "target_faction": owner_faction, "position": pos})
			Causality.record("vandalism", {"target": "AIR-O-MAT", "target_faction": owner_faction, "position": pos, "causes": [theft]})


func _cryo() -> void:
	var bg := Origin.get_tag("background", Game.tags.get("background", ""))
	var lines := [
		"LABEL: \"%s - COLLATERAL #%d. Do not thaw before repayment.\"" % [str(bg.get("name", "Unknown")).to_upper(), randi_range(10000, 99999)],
		"LABEL: \"Contents: 1 human (used). Warranty void if opened.\"",
		"LABEL: \"Thaw date: when profitable.\"",
	]
	EventBus.dialogue_requested.emit("Cryo Pod", lines[randi() % lines.size()], [], Callable())


func _medstation() -> void:
	var missing := Game.max_hp() - Game.hp
	var price := maxi(5, roundi(missing * 0.6 * Factions.price_multiplier(owner_faction)))
	var choices := [
		{"id": "heal", "text": "Full treatment (%d cr)" % price, "disabled": missing < 1.0 or not Game.can_afford(price)},
		{"id": "loan", "text": "Treatment on credit (Halcyon loan, +%d air debt)" % roundi(price * 1.5), "disabled": missing < 1.0},
		{"id": "leave", "text": "Leave"},
	]
	_price = price
	_missing = missing
	EventBus.dialogue_requested.emit("MediCredit(tm)", "\"Your health is our business. Literally. We own it.\"\nHP %d / %d" % [roundi(Game.hp), roundi(Game.max_hp())], choices, _on_med_choice)


func _on_med_choice(choice: String) -> void:
	match choice:
		"heal":
			if Game.spend(_price):
				Game.heal(_missing)
				Audio.play_sfx("heal")
		"loan":
			Game.add_air_debt(roundi(_price * 1.5))
			Game.heal(_missing)
			Audio.play_sfx("heal")
