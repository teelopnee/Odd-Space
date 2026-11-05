shader_type spatial;
// Glossy pixel-friendly water / sludge for planet channels and pools.
// Cheap: three crossing sine swells drive the normal and a soft emission pulse,
// so neon and lamps smear across it like a wet street in an 80s poster.

uniform vec4 deep : source_color = vec4(0.02, 0.04, 0.08, 1.0);
uniform vec4 glow : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float glow_strength = 0.1;
uniform float pixel = 6.0; // world-space quantisation of the ripples (texels per metre)

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = floor(wp.xz * pixel) / pixel;
	float t = TIME;
	float a = sin(p.x * 1.7 + t * 1.3);
	float b = sin(p.y * 2.3 - t * 1.1);
	float c = sin((p.x + p.y) * 3.1 + t * 2.0);
	float w = a * 0.5 + b * 0.5 + c * 0.25;
	vec3 n = normalize(vec3(cos(p.x * 1.7 + t * 1.3) * 0.18 + cos((p.x + p.y) * 3.1 + t * 2.0) * 0.08,
			cos(p.y * 2.3 - t * 1.1) * 0.18, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	ALBEDO = deep.rgb * (0.85 + 0.15 * w);
	METALLIC = 0.6;
	ROUGHNESS = 0.07;
	SPECULAR = 0.8;
	float sparkle = step(1.05, w) * 0.6;
	EMISSION = glow.rgb * glow_strength * (0.75 + 0.25 * w) + glow.rgb * sparkle * glow_strength;
}
