shader_type spatial;
render_mode unshaded;

uniform sampler2D sprite_sheet;
uniform sampler2D gradient_1d_texture:repeat_disable;
uniform vec2 frame_count = vec2(4.0, 3.0); // Columns, Rows
instance uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_scissor_treshold :hint_range(0.0, 1.0, 0.015625) = 0.3;
varying vec2 anim_UV;

void vertex() {
   
    vec2 frame_offset = vec2(
        mod(1.0, frame_count.x) / frame_count.x,
        floor(1.0 / frame_count.x) / frame_count.y
    );

    // Apply texture scaling
    vec2 frame_size = vec2(1.0) / frame_count;
    anim_UV = (UV * frame_size + frame_offset);
}

void fragment() {
	
    float img = texture(sprite_sheet, anim_UV+ uv_offset ).r;
	vec4 tex = texture(gradient_1d_texture,vec2(img));
    ALBEDO = tex.rgb * COLOR.rgb;
	
	float alphad = alpha_scissor_treshold;
    ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD =  alphad;
}