shader_type spatial;
render_mode depth_prepass_alpha;

// Global WeatherFX wind uniforms
global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;

uniform vec4 Color : source_color;
uniform sampler2D Color_Gradiant : source_color;
uniform sampler2D Vor_Noise : source_color;

uniform float Fernal_Power;
uniform float Vor_Scale = 3.0;
uniform float Vor_Speed = 1.0;
uniform float Emmision_Power = 1.0;
uniform float Alpha_Clip : hint_range(0.0, 1.0, 0.02) = 1.0;
uniform float wind_reactivity : hint_range(0.0, 2.0) = 0.5;

void vertex() {
	if (weather_wind_strength > 0.01) {
		vec3 world_wind = normalize(weather_wind_direction);
		vec3 local_wind = (inverse(MODEL_MATRIX) * vec4(world_wind, 0.0)).xyz;
		if (length(local_wind) > 0.001) {
			local_wind = normalize(local_wind);
		}
		float drift = sin(TIME * 4.0 + (VERTEX.x + VERTEX.z) * 2.0) * 0.08 * weather_wind_strength;
		VERTEX += local_wind * (weather_wind_strength * wind_reactivity * 0.15 + drift);
	}
}

void fragment() {
	float speed_boost = 1.0 + clamp(weather_wind_strength * 0.1, 0.0, 2.0);
	vec2 Move_UV = fract(UV + TIME * Vor_Speed * speed_boost);
	vec4 Sample_Vor_Noise = texture(Vor_Noise, Move_UV * Vor_Scale);
	vec4 Gradiant_Color = texture(Color_Gradiant, vec2(COLOR.a, COLOR.a));

	ALBEDO = Color.rgb * Gradiant_Color.rgb;
	ALPHA_SCISSOR_THRESHOLD = COLOR.a;
	ALPHA = Sample_Vor_Noise.r * Color.a;
	EMISSION = Emmision_Power * Color.rgb * Gradiant_Color.rgb;
}

void light() {
}
