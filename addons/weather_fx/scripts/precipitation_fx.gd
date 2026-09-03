# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name PrecipitationFX
extends Node3D

## Rain, splash and snow particle systems driven by WeatherFX signals.
## Follows weather_fx.target_node and slants trajectories with the last received wind.

const RAIN_AMOUNT: Dictionary = {
	ClimateData.WeatherType.RAIN: 1000,
	ClimateData.WeatherType.HEAVY_RAIN: 2500,
	ClimateData.WeatherType.STORM: 3500,
}
const SNOW_AMOUNT: Dictionary = {
	ClimateData.WeatherType.SNOW: 3000,
	ClimateData.WeatherType.HEAVY_SNOW: 8000,
}

@export var weather_fx: WeatherFX
@export var rain_particles: GPUParticles3D
@export var rain_splash_particles: GPUParticles3D
@export var snow_particles: GPUParticles3D

var _weather: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY
var _active: bool = false
var _wind_strength: float = 0.0
var _wind_direction: Vector3 = Vector3.RIGHT


func _ready() -> void:
	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	_setup_renderer_compatibility(OS.has_feature("web") or OS.has_feature("gl_compatibility") or renderer == "gl_compatibility" or RenderingServer.get_rendering_device() == null)
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if not is_instance_valid(weather_fx):
		return
	weather_fx.weather_changed.connect(_on_weather_changed)
	weather_fx.wind_changed.connect(_on_wind_changed)
	weather_fx.playback_changed.connect(_on_playback_changed)
	_weather = weather_fx.active_weather
	_active = weather_fx.is_simulating()
	_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)


func _process(_delta: float) -> void:
	if not (is_instance_valid(rain_particles) and is_instance_valid(rain_splash_particles) and is_instance_valid(snow_particles)):
		return
	if not is_instance_valid(weather_fx) or not is_instance_valid(weather_fx.target_node) or not weather_fx.target_node.is_inside_tree():
		return
	var pos: Vector3 = weather_fx.target_node.global_position
	var wind_offset: Vector3 = -_wind_direction * _wind_strength * 0.22
	rain_particles.global_position = Vector3(pos.x + wind_offset.x, pos.y + 12.0, pos.z + wind_offset.z)
	# Splash ripples always sit on the actual ground elevation, never floating in mid-air
	rain_splash_particles.global_position = Vector3(pos.x, _find_ground_y(pos) + 0.02, pos.z)
	snow_particles.global_position = Vector3(pos.x + wind_offset.x * 1.5, pos.y + 12.0, pos.z + wind_offset.z * 1.5)


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_weather = new_weather
	_apply()


func _on_playback_changed(active: bool) -> void:
	_active = active
	_apply()


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	_wind_strength = strength
	_wind_direction = direction.normalized() if not direction.is_zero_approx() else Vector3.RIGHT
	_apply()


func _apply() -> void:
	if not (is_instance_valid(rain_particles) and is_instance_valid(rain_splash_particles) and is_instance_valid(snow_particles)):
		return
	var rain_amount: int = RAIN_AMOUNT.get(_weather, 0) if _active else 0
	var snow_amount: int = SNOW_AMOUNT.get(_weather, 0) if _active else 0
	if rain_amount > 0 and rain_particles.amount != rain_amount:
		rain_particles.amount = rain_amount
		rain_splash_particles.amount = int(rain_amount * 1.5)
	if snow_amount > 0 and snow_particles.amount != snow_amount:
		snow_particles.amount = snow_amount
	rain_particles.emitting = rain_amount > 0
	rain_splash_particles.emitting = rain_amount > 0
	snow_particles.emitting = snow_amount > 0
	set_process(rain_amount > 0 or snow_amount > 0)

	# Rain: slant velocity along the wind and align the drop mesh with its trajectory
	var rain_mat: ParticleProcessMaterial = rain_particles.process_material as ParticleProcessMaterial
	if rain_mat:
		var fall_vel: Vector3 = Vector3(0.0, -24.0, 0.0) + _wind_direction * (_wind_strength * 0.75)
		rain_mat.particle_flag_align_y = true
		rain_mat.direction = fall_vel.normalized()
		rain_mat.spread = 2.0
		rain_mat.initial_velocity_min = fall_vel.length() * 0.95
		rain_mat.initial_velocity_max = fall_vel.length() * 1.05
		rain_mat.gravity = Vector3(0.0, -9.8, 0.0)
	# Splash: slight downwind spray drift
	var splash_mat: ParticleProcessMaterial = rain_splash_particles.process_material as ParticleProcessMaterial
	if splash_mat:
		splash_mat.gravity = Vector3(_wind_direction.x * _wind_strength * 0.35, -9.8, _wind_direction.z * _wind_strength * 0.35)
	# Snow: lightweight atmospheric drift and swirling turbulence
	var snow_mat: ParticleProcessMaterial = snow_particles.process_material as ParticleProcessMaterial
	if snow_mat:
		snow_mat.direction = (Vector3(0.0, -1.8, 0.0) + _wind_direction * (_wind_strength * 0.7)).normalized()
		snow_mat.gravity = Vector3(_wind_direction.x * _wind_strength * 1.2, -1.5 - _wind_strength * 0.1, _wind_direction.z * _wind_strength * 1.2)
		snow_mat.initial_velocity_min = 1.2 + _wind_strength * 0.3
		snow_mat.initial_velocity_max = 3.0 + _wind_strength * 0.7
		snow_mat.turbulence_enabled = true
		snow_mat.turbulence_noise_strength = 0.6 + 1.8 * clampf(_wind_strength / 8.0, 0.0, 2.0)
		snow_mat.turbulence_noise_scale = 1.0


## Disables sub-emitters and trails on Web / Compatibility renderers, links rain to its splash sub-emitter otherwise.
func _setup_renderer_compatibility(is_compatibility_mode: bool) -> void:
	if not (is_instance_valid(rain_particles) and is_instance_valid(rain_splash_particles) and is_instance_valid(snow_particles)):
		return
	if is_compatibility_mode:
		for particles: GPUParticles3D in [rain_particles, rain_splash_particles, snow_particles]:
			particles.trail_enabled = false
	rain_particles.sub_emitter = NodePath("") if is_compatibility_mode else rain_particles.get_path_to(rain_splash_particles)
	var rain_mat: ParticleProcessMaterial = rain_particles.process_material as ParticleProcessMaterial
	if rain_mat:
		rain_mat.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED if is_compatibility_mode else ParticleProcessMaterial.SUB_EMITTER_AT_END
		rain_mat.sub_emitter_amount_at_end = 1


## Queries the physics world below the given position to find the ground elevation.
func _find_ground_y(origin: Vector3) -> float:
	var world3d: World3D = get_world_3d()
	if world3d == null or world3d.direct_space_state == null:
		return origin.y
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin + Vector3(0.0, 15.0, 0.0), origin - Vector3(0.0, 120.0, 0.0))
	var result: Dictionary = world3d.direct_space_state.intersect_ray(query)
	return (result["position"] as Vector3).y if result.has("position") else 0.0
