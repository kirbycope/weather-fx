# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name FireFX
extends Node3D

## Manages stylized campfire / torch visual effects, aligning smoke particle trajectories,
## spark physics, flame dancing, and light flicker with WeatherFX global wind physics.

# ------------------------------------------------------------------------------
# Exported Properties
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	if smoke_particles == null:
		smoke_particles = find_child("Smoke", true, false) as GPUParticles3D
	if spark_particles == null:
		spark_particles = find_child("Sparks", true, false) as GPUParticles3D
	if fire_light == null:
		fire_light = find_child("Light", true, false) as OmniLight3D


func _process(delta: float) -> void:
	var wind_strength: float = WeatherFX.get_wind_strength()
	var wind_dir: Vector3 = WeatherFX.get_wind_direction()
	if wind_dir.is_zero_approx():
		wind_dir = Vector3(1.0, 0.0, 0.0)
	else:
		wind_dir = wind_dir.normalized()

	# Update Smoke particles drift (natural gentle plume)
	if is_instance_valid(smoke_particles) and smoke_particles.process_material is ParticleProcessMaterial:
		var s_mat = smoke_particles.process_material as ParticleProcessMaterial
		var target_gravity = Vector3(0.0, base_smoke_ascent, 0.0) + wind_dir * (wind_strength * wind_smoke_drift)
		s_mat.gravity = s_mat.gravity.lerp(target_gravity, clampf(delta * 4.0, 0.0, 1.0))
		s_mat.turbulence_noise_strength = 0.05 + 0.12 * clampf(wind_strength / 8.0, 0.0, 1.0)

	# Update Sparks particles drift
	if is_instance_valid(spark_particles) and spark_particles.process_material is ParticleProcessMaterial:
		var sp_mat = spark_particles.process_material as ParticleProcessMaterial
		var target_sp_gravity = Vector3(0.0, base_spark_ascent, 0.0) + wind_dir * (wind_strength * wind_spark_drift)
		sp_mat.gravity = sp_mat.gravity.lerp(target_sp_gravity, clampf(delta * 4.0, 0.0, 1.0))

	# Dynamic campfire light flicker (smooth warm breathing)
	if enable_light_flicker and is_instance_valid(fire_light):
		var t = Time.get_ticks_msec() * 0.008
		var flicker = sin(t * 3.5) * 0.12 + sin(t * 7.1) * 0.06 + sin(t * 13.7) * 0.04
		fire_light.light_energy = maxf(0.8, 2.0 + flicker * (1.0 + clampf(wind_strength * 0.08, 0.0, 1.0)))
