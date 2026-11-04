extends Control
## The Odd Duck's nav console. Pick a procedurally generated planet, read its
## 4-layer matrix (environment / controller / crisis / anomaly), warp.
## Warping = crew betrayal checks + a Space Encounter roll, then landing.

const WARP_TOLL := 15

var _bg: RetroBackdrop
var _map: Control
var _info: RichTextLabel
var _warp_btn: Button
var _side: RichTextLabel
var _selected: Dictionary = {}
var _modal: ColorRect
var _modal_panel: PanelContainer
var _menu: PauseMenu
var _warping := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Game.enter_ship()
	_bg = RetroBackdrop.new()
	_bg.mode = "stars"
	add_child(_bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := HUD.make_label("THE ODD DUCK // NAV CONSOLE", 26, Color(1.0, 0.82, 0.24))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var menu_btn := Button.new()
	menu_btn.text = "SHIP TERMINAL"
	menu_btn.pressed.connect(_open_menu)
	head.add_child(menu_btn)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	# Left: crew + news.
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	_side = _rich()
	left.add_child(_side)
	# Center: the map itself.
	_map = Control.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.draw.connect(_draw_map)
	body.add_child(_map)
	# Right: planet info + warp.
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_info = _rich()
	_info.text = "Select a destination.\n\n[i]QUACK: \"Pick somewhere with breathable air. Or don't. I'm a ship, I don't breathe.\"[/i]"
	scroll.add_child(_info)
	_warp_btn = Button.new()
	_warp_btn.text = "WARP"
	_warp_btn.custom_minimum_size = Vector2(0, 60)
	_warp_btn.disabled = true
	_warp_btn.pressed.connect(_warp)
	rv.add_child(_warp_btn)
	_build_planet_buttons()
	_build_modal()
	_refresh_side()
	Audio.play_music("odd_duck_theme")


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 18)
	return r


func _build_planet_buttons() -> void:
	for p in Game.galaxy:
		var b := Button.new()
		b.text = str(p.name)
		b.add_theme_font_size_override("font_size", 14)
		b.set_meta("planet", p)
		b.pressed.connect(_select.bind(p))
		_map.add_child(b)
	_map.resized.connect(_layout_planets)
	_layout_planets.call_deferred()


func _layout_planets() -> void:
	for b in _map.get_children():
		if not b is Button:
			continue
		var p: Dictionary = b.get_meta("planet")
		var mp: Array = p.get("map_pos", [0.5, 0.5])
		b.reset_size()
		b.position = Vector2(float(mp[0]) * _map.size.x, float(mp[1]) * _map.size.y) + Vector2(-b.size.x * 0.5, 22)
	_map.queue_redraw()


func _planet_point(p: Dictionary) -> Vector2:
	var mp: Array = p.get("map_pos", [0.5, 0.5])
	return Vector2(float(mp[0]) * _map.size.x, float(mp[1]) * _map.size.y)


func _draw_map() -> void:
	var prev := Vector2.ZERO
	var first := true
	for p in Game.galaxy:
		var pt := _planet_point(p)
		if not first:
			_map.draw_dashed_line(prev, pt, Color(0.24, 0.9, 1.0, 0.35), 2.0, 10.0)
		first = false
		prev = pt
	for p in Game.galaxy:
		var pt := _planet_point(p)
		var env := PlanetGenerator.layer(p, "environments")
		var col := Color.from_string(str(env.get("ground_alt", "#808080")), Color.GRAY).lightened(0.3)
		var ctrl_col := DataDB.faction_color(p.get("controller", "")) if p.get("controller", "") != "" else Color(0.7, 0.7, 0.7)
		var r := 16.0 + 4.0 * int(p.get("difficulty", 1))
		_map.draw_circle(pt, r + 8.0, Color(ctrl_col, 0.15))
		_map.draw_circle(pt, r, col)
		_map.draw_arc(pt, r + 3.0, 0.0, TAU, 32, ctrl_col, 2.0, true)
		if p.get("visited", false):
			_map.draw_arc(pt, r + 7.0, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 1.0, true)
		if not _selected.is_empty() and _selected.get("id", "") == p.get("id", ""):
			var pulse := 4.0 * sin(Time.get_ticks_msec() / 200.0)
			_map.draw_arc(pt, r + 12.0 + pulse, 0.0, TAU, 32, Color(1.0, 0.82, 0.24), 3.0, true)


func _process(_delta: float) -> void:
	if not _selected.is_empty():
		_map.queue_redraw()
	if _warping:
		_bg.warp = minf(1.0, _bg.warp + _delta * 0.8)


func _select(p: Dictionary) -> void:
	_selected = p
	Audio.play_sfx("blip", 0.1, -6.0)
	var controller: String = p.get("controller", "")
	var text := "[b][color=#ffd23e]%s[/color][/b]  (danger %d)\n\n%s" % [p.name, int(p.get("difficulty", 1)), PlanetGenerator.describe(p)]
	if controller != "":
		text += "\n\n[color=#3ee6ff]YOUR STANDING:[/color] %s (%+d)%s" % [Factions.standing(controller), Factions.get_rep(controller),
			"  [color=#ff5a5a]GUARDS WILL SHOOT[/color]" if Factions.is_hostile(controller) else ""]
	else:
		text += "\n\n[color=#ff5a5a]LAWLESS: pirates, no police, no witnesses that matter... probably.[/color]"
	var known := Causality.known_crimes_at(p.get("id", ""), controller)
	if not known.is_empty():
		text += "\n[color=#ff3ec8]They've heard about you:[/color] %d crime(s) on the Lumen feed." % known.size()
	text += "\n[color=#3ee6ff]AIR COST:[/color] x%.1f" % float(p.get("air_mult", 1.0))
	text += "\n\n[i]Hyperlane toll: %d cr (Halcyon). Can't pay? It goes on your debt.[/i]" % WARP_TOLL
	_info.text = text
	_warp_btn.disabled = false
	_warp_btn.text = "WARP TO %s" % str(p.name).to_upper()


func _refresh_side() -> void:
	var t := "[b]CREW %d/%d[/b]\n" % [Crew.size(), Crew.MAX_CREW]
	if Crew.size() == 0:
		t += "[i]Just you and QUACK.[/i]\n"
	for id in Crew.order:
		t += "- %s  [color=#ffd23e]%s[/color]\n" % [Crew.def(id).get("name", id), Crew.mood(id)]
	t += "\n[b]CREDITS[/b] %d   [b]AIR DEBT[/b] %d\n[b]BOUNTY[/b] %d\n" % [Game.credits, Game.air_debt, Factions.total_bounty()]
	t += "\n[b][color=#ff3ec8]LUMEN NEWS[/color][/b]\n"
	var heads := Causality.latest_headlines(4)
	if heads.is_empty():
		t += "[i]%s[/i]\n" % DataDB.ads.get("ticker", ["Nothing to report."])[0]
	for h in heads:
		t += "- %s\n" % h
	_side.text = t


# --- Warp sequence -----------------------------------------------------------------------

func _warp() -> void:
	if _selected.is_empty() or _warping:
		return
	_warping = true
	_warp_btn.disabled = true
	if not Game.spend(WARP_TOLL):
		Game.add_air_debt(WARP_TOLL)
	ShipAI.say("on_warp", {}, true)
	Audio.play_sfx("warp")
	await get_tree().create_timer(1.6).timeout
	for ev in Crew.check_betrayals():
		await _show_message("CREW BETRAYAL", ev.text)
	var enc := Encounters.roll_warp_encounter()
	if not enc.is_empty():
		await _run_encounter(enc)
	_bg.warp = 0.0
	Game.save_game()
	Router.goto(Router.PLANET, {"planet_id": _selected.get("id", "")})


func _run_encounter(enc: Dictionary) -> void:
	Audio.play_sfx("alert")
	var choices := []
	for ch in enc.get("choices", []):
		var label := Encounters.format_text(str(ch.get("text", "")))
		if ch.has("chance"):
			label += "  (%d%%)" % roundi(Encounters.choice_chance(ch) * 100.0)
		choices.append({"id": ch.get("id", ""), "text": label, "disabled": not Encounters.choice_available(ch), "data": ch})
	var picked: Dictionary = await _ask(str(enc.get("title", "ENCOUNTER")), Encounters.format_text(str(enc.get("text", ""))), choices)
	var result := Encounters.resolve(enc, picked.get("data", {}))
	var lines: Array = result.get("lines", [])
	var text: String = result.get("text", "")
	if not lines.is_empty():
		text += "\n\n[color=#ffd23e]" + "\n".join(PackedStringArray(lines)) + "[/color]"
	await _show_message("SUCCESS" if result.get("success", true) else "THAT WENT POORLY", text)
	_refresh_side()


# --- Modal helpers -------------------------------------------------------------------------

func _build_modal() -> void:
	_modal = ColorRect.new()
	_modal.color = Color(0.02, 0.0, 0.06, 0.6)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.visible = false
	add_child(_modal)
	_modal_panel = PanelContainer.new()
	_modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	_modal_panel.offset_left = -430
	_modal_panel.offset_right = 430
	_modal_panel.offset_top = -280
	_modal_panel.offset_bottom = 280
	_modal.add_child(_modal_panel)
	_menu = PauseMenu.new()
	_menu.visible = false
	_menu.closed.connect(func():
		_menu.visible = false
		_modal.visible = false
		_refresh_side())
	_modal.add_child(_menu)


func _open_menu() -> void:
	_modal.visible = true
	_modal_panel.visible = false
	_menu.open("")


signal _answered(choice: Dictionary)


## Shows a modal with choices; returns the chosen choice dictionary.
func _ask(title: String, text: String, choices: Array) -> Dictionary:
	for c in _modal_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_modal_panel.add_child(v)
	v.add_child(HUD.make_label(title, 26, Color(1.0, 0.35, 0.85)))
	var body := _rich()
	body.text = text
	v.add_child(body)
	for ch in choices:
		var b := Button.new()
		b.text = "> " + str(ch.get("text", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = ch.get("disabled", false)
		b.pressed.connect(func(): _answered.emit(ch))
		v.add_child(b)
	_modal.visible = true
	_modal_panel.visible = true
	var picked: Dictionary = await _answered
	_modal.visible = false
	Audio.play_sfx("confirm")
	return picked


func _show_message(title: String, text: String) -> void:
	await _ask(title, text, [{"id": "ok", "text": "CONTINUE"}])
