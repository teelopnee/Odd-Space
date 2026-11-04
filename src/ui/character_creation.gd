extends Control
## Dynamic Origin & Tag Engine UI. No classes: pick one tag from each of
## BACKGROUND / MOTIVATION / SECRET. The preview shows exactly what the
## combination does (spawn room, credits, items, rep, bounty, stat mods,
## synergies) and the generated origin story.

var _selected := {"background": "", "motivation": "", "secret": ""}
var _buttons := {}  # category -> {id: Button}
var _name_edit: LineEdit
var _preview: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := RetroBackdrop.new()
	bg.mode = "stars"
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(HUD.make_label("CRYO-THAW REGISTRATION FORM 77-B", 26, Color(1.0, 0.35, 0.85)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(HUD.make_label("NAME:", 18))
	_name_edit = LineEdit.new()
	_name_edit.text = ["Rex Vantablack", "Juniper Null", "Ozzy Debit", "Kit Overdraft", "Sol Quartermain"][randi() % 5]
	_name_edit.custom_minimum_size = Vector2(300, 40)
	_name_edit.max_length = 24
	head.add_child(_name_edit)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)
	var titles := {"background": "BACKGROUND // who you were", "motivation": "MOTIVATION // what you want", "secret": "SECRET / FLAW // what they don't know"}
	for cat in Origin.CATEGORIES:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(panel)
		var pv := VBoxContainer.new()
		panel.add_child(pv)
		pv.add_child(HUD.make_label(titles[cat], 16, Color(1.0, 0.82, 0.24)))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		pv.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		var group := ButtonGroup.new()
		_buttons[cat] = {}
		for t in Origin.list(cat):
			var b := Button.new()
			b.text = t.get("name", t.id)
			b.toggle_mode = true
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(_select.bind(cat, t.id))
			list.add_child(b)
			_buttons[cat][t.id] = b

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(0, 230)
	v.add_child(preview_panel)
	var scroll2 := ScrollContainer.new()
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_panel.add_child(scroll2)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.add_theme_font_size_override("normal_font_size", 16)
	_preview.add_theme_font_size_override("bold_font_size", 17)
	scroll2.add_child(_preview)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	foot.add_child(_button("< BACK", func(): Router.goto(Router.TITLE)))
	foot.add_child(_button("RANDOMIZE", _randomize))
	var go := _button("THAW ME OUT >", _start)
	go.add_theme_color_override("font_color", Color(1.0, 0.82, 0.24))
	foot.add_child(go)
	_randomize()
	Audio.play_music("odd_duck_theme")
	foot.add_child(HUD.make_label("  START = thaw  |  B = back", 13, Color(0.7, 0.8, 1.0)))
	var first: Button = _buttons["background"].values()[0]
	first.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_start()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not _name_edit.has_focus():
		Router.goto(Router.TITLE)
		get_viewport().set_input_as_handled()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 52)
	b.pressed.connect(func():
		Audio.play_sfx("confirm")
		cb.call())
	return b


func _select(cat: String, id: String) -> void:
	_selected[cat] = id
	var b: Button = _buttons[cat].get(id)
	if b and not b.button_pressed:
		b.button_pressed = true
	Audio.play_sfx("blip", 0.1, -8.0)
	_update_preview()


func _randomize() -> void:
	var r := Origin.random_tags()
	for cat in r:
		_select(cat, r[cat])


func _update_preview() -> void:
	var text := ""
	for cat in Origin.CATEGORIES:
		var t := Origin.get_tag(cat, _selected[cat])
		if t.is_empty():
			continue
		text += "[color=#ff3ec8][b]%s[/b][/color]  %s\n" % [str(t.get("name", "")).to_upper(), t.get("desc", "")]
	var p := Origin.preview(_selected)
	var items := []
	for item_id in p.items:
		items.append("%s x%d" % [DataDB.item_name(item_id), p.items[item_id]])
	var reps := []
	for fid in p.rep:
		reps.append("%s %+d" % [DataDB.factions.get(fid, {}).get("short", fid), p.rep[fid]])
	text += "\n[color=#3ee6ff]WAKE UP IN:[/color] %s    [color=#3ee6ff]CREDITS:[/color] %d    [color=#3ee6ff]ITEMS:[/color] %s" % [
		str(p.spawn).replace("_", " ").to_upper(), p.credits, ", ".join(PackedStringArray(items)) if not items.is_empty() else "none"]
	if not reps.is_empty():
		text += "\n[color=#3ee6ff]CONSORTIUM OPINION:[/color] " + ", ".join(PackedStringArray(reps))
	if int(p.bounty) > 0:
		text += "    [color=#ff5a5a]STARTING BOUNTY: %d cr[/color]" % p.bounty
	if str(p.mods) != "":
		text += "\n[color=#3ee6ff]MODIFIERS:[/color] " + str(p.mods)
	if not p.synergies.is_empty():
		text += "\n[color=#ffd23e][b]SYNERGY UNLOCKED: %s[/b][/color]" % ", ".join(PackedStringArray(p.synergies))
	text += "\n\n[i]%s[/i]" % Origin.origin_story(_selected)
	_preview.text = text


func _start() -> void:
	for cat in Origin.CATEGORIES:
		if _selected[cat] == "":
			return
	Game.new_game(_name_edit.text, _selected)
	Router.goto(Router.STATION)
