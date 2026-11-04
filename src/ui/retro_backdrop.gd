class_name RetroBackdrop
extends Control
## Procedural 80s backdrop drawn with _draw(): no textures needed.
##   mode "sunset": striped synth sun + scrolling perspective neon grid
##   mode "stars" : parallax starfield + nebula blobs; `warp` 0..1 streaks them

@export_enum("sunset", "stars") var mode := "sunset"
@export var warp := 0.0

var _t := 0.0
var _stars: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3032
	for i in 220:
		_stars.append([rng.randf(), rng.randf(), rng.randf_range(0.2, 1.0), rng.randf_range(0.5, 2.2)])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	if mode == "sunset":
		_draw_sunset(s)
	else:
		_draw_stars(s)


func _draw_sunset(s: Vector2) -> void:
	var horizon := s.y * 0.58
	# Sky gradient in bands (cheap and very 80s).
	var bands := 24
	for i in bands:
		var t := float(i) / bands
		var c := Color(0.03, 0.01, 0.1).lerp(Color(0.45, 0.05, 0.4), pow(t, 1.6))
		draw_rect(Rect2(0, horizon * t, s.x, horizon / bands + 1.0), c)
	for st in _stars:
		if st[1] * s.y < horizon * 0.8:
			draw_rect(Rect2(st[0] * s.x, st[1] * s.y, st[3], st[3]), Color(1, 1, 1, st[2] * (0.6 + 0.4 * sin(_t * 2.0 + st[0] * 40.0))))
	# Striped sun.
	var sun_c := Vector2(s.x * 0.5, horizon - s.y * 0.02)
	var r := s.y * 0.24
	for i in 40:
		var y0 := sun_c.y - r + (2.0 * r) * float(i) / 40.0
		var dy := y0 - sun_c.y
		var half := sqrt(maxf(0.0, r * r - dy * dy))
		var stripe := y0 > sun_c.y - r * 0.1 and int((y0 - sun_c.y) / 9.0 + _t * 0.8) % 2 == 0
		if stripe:
			continue
		var c := Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.2, 0.6), float(i) / 40.0)
		draw_rect(Rect2(sun_c.x - half, y0, half * 2.0, 2.0 * r / 40.0 + 1.0), c)
	# Ground + perspective grid.
	draw_rect(Rect2(0, horizon, s.x, s.y - horizon), Color(0.04, 0.0, 0.08))
	var grid_col := Color(1.0, 0.24, 0.78, 0.8)
	var scroll := fmod(_t * 0.6, 1.0)
	for i in 14:
		var z := (float(i) + scroll) / 14.0
		var y := horizon + (s.y - horizon) * pow(z, 2.2)
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(grid_col, 0.25 + 0.6 * z), 2.0)
	for i in range(-12, 13):
		var x_bottom := s.x * 0.5 + i * s.x * 0.12
		draw_line(Vector2(s.x * 0.5 + i * s.x * 0.012, horizon), Vector2(x_bottom, s.y), Color(0.24, 0.9, 1.0, 0.45), 2.0)
	draw_line(Vector2(0, horizon), Vector2(s.x, horizon), Color(1.0, 0.6, 0.9), 3.0)


func _draw_stars(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.01, 0.06))
	for i in 5:
		var c := Vector2(s.x * (0.15 + i * 0.18), s.y * (0.3 + 0.4 * sin(i * 1.7)))
		for k in 6:
			draw_circle(c, s.y * (0.28 - k * 0.04), Color(0.35 + 0.1 * i, 0.05, 0.4 - 0.05 * i, 0.04))
	var center := s * 0.5
	for st in _stars:
		var p := Vector2(st[0] * s.x, st[1] * s.y)
		var col := Color(0.8, 0.9, 1.0, st[2])
		if warp > 0.01:
			var dir := (p - center)
			var streak := dir.length() * 0.6 * warp
			p = center + dir * (1.0 + fmod(_t * (0.5 + st[2]) * warp * 3.0, 1.0))
			draw_line(p, p + dir.normalized() * streak * st[2], Color(col, 0.8), st[3])
		else:
			p.x = fmod(p.x + _t * 6.0 * st[2], s.x)
			draw_rect(Rect2(p, Vector2(st[3], st[3])), Color(col, st[2] * (0.6 + 0.4 * sin(_t * 1.5 + st[0] * 30.0))))
