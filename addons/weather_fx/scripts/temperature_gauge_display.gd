# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
@icon("res://addons/weather_fx/assets/icons/weather_fx_icon.svg")
class_name TemperatureGaugeDisplay
extends Control

## Zelda-style circular segmented temperature gauge (scenes/temperature_gauge_display.tscn).
## The shader ring and GaugeNeedle live in the scene; this script only feeds the needle.

@export_group("Node References")
## Assign before the widget enters the tree; falls back to the first node in the "WeatherFX" group.
@export var weather_fx: WeatherFX

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

@onready var _needle: GaugeNeedle = %GaugeNeedle

var _current_temp_celsius: float = 20.0


func _ready() -> void:
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.temperature_changed.connect(_on_temperature_changed)
		_current_temp_celsius = weather_fx.current_temperature
	_update_range_and_needle()


func _on_temperature_changed(temp_celsius: float) -> void:
	_current_temp_celsius = temp_celsius
	_update_range_and_needle()


func _update_range_and_needle() -> void:
	if _needle == null:
		return
	var fahrenheit: bool = temperature_unit == WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT
	_needle.min_value = ClimateData.celsius_to_fahrenheit(min_celsius) if fahrenheit else min_celsius
	_needle.max_value = ClimateData.celsius_to_fahrenheit(max_celsius) if fahrenheit else max_celsius
	_needle.current_value = ClimateData.celsius_to_fahrenheit(_current_temp_celsius) if fahrenheit else _current_temp_celsius
