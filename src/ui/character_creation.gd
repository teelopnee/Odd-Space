extends Control
## Dynamic Origin & Tag Engine UI. No classes: pick one tag from each of
## BACKGROUND / MOTIVATION / SECRET, pick (or roll) how you look, and pick how
## the story starts - thawed out of cryo-collateral, or as a native of one of
## this universe's generated worlds. The universe seed makes the run unique
## (planets, saga cast, story beats) and can be typed in to share a run.

const START_CRYO := ""

var _selected := {"background": "", "motivation": "", "secret": ""}
var _buttons := {}  # category -> {id: Button}
var _name_edit: LineEdit
var _preview: RichTextLabel
var _look_view: LookPreview
var _style_label: Label
var _start_option: OptionButton
var _seed_edit: LineEdit

var _look: Dictionary = {}
var _styles: Array = []
var _style_index := 0
var _cycle := {"skin": 0, "hair": 0, "iris": 0, "glow": 0}
var _seed := 0
var _galaxy: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := RetroBackdrop.new()
	bg.mode = "stars"
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(HUD.make_label("CRYO-THAW REGISTRATION FORM 77-B", 24, Color(1.0, 0.35, 0.85)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(HUD.make_label("NAME:", 18))
	_name_edit = LineEdit.new()
	_name_edit.text = _random_name()
	_name_edit.custom_minimum_size = Vector2(260, 40)
	_name_edit.max_length = 24
	head.add_child(_name_edit)
	head.add_child(_button("DICE", func(): _name_edit.text = _random_name(), Vector2(80, 40)))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 10)
	v.add_child(cols)
	cols.add_child(_appearance_panel())
	var titles := {"background": "BACKGROUND // who you were", "motivation": "MOTIVATION // what you want", "secret": "SECRET / FLAW // what they don't know"}
	for cat in Origin.CATEGORIES:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(panel)
		var pv := VBoxContainer.new()
		panel.add_child(pv)
		pv.add_child(HUD.make_label(titles[cat], 15, Color(1.0, 0.82, 0.24)))
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
			b.add_theme_font_size_override("font_size", 16)
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.tooltip_text = str(t.get("desc", ""))
			b.pressed.connect(_select.bind(cat, t.id))
			list.add_child(b)
			_buttons[cat][t.id] = b

	# How the story starts + which universe.
	var origin_row := HBoxContainer.new()
	origin_row.add_theme_constant_override("separation", 8)
	v.add_child(origin_row)
	origin_row.add_child(HUD.make_label("START:", 17, Color(0.24, 0.9, 1.0)))
	_start_option = OptionButton.new()
	_start_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_option.custom_minimum_size = Vector2(0, 44)
	_start_option.add_theme_font_size_override("font_size", 16)
	_start_option.fit_to_longest_item = false
	_start_option.clip_text = true
	_start_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_start_option.item_selected.connect(func(_i): _update_preview())
	origin_row.add_child(_start_option)
	origin_row.add_child(HUD.make_label("UNIVERSE #", 17, Color(0.24, 0.9, 1.0)))
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(140, 44)
	_seed_edit.max_length = 10
	_seed_edit.text_submitted.connect(func(_t): _apply_seed_text())
	_seed_edit.focus_exited.connect(_apply_seed_text)
	origin_row.add_child(_seed_edit)
	origin_row.add_child(_button("NEW UNIVERSE", func(): _set_seed(_rng.randi() % 1000000000), Vector2(170, 44)))

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(0, 190)
	v.add_child(preview_panel)
	var scroll2 := ScrollContainer.new()
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_panel.add_child(scroll2)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.add_theme_font_size_override("normal_font_size", 15)
	_preview.add_theme_font_size_override("bold_font_size", 16)
	scroll2.add_child(_preview)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	foot.add_child(HUD.make_label("START = begin  |  B = back  ", 13, Color(0.7, 0.8, 1.0)))
	foot.add_child(_button("< BACK", func(): Router.goto(Router.TITLE)))
	foot.add_child(_button("RANDOMIZE ALL", _randomize_all))
	var go := _button("BEGIN >", _start)
	go.add_theme_color_override("font_color", Color(1.0, 0.82, 0.24))
	foot.add_child(go)

	_styles = _player_styles()
	_set_seed(_rng.randi() % 1000000000)
	_random_look()
	_randomize_tags()
	Audio.play_music("odd_duck_theme")
	var first: Button = _buttons["background"].values()[0]
	_safe_focus.call_deferred(first)


func _appearance_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 0)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	panel.add_child(pv)
	pv.add_child(HUD.make_label("LOOK // how they'll ID you", 15, Color(1.0, 0.82, 0.24)))
	_look_view = LookPreview.new()
	_look_view.custom_minimum_size = Vector2(0, 180)
	_look_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(_look_view)
	var style_row := HBoxContainer.new()
	style_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(style_row)
	style_row.add_child(_button("<", func(): _step_style(-1), Vector2(56, 40)))
	_style_label = HUD.make_label("STYLE 01", 16)
	_style_label.custom_minimum_size = Vector2(130, 0)
	_style_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_row.add_child(_style_label)
	style_row.add_child(_button(">", func(): _step_style(1), Vector2(56, 40)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	pv.add_child(grid)
	for spec in [["SKIN", _cycle_slot.bind("skin")], ["HAIR", _cycle_slot.bind("hair")], ["EYES", _cycle_slot.bind("iris")],
			["OUTFIT", _reroll_outfit], ["NEON", _cycle_slot.bind("glow")], ["RANDOM", _random_look]]:
		var gb := _button(spec[0], spec[1], Vector2(80, 40))
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(gb)
	return panel


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_start()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not _name_edit.has_focus() and not _seed_edit.has_focus():
		Router.goto(Router.TITLE)
		get_viewport().set_input_as_handled()


func _button(text: String, cb: Callable, min_size: Vector2 = Vector2(150, 50)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(func():
		Audio.play_sfx("confirm")
		cb.call())
	return b


func _random_name() -> String:
	var saga := Saga.data()
	var names: Dictionary = saga.get("names", {})
	var first: Array = names.get("first", ["Rex"])
	var last: Array = names.get("last", ["Vantablack"])
	if _rng.randf() < 0.3:
		var nick: Array = names.get("nick", ["Static"])
		return "%s %s" % [nick[_rng.randi() % nick.size()], last[_rng.randi() % last.size()]]
	return "%s %s" % [first[_rng.randi() % first.size()], last[_rng.randi() % last.size()]]


# --- Tags ------------------------------------------------------------------------------------

func _select(cat: String, id: String) -> void:
	_selected[cat] = id
	var b: Button = _buttons[cat].get(id)
	if b and not b.button_pressed:
		b.button_pressed = true
	Audio.play_sfx("blip", 0.1, -8.0)
	_update_preview()


func _randomize_tags() -> void:
	var r := Origin.random_tags()
	for cat in r:
		_select(cat, r[cat])


func _randomize_all() -> void:
	_randomize_tags()
	_random_look()
	_name_edit.text = _random_name()
	_set_seed(_rng.randi() % 1000000000)
	_start_option.select(_rng.randi() % _start_option.item_count)
	_update_preview()


# --- Look ------------------------------------------------------------------------------------

func _player_styles() -> Array:
	var out := []
	var all := CharacterLook.variants()
	for v in all:
		var tags: Array = all[v].get("tags", [])
		if tags.has("drone") or tags.has("bug"):
			continue
		out.append(v)
	out.sort()
	if out.is_empty():
		out = ["h00"]
	return out


func _random_look() -> void:
	_look = CharacterLook.random_look(_rng, "hero")
	_style_index = maxi(0, _styles.find(_look.get("variant", "h00")))
	_refresh_look()


func _step_style(dir: int) -> void:
	_style_index = posmod(_style_index + dir, _styles.size())
	_look["variant"] = _styles[_style_index]
	_refresh_look()


func _cycle_slot(slot: String) -> void:
	var pool: Array = {
		"skin": CharacterLook.SKIN,
		"hair": CharacterLook.HAIR_NATURAL + CharacterLook.HAIR_NEON,
		"iris": CharacterLook.IRIS,
		"glow": CharacterLook.GLOW,
	}[slot]
	_cycle[slot] = (int(_cycle[slot]) + 1) % pool.size()
	var colors: Dictionary = _look.get("colors", {})
	colors[slot] = pool[_cycle[slot]]
	if slot == "glow":
		colors["accent"] = pool[_cycle[slot]]
	_look["colors"] = colors
	_refresh_look()


func _reroll_outfit() -> void:
	var fresh := CharacterLook.random_colors(_rng, "hero")
	var colors: Dictionary = _look.get("colors", {})
	for k in ["top", "coat", "pants", "boots", "scarf", "cap", "gloves", "gear"]:
		colors[k] = fresh[k]
	_look["colors"] = colors
	_refresh_look()


func _refresh_look() -> void:
	_look_view.set_look(_look)
	_style_label.text = "STYLE %02d/%02d" % [_style_index + 1, _styles.size()]


# --- Universe & start ------------------------------------------------------------------------

func _apply_seed_text() -> void:
	var digits := ""
	for ch in _seed_edit.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits == "":
		_seed_edit.text = str(_seed)
		return
	if int(digits) != _seed:
		_set_seed(int(digits))


func _set_seed(value: int) -> void:
	_seed = absi(value)
	_seed_edit.text = str(_seed)
	_galaxy = PlanetGenerator.generate_galaxy(_seed, 7)
	var keep := _start_option.selected
	_start_option.clear()
	_start_option.add_item("THAWED - wake up as cryo-collateral in Cold Storage Lot 47")
	for p in _galaxy:
		var env := PlanetGenerator.layer(p, "environments")
		var ctrl := str(p.get("controller", ""))
		var owner_text: String = DataDB.factions.get(ctrl, {}).get("short", ctrl.to_upper()) if ctrl != "" else "LAWLESS"
		_start_option.add_item("NATIVE of %s - %s, run by %s" % [p.get("name", "?"), env.get("name", "?"), owner_text])
	_start_option.select(clampi(keep, 0, _start_option.item_count - 1))
	_update_preview()


func _start_planet_id() -> String:
	var i := _start_option.selected
	if i <= 0 or i - 1 >= _galaxy.size():
		return START_CRYO
	return str(_galaxy[i - 1].get("id", ""))


func _start_text() -> String:
	var pid := _start_planet_id()
	if pid == START_CRYO:
		return "[color=#3ee6ff]START:[/color] Cold Storage Lot 47. You are somebody's collateral. The alarm is your alarm clock. A second-hand ship called the Odd Duck is waiting in the hangar - with a ship AI that already dislikes you."
	var p: Dictionary = _galaxy[_start_option.selected - 1]
	var env := PlanetGenerator.layer(p, "environments")
	var crisis := PlanetGenerator.layer(p, "crises")
	var ctrl := str(p.get("controller", ""))
	var who := DataDB.faction_name(ctrl) if ctrl != "" else "nobody (lawless)"
	return "[color=#3ee6ff]START:[/color] Born and raised on [b]%s[/b] - %s Run by %s; right now: %s. Locals know your face ([color=#7dff4a]+12 rep[/color] with the owners, +40 cr). No cryo prologue: the Odd Duck is parked on the pad, bought on a loan you try not to think about." % [
		p.get("name", "?"), env.get("desc", ""), who, str(crisis.get("name", "")).to_lower()]


func _update_preview() -> void:
	if _preview == null or _start_option == null:
		return
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
	var native := _start_planet_id() != START_CRYO
	var wake: String = str(_galaxy[_start_option.selected - 1].get("name", "?")).to_upper() + " (HOME)" if native else str(p.spawn).replace("_", " ").to_upper()
	text += "\n[color=#3ee6ff]WAKE UP IN:[/color] %s    [color=#3ee6ff]CREDITS:[/color] %d    [color=#3ee6ff]ITEMS:[/color] %s" % [
		wake, int(p.credits) + (40 if native else 0), ", ".join(PackedStringArray(items)) if not items.is_empty() else "none"]
	if not reps.is_empty():
		text += "\n[color=#3ee6ff]CONSORTIUM OPINION:[/color] " + ", ".join(PackedStringArray(reps))
	if int(p.bounty) > 0:
		text += "    [color=#ff5a5a]STARTING BOUNTY: %d cr[/color]" % p.bounty
	if str(p.mods) != "":
		text += "\n[color=#3ee6ff]MODIFIERS:[/color] " + str(p.mods)
	if not p.synergies.is_empty():
		text += "\n[color=#ffd23e][b]SYNERGY UNLOCKED: %s[/b][/color]" % ", ".join(PackedStringArray(p.synergies))
	text += "\n" + _start_text()
	text += "\n\n[i]%s[/i]" % Origin.origin_story(_selected)
	text += "\n[color=#9a7dff]Universe #%d: 7 worlds, one saga nobody else will ever play. Share the number to share the universe.[/color]" % _seed
	_preview.text = text


func _start() -> void:
	for cat in Origin.CATEGORIES:
		if _selected[cat] == "":
			return
	_apply_seed_text()
	var start := _start_planet_id()
	Game.new_game(_name_edit.text, _selected, _seed, _look, start)
	if start == START_CRYO:
		Router.goto(Router.STATION)
	else:
		Router.goto(Router.PLANET, {"planet_id": start})


## Deferred focus that tolerates the control (or its scene) being freed meanwhile.
func _safe_focus(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()
