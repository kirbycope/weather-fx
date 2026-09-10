shader_type spatial;
render_mode unshaded;

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
uniform float wind_reactivity : hint_range(0.0, 2.0) = 0.5;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);

	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

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

vec2 rotate_uv_deg(vec2 uv, float angle_deg) {
	float a = radians(angle_deg);
	float c = cos(a);
	float s = sin(a);

	uv -= 0.5;
	uv = vec2(
		uv.x * c - uv.y * s,
		uv.x * s + uv.y * c
	);

	uv += 0.5;
	return uv;
}

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float r = rand(UV);
	vec2 Move_UV = fract(UV);
	float speed_boost = 1.0 + clamp(weather_wind_strength * 0.1, 0.0, 2.0);
	Move_UV = rotate_uv_deg(Move_UV, (r * 30.0) + (TIME * 20.0 * speed_boost));
	vec4 Sample_Vor_Noise = texture(Vor_Noise, Move_UV * Vor_Scale);
	vec4 Gradiant_Color = texture(Color_Gradiant, vec2(COLOR.a, COLOR.a));

	ALBEDO = Color.rgb * Gradiant_Color.rgb;
	ALPHA = clamp((Sample_Vor_Noise.r * (1.0 - COLOR.a)) - 0.1, 0.0, 1.0);
	EMISSION = Emmision_Power * Color.rgb * Gradiant_Color.rgb;
}
