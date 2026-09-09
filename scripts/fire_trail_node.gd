# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

class_name FireTrailNode
extends Node3D

## A trailing wildfire node that spawns as a small flame, GROWS into burning ground flames,
## roars at PEAK, then BURNS OUT cleanly and frees itself. The life cycle is a Tween.
## Thermal updraft wind streaks only render while the player (or camera) is within
## updraft_vfx_trigger_distance.

@export var grow_time: float = 0.8
@export var peak_time: float = 2.8
@export var decay_time: float = 1.4
@export var max_flame_scale: float = 1.3
@export var updraft_vfx_trigger_distance: float = 5.0
@export var weather_fx: WeatherFX

@onready var _flame_vfx: GPUParticles3D = $FlameVFX
@onready var _updraft_vfx: Node3D = $UpdraftVFX
@onready var _light: OmniLight3D = $OmniLight3D
@onready var _updraft_area: Area3D = $ThermalUpdraftArea
@onready var _audio: AudioStreamPlayer3D = $AudioCrackle

var _is_extinguished: bool = false
var _player: Node3D
var _life: Tween


func _ready() -> void:
	_player = WeatherFX.find_player(get_tree())
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.weather_changed.connect(_on_weather_changed)
		_on_weather_changed(weather_fx.active_weather, weather_fx.active_weather)
	_apply_scale_intensity(0.2)
	_life = create_tween()
	_life.tween_method(_apply_scale_intensity, 0.2, 1.0, grow_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_life.tween_method(_apply_peak_flicker, 0.0, peak_time, peak_time)
	_life.tween_method(_apply_scale_intensity, 1.0, 0.0, decay_time)
	_life.tween_callback(extinguish)


## Proximity culling of the updraft VFX (continuous while burning).
func _process(_delta: float) -> void:
	var reference: Node3D = _player if is_instance_valid(_player) else get_viewport().get_camera_3d()
	var should_show: bool = is_instance_valid(reference) and global_position.distance_to(reference.global_position) <= updraft_vfx_trigger_distance
	if _updraft_vfx.visible == should_show:
		return
	_updraft_vfx.visible = should_show
	for particles: GPUParticles3D in _updraft_vfx.find_children("*", "GPUParticles3D", true, false):
		particles.emitting = should_show


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	if ClimateData.get_precipitation_strength(new_weather) > 0.4:
		extinguish()


func _apply_peak_flicker(t: float) -> void:
	_apply_scale_intensity(1.0 + sin(t * 8.0 + position.x * 3.0) * 0.06)


func _apply_scale_intensity(intensity: float) -> void:
	var s: float = clampf(intensity, 0.0, 1.2) * max_flame_scale
	_flame_vfx.scale = Vector3(s, s * 1.1, s)
	_light.light_energy = 1.8 * intensity
	_light.omni_range = 4.5 * maxf(0.2, intensity)


## Stops the fire, drops the updraft (leaving its groups so it can never grant ghost lift)
## and frees the node once the particles have dissipated.
func extinguish() -> void:
	if _is_extinguished:
		return
	_is_extinguished = true
	set_process(false)
	if _life:
		_life.kill()
	_updraft_area.set_deferred(&"monitoring", false) # may run inside an Area3D signal (e.g. WeatherZone body_entered)
	_updraft_area.set_deferred(&"monitorable", false)
	_updraft_area.remove_from_group(&"Updraft")
	_updraft_area.remove_from_group(&"Thermal")
	_updraft_vfx.visible = false
	for particles: GPUParticles3D in _updraft_vfx.find_children("*", "GPUParticles3D", true, false):
		particles.emitting = false
	_flame_vfx.emitting = false
	_light.visible = false
	_audio.stop()
	get_tree().create_timer(1.2).timeout.connect(queue_free)
