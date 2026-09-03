# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

extends Node3D

## Demo controller for WeatherFX showcasing 20 biomes, weather overrides,
## altitude lapse rate, time-of-day progression, and particle impact effects.
## All UI and WeatherFX signals are wired in demo.tscn; StatusTimer refreshes the readout.

@onready var weather_fx: WeatherFX = $WeatherFX
@onready var date_and_time: Node = $DateAndTime
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var target_marker: Node3D = $DemonstrationTarget

# UI Nodes
@onready var biome_option_button: OptionButton = %BiomeOptionButton
@onready var weather_option_button: OptionButton = %WeatherOptionButton
@onready var time_slider: HSlider = %TimeSlider
@onready var time_value_label: Label = %TimeValueLabel
@onready var altitude_slider: HSlider = %AltitudeSlider
@onready var altitude_value_label: Label = %AltitudeValueLabel
@onready var wind_slider: HSlider = %WindSlider
@onready var wind_value_label: Label = %WindValueLabel
@onready var wind_direction_dial: WindDirectionDial = %WindDirectionDial
@onready var wind_dir_slider: HSlider = %WindDirSlider
@onready var wind_dir_value_label: Label = %WindDirValueLabel
@onready var play_pause_button: Button = %PlayPauseButton
@onready var unit_button: Button = %UnitButton
@onready var forecast_display: WeatherForecastDisplay = %WeatherForecastDisplay
@onready var gauge_display: TemperatureGaugeDisplay = %TemperatureGaugeDisplay
@onready var status_label: Label = %StatusLabel

# Internal camera state
var _camera_distance: float = 8.0
var _camera_yaw: float = 25.0
var _camera_pitch: float = -20.0
var _is_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	biome_option_button.clear()
	for i: int in ClimateData.BIOME_DEFINITIONS.size():
		biome_option_button.add_item("%02d: %s" % [i, ClimateData.get_biome_display_name(i as ClimateData.BiomeZone)], i)
	biome_option_button.selected = int(weather_fx.current_biome)

	weather_option_button.clear()
	weather_option_button.add_item("Simulation (Forecast)", -1)
	weather_option_button.add_item("Blue Sky", ClimateData.WeatherType.BLUE_SKY)
	weather_option_button.add_item("Cloudy", ClimateData.WeatherType.CLOUDY)
	weather_option_button.add_item("Rain (Splashes & Ripples)", ClimateData.WeatherType.RAIN)
	weather_option_button.add_item("Heavy Rain (Intense)", ClimateData.WeatherType.HEAVY_RAIN)
	weather_option_button.add_item("Storm (Thunder & Wind)", ClimateData.WeatherType.STORM)
	weather_option_button.add_item("Snow", ClimateData.WeatherType.SNOW)
	weather_option_button.add_item("Heavy Snow (Blizzard)", ClimateData.WeatherType.HEAVY_SNOW)
	weather_option_button.selected = 0
	_update_ui_state()
	_update_status_display()


func _process(delta: float) -> void:
	_handle_camera_input(delta)


# ------------------------------------------------------------------------------
# UI Signal Handlers (connected in demo.tscn)
# ------------------------------------------------------------------------------
func _on_biome_selected(index: int) -> void:
	weather_fx.current_biome = index as ClimateData.BiomeZone


func _on_weather_selected(index: int) -> void:
	var weather_id: int = weather_option_button.get_item_id(index)
	weather_fx.force_weather = weather_id != -1
	if weather_id != -1:
		weather_fx.manual_weather = weather_id as ClimateData.WeatherType


func _on_time_slider_changed(value: float) -> void:
	weather_fx.manual_time_of_day = value
	time_value_label.text = "%02d:%02d" % [int(value), int(fmod(value * 60.0, 60.0))]


func _on_altitude_slider_changed(value: float) -> void:
	weather_fx.current_altitude = value
	target_marker.position.y = value
	altitude_value_label.text = "%d m" % int(value)


func _on_wind_slider_changed(value: float) -> void:
	weather_fx.wind_strength_multiplier = value
	wind_value_label.text = "%.1fx" % value


func _on_wind_dial_changed(_dir: Vector3, angle_deg: float) -> void:
	if wind_dir_slider == null: # the dial emits during its own _ready, before this node's @onready vars exist
		return
	wind_dir_slider.set_value_no_signal(angle_deg)
	wind_dir_value_label.text = "%d° %s" % [int(angle_deg), wind_direction_dial.get_cardinal_name()]


func _on_wind_dir_slider_changed(value: float) -> void:
	wind_direction_dial.set_angle_degrees(value, true)
	wind_dir_value_label.text = "%d° %s" % [int(value), wind_direction_dial.get_cardinal_name()]


func _on_play_pause_pressed() -> void:
	weather_fx.is_playing = not weather_fx.is_playing
	play_pause_button.text = "Pause" if weather_fx.is_playing else "Resume"


func _on_unit_button_pressed() -> void:
	var fahrenheit: bool = forecast_display.temperature_unit == WeatherForecastDisplay.TemperatureUnit.CELSIUS
	var new_unit: WeatherForecastDisplay.TemperatureUnit = WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT if fahrenheit else WeatherForecastDisplay.TemperatureUnit.CELSIUS
	forecast_display.temperature_unit = new_unit
	gauge_display.temperature_unit = new_unit
	unit_button.text = "°F" if fahrenheit else "°C"


# ------------------------------------------------------------------------------
# State Updates
# ------------------------------------------------------------------------------
func _update_ui_state() -> void:
	if time_slider == null: # WeatherFX emits during its own _ready, before this node's @onready vars exist
		return
	var t: float = weather_fx.get_current_time_hours()
	time_slider.set_value_no_signal(t)
	time_value_label.text = "%02d:%02d" % [int(t), int(fmod(t * 60.0, 60.0))]
	altitude_slider.set_value_no_signal(weather_fx.current_altitude)
	altitude_value_label.text = "%d m" % int(weather_fx.current_altitude)
	wind_slider.set_value_no_signal(weather_fx.wind_strength_multiplier)
	wind_value_label.text = "%.1fx" % weather_fx.wind_strength_multiplier
	var angle_deg: float = wind_direction_dial.get_angle_degrees()
	wind_dir_slider.set_value_no_signal(angle_deg)
	wind_dir_value_label.text = "%d° %s" % [int(angle_deg), wind_direction_dial.get_cardinal_name()]
	play_pause_button.text = "Pause" if weather_fx.is_playing else "Resume"


static func get_wind_rating(strength: float) -> String:
	if strength < 1.5: return "Calm"
	elif strength < 3.5: return "Light Air"
	elif strength < 5.5: return "Breeze"
	elif strength < 8.5: return "Moderate Wind"
	elif strength < 12.0: return "Strong Gale"
	else: return "Storm Force"


## Refreshed by StatusTimer (FPS and cycle countdown are the only continuously changing fields).
func _update_status_display() -> void:
	var temp_c: float = weather_fx.current_temperature
	var wind_spd: float = weather_fx.current_wind_strength
	var remaining: float = weather_fx.cycle_timer.time_left if is_instance_valid(weather_fx.cycle_timer) else 0.0
	status_label.text = "Biome: %s\nWeather: %s%s\nTemp: %.1f°C / %.1f°F\nWind: %.1f m/s (%s - %s)\nAltitude: %d m\nCycle: %d%% (%02d:%02d left)\nFPS: %d" % [
		ClimateData.get_biome_display_name(weather_fx.current_biome),
		ClimateData.get_weather_name(weather_fx.active_weather),
		" (Forced)" if weather_fx.force_weather else " (Simulated)",
		temp_c,
		ClimateData.celsius_to_fahrenheit(temp_c),
		wind_spd,
		get_wind_rating(wind_spd),
		wind_direction_dial.get_cardinal_name(),
		int(weather_fx.current_altitude),
		int(weather_fx.get_cycle_progress() * 100.0),
		int(remaining / 60.0),
		int(fmod(remaining, 60.0)),
		Engine.get_frames_per_second(),
	]


# ------------------------------------------------------------------------------
# Interactive Camera Controls
# ------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
			_last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = clampf(_camera_distance - 0.8, 2.0, 30.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = clampf(_camera_distance + 0.8, 2.0, 30.0)
	elif event is InputEventMouseMotion and _is_dragging:
		var delta_pos: Vector2 = (event as InputEventMouseMotion).position - _last_mouse_pos
		_last_mouse_pos = (event as InputEventMouseMotion).position
		_camera_yaw -= delta_pos.x * 0.4
		_camera_pitch = clampf(_camera_pitch - delta_pos.y * 0.4, -80.0, 80.0)


func _handle_camera_input(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		_camera_yaw += 60.0 * delta
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		_camera_yaw -= 60.0 * delta
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		_camera_pitch = clampf(_camera_pitch + 40.0 * delta, -80.0, 80.0)
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		_camera_pitch = clampf(_camera_pitch - 40.0 * delta, -80.0, 80.0)
	camera_pivot.rotation_degrees = Vector3(_camera_pitch, _camera_yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, _camera_distance)
