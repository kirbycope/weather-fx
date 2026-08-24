# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WeatherForecastDisplay
extends PanelContainer

## HUD forecast widget that visualizes active weather and upcoming forecast cycles
## with Zelda: Breath of the Wild aesthetics, rounded pill frame, SVG vector icons,
## and a smooth timeline scroll that matches the down-arrow indicator under the clock.

# ------------------------------------------------------------------------------
# Enums
# ------------------------------------------------------------------------------
enum TemperatureUnit {
	CELSIUS,
	FAHRENHEIT,
}

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
const COLOR_CYAN: Color = Color(0.565, 0.843, 0.929, 1.0)
const COLOR_FADED: Color = Color(0.565, 0.843, 0.929, 0.65)

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
				_rebuild_display(weather_fx_node.get_forecast())

# ------------------------------------------------------------------------------
# Exported Groups: Styling & Layout
# ------------------------------------------------------------------------------
@export_group("Styling & Layout")
@export var botw_style: bool = true:
	set(value):
		botw_style = value
		_update_theme_style()
		_rebuild_display()

@export var enable_scrolling: bool = true:
	set(value):
		enable_scrolling = value
		if not enable_scrolling and _hbox:
			_hbox.position.x = scroll_offset_start

@export var scroll_offset_start: float = 12.0:
	set(value):
		scroll_offset_start = value
		if _hbox:
			_update_scroll_position()

@export var icon_separation: int = 6:
	set(value):
		icon_separation = value
		if _hbox:
			_hbox.add_theme_constant_override("separation", icon_separation)

@export var icon_size: Vector2 = Vector2(24, 24):
	set(value):
		icon_size = value
		_rebuild_display()

@export var show_temperature: bool = true:
	set(value):
		show_temperature = value
		_update_info_label()

@export var temperature_unit: TemperatureUnit = TemperatureUnit.CELSIUS:
	set(value):
		temperature_unit = value
		_update_info_label()

@export var show_biome_name: bool = true:
	set(value):
		show_biome_name = value
		_update_info_label()

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
var _scroll_container: Control
var _hbox: HBoxContainer
var _vbox: VBoxContainer
var _info_label: Label
var _icon_rects: Array[TextureRect] = []


# ------------------------------------------------------------------------------
# Virtual Callbacks
# ------------------------------------------------------------------------------
func _ready() -> void:
	clip_contents = true
	_setup_ui()
	_update_theme_style()
	if weather_fx_node == null:
		var found: Node = get_tree().root.find_child("WeatherFX", true, false)
		if found is WeatherFX:
			weather_fx_node = found
	else:
		_connect_signals()

	if weather_fx_node:
		_rebuild_display(weather_fx_node.get_forecast())


func _process(_delta: float) -> void:
	if enable_scrolling and weather_fx_node and botw_style:
		_update_scroll_position()


# ------------------------------------------------------------------------------
# Private Methods
# ------------------------------------------------------------------------------
func _update_scroll_position() -> void:
	if _hbox == null or weather_fx_node == null:
		return
	var progress: float = weather_fx_node.get_cycle_progress()
	var step_size: float = icon_size.x + float(icon_separation)
	_hbox.position.x = scroll_offset_start - (progress * step_size)


func _update_theme_style() -> void:
	if botw_style:
		var style_box: StyleBoxFlat = StyleBoxFlat.new()
		style_box.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		style_box.set_corner_radius_all(24)
		style_box.content_margin_left = 0.0
		style_box.content_margin_top = 4.0
		style_box.content_margin_right = 0.0
		style_box.content_margin_bottom = 4.0
		add_theme_stylebox_override("panel", style_box)
	else:
		remove_theme_stylebox_override("panel")


func _setup_ui() -> void:
	if _hbox != null:
		return

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_vbox)

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.add_theme_color_override("font_color", COLOR_CYAN)
	_vbox.add_child(_info_label)

	_scroll_container = Control.new()
	_scroll_container.name = "ScrollContainer"
	_scroll_container.clip_contents = true
	_scroll_container.custom_minimum_size = Vector2(104.0, icon_size.y + 4.0)
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_scroll_container)

	_hbox = HBoxContainer.new()
	_hbox.name = "ForecastIcons"
	_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hbox.add_theme_constant_override("separation", icon_separation)
	_hbox.position = Vector2(scroll_offset_start, 2.0)
	_scroll_container.add_child(_hbox)


func _connect_signals() -> void:
	if is_instance_valid(weather_fx_node):
		if not weather_fx_node.cycle_advanced.is_connected(_on_cycle_advanced):
			weather_fx_node.cycle_advanced.connect(_on_cycle_advanced)
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
		if weather_fx_node.cycle_advanced.is_connected(_on_cycle_advanced):
			weather_fx_node.cycle_advanced.disconnect(_on_cycle_advanced)
		if weather_fx_node.forecast_updated.is_connected(_on_forecast_updated):
			weather_fx_node.forecast_updated.disconnect(_on_forecast_updated)
		if weather_fx_node.biome_changed.is_connected(_on_biome_changed):
			weather_fx_node.biome_changed.disconnect(_on_biome_changed)
		if weather_fx_node.temperature_changed.is_connected(_on_temperature_changed):
			weather_fx_node.temperature_changed.disconnect(_on_temperature_changed)
		if weather_fx_node.weather_changed.is_connected(_on_weather_changed):
			weather_fx_node.weather_changed.disconnect(_on_weather_changed)


func _on_cycle_advanced(_new_active_weather: ClimateData.WeatherType) -> void:
	if weather_fx_node:
		var forecast: Array = weather_fx_node.get_forecast()
		_advance_display_queue(forecast)


func _on_forecast_updated(forecast: Array) -> void:
	if _icon_rects.size() != forecast.size():
		_rebuild_display(forecast)


func _on_biome_changed(_new_biome: ClimateData.BiomeZone, _old_biome: ClimateData.BiomeZone) -> void:
	if weather_fx_node:
		_rebuild_display(weather_fx_node.get_forecast())


func _on_temperature_changed(_new_temp: float) -> void:
	_update_info_label()


func _on_weather_changed(_new_w: ClimateData.WeatherType, _old_w: ClimateData.WeatherType) -> void:
	_update_info_label()


func _update_info_label() -> void:
	if _info_label == null:
		return
	if weather_fx_node:
		var parts: Array[String] = []
		if show_biome_name:
			parts.append(ClimateData.get_biome_display_name(weather_fx_node.current_biome))
		if show_temperature:
			if temperature_unit == TemperatureUnit.FAHRENHEIT:
				var temp_f: float = ClimateData.celsius_to_fahrenheit(weather_fx_node.current_temperature)
				parts.append("%.1f°F" % temp_f)
			else:
				parts.append("%.1f°C" % weather_fx_node.current_temperature)
		_info_label.text = " • ".join(parts)
		_info_label.visible = not parts.is_empty()
	else:
		_info_label.text = "Weather FX"


func _create_icon_rect(w_type: ClimateData.WeatherType, is_active: bool) -> TextureRect:
	var icon_path: String = ClimateData.get_weather_icon_path(w_type)
	var tex: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null

	var rect: TextureRect = TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = icon_size

	if is_active:
		rect.modulate = COLOR_CYAN if botw_style else Color(1.0, 1.0, 1.0, 1.0)
	else:
		rect.modulate = COLOR_FADED if botw_style else Color(0.8, 0.8, 0.8, 0.65)

	return rect


func _update_icon_modulates() -> void:
	for i in range(_icon_rects.size()):
		var rect: TextureRect = _icon_rects[i]
		if i == 0:
			rect.modulate = COLOR_CYAN if botw_style else Color(1.0, 1.0, 1.0, 1.0)
		else:
			rect.modulate = COLOR_FADED if botw_style else Color(0.8, 0.8, 0.8, 0.65)


func _advance_display_queue(forecast: Array) -> void:
	if _hbox == null:
		return

	# Pop oldest weather icon from the front
	if _hbox.get_child_count() > 0:
		var old_first: Node = _hbox.get_child(0)
		_hbox.remove_child(old_first)
		old_first.free()

	if not _icon_rects.is_empty():
		_icon_rects.pop_front()

	# Append newest future weather icon to the back
	if not forecast.is_empty():
		var newest_weather: ClimateData.WeatherType = forecast[-1]
		var new_rect: TextureRect = _create_icon_rect(newest_weather, false)
		_hbox.add_child(new_rect)
		_icon_rects.append(new_rect)

	_update_icon_modulates()
	_update_info_label()
	_update_scroll_position()


func _rebuild_display(forecast: Array = []) -> void:
	if _hbox == null or _info_label == null:
		return

	if forecast.is_empty() and weather_fx_node:
		forecast = weather_fx_node.get_forecast()

	# Remove all existing children immediately
	for child in _hbox.get_children():
		_hbox.remove_child(child)
		child.free()
	_icon_rects.clear()

	_update_info_label()

	# Build fresh forecast icon list
	for i in range(forecast.size()):
		var w_type: ClimateData.WeatherType = forecast[i]
		var rect: TextureRect = _create_icon_rect(w_type, i == 0)
		_hbox.add_child(rect)
		_icon_rects.append(rect)

	_update_scroll_position()
