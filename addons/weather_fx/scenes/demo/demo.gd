# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
extends Node3D

## Demo controller for WeatherFX showcasing 20 biomes, weather overrides,
## altitude lapse rate, time-of-day progression, and particle impact effects.

const WEATHER_NAMES: Dictionary = {
	ClimateData.WeatherType.BLUE_SKY: "Blue Sky",
	ClimateData.WeatherType.CLOUDY: "Cloudy",
	ClimateData.WeatherType.RAIN: "Rain",
	ClimateData.WeatherType.HEAVY_RAIN: "Heavy Rain",
	ClimateData.WeatherType.STORM: "Storm",
	ClimateData.WeatherType.SNOW: "Snow",
	ClimateData.WeatherType.HEAVY_SNOW: "Heavy Snow",
}

@onready var weather_fx: WeatherFX = $WeatherFX
@onready var date_and_time: Node = $DateAndTime
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
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
@onready var play_pause_button: Button = %PlayPauseButton
@onready var advance_cycle_button: Button = %AdvanceCycleButton
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
	if Engine.is_editor_hint():
		return
	_setup_biome_options()
	_setup_weather_options()
	_setup_ui_signals()
	_update_ui_state()


func _process(delta: float) -> void:
	_update_sun_lighting()
	if Engine.is_editor_hint():
		return
	_update_status_display()
	_handle_camera_input(delta)


# ------------------------------------------------------------------------------
# UI Setup
# ------------------------------------------------------------------------------
func _setup_biome_options() -> void:
	biome_option_button.clear()
	for i in range(20):
		var zone: ClimateData.BiomeZone = i as ClimateData.BiomeZone
		var data = ClimateData.get_biome_data(zone)
		var b_name: String = data.get("display_name", data.get("name", "Unknown Biome"))
		biome_option_button.add_item("%02d: %s" % [i, b_name], i)
	biome_option_button.selected = int(weather_fx.current_biome)


func _setup_weather_options() -> void:
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


func _setup_ui_signals() -> void:
	biome_option_button.item_selected.connect(_on_biome_selected)
	weather_option_button.item_selected.connect(_on_weather_selected)
	time_slider.value_changed.connect(_on_time_slider_changed)
	altitude_slider.value_changed.connect(_on_altitude_slider_changed)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	advance_cycle_button.pressed.connect(_on_advance_cycle_pressed)
	unit_button.pressed.connect(_on_unit_button_pressed)

	weather_fx.weather_changed.connect(func(_new, _old): _update_ui_state())
	weather_fx.biome_changed.connect(func(_new, _old): _update_ui_state())
	weather_fx.temperature_changed.connect(func(_temp): _update_ui_state())


# ------------------------------------------------------------------------------
# UI Callbacks
# ------------------------------------------------------------------------------
func _on_biome_selected(index: int) -> void:
	var biome_zone: ClimateData.BiomeZone = index as ClimateData.BiomeZone
	weather_fx.set_biome(biome_zone)
	_apply_biome_ambient(biome_zone)


func _on_weather_selected(index: int) -> void:
	var weather_id = weather_option_button.get_item_id(index)
	if weather_id < 0:
		weather_fx.resume_forecast()
	else:
		weather_fx.set_weather(weather_id as ClimateData.WeatherType)


func _on_time_slider_changed(value: float) -> void:
	if is_instance_valid(date_and_time):
		date_and_time.current_time = value
	weather_fx.manual_time_of_day = value
	time_value_label.text = "%02d:%02d" % [int(value), int(fmod(value * 60.0, 60.0))]


func _on_altitude_slider_changed(value: float) -> void:
	if is_instance_valid(target_marker):
		target_marker.position.y = value
	weather_fx.current_altitude = value
	altitude_value_label.text = "%d m" % int(value)


func _on_play_pause_pressed() -> void:
	weather_fx.toggle_pause()
	play_pause_button.text = "Resume" if not weather_fx.is_playing else "Pause"


func _on_advance_cycle_pressed() -> void:
	weather_fx.advance_cycle()


func _on_unit_button_pressed() -> void:
	var is_celsius = (forecast_display.temperature_unit == WeatherForecastDisplay.TemperatureUnit.CELSIUS)
	var new_unit = WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT if is_celsius else WeatherForecastDisplay.TemperatureUnit.CELSIUS
	forecast_display.temperature_unit = new_unit
	gauge_display.temperature_unit = new_unit
	unit_button.text = "°F" if new_unit == WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT else "°C"


# ------------------------------------------------------------------------------
# State Updates & Environment
# ------------------------------------------------------------------------------
func _update_ui_state() -> void:
	var t = weather_fx.get_current_time_hours()
	time_slider.set_value_no_signal(t)
	time_value_label.text = "%02d:%02d" % [int(t), int(fmod(t * 60.0, 60.0))]
	
	altitude_slider.set_value_no_signal(weather_fx.current_altitude)
	altitude_value_label.text = "%d m" % int(weather_fx.current_altitude)
	
	play_pause_button.text = "Pause" if weather_fx.is_playing else "Resume"


func _update_status_display() -> void:
	var b_data = ClimateData.get_biome_data(weather_fx.current_biome)
	var b_name: String = b_data.get("display_name", b_data.get("name", "Unknown"))
	var w_name: String = WEATHER_NAMES.get(weather_fx.active_weather, "Unknown")
	var temp_c = weather_fx.current_temperature
	var temp_f = ClimateData.celsius_to_fahrenheit(temp_c)
	var prog = weather_fx.get_cycle_progress() * 100.0
	var timer_rem = maxf(0.0, weather_fx.cycle_duration_seconds - weather_fx.get_cycle_timer())

	status_label.text = "Biome: %s\nWeather: %s%s\nTemp: %.1f°C / %.1f°F\nAltitude: %d m\nCycle: %d%% (%02d:%02d left)" % [
		b_name,
		w_name,
		" (Forced)" if weather_fx.force_weather else " (Simulated)",
		temp_c,
		temp_f,
		int(weather_fx.current_altitude),
		int(prog),
		int(timer_rem / 60.0),
		int(fmod(timer_rem, 60.0))
	]


func _update_sun_lighting() -> void:
	if not is_instance_valid(sun_light):
		return
	var t = weather_fx.get_current_time_hours()
	# Map 0h - 24h to sun angle (6h sunrise = 0°, 12h noon = 90°, 18h sunset = 180°, 0h midnight = 270°)
	var sun_rot_x = ((t - 6.0) / 24.0) * TAU
	sun_light.rotation = Vector3(-sun_rot_x, deg_to_rad(-30.0), 0.0)
	
	var is_day = weather_fx.is_daylight(t)
	sun_light.light_energy = 1.0 if is_day else 0.15
	sun_light.light_color = Color(1.0, 0.95, 0.85) if is_day else Color(0.35, 0.45, 0.7)


func _apply_biome_ambient(biome: ClimateData.BiomeZone) -> void:
	match biome:
		ClimateData.BiomeZone.ARCTIC_TUNDRA, ClimateData.BiomeZone.ALPINE_PEAKS, ClimateData.BiomeZone.DESERT_GLACIER:
			sun_light.light_color = Color(0.9, 0.95, 1.0)
		ClimateData.BiomeZone.VOLCANIC_FOOTHILLS, ClimateData.BiomeZone.VOLCANIC_CRATER, ClimateData.BiomeZone.VOLCANIC_CALDERA:
			sun_light.light_color = Color(1.0, 0.7, 0.5)
		ClimateData.BiomeZone.DESERT_DUNES, ClimateData.BiomeZone.DESERT_PLATEAU, ClimateData.BiomeZone.DEEP_DESERT, ClimateData.BiomeZone.ARID_CANYON:
			sun_light.light_color = Color(1.0, 0.9, 0.7)
		ClimateData.BiomeZone.TROPICAL_RAINFOREST, ClimateData.BiomeZone.WETLANDS_VALLEY, ClimateData.BiomeZone.HUMID_COAST:
			sun_light.light_color = Color(0.85, 1.0, 0.9)
		_:
			sun_light.light_color = Color(1.0, 0.95, 0.85)


# ------------------------------------------------------------------------------
# Interactive Camera Controls
# ------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = clampf(_camera_distance - 0.8, 2.0, 30.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = clampf(_camera_distance + 0.8, 2.0, 30.0)

	elif event is InputEventMouseMotion and _is_dragging:
		var delta_pos = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		_camera_yaw -= delta_pos.x * 0.4
		_camera_pitch = clampf(_camera_pitch - delta_pos.y * 0.4, -80.0, 80.0)


func _handle_camera_input(delta: float) -> void:
	if not is_instance_valid(camera_pivot) or not is_instance_valid(camera):
		return

	# Arrow / WASD key camera rotation
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
