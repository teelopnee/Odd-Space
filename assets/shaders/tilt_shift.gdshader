shader_type canvas_item;
// HD-2D tilt-shift: a sharp horizontal band around the player, increasingly
// blurred toward the top (far) and bottom (near) of the screen, which makes
// the 3D world read like a miniature diorama. Screen-space, so it behaves the
// same on every GPU (no depth buffer needed) and is cheap on tablets.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float focus_center : hint_range(0.0, 1.0) = 0.56;
uniform float focus_width : hint_range(0.0, 0.5) = 0.13;
uniform float falloff : hint_range(0.01, 1.0) = 0.32;
uniform float max_lod : hint_range(0.0, 5.0) = 2.4;
uniform float top_strength : hint_range(0.0, 2.0) = 1.0;
uniform float bottom_strength : hint_range(0.0, 2.0) = 0.75;

void fragment() {
	float d = SCREEN_UV.y - focus_center;
	float amount = smoothstep(focus_width, focus_width + falloff, abs(d));
	amount *= d < 0.0 ? top_strength : bottom_strength;
	if (amount < 0.01) {
		discard;
	}
	float lod = amount * max_lod;
	vec2 o = SCREEN_PIXEL_SIZE * (0.75 + lod * 1.6);
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.36;
	c += textureLod(screen_tex, SCREEN_UV + vec2(o.x, o.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-o.x, o.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(o.x, -o.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-o.x, -o.y), lod).rgb * 0.16;
	vec3 sharp = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(mix(sharp, c, clamp(amount, 0.0, 1.0)), 1.0);
}
