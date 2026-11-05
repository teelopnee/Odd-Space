class_name HUD
extends CanvasLayer
## In-level HUD, styled as 80s holographic overlays.
## Built in code so it adapts to any screen ratio (tablet 16:10, phone, PC).
## Listens to EventBus only; gameplay never talks to the HUD directly
## (except Level.bind_player / show_death_screen and the "hud" group calls).

const SCANLINES := preload("res://assets/shaders/scanlines.gdshader")

var player: Player
var camera_rig: CameraRig
var root: Control

var _hp_bar: ProgressBar
var _hp_label: Label
var _credits_label: Label
var _air_label: Label
var _bounty_label: Label
var _loc_label: Label
var _comm_panel: PanelContainer
var _comm_text: RichTextLabel
var _comm_time := 0.0
var _toasts: VBoxContainer
var _ticker_clip: Control
var _ticker_label: Label
var _ticker_items: Array[String] = []
var _ticker_index := 0
var _target_panel: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _sub_box: HBoxContainer
var _current_target: Node = null
var _witness_label: Label
var _prompt_btn: Button
var _touch_root: Control
var _joystick: TouchStick
var _touch_buttons: Array[TouchButton] = []
var _use_btn: TouchButton
var _objective_label: Label
var _oc_bar: HBoxContainer
var _oc_pips: Array[ColorRect] = []
var _oc_label: Label
var _hint_label: Label
var _hint_time := 25.0
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _card: VBoxContainer
var _card_title: Label
var _card_sub: Label
var _gameplay_ui: Array[Control] = []
var cinematic_on := false
signal _dialogue_closed(choice: String)

var _modal: Control
var _dialogue_panel: PanelContainer
var _dialogue_speaker: Label
var _dialogue_text: RichTextLabel
var _dialogue_choices: VBoxContainer
var _dialogue_cb: Callable = Callable()
var _dialogue_open := false
var _queue: Array = []
var _shop_panel: PanelContainer
var _menu: PauseMenu
var _death_panel: PanelContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_overlay()
	_build_status()
	_build_comm()
	_build_toasts()
	_build_ticker()
	_build_target_panel()
	_build_witness_alert()
	_build_prompt()
	_build_touch()
	_build_cinematic()
	_build_modal()
	_connect_signals()
	_refresh_status()


func _build_cinematic() -> void:
	_bar_top = ColorRect.new()
	_bar_top.color = Color(0, 0, 0)
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = 0
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color(0, 0, 0)
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.offset_top = 0
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_bottom)
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.offset_left = -500
	_card.offset_right = 500
	_card.offset_top = -90
	_card.offset_bottom = 60
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	root.add_child(_card)
	_card_sub = make_label("", 20, Color(1.0, 0.82, 0.45))
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_card_sub)
	_card_title = make_label("", 54, Color(1.0, 0.97, 0.9))
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.add_theme_color_override("font_outline_color", Color(0.2, 0.05, 0.25))
	_card_title.add_theme_constant_override("outline_size", 12)
	_card.add_child(_card_title)
	var rule := ColorRect.new()
	rule.color = Color(1.0, 0.82, 0.45, 0.8)
	rule.custom_minimum_size = Vector2(420, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.add_child(rule)


## Letterbox bars + hide gameplay HUD for cutscenes.
func cinematic(on: bool) -> void:
	cinematic_on = on
	var h := 86.0 if on else 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bar_top, "offset_bottom", h, 0.6)
	tw.tween_property(_bar_bottom, "offset_top", -h, 0.6)
	for c in root.get_children():
		if c in [_bar_top, _bar_bottom, _card, _modal, _comm_panel, _toasts] or c is ColorRect:
			continue
		c.visible = not on if c != _target_panel and c != _witness_label and c != _prompt_btn else false
	if not on:
		_touch_root.visible = touch_enabled()
		_refresh_status()


## Octopath-style chapter card: subtitle + big title, fades in and out.
func title_card(title: String, subtitle: String = "", hold: float = 2.4) -> void:
	_card_title.text = title
	_card_sub.text = subtitle
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.8)
	tw.tween_interval(hold)
	tw.tween_property(_card, "modulate:a", 0.0, 0.9)
	Audio.play_sfx("confirm", 0.0, -8.0)


## Await-able dialogue for cutscenes: `await hud.say("Q.U.A.C.K.", "...")`.
func say(speaker: String, text: String, choices: Array = []) -> String:
	show_dialogue(speaker, text, choices, func(id: String): _dialogue_closed.emit(id))
	var picked: String = await _dialogue_closed
	return picked


func bind_player(p: Player, rig: CameraRig) -> void:
	player = p
	camera_rig = rig


# --- Builders ----------------------------------------------------------------------------

static func make_label(text: String, font_size: int = 18, color: Color = Color(0.85, 0.97, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_bar(fill: Color, min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	bar.add_theme_stylebox_override("fill", sb)
	return bar


func _build_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SCANLINES
	mat.set_shader_parameter("line_strength", 0.025)
	mat.set_shader_parameter("vignette", 0.0)
	overlay.material = mat
	root.add_child(overlay)


func _build_status() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	name_row.add_child(make_label(Game.player_name.to_upper(), 20, Color(1.0, 0.82, 0.24)))
	_loc_label = make_label("", 14, Color(0.6, 0.8, 1.0))
	name_row.add_child(_loc_label)
	var hp_row := HBoxContainer.new()
	v.add_child(hp_row)
	_hp_bar = make_bar(Color(1.0, 0.3, 0.5), Vector2(220, 16))
	hp_row.add_child(_hp_bar)
	_hp_label = make_label("100/100", 16)
	hp_row.add_child(_hp_label)
	_oc_bar = HBoxContainer.new()
	_oc_bar.add_theme_constant_override("separation", 3)
	v.add_child(_oc_bar)
	for i in 3:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(72, 9)
		pip.color = Color(0.25, 0.1, 0.25, 0.8)
		_oc_bar.add_child(pip)
		_oc_pips.append(pip)
	_oc_label = make_label("OVERCLOCK", 12, Color(1.0, 0.4, 0.9))
	_oc_bar.add_child(_oc_label)
	_credits_label = make_label("", 17, Color(1.0, 0.85, 0.3))
	v.add_child(_credits_label)
	_air_label = make_label("", 14, Color(0.4, 0.95, 1.0))
	v.add_child(_air_label)
	_bounty_label = make_label("", 14, Color(1.0, 0.35, 0.35))
	v.add_child(_bounty_label)
	_objective_label = make_label("", 14, Color(1.0, 0.85, 0.4))
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(380, 0)
	v.add_child(_objective_label)


func _build_comm() -> void:
	_comm_panel = PanelContainer.new()
	_comm_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_comm_panel.offset_left = -470
	_comm_panel.offset_right = -16
	_comm_panel.offset_top = 14
	_comm_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comm_panel.modulate.a = 0.0
	root.add_child(_comm_panel)
	var v := VBoxContainer.new()
	_comm_panel.add_child(v)
	v.add_child(make_label(">> Q.U.A.C.K.  //  SHIP AI", 14, Color(1.0, 0.82, 0.24)))
	_comm_text = RichTextLabel.new()
	_comm_text.fit_content = true
	_comm_text.custom_minimum_size = Vector2(430, 0)
	_comm_text.scroll_active = false
	_comm_text.add_theme_font_size_override("normal_font_size", 17)
	_comm_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_comm_text)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.offset_left = -470
	_toasts.offset_right = -16
	_toasts.offset_top = 170
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 4)
	root.add_child(_toasts)


func _build_ticker() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -30
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.02, 0.2, 0.75)
	sb.border_width_top = 2
	sb.border_color = Color(1.0, 0.24, 0.78)
	bar.add_theme_stylebox_override("panel", sb)
	root.add_child(bar)
	_ticker_clip = Control.new()
	_ticker_clip.clip_contents = true
	_ticker_clip.custom_minimum_size = Vector2(0, 26)
	_ticker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_ticker_clip)
	_ticker_label = make_label("", 16, Color(1.0, 0.9, 0.95))
	_ticker_clip.add_child(_ticker_label)
	_ticker_items.assign(DataDB.ads.get("ticker", []))
	_ticker_items.shuffle()
	for h in Causality.latest_headlines(3):
		_ticker_items.push_front(h)
	_next_ticker()


func _build_target_panel() -> void:
	_target_panel = PanelContainer.new()
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.offset_left = -230
	_target_panel.offset_right = 230
	_target_panel.offset_top = 12
	_target_panel.visible = false
	root.add_child(_target_panel)
	var v := VBoxContainer.new()
	_target_panel.add_child(v)
	_target_name = make_label("", 17, Color(1.0, 0.4, 0.85))
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_target_name)
	_target_bar = make_bar(Color(1.0, 0.24, 0.78), Vector2(420, 10))
	v.add_child(_target_bar)
	_sub_box = HBoxContainer.new()
	_sub_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_sub_box)


func _build_witness_alert() -> void:
	_witness_label = make_label("", 22, Color(1.0, 0.85, 0.2))
	_witness_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_witness_label.offset_left = -400
	_witness_label.offset_right = 400
	_witness_label.offset_top = 120
	_witness_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_witness_label.visible = false
	root.add_child(_witness_label)


func _build_prompt() -> void:
	_prompt_btn = Button.new()
	_prompt_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_btn.offset_left = -220
	_prompt_btn.offset_right = 220
	_prompt_btn.offset_top = -96
	_prompt_btn.offset_bottom = -50
	_prompt_btn.visible = false
	_prompt_btn.focus_mode = Control.FOCUS_NONE
	_prompt_btn.pressed.connect(func(): if player: player.interact())
	root.add_child(_prompt_btn)


func touch_enabled() -> bool:
	var mode := str(Game.settings.get("touch", "auto"))
	if mode == "on":
		return true
	if mode == "off":
		return false
	if OS.get_cmdline_user_args().has("--touch"):
		return true
	return Router.input_device == "touch"


func apply_settings() -> void:
	if not _modal.visible:
		_touch_root.visible = touch_enabled()
	if camera_rig:
		camera_rig.set_dof_mode(str(Game.settings.get("dof_mode", "tilt_shift")))
	_update_hint()


func _build_touch() -> void:
	_touch_root = Control.new()
	_touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_root.visible = touch_enabled()
	root.add_child(_touch_root)
	_joystick = TouchStick.new()
	_joystick.anchor_left = 0.0
	_joystick.anchor_right = 0.42
	_joystick.anchor_top = 0.35
	_joystick.anchor_bottom = 1.0
	_joystick.offset_bottom = -32
	_touch_root.add_child(_joystick)
	_add_touch_button("melee", "MELEE", Vector2(140, 150), 74, Color(0.35, 1.0, 0.95), 22)
	_add_touch_button("attack", "FIRE", Vector2(305, 118), 56, Color(1.0, 0.3, 0.6), 20)
	_add_touch_button("dodge", "ROLL", Vector2(130, 320), 54, Color(0.5, 0.75, 1.0))
	_add_touch_button("parry", "PARRY", Vector2(282, 270), 50, Color(1.0, 0.82, 0.24), 18)
	_add_touch_button("overclock", "BOOST", Vector2(445, 112), 42, Color(1.0, 0.35, 0.9), 15)
	_add_touch_button("target_cycle", "TGT", Vector2(420, 290), 36, Color(0.7, 0.6, 1.0), 15)
	_add_touch_button("subsystem_next", "PART", Vector2(268, 405), 36, Color(0.7, 0.6, 1.0), 15)
	var med := _add_touch_button("", "MED", Vector2(575, 92), 34, Color(0.4, 1.0, 0.6), 15)
	med.tapped.connect(func(): Game.use_item("medkit") or Game.use_item("antihistamine"))
	var menu := _add_touch_button("", "MENU", Vector2(60, 0), 34, Color(0.85, 0.97, 1.0), 14)
	menu.anchor_top = 0.0
	menu.anchor_bottom = 0.0
	menu.offset_top = 150
	menu.offset_bottom = 150 + 68
	menu.tapped.connect(open_menu.bind(""))
	_hint_label = make_label("", 14, Color(0.85, 0.95, 1.0, 0.85))
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left = 16
	_hint_label.offset_top = -64
	_hint_label.offset_bottom = -36
	root.add_child(_hint_label)
	EventBus.input_device_changed.connect(func(_d):
		if not _modal.visible:
			_touch_root.visible = touch_enabled()
		_hint_time = 20.0
		_update_hint())
	_update_hint()


func _update_hint() -> void:
	if _hint_label == null:
		return
	var dev := Router.input_device
	if dev == "touch":
		_hint_label.text = "MELEE combo  |  hold FIRE = charge shot  |  ROLL at the last moment = PERFECT  |  tap enemy parts to target"
	elif dev == "gamepad":
		_hint_label.text = "X melee  RT shoot (hold: charge)  A roll  RB parry  B overclock  LB/R-stick target  LT part  Y use  START menu"
	else:
		_hint_label.text = "J melee  K shoot (hold: charge)  SPACE roll  L parry  R overclock  TAB target  Q part  F use  ESC menu"


func _add_touch_button(action: String, text: String, from_br: Vector2, radius: float, color: Color, fs: int = 20) -> TouchButton:
	var b := TouchButton.new()
	b.action = action
	b.text = text
	b.color = color
	b.font_size = fs
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -from_br.x - radius
	b.offset_right = -from_br.x + radius
	b.offset_top = -from_br.y - radius
	b.offset_bottom = -from_br.y + radius
	_touch_root.add_child(b)
	_touch_buttons.append(b)
	return b


func _release_touch() -> void:
	_joystick.release()
	for b in _touch_buttons:
		b.release()


func _build_modal() -> void:
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0.02, 0.0, 0.06, 0.35)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	root.add_child(_modal)
	# Dialogue box.
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_panel.offset_left = -560
	_dialogue_panel.offset_right = 560
	_dialogue_panel.offset_top = -40
	_dialogue_panel.offset_bottom = -40
	_dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue_panel.visible = false
	_modal.add_child(_dialogue_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_dialogue_panel.add_child(v)
	_dialogue_speaker = make_label("", 20, Color(1.0, 0.82, 0.24))
	v.add_child(_dialogue_speaker)
	_dialogue_text = RichTextLabel.new()
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.fit_content = true
	_dialogue_text.custom_minimum_size = Vector2(1080, 50)
	_dialogue_text.add_theme_font_size_override("normal_font_size", 19)
	_dialogue_text.add_theme_font_size_override("bold_font_size", 20)
	v.add_child(_dialogue_text)
	_dialogue_choices = VBoxContainer.new()
	_dialogue_choices.add_theme_constant_override("separation", 6)
	v.add_child(_dialogue_choices)
	# Shop.
	_shop_panel = PanelContainer.new()
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.offset_left = -430
	_shop_panel.offset_right = 430
	_shop_panel.offset_top = -300
	_shop_panel.offset_bottom = 300
	_shop_panel.visible = false
	_modal.add_child(_shop_panel)
	# Pause menu.
	_menu = PauseMenu.new()
	_menu.visible = false
	_menu.closed.connect(_close_menu)
	_modal.add_child(_menu)
	# Death screen.
	_death_panel = PanelContainer.new()
	_death_panel.set_anchors_preset(Control.PRESET_CENTER)
	_death_panel.offset_left = -360
	_death_panel.offset_right = 360
	_death_panel.offset_top = -170
	_death_panel.offset_bottom = 170
	_death_panel.visible = false
	_modal.add_child(_death_panel)
	var dv := VBoxContainer.new()
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_theme_constant_override("separation", 14)
	_death_panel.add_child(dv)
	var title := make_label("SUBSCRIPTION TO LIFE: EXPIRED", 30, Color(1.0, 0.3, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(title)
	var sub := make_label("Halcyon has repossessed your remaining organs.\nThe Causality Log keeps everything you did up to your last save.", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(sub)
	var reload := Button.new()
	reload.text = "RELOAD LAST SAVE"
	reload.pressed.connect(_on_reload)
	dv.add_child(reload)
	var quit := Button.new()
	quit.text = "QUIT TO TITLE"
	quit.pressed.connect(func(): Router.goto(Router.TITLE))
	dv.add_child(quit)


# --- Signals ---------------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.player_hp_changed.connect(func(_h, _m): _refresh_status())
	EventBus.credits_changed.connect(func(_v, _d): _refresh_status())
	EventBus.air_billed.connect(func(_c, _d): _refresh_status())
	EventBus.bounty_changed.connect(func(_f, _a): _refresh_status())
	EventBus.ai_say.connect(_on_ai_say)
	EventBus.toast.connect(toast)
	EventBus.news_broadcast.connect(_on_news)
	EventBus.action_recorded.connect(_on_action_recorded)
	EventBus.action_status_changed.connect(_on_action_status)
	EventBus.faction_rep_changed.connect(_on_rep_changed)
	EventBus.crew_bark.connect(_on_crew_bark)
	EventBus.crew_approval_changed.connect(_on_crew_approval)
	EventBus.target_changed.connect(_on_target_changed)
	EventBus.interact_prompt_changed.connect(_on_prompt)
	EventBus.dialogue_requested.connect(show_dialogue)
	EventBus.shop_requested.connect(show_shop)
	EventBus.flaw_offered.connect(_on_flaw_offered)
	EventBus.mishap.connect(_on_mishap)
	EventBus.inventory_changed.connect(func(_i, _c): _refresh_status())
	EventBus.overclock_changed.connect(_on_overclock)
	Saga.objective_changed.connect(_refresh_objective)
	_refresh_objective()


func _refresh_status() -> void:
	if _hp_bar == null:
		return
	_hp_bar.max_value = Game.max_hp()
	_hp_bar.value = Game.hp
	_hp_label.text = " %d/%d" % [roundi(Game.hp), roundi(Game.max_hp())]
	_credits_label.text = "%d CR   MEDKITS x%d" % [Game.credits, Game.item_count("medkit")]
	_air_label.text = "O2 SUBSCRIPTION: ACTIVE" if Game.air_debt == 0 else "O2 DEBT: %d CR (Halcyon is watching)" % Game.air_debt
	_air_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0) if Game.air_debt == 0 else Color(1.0, 0.6, 0.2))
	var b := Factions.total_bounty()
	_bounty_label.text = "BOUNTY: %d CR" % b if b > 0 else ""
	_bounty_label.visible = b > 0
	_loc_label.text = "  @ " + Game.location_name


func toast(text: String, color: Color = Color(0.85, 0.97, 1.0)) -> void:
	var l := make_label(text, 15, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(450, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toasts.add_child(l)
	while _toasts.get_child_count() > 6:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _refresh_objective() -> void:
	if _objective_label == null:
		return
	var lines: Array[String] = []
	var main := Saga.objective_text()
	if main != "":
		lines.append("> " + main)
	for q in Saga.side_quests_at(Game.location_id):
		if q.status == "active":
			lines.append("- %s%s" % [q.title, "  (return for reward)" if q.get("ready", false) else ""])
	_objective_label.text = "\n".join(lines)


func _on_overclock(meter: float, active_time: float) -> void:
	for i in _oc_pips.size():
		var fill := clampf((meter - i * 33.4) / 33.4, 0.0, 1.0)
		_oc_pips[i].color = Color(1.0, 0.3, 0.9, 0.95) if fill >= 1.0 else Color(0.25 + 0.5 * fill, 0.1, 0.25 + 0.4 * fill, 0.85)
	if active_time > 0.0:
		_oc_label.text = "OVERCLOCK!"
		for pip in _oc_pips:
			pip.color = Color(1.0, 0.85, 0.3)
	else:
		var g := Router.glyph("overclock")
		_oc_label.text = "OVERCLOCK" + (" [%s]" % g if g != "" and meter >= 33.4 else "")


func _on_ai_say(text: String, _mood: String) -> void:
	_comm_text.text = text
	_comm_text.visible_ratio = 0.0
	_comm_time = 4.0 + text.length() * 0.045
	_comm_panel.modulate.a = 1.0
	Audio.play_sfx("blip", 0.05, -10.0)


func _on_news(headline: String, _node: Dictionary) -> void:
	_ticker_items.push_front(headline)
	toast(headline, Color(1.0, 0.45, 0.85))


func _on_action_recorded(node: Dictionary) -> void:
	if int(node.severity) <= 0 and node.status != Causality.STATUS_PENDING:
		return
	match node.status:
		Causality.STATUS_PENDING:
			toast("WITNESSED: %s (%d witness%s calling it in!)" % [node.label, node.witnesses.size(), "" if node.witnesses.size() == 1 else "es"], Color(1.0, 0.75, 0.2))
		Causality.STATUS_SECRET:
			if Causality.CRIME_VERBS.has(node.verb):
				toast("UNSEEN: %s. Nobody saw a thing." % node.label, Color(0.6, 0.8, 1.0))


func _on_action_status(node: Dictionary, _old: String) -> void:
	match node.status:
		Causality.STATUS_REPORTED:
			toast("REPORTED: %s -> the Consortium knows." % node.label, Color(1.0, 0.35, 0.35))
		Causality.STATUS_SUPPRESSED:
			toast("SUPPRESSED: the %s report died with the call." % str(node.label).to_lower(), Color(0.5, 1.0, 0.7))


func _on_rep_changed(fid: String, old: int, new_value: int, reason: String) -> void:
	var d := new_value - old
	if d == 0:
		return
	toast("%s %+d  (%s)" % [DataDB.factions.get(fid, {}).get("short", fid), d, reason], DataDB.faction_color(fid))


func _on_crew_bark(member_id: String, text: String) -> void:
	toast("%s: \"%s\"" % [Crew.def(member_id).get("name", member_id), text], Color(0.75, 1.0, 0.6))


func _on_crew_approval(member_id: String, old: int, new_value: int) -> void:
	if absi(new_value - old) >= 3:
		toast("%s approval %+d (%s)" % [Crew.def(member_id).get("name", member_id), new_value - old, Crew.mood(member_id)], Color(0.6, 0.9, 0.6))


func _on_mishap(kind: String, count: int) -> void:
	if count >= 2:
		toast("MISHAP x%d: %s" % [count, kind.replace("_", " ")], Color(0.8, 0.7, 1.0))


func _on_flaw_offered(flaw_id: String, mishap_kind: String) -> void:
	var d := FlawPerk.flaw_def(flaw_id)
	var text := "[b]MISHAP PATTERN DETECTED:[/b] %s\n\nThe universe offers you a deal. Accept the flaw [color=#ff3ec8]%s[/color]\n%s\n\n...and receive [color=#ffd23e]+%d skill points[/color] for free." % [
		mishap_kind.replace("_", " ").to_upper(), str(d.get("name", flaw_id)).to_upper(), d.get("desc", ""), int(d.get("skill_points", 1))]
	show_dialogue("FLAW & PERK", text, [
		{"id": "accept", "text": "ACCEPT THE FLAW (+%d SP)" % int(d.get("skill_points", 1))},
		{"id": "decline", "text": "Decline (it'll come back)"},
	], func(choice: String):
		if choice == "accept":
			FlawPerk.accept_offer()
		else:
			FlawPerk.decline_offer())


func _on_prompt(text: String) -> void:
	var g := Router.glyph("interact")
	_prompt_btn.text = ("[%s]  " % g if g != "" else "") + text.to_upper()
	_prompt_btn.visible = text != ""


# --- Target panel ------------------------------------------------------------------------------

func _on_target_changed(target: Node, sub: String) -> void:
	_current_target = target
	_target_panel.visible = target != null
	for c in _sub_box.get_children():
		c.queue_free()
	if target == null:
		return
	for id in target.subsystem_ids(true):
		var b := Button.new()
		b.text = target.subsystem_label(id)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		if id == sub:
			b.add_theme_color_override("font_color", Color(1.0, 0.3, 0.9))
			b.text = "> %s <" % b.text
		b.pressed.connect(func(): if player and is_instance_valid(target): player.set_target(target, id))
		_sub_box.add_child(b)


func _update_target_panel() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		_target_panel.visible = false
		return
	_target_name.text = "%s  [%s]" % [str(_current_target.display_name).to_upper(), "HOSTILE" if _current_target.hostile else "PEACEFUL"]
	_target_bar.max_value = _current_target.max_hp
	_target_bar.value = maxf(0.0, _current_target.hp)


func _update_witness_alert() -> void:
	var best := -1.0
	var who := ""
	for w in get_tree().get_nodes_in_group("witness"):
		if is_instance_valid(w) and w.is_reporting() and w.progress > best:
			best = w.progress
			who = w.calls_faction
	_witness_label.visible = best >= 0.0
	if best >= 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		_witness_label.modulate.a = 0.65 + 0.35 * sin(t * 10.0)
		_witness_label.text = "!! WITNESS CALLING %s - %d%% - STOP THEM !!" % [who.to_upper(), roundi(best * 100.0)]


# --- Process ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _comm_time > 0.0:
		_comm_text.visible_ratio = minf(1.0, _comm_text.visible_ratio + delta * 2.2)
		_comm_time -= delta
		if _comm_time <= 0.0:
			var tw := create_tween()
			tw.tween_property(_comm_panel, "modulate:a", 0.0, 0.6)
	if not get_tree().paused:
		_ticker_label.position.x -= delta * 90.0
		if _ticker_label.position.x < -_ticker_label.size.x:
			_next_ticker()
	_update_target_panel()
	_update_witness_alert()
	if _hint_label and _hint_time > 0.0:
		_hint_time -= delta
		_hint_label.modulate.a = clampf(_hint_time / 3.0, 0.0, 1.0)


func _next_ticker() -> void:
	if _ticker_items.is_empty():
		return
	_ticker_index = (_ticker_index + 1) % _ticker_items.size()
	var item: String = _ticker_items[_ticker_index]
	# Two out of three items are freshly written news from the copywriter (data/copy.json).
	if randf() < 0.66:
		item = Copy.make("news", null, {"planet": Game.location_name.to_upper() if Game.location_name != "" else "THE SPRAWL"})
	var desk: String = ["LUMEN NEWS", "LUMEN NEWS", "BREAKING", "MARKETS", "LUMEN SPORT", "WEATHER", "LOCAL"][randi() % 7]
	_ticker_label.text = desk + " //  " + item + "  //  "
	_ticker_label.reset_size()
	_ticker_label.position = Vector2(_ticker_clip.size.x + 20.0, 2)


# --- Input: pause & tap-to-target ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event.is_action_pressed("ui_cancel") and _menu.visible):
		if _menu.visible:
			_close_menu()
		elif not _modal.visible:
			open_menu("")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("log") and not _modal.visible:
		open_menu("causality")
		get_viewport().set_input_as_handled()
		return
	if _menu.visible:
		if event.is_action_pressed("target_cycle"):
			_menu.switch_tab(-1)
		elif event.is_action_pressed("parry"):
			_menu.switch_tab(1)
	if _modal.visible or player == null or camera_rig == null:
		return
	var tap_pos := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		tap_pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not touch_enabled():
		tap_pos = event.position
	if tap_pos.x >= 0.0:
		_tap_target(tap_pos)


func _tap_target(pos: Vector2) -> void:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(pos)
	var to := from + cam.project_ray_normal(pos) * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 64)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var area: Object = hit.collider
	if area.has_meta("enemy"):
		var enemy = area.get_meta("enemy")
		if is_instance_valid(enemy) and enemy.is_alive():
			player.set_target(enemy, area.get_meta("subsystem", "core"))
			get_viewport().set_input_as_handled()


# --- Modal: dialogue ---------------------------------------------------------------------------

## choices: Array of {id, text, disabled?}. Empty -> single "OK".
func show_dialogue(speaker: String, text: String, choices: Array, callback: Callable) -> void:
	if _dialogue_open or _shop_panel.visible or _menu.visible:
		_queue.append([speaker, text, choices, callback])
		return
	_dialogue_open = true
	_open_modal()
	_dialogue_panel.visible = true
	_dialogue_speaker.text = speaker.to_upper()
	_dialogue_text.text = text
	_dialogue_cb = callback
	for c in _dialogue_choices.get_children():
		c.queue_free()
	var list := choices if not choices.is_empty() else [{"id": "", "text": "OK"}]
	var first := true
	for ch in list:
		var b := Button.new()
		b.text = "> " + str(ch.get("text", "..."))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = ch.get("disabled", false)
		b.pressed.connect(_on_choice.bind(str(ch.get("id", ""))))
		_dialogue_choices.add_child(b)
		if first and not b.disabled:
			_safe_focus.call_deferred(b)
			first = false


func _on_choice(id: String) -> void:
	_dialogue_open = false
	_dialogue_panel.visible = false
	var cb := _dialogue_cb
	_dialogue_cb = Callable()
	if cb.is_valid():
		cb.call(id)
	_after_modal_closed()


func _after_modal_closed() -> void:
	if _dialogue_open or _shop_panel.visible or _menu.visible:
		return
	if not _queue.is_empty():
		var next: Array = _queue.pop_front()
		show_dialogue(next[0], next[1], next[2], next[3])
		return
	_close_modal()


func _open_modal() -> void:
	_release_touch()
	_modal.visible = true
	_touch_root.visible = false
	_prompt_btn.visible = false
	get_tree().paused = true


func _close_modal() -> void:
	_modal.visible = false
	_touch_root.visible = touch_enabled() and not cinematic_on
	get_tree().paused = false
	if player:
		player.input_grace = 0.25  # the A/Y that confirmed a choice must not also roll / interact
		player.refresh_interaction()
	_refresh_status()


# --- Modal: shop -----------------------------------------------------------------------------

func show_shop(vendor: String, faction_id: String, stock: Array) -> void:
	if _dialogue_open or _menu.visible:
		return
	_open_modal()
	_shop_panel.visible = true
	_fill_shop(vendor, faction_id, stock)


func _fill_shop(vendor: String, faction_id: String, stock: Array) -> void:
	for c in _shop_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_shop_panel.add_child(v)
	v.add_child(make_label("%s  //  %d CR" % [vendor.to_upper(), Game.credits], 22, Color(1.0, 0.82, 0.24)))
	var standing := "%s standing: %s  (prices x%.2f)" % [DataDB.faction_name(faction_id), Factions.standing(faction_id), Factions.price_multiplier(faction_id)] if faction_id != "" else "Independent trader"
	v.add_child(make_label(standing, 14, Color(0.6, 0.85, 1.0)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 420)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for item_id in stock:
		var price := Game.price_of(item_id, faction_id)
		var row := HBoxContainer.new()
		list.add_child(row)
		var info := make_label("%s  (own %d)\n  %s" % [DataDB.item_name(item_id), Game.item_count(item_id), DataDB.items.get(item_id, {}).get("desc", "")], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var buy := Button.new()
		buy.text = "BUY %d" % price
		buy.disabled = not Game.can_afford(price)
		buy.pressed.connect(func():
			if Game.spend(price):
				Game.add_item(item_id, 1)
				Audio.play_sfx("coin")
			_fill_shop(vendor, faction_id, stock))
		row.add_child(buy)
	list.add_child(make_label("-- SELL --", 16, Color(1.0, 0.4, 0.85)))
	for item_id in Game.inventory.keys():
		if not DataDB.items.get(item_id, {}).get("sell", false):
			continue
		var price := Game.sell_price_of(item_id)
		var row := HBoxContainer.new()
		list.add_child(row)
		var info := make_label("%s x%d" % [DataDB.item_name(item_id), Game.item_count(item_id)], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var sell := Button.new()
		sell.text = "SELL +%d" % price
		sell.pressed.connect(func():
			Game.add_item(item_id, -1)
			Game.add_credits(price)
			Audio.play_sfx("coin")
			_fill_shop(vendor, faction_id, stock))
		row.add_child(sell)
	var close := Button.new()
	close.text = "DONE"
	_safe_focus.call_deferred(close)
	close.pressed.connect(func():
		_shop_panel.visible = false
		Game.shop_discount = 0.0
		_after_modal_closed())
	v.add_child(close)


# --- Modal: pause menu & death ------------------------------------------------------------------

func open_menu(tab: String = "") -> void:
	if _dialogue_open or _shop_panel.visible or _death_panel.visible:
		return
	_open_modal()
	_menu.open(tab)


func _close_menu() -> void:
	_menu.visible = false
	_after_modal_closed()


func show_death_screen() -> void:
	_queue.clear()
	_dialogue_panel.visible = false
	_shop_panel.visible = false
	_menu.visible = false
	_open_modal()
	_death_panel.visible = true
	for c in _death_panel.get_child(0).get_children():
		if c is Button:
			_safe_focus.call_deferred(c)
			break


func _on_reload() -> void:
	get_tree().paused = false
	if Game.load_game():
		Router.continue_run()
	else:
		Router.goto(Router.TITLE)


## Deferred focus that tolerates the control (or its scene) being freed meanwhile.
func _safe_focus(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()
