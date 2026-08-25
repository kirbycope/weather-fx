# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WeatherFX
extends Node3D

## WeatherFX manages dynamic weather simulation, 4-minute forecasting cycles,
## altitude/time-based temperatures across 20 biomes, wind shader globals, and audio/VFX control.

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal weather_changed(new_weather: ClimateData.WeatherType, old_weather: ClimateData.WeatherType)
signal forecast_updated(forecast: Array)
signal cycle_advanced(current_weather: ClimateData.WeatherType)
signal biome_changed(new_biome: ClimateData.BiomeZone, old_biome: ClimateData.BiomeZone)
signal temperature_changed(temp_celsius: float)
signal wind_changed(strength: float, direction: Vector3)

# ------------------------------------------------------------------------------
# Exported Groups: Simulation Controls
# ------------------------------------------------------------------------------
@export_group("Simulation Controls")

## Starts or pauses weather cycle progression and audio/VFX playback.
@export var is_playing: bool = true :
	set(value):
		if is_playing != value:
			is_playing = value
			_update_playback_state()

## Allows simulation to tick inside the editor viewport.
@export var editor_weather_enabled: bool = true :
	set(value):
		if editor_weather_enabled != value:
			editor_weather_enabled = value
			_update_playback_state()

## Duration of each weather cycle in real-world seconds (BotW default is 240.0s = 4 minutes).
@export_range(1.0, 3600.0, 1.0) var cycle_duration_seconds: float = 240.0

## Number of forecast steps to maintain (including current cycle).
@export_range(2, 12) var forecast_length: int = 7

## Press to instantly advance to the next forecast cycle in the editor.
@export var trigger_advance_cycle: bool = false :
	set(value):
		if value:
			advance_cycle()

# ------------------------------------------------------------------------------
# Exported Groups: Biome & Weather
# ------------------------------------------------------------------------------
@export_group("Biome & Weather")

## Active climate biome.
@export var current_biome: ClimateData.BiomeZone = ClimateData.BiomeZone.TEMPERATE_PLAINS :
	set(value):
		if current_biome != value:
			var old = current_biome
			current_biome = value
			emit_signal("biome_changed", current_biome, old)
			_regenerate_forecast()
			_update_temperature_and_weather()

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

# ------------------------------------------------------------------------------
# Exported Groups: Environment & Tracking
# ------------------------------------------------------------------------------
@export_group("Environment & Tracking")

## Optional link to a DateAndTime node. If not set, WeatherFX will search scene or use manual time.
@export var date_and_time_node: Node :
	set(value):
		if date_and_time_node != value:
			if date_and_time_node and date_and_time_node.has_signal("time_changed") and date_and_time_node.is_connected("time_changed", _on_external_time_changed):
				date_and_time_node.disconnect("time_changed", _on_external_time_changed)
			date_and_time_node = value
			if date_and_time_node and date_and_time_node.has_signal("time_changed"):
				date_and_time_node.connect("time_changed", _on_external_time_changed)

## Fallback time of day (0.0 - 24.0 hours) used when no DateAndTime node is linked.
@export_range(0.0, 24.0, 0.1) var manual_time_of_day: float = 12.0 :
	set(value):
		manual_time_of_day = value
		_update_temperature_and_weather()

## Optional target node (e.g. Player) to track altitude and position.
@export var target_node: Node3D

## Current altitude in meters. If target_node is assigned, this is updated automatically.
@export_range(0.0, 1500.0, 1.0) var current_altitude: float = 0.0 :
	set(value):
		current_altitude = value
		_update_temperature_and_weather()

## Calculated temperature in °C at current altitude and time.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var current_temperature: float = 20.0

# ------------------------------------------------------------------------------
# Exported Groups: Wind System
# ------------------------------------------------------------------------------
@export_group("Wind System")

## Wind direction vector in 3D world space.
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0).normalized() :
	set(value):
		wind_direction = value.normalized() if not value.is_zero_approx() else Vector3.RIGHT
		_update_wind_globals()

## Global wind multiplier.
@export_range(0.0, 5.0, 0.1) var wind_strength_multiplier: float = 1.0 :
	set(value):
		wind_strength_multiplier = value
		_update_wind_globals()

## Push wind parameters to ProjectSettings / RenderingServer global shader uniforms.
@export var update_global_shader_variables: bool = true

# ------------------------------------------------------------------------------
# Exported Groups: VFX & Audio Binding
# ------------------------------------------------------------------------------
@export_group("VFX & Audio Nodes")

@export var rain_particles: GPUParticles3D
@export var rain_splash_particles: GPUParticles3D
@export var snow_particles: GPUParticles3D
@export var audio_rain_light: AudioStreamPlayer
@export var audio_rain_heavy: AudioStreamPlayer
@export var audio_storm: AudioStreamPlayer
@export var audio_wind: AudioStreamPlayer
@export var world_environment: WorldEnvironment

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _cycle_timer: float = 0.0
var _forecast: Array = []
var _previous_weather: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY
var _is_forward_plus: bool = true


# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	var rendering_method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	var is_web: bool = OS.has_feature("web")
	var is_compatibility: bool = OS.has_feature("gl_compatibility") or rendering_method == "gl_compatibility" or RenderingServer.get_rendering_device() == null
	_is_forward_plus = (rendering_method == "forward_plus") and not is_web and not is_compatibility

	_setup_renderer_compatibility(is_web or is_compatibility)
	
	if date_and_time_node == null:
		var found = get_tree().root.find_child("DateAndTime", true, false)
		if found != null:
			date_and_time_node = found

	if target_node == null:
		var found_player = get_tree().root.find_child("Player", true, false)
		if found_player is Node3D:
			target_node = found_player

	ensure_shader_globals()
	_regenerate_forecast()
	if _can_simulate():
		_update_active_weather()
	else:
		clear_all_effects()
	_update_wind_globals()


## Configures particle features (sub-emitters, trails) based on whether Web / Compatibility renderer is in use.
func _setup_renderer_compatibility(is_compatibility_mode: bool) -> void:
	if is_compatibility_mode:
		# Disable sub-emitters and trails on all GPUParticles3D children to avoid Web / Compatibility warnings
		for child in find_children("*", "GPUParticles3D", true, false):
			if child is GPUParticles3D:
				child.trail_enabled = false
				child.sub_emitter = NodePath("")
				if child.process_material is ParticleProcessMaterial:
					(child.process_material as ParticleProcessMaterial).sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
		if is_instance_valid(rain_particles):
			rain_particles.trail_enabled = false
			rain_particles.sub_emitter = NodePath("")
			if rain_particles.process_material is ParticleProcessMaterial:
				(rain_particles.process_material as ParticleProcessMaterial).sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
		if is_instance_valid(rain_splash_particles):
			rain_splash_particles.trail_enabled = false
			rain_splash_particles.sub_emitter = NodePath("")
			if rain_splash_particles.process_material is ParticleProcessMaterial:
				(rain_splash_particles.process_material as ParticleProcessMaterial).sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
		if is_instance_valid(snow_particles):
			snow_particles.trail_enabled = false
			snow_particles.sub_emitter = NodePath("")
			if snow_particles.process_material is ParticleProcessMaterial:
				(snow_particles.process_material as ParticleProcessMaterial).sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
	else:
		# Forward+ and Mobile support sub-emitters. Dynamically link rain to rain_splash.
		if is_instance_valid(rain_particles) and is_instance_valid(rain_splash_particles):
			rain_particles.sub_emitter = rain_particles.get_path_to(rain_splash_particles)
			if rain_particles.process_material is ParticleProcessMaterial:
				var mat = rain_particles.process_material as ParticleProcessMaterial
				mat.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_END
				mat.sub_emitter_amount_at_end = 1



func _can_simulate() -> bool:
	if Engine.is_editor_hint():
		return is_playing and editor_weather_enabled
	return is_playing


func _update_playback_state() -> void:
	if not is_inside_tree():
		return
	if _can_simulate():
		apply_weather_effects(active_weather)
	else:
		clear_all_effects()


func _process(delta: float) -> void:
	# Check if simulation can tick
	var can_tick = _can_simulate()

	# Update altitude and center particle emitters over target node if available
	if is_instance_valid(target_node):
		current_altitude = maxf(0.0, target_node.global_position.y)
		var target_pos = target_node.global_position
		if is_instance_valid(rain_particles):
			rain_particles.global_position = Vector3(target_pos.x, target_pos.y + 12.0, target_pos.z)
		if is_instance_valid(rain_splash_particles) and rain_splash_particles.get_parent() != rain_particles:
			rain_splash_particles.global_position = Vector3(target_pos.x, target_pos.y, target_pos.z)
		if is_instance_valid(snow_particles):
			snow_particles.global_position = Vector3(target_pos.x, target_pos.y + 12.0, target_pos.z)

	_update_temperature()

	if not can_tick:
		return

	# Advance cycle timer
	_cycle_timer += delta
	if _cycle_timer >= cycle_duration_seconds:
		_cycle_timer = 0.0
		advance_cycle()


# ------------------------------------------------------------------------------
# Weather & Forecast Generation
# ------------------------------------------------------------------------------
## Returns current time in hours (from DateAndTime node if available, otherwise manual_time_of_day).
func get_current_time_hours() -> float:
	if is_instance_valid(date_and_time_node) and "current_time" in date_and_time_node:
		return float(date_and_time_node.current_time)
	return manual_time_of_day


## Returns true if current time is daylight.
func is_daylight(time_hours: float = -1.0) -> bool:
	var t = time_hours if time_hours >= 0.0 else get_current_time_hours()
	return t >= 6.0 and t < 18.0


## Calculates temperature at given altitude and time.
func calculate_temperature(time_hours: float, alt: float) -> float:
	return ClimateData.get_smooth_temperature(current_biome, alt, time_hours)


## Generates a single weather condition based on biome probability, locks, and temperature.
func generate_weather_for_time(time_hours: float) -> ClimateData.WeatherType:
	var biome_info = ClimateData.get_biome_data(current_biome)
	var is_day = is_daylight(time_hours)
	
	# Check day/night blue sky locks
	if is_day and biome_info.get("day_lock_bluesky", false):
		return ClimateData.WeatherType.BLUE_SKY
	if not is_day and biome_info.get("night_lock_bluesky", false):
		return ClimateData.WeatherType.BLUE_SKY

	var b_rate: int = biome_info.get("bluesky_rate", 60)
	var c_rate: int = biome_info.get("cloudy_rate", 20)
	var r_rate: int = biome_info.get("rain_rate", 10)
	var hr_rate: int = biome_info.get("heavy_rain_rate", 5)
	var s_rate: int = biome_info.get("storm_rate", 5)
	var total_rate: int = b_rate + c_rate + r_rate + hr_rate + s_rate
	
	if total_rate <= 0:
		return ClimateData.WeatherType.BLUE_SKY

	var roll = randi() % total_rate
	var temp = calculate_temperature(time_hours, current_altitude)
	var freezing = ClimateData.is_freezing(temp)

	# Blue sky threshold
	if roll < b_rate:
		# Check for sun-shower pattern
		var sun_shower_pat = biome_info.get("bluesky_rain_pat", 0)
		if sun_shower_pat > 0 and randf() < 0.10:
			return ClimateData.WeatherType.SNOW if freezing else ClimateData.WeatherType.RAIN
		return ClimateData.WeatherType.BLUE_SKY

	roll -= b_rate
	# Cloudy threshold
	if roll < c_rate:
		return ClimateData.WeatherType.CLOUDY

	roll -= c_rate
	# Rain threshold
	if roll < r_rate:
		return ClimateData.WeatherType.SNOW if freezing else ClimateData.WeatherType.RAIN

	roll -= r_rate
	# Heavy rain threshold
	if roll < hr_rate:
		return ClimateData.WeatherType.HEAVY_SNOW if freezing else ClimateData.WeatherType.HEAVY_RAIN

	# Storm threshold (thunderstorms stay storm or heavy snow in subzero)
	return ClimateData.WeatherType.HEAVY_SNOW if freezing else ClimateData.WeatherType.STORM


## Rebuilds the entire upcoming forecast queue.
func _regenerate_forecast() -> void:
	_forecast.clear()
	var current_t = get_current_time_hours()
	var hours_per_cycle = (cycle_duration_seconds / 3600.0)
	
	for i in range(forecast_length):
		var cycle_time = fmod(current_t + (i * hours_per_cycle * 24.0), 24.0)
		_forecast.append(generate_weather_for_time(cycle_time))

	emit_signal("forecast_updated", _forecast.duplicate())
	_update_active_weather()


## Advances simulation by one cycle.
func advance_cycle() -> void:
	if _forecast.is_empty():
		_regenerate_forecast()
		return

	_forecast.pop_front()
	
	var current_t = get_current_time_hours()
	var hours_per_cycle = (cycle_duration_seconds / 3600.0)
	var future_time = fmod(current_t + ((forecast_length - 1) * hours_per_cycle * 24.0), 24.0)
	_forecast.append(generate_weather_for_time(future_time))

	emit_signal("forecast_updated", _forecast.duplicate())
	emit_signal("cycle_advanced", _forecast[0])
	_update_active_weather()


# ------------------------------------------------------------------------------
# State & FX Application
# ------------------------------------------------------------------------------
func _update_temperature() -> void:
	var old_temp = current_temperature
	current_temperature = calculate_temperature(get_current_time_hours(), current_altitude)
	if not is_equal_approx(old_temp, current_temperature):
		emit_signal("temperature_changed", current_temperature)


func _update_temperature_and_weather() -> void:
	_update_temperature()
	_update_active_weather()
	_update_wind_globals()


func _update_active_weather() -> void:
	var target_weather: ClimateData.WeatherType
	if force_weather:
		target_weather = manual_weather
	else:
		if _forecast.is_empty():
			_regenerate_forecast()
		target_weather = _forecast[0] if not _forecast.is_empty() else ClimateData.WeatherType.BLUE_SKY

	if active_weather != target_weather or _previous_weather != target_weather:
		var old = active_weather
		active_weather = target_weather
		_previous_weather = target_weather
		apply_weather_effects(active_weather)
		emit_signal("weather_changed", active_weather, old)


## Updates global shader parameters for wind and precipitation.
func _update_wind_globals() -> void:
	var biome_info = ClimateData.get_biome_data(current_biome)
	var base_power: float = biome_info.get("wind_power", 7.5)
	
	# Weather modifier on wind
	var weather_mult = 1.0
	match active_weather:
		ClimateData.WeatherType.BLUE_SKY: weather_mult = 0.8
		ClimateData.WeatherType.CLOUDY: weather_mult = 1.0
		ClimateData.WeatherType.RAIN: weather_mult = 1.2
		ClimateData.WeatherType.HEAVY_RAIN: weather_mult = 1.6
		ClimateData.WeatherType.STORM: weather_mult = 2.2
		ClimateData.WeatherType.SNOW: weather_mult = 0.9
		ClimateData.WeatherType.HEAVY_SNOW: weather_mult = 1.8
		
	var final_strength = base_power * weather_mult * wind_strength_multiplier
	emit_signal("wind_changed", final_strength, wind_direction)
	
	if update_global_shader_variables:
		ensure_shader_globals()
		var precip_val = 0.0
		match active_weather:
			ClimateData.WeatherType.RAIN, ClimateData.WeatherType.SNOW: precip_val = 0.5
			ClimateData.WeatherType.HEAVY_RAIN, ClimateData.WeatherType.HEAVY_SNOW: precip_val = 1.0
			ClimateData.WeatherType.STORM: precip_val = 1.2
			
		RenderingServer.global_shader_parameter_set(&"weather_wind_strength", final_strength)
		RenderingServer.global_shader_parameter_set(&"weather_wind_direction", wind_direction)
		RenderingServer.global_shader_parameter_set(&"weather_precipitation_strength", precip_val)


static var _globals_checked: bool = false

## Verifies that required shader globals exist in ProjectSettings.
static func ensure_shader_globals() -> void:
	if _globals_checked:
		return
	_globals_checked = true
	var required_globals: Array[String] = [
		"weather_wind_strength",
		"weather_wind_direction",
		"weather_precipitation_strength"
	]
	var missing: Array[String] = []
	for param in required_globals:
		if not ProjectSettings.has_setting("shader_globals/" + param):
			missing.append(param)

	if not missing.is_empty():
		push_error("WeatherFX: Missing global shader parameter(s) in Project Settings: %s. Please add them under Project Settings -> Shader Globals or enable the WeatherFX plugin." % [", ".join(missing)])


## Applies visual and audio effects for the given weather type.
func apply_weather_effects(weather_type: ClimateData.WeatherType) -> void:
	clear_all_effects()

	if not _can_simulate():
		return

	match weather_type:
		ClimateData.WeatherType.BLUE_SKY:
			pass
		ClimateData.WeatherType.CLOUDY:
			_apply_fog(false, 0.005)
		ClimateData.WeatherType.RAIN:
			_apply_rain(1000)
			_play_audio(audio_rain_light)
			_apply_fog(true, 0.01)
		ClimateData.WeatherType.HEAVY_RAIN:
			_apply_rain(2500)
			_play_audio(audio_rain_heavy)
			_apply_fog(true, 0.02)
		ClimateData.WeatherType.STORM:
			_apply_rain(3500)
			_play_audio(audio_storm if audio_storm else audio_rain_heavy)
			_play_audio(audio_wind)
			_apply_fog(true, 0.03)
		ClimateData.WeatherType.SNOW:
			_apply_snow(3000, -1.0)
			_apply_fog(true, 0.01)
		ClimateData.WeatherType.HEAVY_SNOW:
			_apply_snow(8000, -2.5)
			_play_audio(audio_wind)
			_apply_fog(true, 0.03)


## Stops all weather particle and audio effects.
func clear_all_effects() -> void:
	if is_instance_valid(rain_particles):
		rain_particles.emitting = false
	if is_instance_valid(rain_splash_particles):
		rain_splash_particles.emitting = false
	if is_instance_valid(snow_particles):
		snow_particles.emitting = false
		
	if is_instance_valid(audio_rain_light): audio_rain_light.stop()
	if is_instance_valid(audio_rain_heavy): audio_rain_heavy.stop()
	if is_instance_valid(audio_storm): audio_storm.stop()
	if is_instance_valid(audio_wind): audio_wind.stop()
	
	if is_instance_valid(world_environment) and world_environment.environment:
		world_environment.environment.fog_enabled = false
		world_environment.environment.volumetric_fog_enabled = false


func _apply_rain(amount: int) -> void:
	if is_instance_valid(rain_particles):
		rain_particles.amount = amount
		rain_particles.emitting = true
	if is_instance_valid(rain_splash_particles):
		rain_splash_particles.amount = int(amount * 1.5)
		rain_splash_particles.emitting = true


func _apply_snow(amount: int, gravity_y: float) -> void:
	if is_instance_valid(snow_particles):
		snow_particles.amount = amount
		if snow_particles.process_material is ParticleProcessMaterial:
			(snow_particles.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, gravity_y, 0.0)
		snow_particles.emitting = true


func _apply_fog(volumetric: bool, density: float) -> void:
	if is_instance_valid(world_environment) and world_environment.environment:
		world_environment.environment.fog_enabled = true
		world_environment.environment.fog_density = density
		if _is_forward_plus and volumetric:
			world_environment.environment.volumetric_fog_enabled = true
			world_environment.environment.volumetric_fog_density = density * 0.5


func _play_audio(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player) and not player.playing:
		player.play()


func _on_external_time_changed(_time: float) -> void:
	_update_temperature_and_weather()


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------
## Starts/resumes the weather cycle progression.
func play() -> void:
	is_playing = true


## Pauses the weather cycle progression.
func pause() -> void:
	is_playing = false


## Toggles play/pause state.
func toggle_pause() -> void:
	is_playing = not is_playing


## Sets active climate biome.
func set_biome(zone: ClimateData.BiomeZone) -> void:
	current_biome = zone


## Overrides weather directly.
func set_weather(weather_type: ClimateData.WeatherType) -> void:
	force_weather = true
	manual_weather = weather_type


## Clears manual weather override and resumes procedural forecast.
func resume_forecast() -> void:
	force_weather = false
	_update_active_weather()


## Returns duplicate array of upcoming forecast.
func get_forecast() -> Array:
	return _forecast.duplicate()


## Returns active weather enum.
func get_current_weather() -> ClimateData.WeatherType:
	return active_weather


## Returns current cycle progress fraction between 0.0 and 1.0.
func get_cycle_progress() -> float:
	if cycle_duration_seconds <= 0.001:
		return 0.0
	return clampf(_cycle_timer / cycle_duration_seconds, 0.0, 1.0)


## Returns elapsed seconds in current weather cycle.
func get_cycle_timer() -> float:
	return _cycle_timer
