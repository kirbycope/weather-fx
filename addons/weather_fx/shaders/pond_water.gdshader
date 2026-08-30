// Copyright (c) 2026 Antigravity Contributors
// SPDX-License-Identifier: MIT

shader_type spatial;
render_mode depth_draw_always, cull_disabled, specular_schlick_ggx;

// Global atmospheric shader parameters from WeatherFX
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

// Water Colors (Toon Palette)
uniform vec4 shallow_color : source_color = vec4(0.28, 0.82, 0.92, 0.88);
uniform vec4 deep_color : source_color = vec4(0.06, 0.35, 0.60, 0.96);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Shore & Contact Foam
uniform float edge_foam_width : hint_range(0.02, 0.5) = 0.22;
uniform float depth_foam_distance : hint_range(0.0, 2.0) = 0.30;
uniform float foam_softness : hint_range(0.01, 1.0) = 0.15;

// Waves & Wind Reaction
uniform float wave_amplitude : hint_range(0.0, 0.2) = 0.025;
uniform float wave_frequency : hint_range(0.1, 8.0) = 3.5;
uniform float wave_speed : hint_range(0.1, 6.0) = 2.0;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform float normal_scale : hint_range(0.0, 1.0) = 0.35;
uniform vec2 uv_scale = vec2(2.5, 2.5);

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_linear;

varying vec3 v_world_pos;
varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 w_wind = normalize(weather_wind_direction);
	vec2 wind_dir_2d = vec2(w_wind.x, w_wind.z);
	if (length(wind_dir_2d) < 0.001) {
		wind_dir_2d = vec2(1.0, 0.0);
	} else {
		wind_dir_2d = normalize(wind_dir_2d);
	}

	float wind_spd = max(0.1, weather_wind_strength);
	float active_speed = wave_speed * (1.0 + wind_spd * 0.15);
	float active_amp = wave_amplitude * (0.6 + clamp(wind_spd * 0.1, 0.0, 2.0));

	// Wind wave propagation
	float wave1 = sin(dot(VERTEX.xz, wind_dir_2d) * wave_frequency + TIME * active_speed);
	float wave2 = cos(dot(VERTEX.xz, vec2(-wind_dir_2d.y, wind_dir_2d.x)) * (wave_frequency * 1.5) + TIME * (active_speed * 1.3));
	
	// Edge dampening so water stays sealed in the pond
	float dist_from_center = length(UV - vec2(0.5)) * 2.0;
	float edge_mask = clamp(1.0 - dist_from_center, 0.0, 1.0);
	edge_mask = smoothstep(0.0, 0.35, edge_mask);

	VERTEX.y += (wave1 * 0.7 + wave2 * 0.3) * active_amp * edge_mask;
}

void fragment() {
	vec3 w_wind = normalize(weather_wind_direction);
	vec2 wind_dir_2d = vec2(w_wind.x, w_wind.z);
	if (length(wind_dir_2d) < 0.001) {
		wind_dir_2d = vec2(1.0, 0.0);
	} else {
		wind_dir_2d = normalize(wind_dir_2d);
	}

	float wind_spd = max(0.1, weather_wind_strength);
	float speed_mult = 0.08 + wind_spd * 0.015;

	// Dual scrolling wind ripples
	vec2 flow_uv1 = v_uv * uv_scale + wind_dir_2d * (TIME * speed_mult);
	vec2 flow_uv2 = v_uv * (uv_scale * 1.3) - vec2(wind_dir_2d.y, -wind_dir_2d.x) * (TIME * speed_mult * 0.65);

	vec3 n1 = texture(normal_map, flow_uv1).rgb;
	vec3 n2 = texture(normal_map, flow_uv2).rgb;
	vec3 blended_normal = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;

	// Raindrop impact ripples during rain
	if (weather_precipitation_strength > 0.05) {
		vec2 rip_uv = v_uv * 16.0;
		vec2 rip_grid = fract(rip_uv) - 0.5;
		float rip_dist = length(rip_grid);
		float rip_wave = sin(rip_dist * 26.0 - TIME * 14.0) * exp(-rip_dist * 5.5);
		blended_normal.xy += rip_wave * 0.35 * weather_precipitation_strength;
	}

	NORMAL_MAP = blended_normal;
	NORMAL_MAP_DEPTH = normal_scale * (0.8 + clamp(wind_spd * 0.06, 0.0, 1.2));

	// 1. Scene contact foam via Depth Texture (where water intersects terrain/objects)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc;
	if (OUTPUT_IS_SRGB) {
		// Compatibility renderer (OpenGL / WebGL): NDC Z range is [-1.0, 1.0]
		ndc = vec3(SCREEN_UV, depth_raw) * 2.0 - 1.0;
	} else {
		// Forward+ / Mobile renderer (Vulkan / Metal / D3D12): NDC Z range is [0.0, 1.0]
		ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	}
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	float linear_scene_depth = -view_coords.z;
	float water_depth = max(0.0, linear_scene_depth + VERTEX.z);

	float depth_foam = 0.0;
	if (depth_foam_distance > 0.001) {
		depth_foam = clamp(1.0 - (water_depth / depth_foam_distance), 0.0, 1.0);
	}

	// 2. Radial shoreline edge foam (mesh perimeter)
	float dist_from_center = length(UV - vec2(0.5)) * 2.0;
	float radial_edge_foam = smoothstep(1.0 - edge_foam_width, 1.0, dist_from_center);

	// Toon animated foam noise & wave contours
	float foam_wave = sin(TIME * (2.6 + wind_spd * 0.2) + dist_from_center * 24.0 + v_uv.x * 16.0 + v_uv.y * 14.0) * 0.5 + 0.5;
	float foam_wave2 = cos(TIME * (3.8 + wind_spd * 0.15) - dist_from_center * 18.0 + v_uv.x * 20.0) * 0.5 + 0.5;
	float combined_foam_noise = (foam_wave * 0.6 + foam_wave2 * 0.4);

	float raw_foam = max(depth_foam, radial_edge_foam) * (0.75 + combined_foam_noise * 0.45);
	float foam = smoothstep(1.0 - foam_softness, 1.0, raw_foam);

	// Toon banded gradient: Deep -> Shallow -> White Shoreline
	float depth_gradient = clamp(dist_from_center * 0.85, 0.0, 1.0);
	vec4 water_col = mix(deep_color, shallow_color, depth_gradient);

	vec3 final_color = mix(water_col.rgb, foam_color.rgb, foam);
	float final_alpha = mix(water_col.a, foam_color.a, foam);

	ALBEDO = final_color;
	ALPHA = final_alpha;
	ROUGHNESS = mix(0.06, 0.45, foam);
	SPECULAR = mix(0.7, 0.2, foam);
	METALLIC = 0.02;
}
