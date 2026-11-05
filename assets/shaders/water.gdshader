shader_type spatial;
// Pixel-friendly water / toxic sludge. Moving ripple bands, a glowing foam line
// along the banks (vertex colour alpha = distance to shore, set by LevelBuilder),
// sparkles, and an emissive pulse so pools read as liquid even at night.

uniform vec4 deep : source_color = vec4(0.02, 0.04, 0.08, 1.0);
uniform vec4 glow : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float glow_strength = 0.1;
uniform float pixel = 6.0; // world-space quantisation of the ripples (texels per metre)
uniform vec4 glow_b : source_color = vec4(1.0, 0.25, 0.8, 1.0); // second sign colour for reflections
uniform float reflect_strength = 0.0; // fake neon-sign reflections (city canals)

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = floor(wp.xz * pixel) / pixel;
	float t = TIME;
	float a = sin(p.x * 1.7 + t * 1.3);
	float b = sin(p.y * 2.3 - t * 1.1);
	float c = sin((p.x + p.y) * 3.1 + t * 2.0);
	float w = a * 0.5 + b * 0.5 + c * 0.25;
	// Slow drifting ripple bands (quantised for the pixel look).
	float band = sin(p.x * 0.9 + p.y * 1.4 - t * 0.8) * 0.5 + 0.5;
	band = floor(band * 4.0) / 4.0;
	vec3 n = normalize(vec3(cos(p.x * 1.7 + t * 1.3) * 0.2 + cos((p.x + p.y) * 3.1 + t * 2.0) * 0.1,
			cos(p.y * 2.3 - t * 1.1) * 0.2, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	float shore = 1.0 - COLOR.a;  // 1 at the bank, 0 in open water
	vec3 shallow = mix(deep.rgb, glow.rgb, 0.18);
	vec3 col = mix(deep.rgb, shallow, band * 0.55 + shore * 0.4);
	ALBEDO = col * (0.7 + 0.2 * w);
	METALLIC = 0.2;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	float sparkle = step(1.08, w) * 0.8;
	float foam = smoothstep(0.55, 1.0, shore) * (0.6 + 0.4 * sin(t * 2.0 + p.x * 4.0 + p.y * 3.0));
	EMISSION = glow.rgb * glow_strength * (0.55 + 0.45 * band + 0.25 * w)
		+ glow.rgb * sparkle * max(glow_strength, 0.15)
		+ mix(vec3(1.0), glow.rgb, 0.5) * foam * max(glow_strength, 0.2) * 1.5;
	// Fake neon reflections: soft vertical smears of sign colour, broken up by the ripples,
	// so a city canal reads as wet glass instead of a black void.
	if (reflect_strength > 0.0) {
		float lane = floor(p.x * 0.9);
		float h = fract(sin(lane * 12.9898 + 4.1) * 43758.5453);
		float smear = smoothstep(0.35, 0.95, sin(p.y * 0.45 + h * 31.0 + t * 0.25) * 0.5 + 0.5) * step(0.4, h);
		float wob = 0.55 + 0.45 * sin(p.y * 6.0 + t * 2.6 + h * 9.0 + w * 2.0);
		vec3 rcol = mix(glow.rgb, glow_b.rgb, step(0.7, h));
		EMISSION += rcol * smear * wob * reflect_strength;
	}
}
