shader_type spatial;
// Vertical sky gradient for planet horizons (unshaded, sits far behind the map).
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 top : source_color = vec4(0.02, 0.01, 0.06, 1.0);
uniform vec4 bottom : source_color = vec4(0.4, 0.2, 0.5, 1.0);

void fragment() {
	float t = smoothstep(0.0, 1.0, UV.y);
	ALBEDO = mix(top.rgb, bottom.rgb * 1.3, t);
}
