shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

// WeatherFX Global Uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

// Grass Appearance Uniforms
uniform vec4 color_base : source_color = vec4(0.12, 0.32, 0.14, 1.0);
uniform vec4 color_tip : source_color = vec4(0.46, 0.74, 0.22, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, hint_default_white;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// Wind Behavior Uniforms
uniform float wind_speed : hint_range(0.1, 10.0) = 1.8;
uniform float wind_turbulence : hint_range(0.0, 3.0) = 0.7;
uniform float wind_wave_size : hint_range(0.01, 1.0) = 0.12;
uniform float sway_strength : hint_range(0.0, 2.0) = 0.45;

void vertex() {
	// Base vertices stay planted (UV.y near 1.0), tip vertices bend (UV.y near 0.0)
	float height_factor = clamp(1.0 - UV.y, 0.0, 1.0);
	
	// Use instance world origin for cohesive clump movement
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	
	// Normalize wind direction with a safe default
	vec3 wind_dir = weather_wind_direction;
	if (length(wind_dir) < 0.01) {
		wind_dir = vec3(1.0, 0.0, 0.0);
	} else {
		wind_dir = normalize(wind_dir);
	}
	
	// Wind strength scaling (base wind + active weather multiplier)
	float current_wind_strength = max(weather_wind_strength, 0.5);
	float effective_speed = wind_speed * (0.8 + 0.15 * current_wind_strength);
	
	// Macro wave passing over the world
	float wave_coord = (world_origin.x * wind_dir.x + world_origin.z * wind_dir.z) * wind_wave_size;
	float wave = sin(TIME * effective_speed + wave_coord);
	
	// Micro turbulence / rustle for natural organic variation
	float turbulence = sin(TIME * effective_speed * 2.3 + world_origin.x * 0.4 + world_origin.z * 0.4) * wind_turbulence;
	
	// Calculate total displacement vector
	float bend = (wave + turbulence * 0.5) * sway_strength * (0.3 + 0.1 * current_wind_strength) * pow(height_factor, 1.6);
	vec3 sway = wind_dir * bend;
	
	// Dip down slightly as it bends forward
	sway.y -= abs(bend) * 0.3 * height_factor;
	
	// Convert world sway displacement to local vertex space
	vec3 local_sway = (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
	VERTEX += local_sway;
	
	// Soften normals towards straight up for natural volumetric foliage shading
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.5));
}

void fragment() {
	// Sample optional texture
	vec4 tex_color = texture(texture_albedo, UV);
	
	// Discard transparent pixels if texture has alpha
	if (tex_color.a < alpha_scissor_threshold) {
		discard;
	}
	
	// Smooth vertical gradient from base to tip
	float gradient_factor = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 base_tint = mix(color_base.rgb, color_tip.rgb, pow(gradient_factor, 1.2));
	
	ALBEDO = tex_color.rgb * base_tint;
	
	// Rain wetness reaction: lower roughness, higher specular during rain
	float wetness = clamp(weather_precipitation_strength, 0.0, 1.0);
	ROUGHNESS = mix(0.75, 0.2, wetness);
	SPECULAR = mix(0.15, 0.6, wetness);
	
	// Subsurface transmission approximation for translucent leaves in sunlight
	BACKLIGHT = vec3(0.2, 0.3, 0.1) * (1.0 - wetness * 0.5);
}
