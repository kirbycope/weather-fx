# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
@icon("res://addons/weather_fx/assets/icons/weather_fx_icon.svg")
class_name WindDirectionDial
extends Control

## Interactive HUD dial and compass widget that visualizes and controls wind direction in real-time.
## Clicking and dragging rotates the wind vector on the linked WeatherFX node.

signal direction_changed(direction: Vector3, angle_degrees: float)

const COLOR_BG: Color = Color(0.08, 0.1, 0.12, 0.85)
const COLOR_BORDER: Color = Color(0.3, 0.45, 0.6, 0.6)
const COLOR_CARDINAL: Color = Color(0.7, 0.82, 0.95, 0.9)
const COLOR_CARDINAL_N: Color = Color(1.0, 0.45, 0.45, 1.0)
const COLOR_ARROW: Color = Color(0.4, 0.85, 1.0, 1.0)
const COLOR_ARROW_HEAD: Color = Color(0.6, 0.95, 1.0, 1.0)
const COLOR_TAIL: Color = Color(0.25, 0.5, 0.75, 0.7)
const CARDINAL_NAMES: Array[String] = ["East", "SE", "South", "SW", "West", "NW", "North", "NE"]

@export_group("Node References")
## Assign before the widget enters the tree; falls back to the first node in the "WeatherFX" group.
@export var weather_fx: WeatherFX

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

var _current_direction: Vector3 = Vector3.RIGHT
var _is_dragging: bool = false
var _font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(dial_radius * 2.0 + 16.0, dial_radius * 2.0 + 16.0)
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.wind_changed.connect(_on_weather_wind_changed)
		set_direction(weather_fx.wind_direction, false)


func _on_weather_wind_changed(_strength: float, direction: Vector3) -> void:
	if not _is_dragging:
		set_direction(direction, false)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_is_dragging = true
			_update_from_mouse_pos(mb.position)
			accept_event()
		elif _is_dragging:
			_is_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _is_dragging:
		_update_from_mouse_pos((event as InputEventMouseMotion).position)
		accept_event()


func _update_from_mouse_pos(local_pos: Vector2) -> void:
	var delta: Vector2 = local_pos - size / 2.0
	if delta.length_squared() > 4.0:
		# delta.x corresponds to East (+X), delta.y corresponds to South (+Z)
		set_direction(Vector3(delta.x, 0.0, delta.y).normalized(), true)


func set_direction(dir: Vector3, notify_weather_node: bool = true) -> void:
	_current_direction = dir.normalized() if not dir.is_zero_approx() else Vector3.RIGHT
	if notify_weather_node and is_instance_valid(weather_fx):
		weather_fx.wind_direction = _current_direction
	direction_changed.emit(_current_direction, get_angle_degrees())
	queue_redraw()


func set_angle_degrees(degrees: float, notify_weather_node: bool = true) -> void:
	var rad: float = deg_to_rad(degrees)
	set_direction(Vector3(cos(rad), 0.0, sin(rad)), notify_weather_node)


func get_direction() -> Vector3:
	return _current_direction


func get_angle_degrees() -> float:
	return wrapf(rad_to_deg(atan2(_current_direction.z, _current_direction.x)), 0.0, 360.0)


func get_cardinal_name() -> String:
	return CARDINAL_NAMES[int(round(get_angle_degrees() / 45.0)) % 8]


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var r: float = dial_radius

	# Background Circle
	draw_circle(center, r, COLOR_BG)
	draw_arc(center, r, 0.0, TAU, 32, COLOR_BORDER, 1.5, true)
	draw_arc(center, r * 0.5, 0.0, TAU, 24, Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.25), 1.0, true)

	# Cardinal Tick Marks (N, E, S, W)
	var ticks: Array[Dictionary] = [
		{"pos": center + Vector2(0.0, -r * 0.72), "text": "N", "color": COLOR_CARDINAL_N},
		{"pos": center + Vector2(r * 0.72, 0.0), "text": "E", "color": COLOR_CARDINAL},
		{"pos": center + Vector2(0.0, r * 0.72), "text": "S", "color": COLOR_CARDINAL},
		{"pos": center + Vector2(-r * 0.72, 0.0), "text": "W", "color": COLOR_CARDINAL},
	]
	for tick: Dictionary in ticks:
		if show_cardinal_labels and _font:
			draw_string(_font, tick["pos"] - Vector2(3.0, -3.0), tick["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 9, tick["color"])
		else:
			draw_circle(tick["pos"], 1.5, tick["color"])

	# Direction Arrow / Vane. Direction vector: X is East (Right), Z is South (Down)
	var dir_2d: Vector2 = Vector2(_current_direction.x, _current_direction.z).normalized()
	var perp_2d: Vector2 = Vector2(-dir_2d.y, dir_2d.x)
	var arrow_tip: Vector2 = center + dir_2d * (r * 0.85)
	var arrow_base: Vector2 = center - dir_2d * (r * 0.5)
	var wing_left: Vector2 = center + dir_2d * (r * 0.2) + perp_2d * (r * 0.28)
	var wing_right: Vector2 = center + dir_2d * (r * 0.2) - perp_2d * (r * 0.28)
	draw_line(arrow_base, center, COLOR_TAIL, 2.0, true)
	draw_polygon(PackedVector2Array([arrow_tip, wing_left, center, wing_right]), PackedColorArray([COLOR_ARROW_HEAD, COLOR_ARROW, COLOR_ARROW, COLOR_ARROW]))

	# Center pivot dot
	draw_circle(center, 3.0, COLOR_ARROW_HEAD)
	draw_circle(center, 1.5, COLOR_BG)
