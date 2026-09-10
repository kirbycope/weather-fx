shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform int segment_count = 10;
uniform float inner_radius = 0.4;
uniform float outer_radius = 0.9;
uniform float angle_start = 2.349;
uniform float angle_range = 4.7124;
uniform float segment_spacing = 0.1;
uniform float ring_radius = 0.55;
uniform float ring_width = 0.05;

uniform vec4 color_start : source_color = vec4(0.4845, 1.0, 1.0, 1.0); // Cyan / Cold
uniform vec4 color_end : source_color = vec4(1.0, 0.7977, 0.4845, 1.0); // Orange / Hot
uniform float zoom = 1.0; // Lower = bigger gauge

void fragment() {
	// Adjust UV to zoom and center at (0, 0)
	vec2 uv = (UV - 0.5) * zoom + 0.5;
	vec2 pos = uv * 2.0 - 1.0;

	float dist = length(pos);

	// Outside of arc
	if (dist < inner_radius || dist > outer_radius) {
		discard;
	}

	float angle = atan(pos.y, pos.x);
	if (angle < angle_start) {
		angle += 6.28318530718; // Wrap negative angles
	}

	if (angle < angle_start || angle > angle_start + angle_range) {
		discard;
	}

	// Determine segment index
	float normalized_angle = (angle - angle_start) / angle_range;
	float seg = normalized_angle * float(segment_count - 1);
	float seg_index = floor(seg + 0.5);

	// Compute segment arc size and start angle
	float arc_step = angle_range / float(segment_count - 1);
	float arc_size;
	float seg_start_angle;

	if (seg_index == 0.0) {
		// First segment: half size, starts at angle_start
		arc_size = arc_step / 2.0;
		seg_start_angle = angle_start;
	} else if (seg_index == float(segment_count - 1)) {
		// Last segment: half size, ends at angle_start + angle_range
		arc_size = arc_step / 2.0;
		seg_start_angle = angle_start + angle_range - arc_size;
	} else {
		// Middle segments: full size, centered
		arc_size = arc_step;
		seg_start_angle = angle_start + arc_step * (seg_index - 0.5);
	}

	// Apply spacing
	if (angle < seg_start_angle + segment_spacing / 2.0 || angle > seg_start_angle + arc_size - segment_spacing / 2.0) {
		discard;
	}

	// Segment color interpolation
	vec4 color = mix(color_start, color_end, seg_index / float(segment_count - 1));

	// Middle 4 segments → dark semi-transparent gray
	int middle_start = (segment_count - 4) / 2;
	int middle_end = middle_start + 4;
	if (int(seg_index) >= middle_start && int(seg_index) < middle_end) {
		color = vec4(0.1, 0.1, 0.1, 0.4);
	}

	// Create inner transparent ring with configurable width
	if (dist >= ring_radius && dist <= ring_radius + ring_width) {
		discard;
	}

	COLOR = color;
}
