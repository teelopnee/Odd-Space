shader_type canvas_item;
// HD-2D lens: tilt-shift miniature blur + vignette + edge chromatic aberration
// + light film grain + a touch of warm/cool split toning. Screen-space, so it
// costs the same on every GPU (tablet friendly). Sits under the HUD layer.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float focus_center : hint_range(0.0, 1.0) = 0.56;
uniform float focus_width : hint_range(0.0, 0.5) = 0.16;
uniform float falloff : hint_range(0.01, 1.0) = 0.30;
uniform float max_lod : hint_range(0.0, 5.0) = 2.1;
uniform float top_strength : hint_range(0.0, 2.0) = 1.0;
uniform float bottom_strength : hint_range(0.0, 2.0) = 0.8;
uniform float vignette : hint_range(0.0, 1.5) = 0.55;
uniform float aberration : hint_range(0.0, 4.0) = 1.4;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform vec4 shadow_tint : source_color = vec4(0.18, 0.12, 0.32, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.86, 0.7, 1.0);
uniform float toning : hint_range(0.0, 1.0) = 0.22;
uniform bool tilt_shift = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = uv.y - focus_center;
	float amount = 0.0;
	if (tilt_shift) {
		amount = smoothstep(focus_width, focus_width + falloff, abs(d));
		amount *= d < 0.0 ? top_strength : bottom_strength;
	}
	float lod = amount * max_lod;
	vec2 o = SCREEN_PIXEL_SIZE * (0.75 + lod * 1.6);
	// Chromatic aberration grows toward the screen edges.
	vec2 dir = uv - vec2(0.5);
	vec2 ca = dir * SCREEN_PIXEL_SIZE * aberration * 6.0 * dot(dir, dir) * 4.0;
	vec3 c;
	c.r = textureLod(screen_tex, uv + ca, lod).r;
	c.g = textureLod(screen_tex, uv, lod).g;
	c.b = textureLod(screen_tex, uv - ca, lod).b;
	if (amount > 0.01) {
		vec3 blur = textureLod(screen_tex, uv + vec2(o.x, o.y), lod).rgb
			+ textureLod(screen_tex, uv + vec2(-o.x, o.y), lod).rgb
			+ textureLod(screen_tex, uv + vec2(o.x, -o.y), lod).rgb
			+ textureLod(screen_tex, uv + vec2(-o.x, -o.y), lod).rgb;
		c = mix(c, blur * 0.25, clamp(amount, 0.0, 1.0) * 0.64);
	}
	// Split toning: violet shadows, warm highlights (classic HD-2D grade).
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 toned = mix(c * mix(vec3(1.0), shadow_tint.rgb * 2.2, 1.0 - lum), c * mix(vec3(1.0), highlight_tint.rgb * 1.15, lum), lum);
	c = mix(c, toned, toning);
	// Vignette.
	float v = smoothstep(0.25, 0.95, length(dir * vec2(1.15, 1.0)));
	c *= 1.0 - v * vignette;
	// Grain.
	c += (hash(uv * 900.0 + fract(TIME) * 37.0) - 0.5) * grain;
	COLOR = vec4(c, 1.0);
}
