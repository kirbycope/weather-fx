shader_type spatial;

// Global WeatherFX wind uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;

uniform sampler2D Noise_Texture : source_color;
uniform sampler2D Coloring_Texture : source_color;
uniform sampler2D UV_Random : source_color;
uniform sampler2D Alpha_Texture : source_color;
uniform vec2 Speed = vec2(0.2, 0.0);
uniform float Emmision_Power = 1.0;
uniform float Twist_Power = 1.0;

uniform sampler2D Vertex_Noise_Texture;
uniform sampler2D Vertex_Noise_Power_Texture;
uniform float Displace_Power = 0.5;

uniform float Fresnel_Power = 1.0;
uniform float Random_Power = 1.0;
uniform vec3 Fresnel_Color : source_color;

uniform sampler2D Tail_Vertex_Noise_Texture;
uniform sampler2D Tail_Vertex_Noise_Power_Texture;
uniform float Tail_Displace_Power = 0.5;

// Wind dancing parameters
uniform float wind_reactivity : hint_range(0.0, 2.0) = 0.55;
uniform float wind_flutter_speed : hint_range(1.0, 16.0) = 7.0;

void vertex() {
	float wind_norm = clamp(weather_wind_strength / 7.5, 0.0, 3.0);
	float wind_speed_boost = 1.0 + wind_norm * 0.45;
	vec2 animated_speed = Speed * wind_speed_boost;

	vec2 UV1 = mod(UV + animated_speed * TIME, 1.0);
	UV1 = mod(UV + vec2(animated_speed.y) * TIME, 1.0);

	// Tail noise offset
	float Tail_Noise_Data = texture(Tail_Vertex_Noise_Texture, vec2(UV1.y, UV1.y)).r;
	float Tail_Noise_Power_Data = texture(Tail_Vertex_Noise_Power_Texture, UV).r;
	vec3 Center_Offset = (vec3(-2.0) * Tail_Displace_Power * Tail_Noise_Power_Data);
	VERTEX.xz += ((Center_Offset + NORMAL + (Tail_Noise_Data * Tail_Noise_Power_Data)) * Tail_Displace_Power).xz;

	// Atmospheric wind dancing & dynamic flame whip
	if (weather_wind_strength > 0.01) {
		vec3 world_wind_dir = normalize(weather_wind_direction);
		vec3 local_wind_dir = (inverse(MODEL_MATRIX) * vec4(world_wind_dir, 0.0)).xyz;
		if (length(local_wind_dir) > 0.001) {
			local_wind_dir = normalize(local_wind_dir);
		} else {
			local_wind_dir = vec3(1.0, 0.0, 0.0);
		}
		vec3 local_wind_perp = vec3(-local_wind_dir.z, 0.0, local_wind_dir.x);

		float wind_power = wind_norm * wind_reactivity;

		// Height factor: anchored firmly at bottom (Y ~ -1.0), full whipping motion at top (Y ~ 1.5 to 2.0)
		float height_factor = clamp((VERTEX.y + 0.6) / 2.2, 0.0, 1.0);
		height_factor = pow(height_factor, 1.3);

		// Multi-harmonic lively flame dancing and licking
		float dance_fast = sin(TIME * (wind_flutter_speed + wind_norm * 2.0) + (VERTEX.x + VERTEX.z) * 3.2) * 0.18 * wind_power;
		float dance_wobble = cos(TIME * (wind_flutter_speed * 1.3 + wind_norm * 2.5) + VERTEX.y * 3.0) * 0.12 * wind_power;
		float dance_sway = sin(TIME * (wind_flutter_speed * 0.6) + VERTEX.y * 1.6) * 0.25 * wind_power;

		vec3 wind_displacement = (local_wind_dir * (wind_power * 0.45 + dance_sway + dance_fast) + local_wind_perp * dance_wobble) * height_factor;
		wind_displacement.y -= length(wind_displacement.xz) * 0.22 * height_factor;

		VERTEX += wind_displacement;
	}
}

void fragment() {
	float wind_norm = clamp(weather_wind_strength / 7.5, 0.0, 3.0);
	float wind_speed_boost = 1.0 + wind_norm * 0.45;
	vec2 animated_speed = Speed * wind_speed_boost;

	vec2 UV1 = mod(UV + animated_speed * TIME, 1.0);
	float dynamic_twist = Twist_Power + sin(TIME * 6.0) * 0.2 * wind_norm;
	UV1.x = mod(UV1.x + UV1.y * dynamic_twist, 1.0);

	vec2 Twisted_UV_For_random = UV * dynamic_twist;
	Twisted_UV_For_random.y = fract(Twisted_UV_For_random.y + animated_speed.x * TIME);
	vec2 Random_UV = (UV + texture(UV_Random, Twisted_UV_For_random).r * Random_Power);

	vec4 Noise = texture(Noise_Texture, UV1);
	vec4 Color_ = texture(Coloring_Texture, Random_UV);

	vec4 Final_Color = Noise * Color_;

	float Fresnel = pow(1.0 - dot(NORMAL, VIEW), Fresnel_Power);

	Final_Color.rgb = mix(Final_Color.rgb, Fresnel_Color, Fresnel);
	ALBEDO = Final_Color.rgb;
	EMISSION = Final_Color.rgb * Emmision_Power;

	float Alpha = texture(Alpha_Texture, UV).a;
	Alpha = clamp(Alpha + Final_Color.a, 0.0, 1.0);

	ALPHA = Alpha;
}
