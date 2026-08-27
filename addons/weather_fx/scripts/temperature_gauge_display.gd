# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name TemperatureGaugeDisplay
extends Button

## Zelda-style circular segmented temperature gauge widget that visualizes real-time climate temperature.

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
const DEFAULT_SHADER: Shader = preload("res://addons/weather_fx/resources/temperature_gauge.gdshader")

const GaugeNeedleScript: Script = preload("res://addons/weather_fx/scripts/gauge_needle.gd")

# ------------------------------------------------------------------------------
# Exported Groups: Node References
# ------------------------------------------------------------------------------
@export_group("Node References")
@export var weather_fx_node: WeatherFX:
	set(value):
		if weather_fx_node != value:
			_disconnect_signals()
			weather_fx_node = value
			_connect_signals()
			if weather_fx_node:
				_update_temperature(weather_fx_node.current_temperature)

# ------------------------------------------------------------------------------
# Exported Groups: Unit & Range
# ------------------------------------------------------------------------------
@export_group("Temperature Settings")
@export var temperature_unit: WeatherForecastDisplay.TemperatureUnit = WeatherForecastDisplay.TemperatureUnit.CELSIUS:
	set(value):
		temperature_unit = value
		_update_range_and_needle()

@export var min_celsius: float = -30.0:
	set(value):
		min_celsius = value
		_update_range_and_needle()

@export var max_celsius: float = 50.0:
	set(value):
		max_celsius = value
		_update_range_and_needle()

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
var _gauge_rect: TextureRect
var _needle: Control
var _current_temp_celsius: float = 20.0


# ------------------------------------------------------------------------------
# Virtual Callbacks
# ------------------------------------------------------------------------------
func _ready() -> void:
	_setup_ui()
	if weather_fx_node == null:
		var found: Node = get_tree().root.find_child("WeatherFX", true, false)
		if found is WeatherFX:
			weather_fx_node = found
	else:
		_connect_signals()

	if weather_fx_node:
		_update_temperature(weather_fx_node.current_temperature)
	else:
		_update_range_and_needle()


# ------------------------------------------------------------------------------
# Private Methods
# ------------------------------------------------------------------------------
func _setup_ui() -> void:
	custom_minimum_size = Vector2(36, 36)
	flat = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style_box: StyleBoxFlat = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	style_box.set_corner_radius_all(24)
	style_box.content_margin_left = 0
	style_box.content_margin_top = 0
	style_box.content_margin_right = 0
	style_box.content_margin_bottom = 0
	add_theme_stylebox_override("normal", style_box)
	add_theme_stylebox_override("hover", style_box)
	add_theme_stylebox_override("pressed", style_box)
	add_theme_stylebox_override("disabled", style_box)
	add_theme_stylebox_override("focus", style_box)

	if _gauge_rect == null:
		_gauge_rect = TextureRect.new()
		_gauge_rect.name = "Gauge"
		_gauge_rect.custom_minimum_size = Vector2(36, 36)
		_gauge_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_gauge_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_gauge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = DEFAULT_SHADER
		_gauge_rect.material = mat

		var tex: PlaceholderTexture2D = PlaceholderTexture2D.new()
		tex.size = Vector2(36, 36)
		_gauge_rect.texture = tex

		add_child(_gauge_rect)

	if _needle == null:
		_needle = GaugeNeedleScript.new() as Control
		_needle.name = "GaugeNeedle"
		_needle.custom_minimum_size = Vector2(36, 36)
		_needle.set("needle_length", 12.0)
		_needle.set("min_value", min_celsius)
		_needle.set("max_value", max_celsius)
		_needle.set("current_value", _current_temp_celsius)
		add_child(_needle)


func _connect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if not weather_fx_node.temperature_changed.is_connected(_on_temperature_changed):
			weather_fx_node.temperature_changed.connect(_on_temperature_changed)


func _disconnect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if weather_fx_node.temperature_changed.is_connected(_on_temperature_changed):
			weather_fx_node.temperature_changed.disconnect(_on_temperature_changed)


func _on_temperature_changed(temp_celsius: float) -> void:
	_update_temperature(temp_celsius)


func _update_temperature(temp_celsius: float) -> void:
	_current_temp_celsius = temp_celsius
	_update_range_and_needle()


func _update_range_and_needle() -> void:
	if _needle == null:
		return

	if temperature_unit == WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT:
		_needle.set("min_value", ClimateData.celsius_to_fahrenheit(min_celsius))
		_needle.set("max_value", ClimateData.celsius_to_fahrenheit(max_celsius))
		_needle.call("set_value", ClimateData.celsius_to_fahrenheit(_current_temp_celsius))
	else:
		_needle.set("min_value", min_celsius)
		_needle.set("max_value", max_celsius)
		_needle.call("set_value", _current_temp_celsius)


# ------------------------------------------------------------------------------
# Public Methods
# ------------------------------------------------------------------------------
func get_needle() -> Control:
	return _needle
