class_name CharacterLook
extends RefCounted
## Random, recolourable characters.
## A "look" = {"variant": "h07", "colors": {slot_name: "#rrggbb", ...}}.
## variant picks the pre-rendered geometry (hair style, outfit, accessories,
## body) from assets/sprites/characters/variants.json; colors fill the 16
## palette slots (skin, hair, top, pants...). Each slot becomes a 6-step
## hue-shifted ramp (outline, inner line, shadow, base, light, highlight).

const SLOTS := ["skin", "hair", "top", "pants", "boots", "accent", "coat", "gear",
	"glow", "eyewhite", "iris", "dark", "scarf", "cap", "gloves", "flash"]

const SKIN := ["#ffe0c8", "#f6c9a4", "#e8b088", "#d49a6e", "#b97c52", "#9a6040", "#7a4630", "#5a3222",
	"#3e2418", "#b8c8ff", "#a8e0b0", "#d8b0ff", "#9ad8e0"]
const HAIR_NATURAL := ["#1a1418", "#3a2418", "#5a3a22", "#8a5a30", "#c89a50", "#e8d090", "#b8b8c0", "#f0f0f0", "#8a2a1a"]
const HAIR_NEON := ["#2cc9c0", "#ff3ec8", "#3ee6ff", "#7dff4a", "#ffd23e", "#9a7dff", "#ff5a3a", "#3a6aff"]
const CLOTH_DARK := ["#24242e", "#2e2a38", "#1e2838", "#38302a", "#2a3a2e", "#3a2434", "#40404a", "#2a2a22", "#4a3a2a"]
const CLOTH_MID := ["#5a6a8a", "#7a3a8a", "#3a7a5a", "#8a5a3a", "#6a6a72", "#3a5a8a", "#8a3a3a", "#5a7a3a", "#c8c0b0", "#e8e4dc"]
const CLOTH_BRIGHT := ["#e8742a", "#ff3ec8", "#3ee6ff", "#ffd23e", "#7dff4a", "#ff5a5a", "#9a7dff", "#3a6aff", "#f0f0f4", "#c8a060"]
const IRIS := ["#3a6aff", "#2a8a4a", "#7a4a2a", "#8a2aa0", "#d02a2a", "#2ab0c0", "#a07a2a", "#5a5a6a"]
const BOOTS := ["#3a2a22", "#24242c", "#5a3a22", "#4a4a52", "#6a2a2a", "#2a3a4a"]
const GLOW := ["#3ee6ff", "#ff3ec8", "#7dff4a", "#ffd23e", "#ff4a4a", "#9a7dff"]

## Faction uniforms: base, trim, glow.
const FACTION_STYLE := {
	"paragon": {"top": "#26357a", "coat": "#1c2450", "pants": "#1a2040", "cap": "#e8ecff", "accent": "#e8ecff", "gear": "#3a4a7a", "glow": "#3ee6ff"},
	"halcyon": {"top": "#3a3020", "coat": "#2a2418", "pants": "#22201a", "cap": "#c8a040", "accent": "#ffd23e", "gear": "#6a5a3a", "glow": "#ffd23e"},
	"gristle": {"top": "#3a6a2a", "coat": "#2a4a22", "pants": "#3a3020", "cap": "#c8a060", "accent": "#c8a060", "gear": "#4a5a3a", "glow": "#7dff4a"},
	"oxy": {"top": "#e8f4ff", "coat": "#c8dce8", "pants": "#3a4a5a", "cap": "#3ee6ff", "accent": "#3ee6ff", "gear": "#8a9aaa", "glow": "#3ee6ff"},
	"lumen": {"top": "#2a1030", "coat": "#3a1440", "pants": "#1a1020", "cap": "#ff3ec8", "accent": "#ff3ec8", "gear": "#4a2a5a", "glow": "#ff3ec8"},
}

static var _variants: Dictionary = {}
static var _palette_cache: Dictionary = {}


static func variants() -> Dictionary:
	if _variants.is_empty():
		var path := "res://assets/sprites/characters/variants.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_variants = parsed
	return _variants


static func variants_with(tag: String) -> Array:
	var out := []
	for v in variants():
		if variants()[v].get("tags", []).has(tag):
			out.append(v)
	return out


static func _pick(rng: RandomNumberGenerator, list: Array):
	return list[rng.randi() % list.size()]


## style: "hero" | "civilian" | "worker" | "corporate[:faction]" | "punk" | "heavy[:faction]"
##        "cop[:faction]" | "robot" | "drone[:faction]" | "bug"
static func random_look(rng: RandomNumberGenerator, style: String = "civilian") -> Dictionary:
	var parts := style.split(":")
	var kind := parts[0]
	var faction := parts[1] if parts.size() > 1 else ""
	var tag := kind
	if kind == "drone":
		tag = "drone"
	elif kind == "bug":
		tag = "bug"
	var pool := variants_with(tag)
	if pool.is_empty():
		pool = variants_with("civilian")
	if pool.is_empty():
		pool = ["h00"]
	var variant: String = _pick(rng, pool)
	return {"variant": variant, "colors": random_colors(rng, kind, faction)}


static func random_colors(rng: RandomNumberGenerator, kind: String = "civilian", faction: String = "") -> Dictionary:
	var c := {}
	c["skin"] = _pick(rng, SKIN.slice(0, 9)) if rng.randf() < 0.88 else _pick(rng, SKIN)
	var neon := kind == "punk" or (kind in ["hero", "civilian"] and rng.randf() < 0.35)
	c["hair"] = _pick(rng, HAIR_NEON) if neon else _pick(rng, HAIR_NATURAL)
	c["top"] = _pick(rng, CLOTH_MID if rng.randf() < 0.6 else CLOTH_DARK)
	c["pants"] = _pick(rng, CLOTH_DARK)
	c["boots"] = _pick(rng, BOOTS)
	c["coat"] = _pick(rng, CLOTH_BRIGHT if rng.randf() < 0.5 else CLOTH_MID)
	c["accent"] = _pick(rng, CLOTH_BRIGHT)
	c["gear"] = _pick(rng, ["#5a5a6a", "#6a6a80", "#4a4a52", "#7a7068", "#3a3a48"])
	c["glow"] = _pick(rng, GLOW)
	c["eyewhite"] = "#f4f4f0"
	c["iris"] = _pick(rng, IRIS)
	c["dark"] = "#1a1030"
	c["scarf"] = _pick(rng, CLOTH_BRIGHT)
	c["cap"] = _pick(rng, CLOTH_BRIGHT + CLOTH_DARK)
	c["gloves"] = _pick(rng, CLOTH_DARK)
	c["flash"] = "#bff8ff"
	if kind == "corporate":
		c["coat"] = _pick(rng, ["#24242e", "#e8e4dc", "#3a2434", "#1e2838"])
		c["top"] = "#f0f0f4"
		c["pants"] = c["coat"]
	if kind == "robot":
		c["gear"] = _pick(rng, ["#9aa4b8", "#c8b890", "#8a9a8a", "#b0a0c0", "#d0d0d8"])
	if kind == "bug":
		var shell: String = _pick(rng, ["#8fc84a", "#c84a8f", "#4ac8b8", "#c8a04a", "#7a6ad8"])
		c["top"] = shell
		c["coat"] = Color(shell).darkened(0.25).to_html(false)
		c["accent"] = "#f0e0a0"
	if faction != "" and FACTION_STYLE.has(faction):
		var fs: Dictionary = FACTION_STYLE[faction]
		for k in fs:
			if kind in ["cop", "heavy", "corporate", "drone"] or k in ["accent", "glow"]:
				c[k] = fs[k]
	return c


## 6-step hue-shifted ramp: [outer outline, inner line, shadow, base, light, highlight].
static func ramp(base: Color) -> Array[Color]:
	var h := base.h
	var s := base.s
	var v := base.v
	return [
		Color.from_hsv(_shift(h, 0.72, 0.35), minf(1.0, s * 1.2 + 0.15), v * 0.16),
		Color.from_hsv(_shift(h, 0.72, 0.30), minf(1.0, s * 1.15 + 0.12), v * 0.34),
		Color.from_hsv(_shift(h, 0.72, 0.16), minf(1.0, s * 1.08 + 0.05), v * 0.68),
		base,
		Color.from_hsv(_shift(h, 0.13, 0.10), s * 0.85, minf(1.0, v * 1.15 + 0.05)),
		Color.from_hsv(_shift(h, 0.13, 0.18), s * 0.55, minf(1.0, v * 1.3 + 0.14)),
	]


static func _shift(h: float, to: float, amt: float) -> float:
	var d := fposmod(to - h + 0.5, 1.0) - 0.5
	return fposmod(h + d * amt, 1.0)


static func palette_texture(colors: Dictionary) -> ImageTexture:
	var key := JSON.stringify(colors)
	if _palette_cache.has(key):
		return _palette_cache[key]
	var img := Image.create_empty(6, 16, false, Image.FORMAT_RGBA8)
	for y in SLOTS.size():
		var base := Color.from_string(str(colors.get(SLOTS[y], "#808080")), Color.GRAY)
		var r := ramp(base)
		for x in 6:
			img.set_pixel(x, y, r[x])
	var tex := ImageTexture.create_from_image(img)
	_palette_cache[key] = tex
	return tex


static func default_look() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3032
	var look := random_look(rng, "hero")
	look["variant"] = "h00"
	return look
