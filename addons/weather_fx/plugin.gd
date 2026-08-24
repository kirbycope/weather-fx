# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
extends EditorPlugin


func _enter_tree() -> void:
	var weather_icon = preload("res://addons/weather_fx/icons/weather_fx_icon.svg")
	var zone_icon = preload("res://addons/weather_fx/icons/weather_zone_icon.svg")
	
	add_custom_type("WeatherFX", "Node3D", preload("res://addons/weather_fx/weather_fx.gd"), weather_icon)
	add_custom_type("WeatherZone", "Area3D", preload("res://addons/weather_fx/weather_zone.gd"), zone_icon)
	add_custom_type("WeatherForecastDisplay", "PanelContainer", preload("res://addons/weather_fx/weather_forecast_display.gd"), weather_icon)


func _exit_tree() -> void:
	remove_custom_type("WeatherFX")
	remove_custom_type("WeatherZone")
	remove_custom_type("WeatherForecastDisplay")
