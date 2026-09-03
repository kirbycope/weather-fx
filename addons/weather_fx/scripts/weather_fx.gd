# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
@icon("res://addons/weather_fx/assets/icons/weather_fx_icon.svg")
class_name WeatherFX
extends Node3D

## WeatherFX manages dynamic weather simulation, 4-minute forecasting cycles,
## altitude/time-based temperatures across 20 biomes, wind shader globals, fog and sun lighting.
## Precipitation particles and audio live in the PrecipitationFX / WeatherAudio child nodes and
## react to this node's signals. Consumers find the active instance via the "WeatherFX" group.

# Signals
signal weather_changed(new_weather: ClimateData.WeatherType, old_weather: ClimateData.WeatherType)
signal forecast_updated(forecast: Array[ClimateData.WeatherType])
signal cycle_advanced(current_weather: ClimateData.WeatherType)
signal biome_changed(new_biome: ClimateData.BiomeZone, old_biome: ClimateData.BiomeZone)
signal temperature_changed(temp_celsius: float)
signal wind_changed(strength: float, direction: Vector3)
signal daylight_changed(is_day: bool)
## Emitted when the simulation starts or stops ticking (play/pause, editor toggle).
signal playback_changed(active: bool)

# Constants
const WIND_WEATHER_MULTIPLIER: Dictionary = {
	ClimateData.WeatherType.BLUE_SKY: 0.8,
	ClimateData.WeatherType.CLOUDY: 1.0,
	ClimateData.WeatherType.RAIN: 1.2,
	ClimateData.WeatherType.HEAVY_RAIN: 1.6,
	ClimateData.WeatherType.STORM: 2.2,
	ClimateData.WeatherType.SNOW: 0.9,
	ClimateData.WeatherType.HEAVY_SNOW: 1.8,
}
const FOG_DENSITY: Dictionary = {
	ClimateData.WeatherType.CLOUDY: 0.005,
	ClimateData.WeatherType.RAIN: 0.01,
	ClimateData.WeatherType.HEAVY_RAIN: 0.02,
	ClimateData.WeatherType.STORM: 0.03,
	ClimateData.WeatherType.SNOW: 0.01,
	ClimateData.WeatherType.HEAVY_SNOW: 0.03,
}
const REQUIRED_SHADER_GLOBALS: Array[String] = [
	"weather_wind_strength",
	"weather_wind_direction",
	"weather_precipitation_strength",
	"weather_foliage_tint",
	"weather_grass_tint",
]
## Frames to wait between full-tree class-based player searches when no Player exists.
const PLAYER_SEARCH_COOLDOWN_FRAMES: int = 120

# Exported Groups: Simulation Controls
@export_group("Simulation Controls")

## Starts or pauses weather cycle progression and audio/VFX playback.
@export var is_playing: bool = true :
	set(value):
		if is_playing != value:
			is_playing = value
			_update_playback_state()

## Allows simulation to tick inside the editor viewport.
@export var editor_weather_enabled: bool = false :
	set(value):
		if editor_weather_enabled != value:
			editor_weather_enabled = value
			_update_playback_state()

## Duration of each weather cycle in real-world seconds (BotW default is 240.0s = 4 minutes).
@export_range(1.0, 3600.0, 1.0) var cycle_duration_seconds: float = 240.0 :
	set(value):
		cycle_duration_seconds = value
		if is_instance_valid(cycle_timer):
			cycle_timer.wait_time = value

## Number of forecast steps to maintain (including current cycle).
@export_range(2, 12) var forecast_length: int = 7

## Press to instantly advance to the next forecast cycle in the editor.
@export var trigger_advance_cycle: bool = false :
	set(value):
		if value:
			advance_cycle()

## Timer that advances the forecast cycle; wired to advance_cycle() in weather_fx.tscn.
@export var cycle_timer: Timer

# Exported Groups: Biome & Weather
@export_group("Biome & Weather")

## Active climate biome.
@export var current_biome: ClimateData.BiomeZone = ClimateData.BiomeZone.TEMPERATE_PLAINS :
	set(value):
		if current_biome != value:
			var old: ClimateData.BiomeZone = current_biome
			current_biome = value
			_regenerate_forecast()
			_update_temperature()
			_update_wind_globals()
			_update_sun_lighting()
			biome_changed.emit(current_biome, old)

## Force manual weather instead of procedural simulation.
@export var force_weather: bool = false :
	set(value):
		force_weather = value
		_update_active_weather()

## Target weather when force_weather is true.
@export var manual_weather: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY :
	set(value):
		manual_weather = value
		if force_weather:
			_update_active_weather()

## Current active weather condition.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var active_weather: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY

# Exported Groups: Environment & Tracking
@export_group("Environment & Tracking")

## Optional clock node exposing `current_time` (hours) and a `time_changed(float)` signal,
## e.g. the DateAndTime addon. Falls back to manual_time_of_day when unset.
@export var date_and_time_node: Node :
	set(value):
		if date_and_time_node == value:
			return
		if is_instance_valid(date_and_time_node) and date_and_time_node.has_signal(&"time_changed"):
			date_and_time_node.disconnect(&"time_changed", _on_external_time_changed)
		date_and_time_node = value
		if is_instance_valid(date_and_time_node) and date_and_time_node.has_signal(&"time_changed"):
			date_and_time_node.connect(&"time_changed", _on_external_time_changed)
		_update_time_of_day()

## Fallback time of day (0.0 - 24.0 hours) used when no clock node is linked.
@export_range(0.0, 24.0, 0.1) var manual_time_of_day: float = 12.0 :
	set(value):
		if is_equal_approx(manual_time_of_day, value):
			return
		manual_time_of_day = value
		if is_instance_valid(date_and_time_node) and "current_time" in date_and_time_node and not is_equal_approx(float(date_and_time_node.get(&"current_time")), value):
			date_and_time_node.set(&"current_time", value)
		_update_time_of_day()

## Optional target node (e.g. Player) to track altitude; child FX also follow it.
@export var target_node: Node3D

## Optional DirectionalLight3D to automatically orient and tint based on time of day and biome.
@export var sun_light: DirectionalLight3D :
	set(value):
		sun_light = value
		_update_sun_lighting()

## Optional WorldEnvironment whose fog follows the active weather.
@export var world_environment: WorldEnvironment

## Current altitude in meters. If target_node is assigned, this is updated automatically.
@export_range(0.0, 1500.0, 1.0) var current_altitude: float = 0.0 :
	set(value):
		if is_equal_approx(current_altitude, value):
			return
		current_altitude = value
		_update_temperature()

## Calculated temperature in °C at current altitude and time.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var current_temperature: float = 20.0

# Exported Groups: Wind System
@export_group("Wind System")

## Wind direction vector in 3D world space.
@export var wind_direction: Vector3 = Vector3.RIGHT :
	set(value):
		wind_direction = value.normalized() if not value.is_zero_approx() else Vector3.RIGHT
		_update_wind_globals()

## Global wind multiplier.
@export_range(0.0, 5.0, 0.1) var wind_strength_multiplier: float = 1.0 :
	set(value):
		wind_strength_multiplier = value
		_update_wind_globals()

## Calculated wind strength (0.0 when paused or simulation disabled).
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var current_wind_strength: float = 0.0

@export_group("Performance & Optimizations")
@export var update_global_shader_variables: bool = true

@export_group("Foliage & Grass Biome Tinting")
@export var enable_biome_tinting: bool = true ## Dynamically tints tree canopies, leaves, and ground grass based on current biome.
@export var biome_tint_transition_speed: float = 2.0 ## Smooth blend speed when transitioning between biomes.

var current_foliage_tint: Color = Color.WHITE
var current_grass_tint: Color = Color.WHITE

# Static state shared with CPU scripts that have no node reference (see get_wind_strength()).
static var active_wind_strength: float = 0.0
static var active_wind_direction: Vector3 = Vector3.RIGHT
static var active_precipitation_strength: float = 0.0
static var _player_cache: Node3D = null
static var _player_search_cooldown_frame: int = -1
static var _globals_checked: bool = false

# Internal State
var _forecast: Array[ClimateData.WeatherType] = []
var _is_forward_plus: bool = true
var _is_day: bool = true


# Lifecycle
func _enter_tree() -> void:
	add_to_group(&"WeatherFX")


func _ready() -> void:
	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	_is_forward_plus = renderer == "forward_plus" and not OS.has_feature("web") and not OS.has_feature("gl_compatibility")
	ensure_shader_globals()
	_regenerate_forecast()
	_update_active_weather(true)
	_update_playback_state()
	_update_time_of_day()


func _process(delta: float) -> void:
	if not is_simulating():
		return
	if is_instance_valid(target_node) and target_node.is_inside_tree():
		current_altitude = maxf(0.0, target_node.global_position.y)
	_update_biome_tinting(delta)


## True while the weather cycle ticks (playing, and in the editor only with editor_weather_enabled).
func is_simulating() -> bool:
	if not is_inside_tree():
		return false
	return is_playing and (editor_weather_enabled or not Engine.is_editor_hint())


func _update_playback_state() -> void:
	if not is_inside_tree():
		return
	var active: bool = is_simulating()
	if is_instance_valid(cycle_timer):
		cycle_timer.paused = not active
		if active and cycle_timer.is_stopped():
			cycle_timer.start()
	_update_active_weather()
	_update_wind_globals()
	_update_fog()
	playback_changed.emit(active)


# Time & Temperature
## Returns current time in hours (from the clock node if available, otherwise manual_time_of_day).
func get_current_time_hours() -> float:
	if is_instance_valid(date_and_time_node) and "current_time" in date_and_time_node:
		return float(date_and_time_node.get(&"current_time"))
	return manual_time_of_day


## Returns true if the given time (or the current time when omitted) is daylight.
func is_daylight(time_hours: float = -1.0) -> bool:
	var t: float = time_hours if time_hours >= 0.0 else get_current_time_hours()
	return t >= 6.0 and t < 18.0


## Calculates temperature for the active biome at the given time and altitude.
func calculate_temperature(time_hours: float, alt: float) -> float:
	return ClimateData.get_smooth_temperature(current_biome, alt, time_hours)


func _on_external_time_changed(time: float) -> void:
	manual_time_of_day = time


func _update_time_of_day() -> void:
	_update_temperature()
	_update_sun_lighting()
	var day: bool = is_daylight()
	if day != _is_day:
		_is_day = day
		daylight_changed.emit(day)


func _update_temperature() -> void:
	var temp: float = calculate_temperature(get_current_time_hours(), current_altitude)
	if not is_equal_approx(temp, current_temperature):
		current_temperature = temp
		temperature_changed.emit(current_temperature)


# Weather & Forecast Generation
## Generates a single weather condition based on biome probability, locks, and temperature.
func generate_weather_for_time(time_hours: float) -> ClimateData.WeatherType:
	var biome_info: Dictionary = ClimateData.get_biome_data(current_biome)
	var is_day: bool = is_daylight(time_hours)
	if (is_day and biome_info.get("day_lock_bluesky", false)) or (not is_day and biome_info.get("night_lock_bluesky", false)):
		return ClimateData.WeatherType.BLUE_SKY

	var b_rate: int = biome_info.get("bluesky_rate", 60)
	var c_rate: int = biome_info.get("cloudy_rate", 20)
	var r_rate: int = biome_info.get("rain_rate", 10)
	var hr_rate: int = biome_info.get("heavy_rain_rate", 5)
	var s_rate: int = biome_info.get("storm_rate", 5)
	var total_rate: int = b_rate + c_rate + r_rate + hr_rate + s_rate
	if total_rate <= 0:
		return ClimateData.WeatherType.BLUE_SKY

	var roll: int = randi() % total_rate
	var freezing: bool = ClimateData.is_freezing(calculate_temperature(time_hours, current_altitude))
	if roll < b_rate:
		# Rare sun-shower pattern
		if int(biome_info.get("bluesky_rain_pat", 0)) > 0 and randf() < 0.10:
			return ClimateData.WeatherType.SNOW if freezing else ClimateData.WeatherType.RAIN
		return ClimateData.WeatherType.BLUE_SKY
	roll -= b_rate
	if roll < c_rate:
		return ClimateData.WeatherType.CLOUDY
	roll -= c_rate
	if roll < r_rate:
		return ClimateData.WeatherType.SNOW if freezing else ClimateData.WeatherType.RAIN
	roll -= r_rate
	if roll < hr_rate:
		return ClimateData.WeatherType.HEAVY_SNOW if freezing else ClimateData.WeatherType.HEAVY_RAIN
	return ClimateData.WeatherType.HEAVY_SNOW if freezing else ClimateData.WeatherType.STORM


## Rebuilds the entire upcoming forecast queue.
func _regenerate_forecast() -> void:
	_forecast.clear()
	var current_t: float = get_current_time_hours()
	var hours_per_cycle: float = cycle_duration_seconds / 3600.0 * 24.0
	for i: int in forecast_length:
		_forecast.append(generate_weather_for_time(fmod(current_t + i * hours_per_cycle, 24.0)))
	forecast_updated.emit(_forecast.duplicate())
	_update_active_weather()


## Advances simulation by one cycle.
func advance_cycle() -> void:
	if _forecast.is_empty():
		_regenerate_forecast()
		return
	_forecast.pop_front()
	var hours_per_cycle: float = cycle_duration_seconds / 3600.0 * 24.0
	_forecast.append(generate_weather_for_time(fmod(get_current_time_hours() + (forecast_length - 1) * hours_per_cycle, 24.0)))
	forecast_updated.emit(_forecast.duplicate())
	cycle_advanced.emit(_forecast[0])
	_update_active_weather()


func _update_active_weather(force_apply: bool = false) -> void:
	if not is_simulating():
		return
	if _forecast.is_empty():
		_regenerate_forecast()
	var target_weather: ClimateData.WeatherType = manual_weather if force_weather else _forecast[0]
	if not force_apply and active_weather == target_weather:
		return
	var old: ClimateData.WeatherType = active_weather
	active_weather = target_weather
	_update_wind_globals()
	_update_fog()
	weather_changed.emit(active_weather, old)


# Wind, Fog, Sun & Tinting
## Updates cached wind/precipitation values, global shader parameters and emits wind_changed.
func _update_wind_globals() -> void:
	var active: bool = is_simulating()
	var base_power: float = ClimateData.get_biome_data(current_biome).get("wind_power", 7.5)
	current_wind_strength = base_power * WIND_WEATHER_MULTIPLIER[active_weather] * wind_strength_multiplier if active else 0.0
	active_wind_strength = current_wind_strength
	active_wind_direction = wind_direction
	active_precipitation_strength = ClimateData.get_precipitation_strength(active_weather) if active else 0.0
	if update_global_shader_variables:
		RenderingServer.global_shader_parameter_set(&"weather_wind_strength", current_wind_strength)
		RenderingServer.global_shader_parameter_set(&"weather_wind_direction", wind_direction)
		RenderingServer.global_shader_parameter_set(&"weather_precipitation_strength", active_precipitation_strength)
	wind_changed.emit(current_wind_strength, wind_direction)


func _update_fog() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var env: Environment = world_environment.environment
	var density: float = FOG_DENSITY.get(active_weather, 0.0) if is_simulating() else 0.0
	env.fog_enabled = density > 0.0
	env.fog_density = density
	env.volumetric_fog_enabled = _is_forward_plus and density > 0.0 and active_weather != ClimateData.WeatherType.CLOUDY
	env.volumetric_fog_density = density * 0.5


## Updates the sun DirectionalLight3D orientation, energy, and color based on time of day and biome.
func _update_sun_lighting() -> void:
	if not is_instance_valid(sun_light):
		return
	var t: float = get_current_time_hours()
	# Map 0h - 24h to sun angle (6h sunrise = 0°, 12h noon = 90°, 18h sunset = 180°, 0h midnight = 270°)
	sun_light.rotation = Vector3(-((t - 6.0) / 24.0) * TAU, deg_to_rad(-30.0), 0.0)
	var is_day: bool = is_daylight(t)
	sun_light.light_energy = 1.0 if is_day else 0.15
	match current_biome:
		ClimateData.BiomeZone.ARCTIC_TUNDRA, ClimateData.BiomeZone.ALPINE_PEAKS, ClimateData.BiomeZone.DESERT_GLACIER:
			sun_light.light_color = Color(0.9, 0.95, 1.0) if is_day else Color(0.3, 0.4, 0.65)
		ClimateData.BiomeZone.VOLCANIC_FOOTHILLS, ClimateData.BiomeZone.VOLCANIC_CRATER, ClimateData.BiomeZone.VOLCANIC_CALDERA:
			sun_light.light_color = Color(1.0, 0.7, 0.5) if is_day else Color(0.5, 0.25, 0.2)
		ClimateData.BiomeZone.DESERT_DUNES, ClimateData.BiomeZone.DESERT_PLATEAU, ClimateData.BiomeZone.DEEP_DESERT, ClimateData.BiomeZone.ARID_CANYON:
			sun_light.light_color = Color(1.0, 0.9, 0.7) if is_day else Color(0.3, 0.35, 0.55)
		ClimateData.BiomeZone.TROPICAL_RAINFOREST, ClimateData.BiomeZone.WETLANDS_VALLEY, ClimateData.BiomeZone.HUMID_COAST:
			sun_light.light_color = Color(0.85, 1.0, 0.9) if is_day else Color(0.25, 0.4, 0.5)
		_:
			sun_light.light_color = Color(1.0, 0.95, 0.85) if is_day else Color(0.35, 0.45, 0.7)


## Smoothly blends global foliage and grass color tints toward the active biome targets.
func _update_biome_tinting(delta: float) -> void:
	var target_foliage: Color = get_target_foliage_tint()
	var target_grass: Color = get_target_grass_tint()
	if current_foliage_tint.is_equal_approx(target_foliage) and current_grass_tint.is_equal_approx(target_grass):
		return
	var weight: float = clampf(delta * biome_tint_transition_speed, 0.0, 1.0)
	current_foliage_tint = current_foliage_tint.lerp(target_foliage, weight)
	current_grass_tint = current_grass_tint.lerp(target_grass, weight)
	if update_global_shader_variables:
		RenderingServer.global_shader_parameter_set(&"weather_foliage_tint", current_foliage_tint)
		RenderingServer.global_shader_parameter_set(&"weather_grass_tint", current_grass_tint)


## Target foliage tint for the active biome, normalized so TEMPERATE_PLAINS renders untinted.
func get_target_foliage_tint() -> Color:
	if not enable_biome_tinting:
		return Color.WHITE
	var reference: Color = ClimateData.get_biome_foliage_tint(ClimateData.BiomeZone.TEMPERATE_PLAINS)
	return normalize_biome_tint(ClimateData.get_biome_foliage_tint(current_biome), reference)


## Target grass tint for the active biome, normalized so TEMPERATE_PLAINS renders untinted.
func get_target_grass_tint() -> Color:
	if not enable_biome_tinting:
		return Color.WHITE
	var reference: Color = ClimateData.get_biome_grass_tint(ClimateData.BiomeZone.TEMPERATE_PLAINS)
	return normalize_biome_tint(ClimateData.get_biome_grass_tint(current_biome), reference)


## Normalizes a biome tint per-channel against a reference so the reference biome is identity (white).
static func normalize_biome_tint(tint: Color, reference: Color) -> Color:
	return Color(tint.r / maxf(reference.r, 0.001), tint.g / maxf(reference.g, 0.001), tint.b / maxf(reference.b, 0.001), 1.0)


## Verifies that required shader globals exist in ProjectSettings.
static func ensure_shader_globals() -> void:
	if _globals_checked:
		return
	_globals_checked = true
	var missing: Array[String] = REQUIRED_SHADER_GLOBALS.filter(func(param: String) -> bool: return not ProjectSettings.has_setting("shader_globals/" + param))
	if not missing.is_empty():
		push_error("WeatherFX: Missing global shader parameter(s) in Project Settings: %s. Please add them under Project Settings -> Shader Globals or enable the WeatherFX plugin." % [", ".join(missing)])


# Public API
## Overrides weather directly.
func set_weather(weather_type: ClimateData.WeatherType) -> void:
	force_weather = true
	manual_weather = weather_type


## Clears manual weather override and resumes procedural forecast.
func resume_forecast() -> void:
	force_weather = false


## Returns duplicate array of upcoming forecast.
func get_forecast() -> Array[ClimateData.WeatherType]:
	return _forecast.duplicate()


## Returns current cycle progress fraction between 0.0 and 1.0.
func get_cycle_progress() -> float:
	if not is_instance_valid(cycle_timer) or cycle_timer.is_stopped():
		return 0.0
	return 1.0 - cycle_timer.time_left / cycle_timer.wait_time


# Static helpers for scripts without a node reference
static func get_wind_strength() -> float:
	return active_wind_strength


static func get_wind_direction() -> Vector3:
	return active_wind_direction


static func get_precipitation_strength() -> float:
	return active_precipitation_strength


## BotW-style wind spread factor shared by all fire propagation systems:
## downwind alignment boosts range, upwind alignment suppresses it.
static func get_wind_spread_factor(wind_alignment: float, wind_strength: float, wind_multiplier: float = 0.35) -> float:
	var downwind_boost: float = maxf(0.0, wind_alignment) * minf(wind_strength * wind_multiplier, 2.5)
	var upwind_penalty: float = maxf(0.0, -wind_alignment) * 0.5
	return 1.0 + downwind_boost - upwind_penalty


## Returns true if the node is the player. Prefers the "Player" group (clean decoupling),
## falling back to a `class_name Player` script check for scenes that don't use the group.
static func is_player_node(node: Node) -> bool:
	if node == null:
		return false
	if node.is_in_group(&"Player"):
		return true
	var node_script: Script = node.get_script() as Script
	while node_script:
		if node_script.get_global_name() == &"Player":
			return true
		node_script = node_script.get_base_script()
	return false


## Finds the active Player. Prefers the O(1) "Player" group lookup; only falls back to a
## cached, rate-limited class-based tree scan when no node is in the group.
static func find_player(tree: SceneTree) -> Node3D:
	if tree == null or tree.root == null:
		return null
	var grouped: Node = tree.get_first_node_in_group(&"Player")
	if grouped is Node3D:
		return grouped as Node3D
	if is_instance_valid(_player_cache) and _player_cache.is_inside_tree():
		return _player_cache
	_player_cache = null
	var frame: int = Engine.get_process_frames()
	if _player_search_cooldown_frame >= 0 and frame - _player_search_cooldown_frame < PLAYER_SEARCH_COOLDOWN_FRAMES:
		return null
	_player_search_cooldown_frame = frame
	for body: Node in tree.root.find_children("*", "CharacterBody3D", true, false):
		if is_player_node(body):
			_player_cache = body as Node3D
			break
	return _player_cache
