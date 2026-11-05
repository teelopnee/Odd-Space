shader_type spatial;
// Giant hologram version of a palette-indexed character sprite (Blade-Runner-style ad
// figures). Additive, unshaded: luminance of the palette colour is remapped onto a
// two-tone holo gradient, with scrolling scanlines, flicker and glitch bands.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D sheet : filter_nearest;
uniform sampler2D palette : filter_nearest, source_color;
uniform vec4 holo_a : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform vec4 holo_b : source_color = vec4(1.0, 0.25, 0.85, 1.0);
uniform float intensity = 1.4;
uniform float glitch = 0.0;

void fragment() {
	vec4 s = texture(sheet, UV);
	if (s.a < 0.5) {
		discard;
	}
	int slot = int(s.r * 255.0 + 0.5) / 16;
	int band = clamp(int(s.g * 255.0 + 0.5) / 40, 0, 5);
	vec3 c = texelFetch(palette, ivec2(band, slot), 0).rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scan = 0.55 + 0.45 * step(0.45, fract(wp.y * 5.0 - TIME * 1.3));
	float flick = 0.88 + 0.12 * sin(TIME * 23.0) * sin(TIME * 7.3);
	float edge = band <= 1 ? 1.8 : 1.0;
	float glow = (slot == 8 || slot == 15) ? 2.0 : 1.0;
	vec3 col = mix(holo_b.rgb, holo_a.rgb, clamp(lum * 1.5, 0.0, 1.0)) * (0.3 + lum) * edge * glow;
	float bandline = floor(wp.y * 2.5 + TIME * 3.0);
	float g = step(0.96 - glitch * 0.3, fract(sin(bandline * 91.7) * 4375.5));
	ALBEDO = col * scan * flick * intensity * (1.0 + g * 1.5);
}
