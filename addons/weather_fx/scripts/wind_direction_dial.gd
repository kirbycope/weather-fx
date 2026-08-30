# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WindDirectionDial
extends Control

## Interactive HUD dial and compass widget that visualizes and controls wind direction in real-time.
## Clicking and dragging rotates the wind vector, updating global shaders, particle physics, and VFX.

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal direction_changed(direction: Vector3, angle_degrees: float)

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
const COLOR_BG: Color = Color(0.08, 0.1, 0.12, 0.85)
const COLOR_BORDER: Color = Color(0.3, 0.45, 0.6, 0.6)
const COLOR_CARDINAL: Color = Color(0.7, 0.82, 0.95, 0.9)
const COLOR_CARDINAL_N: Color = Color(1.0, 0.45, 0.45, 1.0)
const COLOR_ARROW: Color = Color(0.4, 0.85, 1.0, 1.0)
const COLOR_ARROW_HEAD: Color = Color(0.6, 0.95, 1.0, 1.0)
const COLOR_TAIL: Color = Color(0.25, 0.5, 0.75, 0.7)

# ------------------------------------------------------------------------------
# Exported Properties
# ------------------------------------------------------------------------------
@export_group("Node References")
@export var weather_fx_node: WeatherFX:
	set(value):
		if weather_fx_node != value:
			_disconnect_signals()
			weather_fx_node = value
			_connect_signals()
			if is_instance_valid(weather_fx_node):
				set_direction(weather_fx_node.wind_direction)

@export_group("Styling")
@export var dial_radius: float = 24.0:
	set(value):
		dial_radius = value
		queue_redraw()

@export var show_cardinal_labels: bool = true:
	set(value):
		show_cardinal_labels = value
		queue_redraw()

@export var interactive: bool = true

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
var _current_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
var _is_dragging: bool = false
var _font: Font


# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	custom_minimum_size = Vector2(dial_radius * 2.0 + 16.0, dial_radius * 2.0 + 16.0)
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

	if weather_fx_node == null:
		var found = get_tree().root.find_child("WeatherFX", true, false)
		if found is WeatherFX:
			weather_fx_node = found
	else:
		_connect_signals()

	if is_instance_valid(weather_fx_node):
		set_direction(weather_fx_node.wind_direction)


func _connect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if not weather_fx_node.wind_changed.is_connected(_on_weather_wind_changed):
			weather_fx_node.wind_changed.connect(_on_weather_wind_changed)


func _disconnect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if weather_fx_node.wind_changed.is_connected(_on_weather_wind_changed):
			weather_fx_node.wind_changed.disconnect(_on_weather_wind_changed)


func _on_weather_wind_changed(_strength: float, direction: Vector3) -> void:
	if not _is_dragging:
		set_direction(direction, false)


# ------------------------------------------------------------------------------
# Input Handling
# ------------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_update_from_mouse_pos(mb.position)
				accept_event()
			else:
				if _is_dragging:
					_is_dragging = false
					accept_event()

	elif event is InputEventMouseMotion and _is_dragging:
		var mm = event as InputEventMouseMotion
		_update_from_mouse_pos(mm.position)
		accept_event()


func _update_from_mouse_pos(local_pos: Vector2) -> void:
	var center = size / 2.0
	var delta = local_pos - center
	if delta.length_squared() > 4.0:
		# delta.x corresponds to East (+X), delta.y corresponds to South (+Z)
		var new_dir = Vector3(delta.x, 0.0, delta.y).normalized()
		set_direction(new_dir, true)


# ------------------------------------------------------------------------------
# Public Methods
# ------------------------------------------------------------------------------
func set_direction(dir: Vector3, notify_weather_node: bool = true) -> void:
	var normalized = dir.normalized() if not dir.is_zero_approx() else Vector3(1.0, 0.0, 0.0)
	_current_direction = normalized
	
	if notify_weather_node and is_instance_valid(weather_fx_node):
		weather_fx_node.wind_direction = _current_direction

	var angle_deg = wrapf(rad_to_deg(atan2(_current_direction.z, _current_direction.x)), 0.0, 360.0)
	emit_signal("direction_changed", _current_direction, angle_deg)
	queue_redraw()


func set_angle_degrees(degrees: float, notify_weather_node: bool = true) -> void:
	var rad = deg_to_rad(degrees)
	var dir = Vector3(cos(rad), 0.0, sin(rad))
	set_direction(dir, notify_weather_node)


func get_direction() -> Vector3:
	return _current_direction


func get_angle_degrees() -> float:
	return wrapf(rad_to_deg(atan2(_current_direction.z, _current_direction.x)), 0.0, 360.0)


func get_cardinal_name() -> String:
	var angle_deg = get_angle_degrees()
	var dirs = ["East", "SE", "South", "SW", "West", "NW", "North", "NE"]
	var index = int(round(angle_deg / 45.0)) % 8
	return dirs[index]


# ------------------------------------------------------------------------------
# Drawing
# ------------------------------------------------------------------------------
func _draw() -> void:
	var center = size / 2.0
	var r = dial_radius

	# Background Circle
	draw_circle(center, r, COLOR_BG)
	draw_arc(center, r, 0.0, TAU, 32, COLOR_BORDER, 1.5, true)
	draw_arc(center, r * 0.5, 0.0, TAU, 24, Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.25), 1.0, true)

	# Cardinal Tick Marks (N, E, S, W)
	var ticks = [
		{"pos": center + Vector2(0.0, -r * 0.72), "text": "N", "color": COLOR_CARDINAL_N},
		{"pos": center + Vector2(r * 0.72, 0.0), "text": "E", "color": COLOR_CARDINAL},
		{"pos": center + Vector2(0.0, r * 0.72), "text": "S", "color": COLOR_CARDINAL},
		{"pos": center + Vector2(-r * 0.72, 0.0), "text": "W", "color": COLOR_CARDINAL}
	]

	if show_cardinal_labels and _font:
		var font_size = 9
		for t in ticks:
			var str_text: String = t["text"]
			var str_color: Color = t["color"]
			var text_pos = t["pos"] - Vector2(3.0, -3.0)
			draw_string(_font, text_pos, str_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, str_color)
	else:
		for t in ticks:
			draw_circle(t["pos"], 1.5, t["color"])

	# Direction Arrow / Vane
	# Direction vector: X is East (Right), Z is South (Down)
	var dir_2d = Vector2(_current_direction.x, _current_direction.z).normalized()
	var perp_2d = Vector2(-dir_2d.y, dir_2d.x)

	var arrow_tip = center + dir_2d * (r * 0.85)
	var arrow_base = center - dir_2d * (r * 0.5)
	var wing_left = center + dir_2d * (r * 0.2) + perp_2d * (r * 0.28)
	var wing_right = center + dir_2d * (r * 0.2) - perp_2d * (r * 0.28)

	# Tail line
	draw_line(arrow_base, center, COLOR_TAIL, 2.0, true)

	# Arrowhead polygon
	var arrow_points = PackedVector2Array([arrow_tip, wing_left, center, wing_right])
	var arrow_colors = PackedColorArray([COLOR_ARROW_HEAD, COLOR_ARROW, COLOR_ARROW, COLOR_ARROW])
	draw_polygon(arrow_points, arrow_colors)

	# Center pivot dot
	draw_circle(center, 3.0, COLOR_ARROW_HEAD)
	draw_circle(center, 1.5, COLOR_BG)
