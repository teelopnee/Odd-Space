class_name PauseMenu
extends PanelContainer
## Ship terminal / pause menu. Tabs are rebuilt every time it opens so they
## always show live data: STATUS, PERKS, FACTIONS, CREW, CAUSALITY, ITEMS, SYSTEM.

signal closed

var _tabs: TabContainer
var _close_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_right = -40
	offset_top = 30
	offset_bottom = -40
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := HUD.make_label("THE ODD DUCK // SHIP TERMINAL   %s" % Game.player_name.to_upper(), 22, Color(1.0, 0.82, 0.24))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(HUD.make_label("LB/RB: tabs  ", 13, Color(0.7, 0.8, 1.0)))
	var close := Button.new()
	close.text = "RESUME  X"
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	_close_btn = close
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)


func open(tab: String = "") -> void:
	visible = true
	_rebuild()
	if tab != "":
		for i in _tabs.get_tab_count():
			if _tabs.get_tab_title(i).to_lower() == tab.to_lower():
				_tabs.current_tab = i


func switch_tab(dir: int) -> void:
	_tabs.current_tab = posmod(_tabs.current_tab + dir, _tabs.get_tab_count())
	_focus_first.call_deferred()


func _focus_first() -> void:
	var page := _tabs.get_current_tab_control()
	if page == null:
		return
	var stack: Array = [page]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is Button and not n.disabled and n.is_visible_in_tree():
			n.grab_focus()
			return
		stack.append_array(n.get_children())
	_close_btn.grab_focus()


func _rebuild() -> void:
	var keep := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tab_status()
	_tab_perks()
	_tab_factions()
	_tab_crew()
	_tab_causality()
	_tab_items()
	_tab_system()
	if keep >= 0 and keep < _tabs.get_tab_count():
		_tabs.current_tab = keep
	_focus_first.call_deferred()


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	return v


func _rich(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = text
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 17)
	r.add_theme_font_size_override("bold_font_size", 18)
	return r


# --- Tabs ----------------------------------------------------------------------------------

func _tab_status() -> void:
	var v := _page("Status")
	var tag_lines := ""
	for cat in Origin.CATEGORIES:
		var t := Origin.get_tag(cat, Game.tags.get(cat, ""))
		tag_lines += "[color=#ff3ec8]%s:[/color] [b]%s[/b] - %s\n" % [cat.to_upper(), t.get("name", "?"), t.get("desc", "")]
	v.add_child(_rich("[b]%s[/b]   Play time %d min\n\n%s\n[i]%s[/i]" % [Game.player_name.to_upper(), int(Game.play_time / 60.0), tag_lines, Origin.origin_story()]))
	var stats := ["max_hp", "move_speed", "damage", "fire_rate", "accuracy", "parry_window", "roll_cooldown", "air_cost_mult", "price_mult", "bribe_mult", "witness_time_mult", "loot_mult"]
	var s := "[color=#3ee6ff]STATS[/color]\n"
	for st in stats:
		s += "%-20s %6.2f\n" % [st.to_upper(), Game.stat(st)]
	v.add_child(_rich(s))
	var flaws := "[color=#ff3ec8]FLAWS[/color]\n"
	if Game.flaws.is_empty():
		flaws += "None yet. Keep failing at things and the universe will offer some.\n"
	for f in Game.flaws:
		var d := FlawPerk.flaw_def(f)
		flaws += "- [b]%s[/b]: %s\n" % [d.get("name", f), d.get("desc", "")]
	v.add_child(_rich(flaws))


func _tab_perks() -> void:
	var v := _page("Perks")
	v.add_child(HUD.make_label("SKILL POINTS: %d   (earn them by accepting flaws)" % Game.skill_points, 20, Color(1.0, 0.82, 0.24)))
	var perks: Dictionary = DataDB.flaws_perks.get("perks", {})
	for id in perks:
		var d: Dictionary = perks[id]
		var row := HBoxContainer.new()
		v.add_child(row)
		var owned := Game.perks.has(id)
		var l := HUD.make_label("%s%s  -  %s" % ["[OWNED] " if owned else "", d.get("name", id), d.get("desc", "")], 16, Color(0.5, 1.0, 0.7) if owned else Color(0.85, 0.97, 1.0))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		if not owned:
			var b := Button.new()
			b.text = "BUY (%d SP)" % int(d.get("cost", 1))
			b.disabled = not FlawPerk.can_buy_perk(id)
			b.pressed.connect(func():
				FlawPerk.buy_perk(id)
				_rebuild())
			row.add_child(b)


func _tab_factions() -> void:
	var v := _page("Factions")
	v.add_child(HUD.make_label("THE CONSORTIUM  //  your standing with the five companies that own the sky", 16, Color(0.6, 0.85, 1.0)))
	for fid in Factions.ids():
		var d: Dictionary = DataDB.factions[fid]
		var col := DataDB.faction_color(fid)
		var box := VBoxContainer.new()
		v.add_child(box)
		box.add_child(HUD.make_label("%s  -  %s  (%+d)" % [d.get("name", fid), Factions.standing(fid), Factions.get_rep(fid)], 19, col))
		var bar := HUD.make_bar(col, Vector2(600, 12))
		bar.min_value = -100
		bar.max_value = 100
		bar.value = Factions.get_rep(fid)
		box.add_child(bar)
		var extra := "\"%s\"   Prices x%.2f" % [d.get("motto", ""), Factions.price_multiplier(fid)]
		if Factions.get_bounty(fid) > 0:
			extra += "   BOUNTY %d cr" % Factions.get_bounty(fid)
		if Factions.is_hostile(fid):
			extra += "   [GUARDS SHOOT ON SIGHT]"
		box.add_child(HUD.make_label(extra, 14))


func _tab_crew() -> void:
	var v := _page("Crew")
	v.add_child(HUD.make_label("CREW %d/%d  //  they judge everything you do" % [Crew.size(), Crew.MAX_CREW], 18, Color(1.0, 0.82, 0.24)))
	if Crew.size() == 0:
		v.add_child(HUD.make_label("No crew yet. QUACK says it counts as crew. It does not.", 16))
	for id in Crew.order:
		var d := Crew.def(id)
		var a := Crew.approval(id)
		var vals: Dictionary = d.get("values", {})
		v.add_child(_rich("[b]%s[/b] - %s   [color=#ffd23e]%s[/color] (%+d)\n%s\n[color=#3ee6ff]Values:[/color] mercy %+.1f / order %+.1f / greed %+.1f" % [
			d.get("name", id), d.get("title", ""), Crew.mood(id), a, d.get("bio", ""),
			float(vals.get("mercy", 0)), float(vals.get("order", 0)), float(vals.get("greed", 0))]))
		var bar := HUD.make_bar(Color(0.5, 1.0, 0.6) if a > Crew.GRUMBLE_AT else Color(1.0, 0.3, 0.3), Vector2(500, 10))
		bar.min_value = -100
		bar.max_value = 100
		bar.value = a
		v.add_child(bar)


func _tab_causality() -> void:
	var v := _page("Causality")
	var total := Causality.nodes.size()
	v.add_child(HUD.make_label("CAUSALITY GRAPH  //  %d events remembered, %d reported, %d suppressed, %d secret" % [
		total, Causality.query("", Causality.STATUS_REPORTED).size(), Causality.query("", Causality.STATUS_SUPPRESSED).size(),
		Causality.query("", Causality.STATUS_SECRET).size()], 16, Color(0.6, 0.85, 1.0)))
	if total == 0:
		v.add_child(HUD.make_label("Nothing yet. The universe is waiting for you to do something regrettable.", 16))
	var colors := {"secret": "#8fa8ff", "pending": "#ffd23e", "reported": "#ff5a6a", "suppressed": "#6aff9a"}
	for i in range(total - 1, maxi(-1, total - 60), -1):
		var n: Dictionary = Causality.nodes[i]
		var line := "[color=%s][%s][/color] %s" % [colors.get(n.status, "#ffffff"), str(n.status).to_upper(), Causality.describe(n)]
		if not n.causes.is_empty():
			line += "  [color=#c07dff]<- caused by #%s[/color]" % ", #".join(PackedStringArray(n.causes.map(func(c): return str(c))))
		if not n.witnesses.is_empty():
			line += "  (%d witness%s)" % [n.witnesses.size(), "" if n.witnesses.size() == 1 else "es"]
		if str(n.get("headline", "")) != "":
			line += "\n    [i][color=#ff3ec8]%s[/color][/i]" % n.headline
		v.add_child(_rich(line))


func _tab_items() -> void:
	var v := _page("Items")
	v.add_child(HUD.make_label("%d CREDITS   //   AIR DEBT %d" % [Game.credits, Game.air_debt], 18, Color(1.0, 0.85, 0.3)))
	if Game.inventory.is_empty():
		v.add_child(HUD.make_label("Your pockets contain lint (non-tradeable).", 16))
	for item_id in Game.inventory.keys():
		var d: Dictionary = DataDB.items.get(item_id, {})
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := HUD.make_label("%s x%d  -  %s" % [DataDB.item_name(item_id), Game.item_count(item_id), d.get("desc", "")], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		if d.has("use"):
			var b := Button.new()
			b.text = "USE"
			b.pressed.connect(func():
				Game.use_item(item_id)
				_rebuild())
			row.add_child(b)


func _tab_system() -> void:
	var v := _page("System")
	for slot in [1, 2, 3]:
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := HUD.make_label("SLOT %d: %s" % [slot, Game.save_summary(slot)], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var save := Button.new()
		save.text = "SAVE"
		save.pressed.connect(func():
			Game.save_game(slot)
			EventBus.toast.emit("Saved to slot %d" % slot, Color(0.5, 1.0, 0.7))
			_rebuild())
		row.add_child(save)
		var load_btn := Button.new()
		load_btn.text = "LOAD"
		load_btn.disabled = not Game.has_save(slot)
		load_btn.pressed.connect(func():
			if Game.load_game(slot):
				Router.continue_run())
		row.add_child(load_btn)
	v.add_child(HUD.make_label("Autosave happens on landing and when boarding the Odd Duck.", 14, Color(0.6, 0.8, 1.0)))
	v.add_child(HUD.make_label("-- DEVICE SETTINGS --", 16, Color(1.0, 0.4, 0.85)))
	_cycle_setting(v, "Depth of field", "dof_mode", ["tilt_shift", "physical", "off"])
	_cycle_setting(v, "Touch controls", "touch", ["auto", "on", "off"])
	_cycle_setting(v, "Music volume (dB)", "music_db", [-8.0, -14.0, -20.0, -80.0, 0.0])
	_cycle_setting(v, "SFX volume (dB)", "sfx_db", [-4.0, -10.0, -16.0, -80.0, 0.0])
	var quit := Button.new()
	quit.text = "QUIT TO TITLE (autosaves)"
	quit.pressed.connect(func():
		Causality.flush_pending()
		Game.save_game()
		Router.goto(Router.TITLE))
	v.add_child(quit)


func _cycle_setting(parent: Control, label: String, key: String, options: Array) -> void:
	var b := Button.new()
	b.text = "%s: %s" % [label, str(Game.settings.get(key, options[0])).to_upper()]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		var idx := options.find(Game.settings.get(key, options[0]))
		Game.settings[key] = options[(idx + 1) % options.size()]
		Game.save_settings()
		Audio.apply_volumes()
		get_tree().call_group("hud", "apply_settings")
		_rebuild())
	parent.add_child(b)
