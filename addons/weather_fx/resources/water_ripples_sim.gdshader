// Copyright (c) 2026 Antigravity Contributors
// SPDX-License-Identifier: MIT

shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Height-field wave simulation behind WaterRipples. The viewport it draws into never clears, so the
// back buffer holds last frame's state: R = height, G = the height a frame earlier, B = last frame's
// body mask. Alpha carries no data: the render target does not hand it back reliably.
// Each frame the wave equation advances the height. Wherever a body sits in the water the surface is
// pulled down into a hollow the shape of its footprint (`sink`), and wherever the footprint changed
// since the last frame (a hull moved on, an arm came down, a float bobbed) the water is pushed
// (`push`); a moving hollow throws a bow wave ahead and a wake behind on its own.
uniform sampler2D previous_state : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D mask_texture : filter_linear, repeat_disable; // bodies seen from below; alpha where one is in the water
uniform float wave_speed : hint_range(0.0, 0.5) = 0.4; // propagation per step in texels^2; above 0.5 the simulation blows up
uniform float damping : hint_range(0.9, 1.0) = 0.985; // how much height survives each step
uniform float sink : hint_range(0.0, 2.0) = 0.6; // how deep a body's footprint sits in the water
uniform float sink_rate : hint_range(0.0, 1.0) = 0.15; // how quickly the surface settles to that depth under a body
uniform float push : hint_range(0.0, 3.0) = 0.3; // how hard a body displaces the water where its footprint arrives or leaves
uniform float mask_blur : hint_range(0.0, 4.0) = 1.5; // texels the footprint is softened by, so it never reads as pixels

// The body footprint softened over a small cross, so edges are slopes rather than steps
float footprint(vec2 uv, vec2 texel) {
	vec2 offset = texel * mask_blur;
	float sum = texture(mask_texture, uv).a * 2.0
			+ texture(mask_texture, uv + vec2(offset.x, 0.0)).a
			+ texture(mask_texture, uv - vec2(offset.x, 0.0)).a
			+ texture(mask_texture, uv + vec2(0.0, offset.y)).a
			+ texture(mask_texture, uv - vec2(0.0, offset.y)).a
			+ texture(mask_texture, uv + offset).a
			+ texture(mask_texture, uv - offset).a
			+ texture(mask_texture, uv + vec2(offset.x, -offset.y)).a
			+ texture(mask_texture, uv - vec2(offset.x, -offset.y)).a;
	return sum / 10.0;
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec4 state = texture(previous_state, SCREEN_UV);
	float height = state.r;
	float laplacian = texture(previous_state, SCREEN_UV + vec2(texel.x, 0.0)).r
			+ texture(previous_state, SCREEN_UV - vec2(texel.x, 0.0)).r
			+ texture(previous_state, SCREEN_UV + vec2(0.0, texel.y)).r
			+ texture(previous_state, SCREEN_UV - vec2(0.0, texel.y)).r
			- 4.0 * height;
	float next_height = (2.0 * height - state.g + wave_speed * laplacian) * damping;

	float mask = footprint(SCREEN_UV, texel);
	// The body sits in a hollow of its own shape...
	next_height = mix(next_height, -sink * mask, sink_rate * mask);
	// ...and shoves the water where the hollow moves: up ahead of it, down where it has left
	float change = mask - state.b;
	next_height += change * push;
	next_height = clamp(next_height, -2.0, 2.0);

	// The pool walls hold the water: no height along the border
	vec2 edge = min(SCREEN_UV, 1.0 - SCREEN_UV);
	if (min(edge.x, edge.y) < texel.x * 1.5) {
		next_height = 0.0;
	}

	COLOR = vec4(next_height, height, mask, 1.0);
}
