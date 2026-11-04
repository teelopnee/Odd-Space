extends Control
## Title screen: synthwave sunset, logo, Continue / New Game.

const SLOGANS := [
	"ODD-SPACE is a Consortium-Approved Adventure(tm). Fun is billed separately.",
	"OxyGenix reminds you: holding your breath is a breach of contract.",
	"Halcyon Debt & Trust: proud sponsor of your frozen years.",
	"Lumen Omnimedia: if we didn't report it, it didn't happen.",
	"Paragon Compliance: report a friend today!",
	"Gristle Nutrition: chew responsibly.",
]

var _slogan: Label
var _slogan_i := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := RetroBackdrop.new()
	bg.mode = "sunset"
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -330
	v.offset_right = 330
	v.offset_top = -330
	v.offset_bottom = 150
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var title := HUD.make_label("ODD-SPACE", 96, Color(1.0, 0.35, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.24, 0.9, 1.0))
	title.add_theme_constant_override("outline_size", 10)
	v.add_child(title)
	var sub := HUD.make_label("THE 32ND CENTURY IS UNDER NEW MANAGEMENT", 18, Color(0.6, 0.95, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	if Game.has_save():
		var cont := _button("CONTINUE", _on_continue)
		v.add_child(cont)
		var info := HUD.make_label(Game.save_summary(Game.AUTOSAVE_SLOT), 14, Color(0.8, 0.8, 1.0))
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(info)
	v.add_child(_button("NEW GAME", func(): Router.goto(Router.CREATOR)))
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		v.add_child(_button("QUIT", func(): get_tree().quit()))
	_slogan = HUD.make_label(SLOGANS[0], 16, Color(1.0, 0.85, 0.3))
	_slogan.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_slogan.offset_top = -44
	_slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_slogan)
	var ver := HUD.make_label("v%s  //  Godot %s" % [ProjectSettings.get_setting("application/config/version", "0"), Engine.get_version_info().string], 12, Color(1, 1, 1, 0.4))
	ver.position = Vector2(10, 8)
	add_child(ver)
	Audio.play_music("odd_duck_theme")
	var timer := Timer.new()
	timer.wait_time = 4.0
	timer.autostart = true
	timer.timeout.connect(_next_slogan)
	add_child(timer)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 58)
	b.add_theme_font_size_override("font_size", 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Audio.play_sfx("confirm")
		cb.call())
	return b


func _next_slogan() -> void:
	_slogan_i = (_slogan_i + 1) % SLOGANS.size()
	_slogan.text = SLOGANS[_slogan_i]


func _on_continue() -> void:
	if Game.load_game():
		Router.continue_run()
