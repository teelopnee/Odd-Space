shader_type canvas_item;
// Subtle 80s CRT / hologram overlay: scanlines + vignette + faint magenta edge.
// Kept very light so it never hurts readability on a tablet.

uniform float line_strength : hint_range(0.0, 0.5) = 0.06;
uniform float line_density = 2.2;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint : source_color = vec4(1.0, 0.24, 0.78, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	float line = sin(FRAGCOORD.y * 3.14159 / line_density) * 0.5 + 0.5;
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.45, 0.85, d) * vignette;
	vec3 col = mix(vec3(0.0), tint.rgb * 0.25, smoothstep(0.6, 0.9, d));
	COLOR = vec4(col, line * line_strength + vig);
}
