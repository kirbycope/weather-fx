# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WeatherForecastDisplay
extends PanelContainer

## HUD forecast gauge widget that automatically visualizes active weather,
## biome names, live temperature, and upcoming forecast cycles when moving between regions.

@export var weather_fx_node: WeatherFX :
	set(value):
		if weather_fx_node != value:
			_disconnect_signals()
			weather_fx_node = value
			_connect_signals()
			if weather_fx_node:
				_update_display(weather_fx_node.get_forecast())

@export var icon_size: Vector2 = Vector2(32, 32) :
	set(value):
		icon_size = value
		_update_display()

@export var show_temperature: bool = true :
	set(value):
		show_temperature = value
		_update_display()

@export var show_biome_name: bool = true :
	set(value):
		show_biome_name = value
		_update_display()

var _hbox: HBoxContainer
var _info_label: Label
var _icon_rects: Array[TextureRect] = []


func _ready() -> void:
	_setup_ui()
	if weather_fx_node == null:
		var found = get_tree().root.find_child("WeatherFX", true, false)
		if found is WeatherFX:
			weather_fx_node = found
	else:
		_connect_signals()
		
	if weather_fx_node:
		_update_display(weather_fx_node.get_forecast())


func _setup_ui() -> void:
	if _hbox != null:
		return
		
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_info_label)

	_hbox = HBoxContainer.new()
	_hbox.name = "ForecastIcons"
	_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(_hbox)


func _connect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if not weather_fx_node.forecast_updated.is_connected(_on_forecast_updated):
			weather_fx_node.forecast_updated.connect(_on_forecast_updated)
		if not weather_fx_node.biome_changed.is_connected(_on_biome_changed):
			weather_fx_node.biome_changed.connect(_on_biome_changed)
		if not weather_fx_node.temperature_changed.is_connected(_on_temperature_changed):
			weather_fx_node.temperature_changed.connect(_on_temperature_changed)
		if not weather_fx_node.weather_changed.is_connected(_on_weather_changed):
			weather_fx_node.weather_changed.connect(_on_weather_changed)


func _disconnect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if weather_fx_node.forecast_updated.is_connected(_on_forecast_updated):
			weather_fx_node.forecast_updated.disconnect(_on_forecast_updated)
		if weather_fx_node.biome_changed.is_connected(_on_biome_changed):
			weather_fx_node.biome_changed.disconnect(_on_biome_changed)
		if weather_fx_node.temperature_changed.is_connected(_on_temperature_changed):
			weather_fx_node.temperature_changed.disconnect(_on_temperature_changed)
		if weather_fx_node.weather_changed.is_connected(_on_weather_changed):
			weather_fx_node.weather_changed.disconnect(_on_weather_changed)


func _on_forecast_updated(forecast: Array) -> void:
	_update_display(forecast)


func _on_biome_changed(_new_biome: ClimateData.BiomeZone, _old_biome: ClimateData.BiomeZone) -> void:
	if weather_fx_node:
		_update_display(weather_fx_node.get_forecast())


func _on_temperature_changed(_new_temp: float) -> void:
	_update_info_label()


func _on_weather_changed(_new_w: ClimateData.WeatherType, _old_w: ClimateData.WeatherType) -> void:
	if weather_fx_node:
		_update_display(weather_fx_node.get_forecast())


func _update_info_label() -> void:
	if _info_label == null:
		return
	if weather_fx_node:
		var parts: Array[String] = []
		if show_biome_name:
			parts.append(ClimateData.get_biome_display_name(weather_fx_node.current_biome))
		if show_temperature:
			parts.append("%.1f°C" % weather_fx_node.current_temperature)
		_info_label.text = " • ".join(parts)
		_info_label.visible = not parts.is_empty()
	else:
		_info_label.text = "Weather FX"


func _update_display(forecast: Array = []) -> void:
	if _hbox == null or _info_label == null:
		return

	if forecast.is_empty() and weather_fx_node:
		forecast = weather_fx_node.get_forecast()

	# Clear previous icons
	for child in _hbox.get_children():
		child.queue_free()
	_icon_rects.clear()

	_update_info_label()

	# Build forecast icons
	for i in range(forecast.size()):
		var w_type: ClimateData.WeatherType = forecast[i]
		var icon_path = ClimateData.get_weather_icon_path(w_type)
		var tex = load(icon_path) if ResourceLoader.exists(icon_path) else null
		
		var rect = TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		if i == 0:
			# Highlight current active weather
			rect.custom_minimum_size = icon_size * 1.2
			rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			# Upcoming forecast cycles
			rect.custom_minimum_size = icon_size * 0.8
			rect.modulate = Color(0.8, 0.8, 0.8, 0.65)
			
		_hbox.add_child(rect)
		_icon_rects.append(rect)
