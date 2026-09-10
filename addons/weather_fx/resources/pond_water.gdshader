// Copyright (c) 2026 Antigravity Contributors
// SPDX-License-Identifier: MIT

shader_type spatial;
render_mode depth_draw_always, cull_disabled, specular_schlick_ggx;
// Meshes that write stencil 1 (a boat hull's water mask) cut holes in the surface
stencil_mode read, compare_not_equal, 1;

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

// Wind waves: a sum of Gerstner (trochoidal) waves fanned around the wind. The water moves sideways
// toward each crest as well as up, which is what pinches crests sharp and leaves the troughs broad,
// the way GodotOceanWaves' FFT surface does; a small pond only needs a handful of waves.
uniform float wave_amplitude : hint_range(0.0, 0.5) = 0.04; // metres, the tallest crest at calm wind is 0.6 of this
uniform float wave_frequency : hint_range(0.1, 8.0) = 3.5; // wave number (rad/m) of the middle wave; longer waves are half it
uniform float wave_speed : hint_range(0.1, 6.0) = 1.0; // tempo of the deep-water dispersion (1 = physical)
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.85; // how sharp the crests pinch; 1 is the limit before they loop over
uniform float crest_foam : hint_range(0.0, 1.0) = 0.4; // how much of a pinched crest foams; 0 leaves the crests bare
uniform float crest_light : hint_range(0.0, 1.0) = 0.35; // how much a crest brightens toward the shallow colour
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform float normal_scale : hint_range(0.0, 1.0) = 0.35;
uniform vec2 uv_scale = vec2(2.5, 2.5);

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_linear;

// Body ripples from a WaterRipples node: R = simulated height, B = the bodies' footprint. The node fills these in.
uniform sampler2D ripple_texture : filter_linear, repeat_disable;
uniform vec4 ripple_area = vec4(0.0); // world X, world Z, width, depth of the simulated surface; a zero width means none
uniform float ripple_height : hint_range(0.0, 0.5) = 0.04; // metres of displacement per unit of simulated height
uniform float ripple_shading : hint_range(0.0, 8.0) = 3.0; // how steeply the ripples tilt the lighting; toon water exaggerates
uniform float ripple_crest_light : hint_range(0.0, 1.0) = 0.25; // how much a ripple crest brightens toward the shallow colour

const int WAVE_COUNT = 6;
const float GRAVITY = 9.8;
// Each wave: angle from the wind (rad), wave number as a multiple of wave_frequency, share of wave_amplitude.
// The shares sum to 1, so the summed crest never rises above the active amplitude. Buoyancy mirrors this table.
const vec3 WAVES[WAVE_COUNT] = {
	vec3(0.0, 0.5, 0.30),
	vec3(0.35, 0.8, 0.22),
	vec3(-0.45, 1.1, 0.18),
	vec3(0.9, 1.7, 0.12),
	vec3(-1.1, 2.3, 0.10),
	vec3(0.2, 3.2, 0.08)
};

varying vec3 v_world_pos;
varying vec2 v_uv;
varying float v_jacobian; // how pinched the surface is: 1 flat, toward 0 at a sharp crest
varying float v_crest; // wave height as a share of the active amplitude, 0 in the troughs

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Three overlapping drop layers; each cell lands one drop at a random spot on its own schedule,
// and heavier rain wakes more of the cells.
vec2 rain_ripples(vec2 uv, float t) {
	vec2 total = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 cell_uv = uv * (13.0 + fi * 6.0) + vec2(fi * 0.37, fi * 0.71);
		vec2 id = floor(cell_uv);
		vec2 f = fract(cell_uv);
		float h = hash21(id + fi * 17.0);
		if (h > weather_precipitation_strength * 1.3) {
			continue;
		}
		vec2 center = vec2(hash21(id + 3.1), hash21(id + 7.7)) * 0.7 + 0.15;
		float period = 1.1 + hash21(id + 11.3) * 1.7;
		float phase = fract(t / period + h);
		vec2 offset = f - center;
		float d = length(offset);
		float radius = phase * 0.4;
		float ring = sin((d - radius) * 45.0) * exp(-abs(d - radius) * 14.0);
		float fade = (1.0 - phase) * smoothstep(0.0, 0.08, phase);
		total += (offset / max(d, 0.001)) * ring * fade;
	}
	return total;
}

// Texture coordinate of a world point in the ripple simulation (its mask camera looks up from below,
// so V runs along -Z), and whether the point lies inside it
vec2 ripple_uv(vec2 world_xz) {
	vec2 uv = (world_xz - ripple_area.xy) / ripple_area.zw;
	return vec2(uv.x, 1.0 - uv.y);
}

bool ripple_inside(vec2 uv) {
	return ripple_area.z > 0.0 && all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)));
}

vec2 wind_direction_2d() {
	vec2 wind = vec2(weather_wind_direction.x, weather_wind_direction.z);
	return length(wind) < 0.001 ? vec2(1.0, 0.0) : normalize(wind);
}

void vertex() {
	v_uv = UV;
	vec2 wind_dir = wind_direction_2d();
	float wind_spd = max(0.1, weather_wind_strength);
	float tempo = wave_speed * (1.0 + wind_spd * 0.15);
	float amplitude = wave_amplitude * (0.6 + clamp(wind_spd * 0.1, 0.0, 2.0));

	// Edge dampening so water stays sealed in the pond
	float dist_from_center = length(UV - vec2(0.5)) * 2.0;
	float edge_mask = smoothstep(0.0, 0.35, clamp(1.0 - dist_from_center, 0.0, 1.0));

	// Sum the Gerstner waves: position offset, the two surface tangents for the normal and the Jacobian
	vec3 offset = vec3(0.0);
	vec3 d_dx = vec3(1.0, 0.0, 0.0);
	vec3 d_dz = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		float angle = WAVES[i].x;
		vec2 dir = vec2(wind_dir.x * cos(angle) - wind_dir.y * sin(angle), wind_dir.x * sin(angle) + wind_dir.y * cos(angle));
		float k = wave_frequency * WAVES[i].y;
		float a = amplitude * WAVES[i].z;
		// Sideways travel per wave, sized so the summed crests never loop over
		float q = wave_steepness / (k * a * float(WAVE_COUNT) + 0.0001);
		float phase = k * dot(dir, VERTEX.xz) - sqrt(GRAVITY * k) * tempo * TIME;
		float s = sin(phase);
		float c = cos(phase);
		offset += vec3(q * a * dir.x * c, a * s, q * a * dir.y * c);
		float qak = q * a * k * s;
		d_dx += vec3(-dir.x * dir.x * qak, a * k * dir.x * c, -dir.x * dir.y * qak);
		d_dz += vec3(-dir.x * dir.y * qak, a * k * dir.y * c, -dir.y * dir.y * qak);
	}
	offset *= edge_mask;
	d_dx = mix(vec3(1.0, 0.0, 0.0), d_dx, edge_mask);
	d_dz = mix(vec3(0.0, 0.0, 1.0), d_dz, edge_mask);
	v_jacobian = d_dx.x * d_dz.z - d_dx.z * d_dz.x;
	v_crest = clamp(offset.y / max(amplitude, 0.0001), 0.0, 1.0);

	// Bodies moving in the water displace it for real, on top of the wind waves
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (ripple_area.z > 0.0) {
		vec2 uv = ripple_uv(world_pos.xz);
		if (ripple_inside(uv)) {
			offset.y += textureLod(ripple_texture, uv, 0.0).r * ripple_height * edge_mask;
		}
	}
	VERTEX += offset;
	NORMAL = normalize(cross(d_dz, d_dx));
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wind_dir = wind_direction_2d();
	float wind_spd = max(0.1, weather_wind_strength);
	float speed_mult = 0.08 + wind_spd * 0.015;

	// Dual scrolling wind ripples
	vec2 flow_uv1 = v_uv * uv_scale + wind_dir * (TIME * speed_mult);
	vec2 flow_uv2 = v_uv * (uv_scale * 1.3) - vec2(wind_dir.y, -wind_dir.x) * (TIME * speed_mult * 0.65);

	vec3 n1 = texture(normal_map, flow_uv1).rgb;
	vec3 n2 = texture(normal_map, flow_uv2).rgb;
	vec3 blended_normal = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;

	// Raindrop impact ripples during rain: scattered, staggered rings, never a lattice
	if (weather_precipitation_strength > 0.05) {
		blended_normal.xy += rain_ripples(v_uv, TIME) * 0.3 * weather_precipitation_strength;
	}

	// Body ripples: tilt the wave normal by the simulated slope, brighten the crests, and foam the tallest of them
	float body_foam = 0.0;
	float ripple_crest = 0.0;
	if (ripple_area.z > 0.0) {
		vec2 uv = ripple_uv(v_world_pos.xz);
		if (ripple_inside(uv)) {
			vec2 texel = 1.0 / vec2(textureSize(ripple_texture, 0));
			vec2 texel_world = ripple_area.zw * texel;
			vec4 ripple = texture(ripple_texture, uv);
			float dh_dx = (texture(ripple_texture, uv + vec2(texel.x, 0.0)).r - texture(ripple_texture, uv - vec2(texel.x, 0.0)).r) * ripple_height / (2.0 * texel_world.x);
			float dh_dz = (texture(ripple_texture, uv + vec2(0.0, texel.y)).r - texture(ripple_texture, uv - vec2(0.0, texel.y)).r) * ripple_height / (2.0 * texel_world.y);
			vec3 tilt_world = vec3(-dh_dx, 0.0, -dh_dz) * ripple_shading;
			NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt_world, 0.0)).xyz);
			ripple_crest = clamp(ripple.r, 0.0, 2.0);
			body_foam = smoothstep(0.9, 1.6, ripple.r);
		}
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

	// 2. Radial shoreline edge foam (mesh perimeter); a width of 0 leaves the rim to the contact foam
	float dist_from_center = length(UV - vec2(0.5)) * 2.0;
	float radial_edge_foam = edge_foam_width > 0.001 ? smoothstep(1.0 - edge_foam_width, 1.0, dist_from_center) : 0.0;

	// 3. Crest foam where the waves pinch together (a Jacobian near 0), as GodotOceanWaves foams its peaks
	float pinch = 1.0 - smoothstep(0.0, 0.5, v_jacobian);
	float wave_foam = pinch * crest_foam;

	// Toon animated foam noise & wave contours
	float foam_wave = sin(TIME * (2.6 + wind_spd * 0.2) + dist_from_center * 24.0 + v_uv.x * 16.0 + v_uv.y * 14.0) * 0.5 + 0.5;
	float foam_wave2 = cos(TIME * (3.8 + wind_spd * 0.15) - dist_from_center * 18.0 + v_uv.x * 20.0) * 0.5 + 0.5;
	float combined_foam_noise = (foam_wave * 0.6 + foam_wave2 * 0.4);

	float raw_foam = max(depth_foam, radial_edge_foam) * (0.75 + combined_foam_noise * 0.45);
	raw_foam = max(raw_foam, max(body_foam, wave_foam) * (0.7 + combined_foam_noise * 0.35));
	float foam = smoothstep(1.0 - foam_softness, 1.0, raw_foam);

	// Toon banded gradient: Deep -> Shallow -> White Shoreline
	float depth_gradient = clamp(dist_from_center * 0.85, 0.0, 1.0);
	vec4 water_col = mix(deep_color, shallow_color, depth_gradient);
	// Crests of the waves and the body ripples catch the light
	float lit = clamp(v_crest * crest_light + ripple_crest * ripple_crest_light, 0.0, 0.7);
	water_col.rgb = mix(water_col.rgb, shallow_color.rgb, lit);

	ALBEDO = mix(water_col.rgb, foam_color.rgb, foam);
	ALPHA = mix(water_col.a, foam_color.a, foam);
	ROUGHNESS = mix(0.06, 0.45, foam);
	SPECULAR = mix(0.7, 0.2, foam);
	METALLIC = 0.02;
}
