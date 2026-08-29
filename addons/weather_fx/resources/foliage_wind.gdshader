shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

// WeatherFX Global Uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

// Canopy Appearance Uniforms
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 foliage_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.2;

// Foliage Wind Uniforms
uniform float wind_speed : hint_range(0.1, 10.0) = 1.5;
uniform float canopy_sway_strength : hint_range(0.0, 1.0) = 0.18;
uniform float leaf_flutter_strength : hint_range(0.0, 1.0) = 0.08;

void vertex() {
	// Height/distance factor: vertices higher up sway more
	float height_factor = clamp(VERTEX.y * 0.25, 0.1, 1.5);
	
	// World origin of the tree
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	
	// Normalize wind direction
	vec3 wind_dir = weather_wind_direction;
	if (length(wind_dir) < 0.01) {
		wind_dir = vec3(1.0, 0.0, 0.0);
	} else {
		wind_dir = normalize(wind_dir);
	}
	
	if (weather_wind_strength > 0.001) {
		float wind_scale = weather_wind_strength / 7.5;
		float effective_speed = wind_speed * (0.8 + 0.2 * wind_scale);
		
		// Canopy overall sway (low frequency)
		float sway_phase = TIME * effective_speed + (world_origin.x + world_origin.z) * 0.1;
		float canopy_sway = sin(sway_phase) * canopy_sway_strength * (0.2 + 0.6 * wind_scale) * height_factor;
		
		// Leaf branch fluttering (high frequency)
		float flutter_phase = TIME * effective_speed * 3.5 + (VERTEX.x * 2.0 + VERTEX.z * 2.0);
		float leaf_flutter = sin(flutter_phase) * leaf_flutter_strength * (0.3 + 0.5 * wind_scale);
		
		vec3 total_sway = wind_dir * (canopy_sway + leaf_flutter);
		total_sway.y -= abs(canopy_sway) * 0.15;
		
		// Convert to local vertex space
		vec3 local_sway = (inverse(MODEL_MATRIX) * vec4(total_sway, 0.0)).xyz;
		VERTEX += local_sway;
	}
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
	
	BACKLIGHT = vec3(0.18, 0.28, 0.12) * (1.0 - wetness * 0.4);
}
