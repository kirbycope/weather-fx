shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_schlick_ggx;

// =============================================================================
// WeatherFX - Stylized Wind-Reactive Foliage & Grass Shader
// Incorporates harmonic vegetation sway physics with WeatherFX global wind uniforms.
// =============================================================================

// WeatherFX Global Atmospheric Uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

// Grass Appearance & Gradients
group_uniforms Shading;
uniform vec4 color_base : source_color = vec4(0.10, 0.24, 0.10, 1.0);
uniform vec4 color_mid : source_color = vec4(0.40, 0.70, 0.25, 1.0);
uniform vec4 color_tip : source_color = vec4(0.75, 0.95, 0.40, 1.0);
uniform vec4 color_dry_variation : source_color = vec4(0.66, 0.62, 0.28, 1.0);
uniform float dry_patch_scale : hint_range(0.01, 0.5, 0.01) = 0.06;
uniform float dry_patch_blend : hint_range(0.0, 1.0, 0.05) = 0.18;
uniform float ambient_occlusion_strength : hint_range(0.0, 1.0, 0.05) = 0.45;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, hint_default_white;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// Volumetric Foliage Light & Subsurface
group_uniforms Transmission;
uniform vec3 transmission_tint : source_color = vec3(0.35, 0.52, 0.14);
uniform float transmission_strength : hint_range(0.0, 1.0, 0.05) = 0.35;
uniform float normal_up_bias : hint_range(0.0, 1.0, 0.05) = 0.55;

// Wind Physics & Dynamics
group_uniforms Wind;
uniform float wind_speed : hint_range(0.1, 10.0, 0.1) = 1.6;
uniform float wind_turbulence : hint_range(0.0, 3.0, 0.05) = 0.75;
uniform float wind_wave_size : hint_range(0.01, 1.0, 0.01) = 0.15;
uniform float sway_strength : hint_range(0.0, 2.0, 0.05) = 0.50;

// Character & Object Interaction
group_uniforms Interaction;
instance uniform vec3 player_position;
uniform float player_displacement_strength : hint_range(0.0, 2.0, 0.05) = 0.6;
uniform float player_displacement_radius : hint_range(0.1, 5.0, 0.1) = 1.2;

varying vec3 v_world_pos;
varying float v_height;

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Height factor along the blade: roots at VERTEX.y <= 0.0 remain firmly planted
	float height = max(VERTEX.y, 0.0);
	v_height = clamp(height / 1.2, 0.0, 1.0);
	
	// Normalized global wind direction vector
	vec3 wind_dir = weather_wind_direction;
	if (length(wind_dir) < 0.01) {
		wind_dir = vec3(1.0, 0.0, 0.0);
	} else {
		wind_dir = normalize(wind_dir);
	}
	vec3 wind_perp = vec3(-wind_dir.z, 0.0, wind_dir.x);
	
	// Harmonic wind sway guided by vegetation_sway sinusoidal wave physics
	float effective_speed = wind_speed * (0.8 + 0.25 * weather_wind_strength);
	float wave_coord = (world_origin.x * wind_dir.x + world_origin.z * wind_dir.z) * wind_wave_size;
	
	// Main harmonic oscillation + micro turbulence rustle
	float wave_main = sin(wave_coord + TIME * effective_speed + height * 0.4);
	float wave_micro = sin(wave_coord * 2.3 + TIME * effective_speed * 1.8 + world_origin.x * 0.5) * 0.3 * wind_turbulence;
	
	// Wind push (steady lean + dynamic sway)
	float lean = weather_wind_strength * 0.05;
	float sway_oscillation = (wave_main + wave_micro) * (0.08 + 0.03 * weather_wind_strength) * sway_strength;
	float total_sway = lean + sway_oscillation;
	
	vec3 world_sway = (wind_dir * total_sway + wind_perp * (wave_micro * 0.03 * sway_strength)) * height;
	
	// Player / entity displacement interaction
	vec3 push_delta = v_world_pos - player_position;
	float dist_to_player = length(vec3(push_delta.x, push_delta.y * 1.6, push_delta.z));
	if (dist_to_player < player_displacement_radius && dist_to_player > 0.001) {
		float push_factor = smoothstep(player_displacement_radius, 0.0, dist_to_player) * v_height * player_displacement_strength;
		world_sway += normalize(vec3(push_delta.x, -0.2, push_delta.z)) * push_factor;
	}
	
	// Apply displacement in local vertex coordinates
	vec3 local_sway = (inverse(MODEL_MATRIX) * vec4(world_sway, 0.0)).xyz;
	VERTEX += local_sway;
	
	// Soften vertex normals upward towards sky for volumetric foliage shading
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), normal_up_bias));
}

void fragment() {
	vec4 tex_color = texture(texture_albedo, UV);
	if (tex_color.a < alpha_scissor_threshold) {
		discard;
	}
	
	float h = v_height;
	
	// 3-Stop vertical color gradient (Root -> Mid -> Tip)
	vec3 grad_color;
	if (h < 0.45) {
		grad_color = mix(color_base.rgb, color_mid.rgb, h / 0.45);
	} else {
		grad_color = mix(color_mid.rgb, color_tip.rgb, (h - 0.45) / 0.55);
	}
	
	// Root ambient occlusion darkening
	float ao = pow(1.0 - h, 3.5) * ambient_occlusion_strength;
	grad_color = mix(grad_color, color_base.rgb * 0.35, ao);
	
	// Subtle macro terrain color variation (rolling meadow patches)
	float patch_noise = sin(v_world_pos.x * dry_patch_scale) * cos(v_world_pos.z * dry_patch_scale);
	patch_noise = clamp(patch_noise * 0.5 + 0.5, 0.0, 1.0);
	grad_color = mix(grad_color, color_dry_variation.rgb, patch_noise * dry_patch_blend * h);
	
	vec3 albedo_result = tex_color.rgb * grad_color;
	
	// Rain & precipitation response
	float wetness = clamp(weather_precipitation_strength, 0.0, 1.0);
	albedo_result *= (1.0 - wetness * 0.22); // Rain-soaked darkening
	
	ALBEDO = albedo_result;
	ROUGHNESS = mix(0.65, 0.15, wetness);
	SPECULAR = mix(0.20, 0.75, wetness);
	
	// Subsurface transmission / backlight through sunlit blade tips
	BACKLIGHT = transmission_tint * transmission_strength * h * (1.0 - wetness * 0.4);
	
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
