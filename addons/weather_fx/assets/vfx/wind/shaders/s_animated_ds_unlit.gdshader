shader_type spatial;
render_mode blend_mix, unshaded ,cull_disabled;

uniform sampler2D sprite_sheet;
uniform vec2 frame_count = vec2(4.0, 3.0); // Columns, Rows

varying vec2 anim_UV;

void vertex() {
    // Calculate frame offset (your original method)
    float last_cell = (frame_count.x * frame_count.y) - 1.0;
    float frame_index = floor(COLOR.a * last_cell);
    vec2 frame_offset = vec2(
        mod(frame_index, frame_count.x) / frame_count.x,
        floor(frame_index / frame_count.x) / frame_count.y
    );

    // Apply texture scaling
    vec2 frame_size = vec2(1.0) / frame_count;
    anim_UV = (UV * frame_size + frame_offset);
}

void fragment() {
    vec4 tex = texture(sprite_sheet, anim_UV);
    ALBEDO = tex.rgb * COLOR.rgb;
    ALPHA = tex.a;
}
