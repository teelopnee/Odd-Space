shader_type spatial;
// Wind-swayed pixel-art plants drawn as camera-facing quads (the HD-2D camera
// never changes yaw, so quads simply face +Z). One MultiMesh per level:
// INSTANCE_CUSTOM.x = atlas cell, COLOR = per-instance tint.
render_mode cull_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float cells = 8.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float wind_strength = 0.12;
uniform float emission_strength = 0.0;

varying float v_cell;
varying vec3 v_color;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + wpos.x * 0.8 + wpos.z * 0.45) + 0.45 * sin(TIME * 3.3 + wpos.z * 1.3);
	float top = 1.0 - UV.y;
	VERTEX.x += sway * wind_strength * top * top;
	v_cell = INSTANCE_CUSTOM.x;
	v_color = COLOR.rgb;
}

void fragment() {
	vec2 uv = vec2((UV.x + floor(v_cell + 0.5)) / cells, UV.y);
	vec4 c = texture(atlas, uv);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb * v_color;
	EMISSION = ALBEDO * emission_strength * c.r;
	ROUGHNESS = 0.9;
}
