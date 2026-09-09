shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform vec4 ash_color : source_color = vec4(0.06, 0.05, 0.04, 0.75);
uniform vec4 ember_color : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform float ember_intensity : hint_range(0.0, 5.0) = 1.2;

void fragment() {
	vec2 uv_centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(uv_centered);
	if (dist > 1.0) {
		discard;
	}
	float mask = smoothstep(1.0, 0.15, dist);
	float ember_ring = smoothstep(0.4, 0.7, dist) * smoothstep(0.9, 0.7, dist);

	vec3 col = mix(ash_color.rgb, ember_color.rgb * ember_intensity, ember_ring * 0.3);
	ALBEDO = col;
	ALPHA = mask * ash_color.a;
}
