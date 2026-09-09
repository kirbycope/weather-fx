shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_toon, specular_toon;

uniform vec2 Texture_Scale = vec2(1.000000, 1.000000);
uniform sampler2D Disolver_Texture : source_color;
uniform float Light_attenuation = 1.3;
uniform float Shadow_roundness = 1.0;
uniform sampler2D Color_1D_Gradient : source_color, hint_default_black;


void fragment() {
// Input:2
	vec4 n_out2p0 = COLOR;
	float n_out2p4 = n_out2p0.a;


// Vector2Parameter:6
	vec2 n_out6p0 = Texture_Scale;


// UVFunc:5
	vec2 n_in5p2 = vec2(0.00000, 0.00000);
	vec2 n_out5p0 = (UV - n_in5p2) * n_out6p0 + n_in5p2;


	vec4 n_out4p0;
// Texture2D:4
	n_out4p0 = texture(Disolver_Texture, n_out5p0);
	float n_out4p1 = n_out4p0.r;


// Output:0
	ALBEDO = vec3(n_out2p0.xyz);
	ALPHA = n_out4p1;
	ALPHA_SCISSOR_THRESHOLD = n_out2p4;

}

void light() {

	float dot_result = dot(NORMAL, LIGHT);
	float add_some_math = (clamp(dot_result, -0.90, 0.90) + 1.0)*0.47*Light_attenuation;
	float fresnel = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), Shadow_roundness);
	float round_cell_shade = clamp(add_some_math,0.04, 0.98) * fresnel;
	vec4 color_1D_gradient = texture(Color_1D_Gradient, vec2(round_cell_shade));
	DIFFUSE_LIGHT = clamp(LIGHT_COLOR * vec3(color_1D_gradient.xyz), vec3(0), vec3(1));

}
