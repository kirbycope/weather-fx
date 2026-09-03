# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
@icon("res://addons/weather_fx/assets/icons/weather_fx_icon.svg")
class_name WeatherForecastDisplay
extends PanelContainer

## HUD forecast widget (scenes/weather_forecast_display.tscn) that shows the active weather and
## upcoming forecast cycles as a Zelda-style pill with SVG icons. The icon strip scrolls with a
## Tween synchronized to the WeatherFX cycle timer.

enum TemperatureUnit {
	CELSIUS,
	FAHRENHEIT,
}

const COLOR_CYAN: Color = Color(0.565, 0.843, 0.929, 1.0)
const COLOR_FADED: Color = Color(0.565, 0.843, 0.929, 0.65)
const BOTW_PANEL_STYLE: StyleBox = preload("res://addons/weather_fx/resources/hud_panel_style.tres")

@export_group("Node References")
## Assign before the widget enters the tree; falls back to the first node in the "WeatherFX" group.
@export var weather_fx: WeatherFX

@export_group("Styling & Layout")
@export var botw_style: bool = true:
	set(value):
		botw_style = value
		_update_theme_style()
		_rebuild_display()

@export var enable_scrolling: bool = true:
	set(value):
		enable_scrolling = value
		_restart_scroll()

@export var scroll_offset_start: float = 12.0:
	set(value):
		scroll_offset_start = value
		_restart_scroll()

@export var icon_separation: int = 6:
	set(value):
		icon_separation = value
		if _hbox:
			_hbox.add_theme_constant_override(&"separation", icon_separation)

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

@onready var _info_label: Label = %InfoLabel
@onready var _hbox: HBoxContainer = %ForecastIcons

var _icon_rects: Array[TextureRect] = []
var _scroll_tween: Tween


func _ready() -> void:
	_update_theme_style()
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.forecast_updated.connect(_rebuild_display)
		weather_fx.temperature_changed.connect(_update_info_label.unbind(1))
		weather_fx.playback_changed.connect(_restart_scroll.unbind(1))
	_rebuild_display()


func _update_theme_style() -> void:
	if botw_style:
		add_theme_stylebox_override(&"panel", BOTW_PANEL_STYLE)
	else:
		remove_theme_stylebox_override(&"panel")


func _update_info_label() -> void:
	if _info_label == null:
		return
	if not is_instance_valid(weather_fx):
		_info_label.text = "Weather FX"
		return
	var parts: Array[String] = []
	if show_biome_name:
		parts.append(ClimateData.get_biome_display_name(weather_fx.current_biome))
	if show_temperature:
		var fahrenheit: bool = temperature_unit == TemperatureUnit.FAHRENHEIT
		parts.append("%.1f°F" % ClimateData.celsius_to_fahrenheit(weather_fx.current_temperature) if fahrenheit else "%.1f°C" % weather_fx.current_temperature)
	_info_label.text = " • ".join(parts)
	_info_label.visible = not parts.is_empty()


func _rebuild_display(forecast: Array[ClimateData.WeatherType] = []) -> void:
	if _hbox == null:
		return
	if forecast.is_empty() and is_instance_valid(weather_fx):
		forecast = weather_fx.get_forecast()
	for child: Node in _hbox.get_children():
		_hbox.remove_child(child)
		child.free()
	_icon_rects.clear()
	_update_info_label()
	for i: int in forecast.size():
		var rect: TextureRect = TextureRect.new()
		rect.texture = ClimateData.get_weather_icon(forecast[i])
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = icon_size
		rect.modulate = (COLOR_CYAN if i == 0 else COLOR_FADED) if botw_style else (Color.WHITE if i == 0 else Color(0.8, 0.8, 0.8, 0.65))
		_hbox.add_child(rect)
		_icon_rects.append(rect)
	_restart_scroll()


## Positions the icon strip at the current cycle progress and tweens it one step over the rest of the cycle.
func _restart_scroll() -> void:
	if _scroll_tween:
		_scroll_tween.kill()
	if _hbox == null:
		return
	var step: float = icon_size.x + float(icon_separation)
	var progress: float = weather_fx.get_cycle_progress() if is_instance_valid(weather_fx) else 0.0
	_hbox.position.x = scroll_offset_start - progress * step
	if not (enable_scrolling and botw_style and is_instance_valid(weather_fx) and weather_fx.is_simulating()):
		return
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_hbox, ^"position:x", scroll_offset_start - step, weather_fx.cycle_duration_seconds * (1.0 - progress))
