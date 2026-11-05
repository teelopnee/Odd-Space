shader_type canvas_item;
// 2D (UI) version of indexed_sprite.gdshader: palette-indexed sheet -> colours.
// R = slot * 16 + 8, G = band * 40 + 20 (see tools/sprite_forge.py).

uniform sampler2D palette : filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	if (s.a < 0.5) {
		discard;
	}
	int slot = int(s.r * 255.0 + 0.5) / 16;
	int band = clamp(int(s.g * 255.0 + 0.5) / 40, 0, 5);
	vec3 c = texelFetch(palette, ivec2(band, slot), 0).rgb;
	if (slot == 8 || slot == 15) {
		c *= 1.25;
	}
	// (COLOR arrives pre-multiplied by the sheet texel, so overwrite it.)
	COLOR = vec4(c * tint.rgb, tint.a);
}
