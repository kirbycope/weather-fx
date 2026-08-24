# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name GaugeNeedle
extends Control

## Gauge needle drawing control that smoothly points to the current value along a circular arc.

# ------------------------------------------------------------------------------
# Exported Groups: Needle Properties
# ------------------------------------------------------------------------------
@export_group("Needle Styling")
@export var needle_length: float = 12.0
@export var needle_width: float = 1.5
@export var center_circle_radius: float = 3.0
@export var needle_color: Color = Color(0.486, 1.0, 1.0, 1.0)
@export var center_color: Color = Color(0.486, 1.0, 1.0, 1.0)

# ------------------------------------------------------------------------------
# Exported Groups: Gauge Range
# ------------------------------------------------------------------------------
@export_group("Gauge Range")
@export var angle_start: float = 2.349
@export var angle_range: float = 4.7124
@export var min_value: float = -30.0
@export var max_value: float = 50.0

@export var current_value: float = 20.0:
	set(value):
		current_value = clampf(value, min_value, max_value)
		update_needle_angle()
		if not smooth_movement:
			current_angle = target_angle
			queue_redraw()

# ------------------------------------------------------------------------------
# Exported Groups: Animation
# ------------------------------------------------------------------------------
@export_group("Animation")
@export var smooth_movement: bool = true
@export var animation_speed: float = 5.0

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
var target_angle: float = 0.0
var current_angle: float = 0.0


# ------------------------------------------------------------------------------
# Virtual Callbacks
# ------------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_needle_angle()
	current_angle = target_angle


func _process(delta: float) -> void:
	if smooth_movement and absf(current_angle - target_angle) > 0.005:
		current_angle = lerp_angle(current_angle, target_angle, animation_speed * delta)
		queue_redraw()
	elif not smooth_movement and current_angle != target_angle:
		current_angle = target_angle
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	draw_circle(center, center_circle_radius, center_color)
	var needle_end: Vector2 = center + Vector2(cos(current_angle), sin(current_angle)) * needle_length
	draw_line(center, needle_end, needle_color, needle_width, true)


# ------------------------------------------------------------------------------
# Public Methods
# ------------------------------------------------------------------------------
func update_needle_angle() -> void:
	var range_span: float = max_value - min_value
	if range_span <= 0.0001:
		target_angle = angle_start
		return
	var normalized_value: float = (current_value - min_value) / range_span
	target_angle = angle_start + (normalized_value * angle_range)


func set_value(value: float) -> void:
	current_value = value


func set_percentage(percentage: float) -> void:
	var frac: float = clampf(percentage / 100.0, 0.0, 1.0)
	set_value(min_value + frac * (max_value - min_value))


func get_percentage() -> float:
	var range_span: float = max_value - min_value
	if range_span <= 0.0001:
		return 0.0
	return ((current_value - min_value) / range_span) * 100.0
