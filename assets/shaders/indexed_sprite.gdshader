shader_type spatial;
// Palette-indexed character sprite (see tools/sprite_forge.py).
// sheet.r = slot*16+8, sheet.g = band*40+20. palette = 6 bands x 16 slots.
// Lit by scene lights, casts shadows (discard = alpha scissor), glow slots emit.
render_mode cull_disabled, specular_disabled, depth_draw_opaque;

uniform sampler2D sheet : filter_nearest;
uniform sampler2D palette : filter_nearest, source_color;
uniform vec4 tint : source_color = vec4(1.0);
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float alpha = 1.0;
uniform bool ghost = false;

void fragment() {
	vec4 s = texture(sheet, UV);
	if (s.a < 0.5) {
		discard;
	}
	int slot = int(s.r * 255.0 + 0.5) / 16;
	int band = clamp(int(s.g * 255.0 + 0.5) / 40, 0, 5);
	vec3 c = texelFetch(palette, ivec2(band, slot), 0).rgb * tint.rgb;
	c = mix(c, flash_color, clamp(flash, 0.0, 1.0));
	ALBEDO = ghost ? vec3(0.0) : c;
	// Glowing slots: 8 = visor/LEDs, 15 = muzzle flash / energy baton.
	float glow = (slot == 8 || slot == 15) ? 1.6 : 0.0;
	EMISSION = ghost ? c * 2.5 : c * glow + flash_color * flash * 0.8;
	if (alpha < 0.99) {
		// Dithered fade so the sprite stays in the opaque pass (keeps shadows).
		float d = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (d > alpha) {
			discard;
		}
	}
}
