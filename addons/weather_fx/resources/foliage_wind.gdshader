shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

// =============================================================================
// WeatherFX - Stylized Wind-Reactive Foliage & Tree Canopy Shader
// Features harmonic branch swaying, crisp leaf rustle, and natural texture shading.
// =============================================================================

// WeatherFX Global Atmospheric Uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

// Canopy Appearance Uniforms
group_uniforms Shading;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 foliage_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.25;
uniform float normal_up_bias : hint_range(0.0, 1.0, 0.05) = 0.35;

// Foliage Wind Dynamics
group_uniforms Wind;
uniform float wind_speed : hint_range(0.1, 5.0, 0.1) = 1.2;
uniform float trunk_sway_strength : hint_range(0.0, 0.5, 0.01) = 0.05;
uniform float branch_sway_strength : hint_range(0.0, 1.0, 0.02) = 0.20;
uniform float branch_sway_speed : hint_range(0.1, 5.0, 0.1) = 1.8;
uniform float leaf_rustle_strength : hint_range(0.0, 0.5, 0.01) = 0.07;
uniform float rustle_frequency : hint_range(1.0, 30.0, 0.5) = 14.0;
uniform float rustle_spatial_scale : hint_range(1.0, 20.0, 0.5) = 8.0;

varying vec3 v_world_pos;

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Height factor: roots stay firmly grounded, upper canopy branches sway flexibly
	float height = max(VERTEX.y, 0.0);
	float height_factor = clamp(height / 4.2, 0.0, 1.4);
	
	// Normalized global wind vector
	vec3 wind_dir = weather_wind_direction;
	if (length(wind_dir) < 0.01) {
		wind_dir = vec3(1.0, 0.0, 0.0);
	} else {
		wind_dir = normalize(wind_dir);
	}
	vec3 wind_perp = vec3(-wind_dir.z, 0.0, wind_dir.x);
	
	float wind_scale = weather_wind_strength / 7.5;
	
	// 1. Trunk Lean (Low-amplitude foundation lean)
	float slow_time = TIME * wind_speed * (0.8 + 0.3 * wind_scale);
	float slow_wave = sin(slow_time + (world_origin.x + world_origin.z) * 0.1 + height * 0.12);
	float steady_lean = weather_wind_strength * 0.018;
	float trunk_lean = (slow_wave * 0.5 + steady_lean) * trunk_sway_strength * height_factor;
	vec3 trunk_displacement = wind_dir * trunk_lean;
	
	// 2. Harmonic Branch / Canopy Sway (Gracefully undulating branches)
	float branch_phase = (VERTEX.x * 0.5 + VERTEX.z * 0.5 + height * 0.6 + world_origin.x * 0.2);
	float branch_wave = sin(TIME * branch_sway_speed * (0.85 + 0.25 * wind_scale) + branch_phase);
	float branch_lean = (branch_wave * 0.65 + 0.35) * branch_sway_strength * height_factor * (0.4 + 0.6 * clamp(wind_scale, 0.0, 2.5));
	vec3 branch_displacement = wind_dir * branch_lean + wind_perp * (cos(TIME * branch_sway_speed * 0.75 + branch_phase) * branch_lean * 0.4);
	branch_displacement.y -= abs(branch_lean) * 0.14;
	
	// 3. Multi-Octave High-Frequency Leaf Rustle & Jitter
	float f_base = rustle_frequency * (0.85 + 0.4 * wind_scale);
	float t1 = TIME * f_base;
	float t2 = TIME * (f_base * 1.57);
	float t3 = TIME * (f_base * 2.31);
	
	vec3 pos_seed = VERTEX * rustle_spatial_scale + world_origin * 0.5;
	
	float rustle1 = sin(t1 + pos_seed.x + pos_seed.y * 1.3);
	float rustle2 = cos(t2 + pos_seed.z * 1.4 + pos_seed.x * 0.7);
	float rustle3 = sin(t3 + (pos_seed.x + pos_seed.y + pos_seed.z) * 0.8);
	
	float combined_rustle = (rustle1 * 0.5 + rustle2 * 0.35 + rustle3 * 0.15);
	float rustle_amp = leaf_rustle_strength * height_factor * (0.3 + 0.7 * clamp(wind_scale, 0.0, 2.5));
	
	vec3 leaf_displacement = NORMAL * (combined_rustle * rustle_amp * 0.6)
		+ wind_perp * (rustle2 * rustle_amp * 0.4)
		+ wind_dir * (rustle1 * rustle_amp * 0.25);
		
	vec3 total_sway = trunk_displacement + branch_displacement + leaf_displacement;
	
	// Apply displacement in local mesh coordinates
	vec3 local_sway = (inverse(MODEL_MATRIX) * vec4(total_sway, 0.0)).xyz;
	VERTEX += local_sway;
	
	// Soften normals upward towards sky for volumetric foliage shading
	vec3 perturbed_normal = normalize(NORMAL + local_sway * 0.8);
	NORMAL = normalize(mix(perturbed_normal, vec3(0.0, 1.0, 0.0), normal_up_bias));
}

void fragment() {
	vec4 tex_color = texture(texture_albedo, UV);
	
	if (tex_color.a < alpha_scissor_threshold) {
		discard;
	}
	
	ALBEDO = tex_color.rgb * foliage_tint.rgb;
	
	// Rain wetness reaction
	float wetness = clamp(weather_precipitation_strength, 0.0, 1.0);
	ROUGHNESS = mix(0.7, 0.25, wetness);
	SPECULAR = mix(0.2, 0.5, wetness);
	
	BACKLIGHT = vec3(0.22, 0.35, 0.15) * (1.0 - wetness * 0.4);
	
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
