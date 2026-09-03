shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

// =============================================================================
// WeatherFX - Stylized Wind-Reactive & Burnable Foliage/Grass Shader
// Incorporates harmonic vegetation sway physics, Minecraft-style biome tinting,
// and BotW/TotK gold-standard wind-driven fire combustion & ash charring.
// =============================================================================

// WeatherFX Global Atmospheric Uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;
// source_color hint is required to bind a ProjectSettings shader global of type "color"
global uniform vec4 weather_grass_tint : source_color;

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

// Combustion & Wildfire Dynamics (BotW Decomp Style)
group_uniforms Combustion;
uniform float burn_progress : hint_range(0.0, 1.0, 0.01) = 0.0;
instance uniform float instance_burn_progress : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec4 ember_inner_color : source_color = vec4(4.0, 1.8, 0.3, 1.0);
uniform vec4 ember_outer_color : source_color = vec4(2.5, 0.4, 0.05, 1.0);
uniform vec4 ash_color : source_color = vec4(0.06, 0.05, 0.04, 1.0);

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
uniform bool enable_player_displacement = false;
instance uniform vec3 player_position;
uniform float player_displacement_strength : hint_range(0.0, 2.0, 0.05) = 0.0;
uniform float player_displacement_radius : hint_range(0.1, 5.0, 0.1) = 1.2;

varying vec3 v_world_pos;
varying float v_height;
varying float v_burn;

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Determine effective burn factor from material uniform or instance uniform
	float effective_burn = max(burn_progress, instance_burn_progress);
	v_burn = clamp(effective_burn, 0.0, 1.0);
	
	// Height factor along the blade (local mesh space): roots at VERTEX.y <= 0.0 remain firmly planted
	float height = max(VERTEX.y, 0.0);
	v_height = clamp(height / 1.2, 0.0, 1.0);
	
	// Normalized global wind direction vector
	vec3 wind_dir = weather_wind_direction;
	if (length(wind_dir) < 0.01) {
		wind_dir = vec3(1.0, 0.0, 0.0);
	} else {
		wind_dir = normalize(wind_dir);
	}
	
	// Transform wind direction to local mesh space so sway stays scale-invariant
	vec3 local_wind_dir = normalize((inverse(MODEL_MATRIX) * vec4(wind_dir, 0.0)).xyz);
	vec3 local_wind_perp = vec3(-local_wind_dir.z, 0.0, local_wind_dir.x);
	
	// Harmonic wind sway guided by sinusoidal wave physics
	float effective_speed = wind_speed * (0.8 + 0.25 * weather_wind_strength);
	float wave_coord = (world_origin.x * wind_dir.x + world_origin.z * wind_dir.z) * wind_wave_size;
	
	// Main harmonic oscillation + micro turbulence rustle
	float wave_main = sin(wave_coord + TIME * effective_speed + height * 0.4);
	float wave_micro = sin(wave_coord * 2.3 + TIME * effective_speed * 1.8 + world_origin.x * 0.5) * 0.3 * wind_turbulence;
	
	// Wind push (steady lean + dynamic sway)
	float lean = weather_wind_strength * 0.025;
	float sway_oscillation = (wave_main + wave_micro) * (0.05 + 0.02 * weather_wind_strength) * sway_strength;
	float total_sway = lean + sway_oscillation;
	
	// Local sway displacement proportional to blade height
	vec3 local_sway = (local_wind_dir * total_sway + local_wind_perp * (wave_micro * 0.02 * sway_strength)) * height;
	
	// Length conservation: bending down when swaying to eliminate vertical elongation
	local_sway.y -= min(height * 0.35, (local_sway.x * local_sway.x + local_sway.z * local_sway.z) * 0.5);
	
	// Fire combustion physics: violent thermal updraft turbulence & blade height decay
	if (v_burn > 0.01) {
		// Heat flutter jitter while burning
		float heat_intensity = sin(v_burn * 3.1415926);
		float heat_flutter = sin(TIME * 28.0 + v_world_pos.x * 4.0 + v_world_pos.z * 4.0) * heat_intensity * 0.06;
		local_sway.x += heat_flutter * height;
		local_sway.z += heat_flutter * height;
		
		// Blade collapses down into charred ground ash
		float height_collapse = mix(1.0, 0.35, smoothstep(0.3, 0.95, v_burn));
		VERTEX.y *= height_collapse;
	}
	
	// Player / entity displacement interaction (local space)
	if (enable_player_displacement && player_displacement_strength > 0.0) {
		vec3 push_delta = v_world_pos - player_position;
		float dist_to_player = length(vec3(push_delta.x, push_delta.y * 1.6, push_delta.z));
		if (dist_to_player < player_displacement_radius && dist_to_player > 0.001) {
			float push_factor = smoothstep(player_displacement_radius, 0.0, dist_to_player) * v_height * player_displacement_strength;
			vec3 world_push = normalize(vec3(push_delta.x, -0.2, push_delta.z)) * push_factor;
			vec3 local_push = (inverse(MODEL_MATRIX) * vec4(world_push, 0.0)).xyz;
			local_sway += clamp(local_push, vec3(-height * 0.8), vec3(height * 0.8));
		}
	}
	
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
	float burn = v_burn;
	
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
	
	// Minecraft/TotK style biome tinting
	vec3 biome_grass_tint = weather_grass_tint.rgb;
	if (length(biome_grass_tint) < 0.01) {
		biome_grass_tint = vec3(1.0);
	}
	vec3 albedo_result = tex_color.rgb * grad_color * biome_grass_tint;
	
	// Rain & precipitation response
	float wetness = clamp(weather_precipitation_strength, 0.0, 1.0);
	albedo_result *= (1.0 - wetness * 0.22); // Rain-soaked darkening
	
	// =========================================================================
	// Gold-Standard Fire & Combustion Edge (BotW Decomp Style)
	// =========================================================================
	vec3 fire_emission = vec3(0.0);
	if (burn > 0.005) {
		// Combustion flame front travelling down the blade
		float flame_threshold = 1.0 - burn;
		float flame_band = smoothstep(flame_threshold - 0.22, flame_threshold, h) * (1.0 - smoothstep(flame_threshold, flame_threshold + 0.18, h));
		
		// Glowing orange/yellow ember emission
		float ember_glow_strength = smoothstep(0.02, 0.85, burn) * (1.0 - smoothstep(0.85, 1.0, burn));
		fire_emission = mix(ember_outer_color.rgb, ember_inner_color.rgb, flame_band) * flame_band * 3.5 * ember_glow_strength;
		
		// Charred ash color blend behind the flame front
		float ash_factor = smoothstep(flame_threshold - 0.1, 1.0, h) * smoothstep(0.15, 0.95, burn);
		albedo_result = mix(albedo_result, ash_color.rgb, ash_factor);
	}
	
	ALBEDO = albedo_result;
	EMISSION = fire_emission;
	ROUGHNESS = mix(0.85, 0.4, wetness);
	SPECULAR = mix(0.05, 0.25, wetness);
	
	// Subsurface transmission / backlight through sunlit blade tips (extinguished when burning)
	BACKLIGHT = transmission_tint * transmission_strength * h * 0.4 * (1.0 - wetness * 0.4) * (1.0 - smoothstep(0.1, 0.7, burn));
	
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
