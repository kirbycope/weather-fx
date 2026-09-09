# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

class_name FireFX
extends Node3D

## Stylized campfire / torch effects: smoke and spark drift follow the wind reported by
## WeatherFX.wind_changed, and the light flickers with a warm breathing pattern.

@export var weather_fx: WeatherFX

@export_group("Particle & Light Bindings")
@export var smoke_particles: GPUParticles3D
@export var spark_particles: GPUParticles3D
@export var fire_light: OmniLight3D

@export_group("Wind Drift Parameters")
@export var base_smoke_ascent: float = 1.8
@export var wind_smoke_drift: float = 0.25
@export var base_spark_ascent: float = 3.2
@export var wind_spark_drift: float = 0.45
@export var enable_light_flicker: bool = true

var _wind_strength: float = 0.0
var _wind_direction: Vector3 = Vector3.RIGHT


func _ready() -> void:
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if not is_instance_valid(weather_fx):
		return
	weather_fx.wind_changed.connect(_on_wind_changed)
	_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	_wind_strength = strength
	_wind_direction = direction.normalized() if not direction.is_zero_approx() else Vector3.RIGHT
	var smoke_mat: ParticleProcessMaterial = smoke_particles.process_material as ParticleProcessMaterial if is_instance_valid(smoke_particles) else null
	if smoke_mat:
		smoke_mat.turbulence_noise_strength = 0.05 + 0.12 * clampf(strength / 8.0, 0.0, 1.0)


func _process(delta: float) -> void:
	var weight: float = clampf(delta * 4.0, 0.0, 1.0)
	# Smoke: natural gentle plume leaning downwind
	var smoke_mat: ParticleProcessMaterial = smoke_particles.process_material as ParticleProcessMaterial if is_instance_valid(smoke_particles) else null
	if smoke_mat:
		smoke_mat.gravity = smoke_mat.gravity.lerp(Vector3(0.0, base_smoke_ascent, 0.0) + _wind_direction * (_wind_strength * wind_smoke_drift), weight)
	# Sparks
	var spark_mat: ParticleProcessMaterial = spark_particles.process_material as ParticleProcessMaterial if is_instance_valid(spark_particles) else null
	if spark_mat:
		spark_mat.gravity = spark_mat.gravity.lerp(Vector3(0.0, base_spark_ascent, 0.0) + _wind_direction * (_wind_strength * wind_spark_drift), weight)
	# Dynamic campfire light flicker (smooth warm breathing)
	if enable_light_flicker and is_instance_valid(fire_light):
		var t: float = Time.get_ticks_msec() * 0.008
		var flicker: float = sin(t * 3.5) * 0.12 + sin(t * 7.1) * 0.06 + sin(t * 13.7) * 0.04
		fire_light.light_energy = maxf(0.8, 2.0 + flicker * (1.0 + clampf(_wind_strength * 0.08, 0.0, 1.0)))
