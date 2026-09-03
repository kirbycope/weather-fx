# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name BurnableGrass
extends Node3D

## Interactive, wind-reactive burnable grass patch. When ignited it burns with glowing embers,
## spreads downwind following BotW/TotK fire propagation physics, douses in rain, and drives a
## vertical thermal updraft that launches paragliders skyward.
## Node wiring (HitboxArea signals, BurnTimer, SpreadTimer) lives in burnable_grass.tscn.

signal ignited()
signal extinguished()
signal burned_out()

@export_group("Fire & Burning State")
@export var is_burning: bool = false:
	set(val):
		if is_burning != val:
			is_burning = val
			if is_inside_tree():
				_update_burn_state()

@export var auto_ignite: bool = false ## If true, ignites immediately on ready (useful for testing updrafts).
@export var burn_duration: float = 20.0 ## Time in seconds before burning out (0.0 = burns indefinitely).
@export var is_charred: bool = false ## State after fire consumes the grass into ash.
@export var current_burn_progress: float = 0.0 ## 0.0 (healthy) -> 0.5 (burning) -> 1.0 (charred ash).

@export_group("Thermal Updraft")
@export var enable_thermal_updraft: bool = true ## Activates the ThermalUpdraftArea lift column while burning.

@export_group("Wind-Driven Fire Propagation")
@export var enable_fire_spread: bool = true ## Propagates fire to neighboring grass along the wind vector.
@export var spread_radius: float = 4.5 ## Base isotropic spread radius in meters.
@export var spread_interval: float = 2.5 ## Interval between fire spread propagation checks.
@export var wind_spread_multiplier: float = 0.35 ## Speed and range boost along the active wind vector.
@export var rain_extinguish_enabled: bool = true ## Automatically douses fire during rain or storm.

@export_group("Interaction & Visuals")
@export var enable_interaction: bool = true
## Input action that ignites / extinguishes the patch while the player stands in the hitbox.
@export var ignite_action: StringName = &"action"
@export var grass_scale: Vector3 = Vector3.ONE
@export var custom_grass_material: Material
@export var weather_fx: WeatherFX

@onready var _grass_mesh: MeshInstance3D = $GrassMesh
@onready var _fire_vfx: Node3D = $FireVFX
@onready var _updraft_vfx: Node3D = $UpdraftVFX
@onready var _updraft_area: Area3D = $ThermalUpdraftArea
@onready var _audio: AudioStreamPlayer3D = $FireAudio
@onready var _burn_timer: Timer = $BurnTimer
@onready var _spread_timer: Timer = $SpreadTimer
## Optional project-specific prompt node shown while the player stands in the hitbox.
@onready var _action_prompt: Node3D = get_node_or_null(^"ActionPrompt")

var _player_nearby: bool = false
var _wind_strength: float = WeatherFX.active_wind_strength
var _wind_direction: Vector3 = WeatherFX.active_wind_direction
var _is_raining: bool = WeatherFX.active_precipitation_strength > 0.4


func _ready() -> void:
	# Per-instance material so burn_progress does not leak to sibling patches
	var mat: Material = custom_grass_material if custom_grass_material else _grass_mesh.material_override
	if mat:
		_grass_mesh.material_override = mat.duplicate()
	if Engine.is_editor_hint():
		_update_burn_state()
		return
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.wind_changed.connect(_on_wind_changed)
		weather_fx.weather_changed.connect(_on_weather_changed)
		_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)
		_is_raining = weather_fx.is_simulating() and ClimateData.get_precipitation_strength(weather_fx.active_weather) > 0.4
	if auto_ignite:
		ignite()
	else:
		_update_burn_state()


## Only runs while burning with a finite burn_duration: animates the charring shader parameter.
func _process(_delta: float) -> void:
	current_burn_progress = 1.0 - _burn_timer.time_left / burn_duration
	_update_shader_burn_progress()


func _unhandled_input(event: InputEvent) -> void:
	if not enable_interaction or not _player_nearby or is_charred or not InputMap.has_action(ignite_action):
		return
	if event.is_action_pressed(ignite_action) and not event.is_echo():
		if is_burning:
			extinguish()
		else:
			ignite()
		get_viewport().set_input_as_handled()


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	_wind_strength = strength
	_wind_direction = direction


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_is_raining = ClimateData.get_precipitation_strength(new_weather) > 0.4
	if rain_extinguish_enabled and _is_raining:
		extinguish()


## Ignites this grass patch, activates the thermal updraft and hands field-wide creeping
## propagation to the first overlapping GrassField so there is a single creeper engine.
func ignite() -> void:
	if is_burning or is_charred or (rain_extinguish_enabled and _is_raining):
		return
	current_burn_progress = 0.1
	is_burning = true
	for field: Node in get_tree().get_nodes_in_group(&"GrassField"):
		if field is GrassField and (field as GrassField).ignite_at(global_position, spread_radius, burn_duration if burn_duration > 0.0 else 6.0):
			break
	ignited.emit()


## Extinguishes the fire safely.
func extinguish() -> void:
	if not is_burning:
		return
	current_burn_progress = 0.0
	is_burning = false
	extinguished.emit()


## Triggered when grass has burned for full duration into charred ash.
func burn_out() -> void:
	is_charred = true
	current_burn_progress = 1.0
	is_burning = false
	_update_burn_state()
	burned_out.emit()


## Propagates fire to neighboring BurnableGrass patches along the active wind vector
## (BotW/TotK gold-standard directional wildfire propagation). Driven by SpreadTimer.
func spread_to_neighbors() -> void:
	if not is_inside_tree():
		return
	var h_wind: Vector2 = Vector2(_wind_direction.x, _wind_direction.z)
	var has_wind: bool = h_wind.length_squared() > 0.001
	if has_wind:
		h_wind = h_wind.normalized()
	for node: Node in get_tree().get_nodes_in_group(&"BurnableGrass"):
		var other: BurnableGrass = node as BurnableGrass
		if other == null or other == self or other.is_burning or other.is_charred:
			continue
		var delta_pos: Vector3 = other.global_position - global_position
		var h_delta: Vector2 = Vector2(delta_pos.x, delta_pos.z)
		var dist: float = h_delta.length()
		if dist < 0.001:
			continue
		var wind_align: float = (h_delta / dist).dot(h_wind) if has_wind else 0.0
		# BotW decomp standard: downwind fire propagation boost, upwind suppression
		if dist <= spread_radius * WeatherFX.get_wind_spread_factor(wind_align, _wind_strength, wind_spread_multiplier):
			other.ignite()


func _update_shader_burn_progress() -> void:
	var shader_mat: ShaderMaterial = _grass_mesh.material_override as ShaderMaterial
	if shader_mat:
		shader_mat.set_shader_parameter(&"burn_progress", current_burn_progress)


func _update_burn_state() -> void:
	var updraft_on: bool = is_burning and enable_thermal_updraft
	_fire_vfx.visible = is_burning
	for particles: GPUParticles3D in _fire_vfx.find_children("*", "GPUParticles3D", true, false):
		particles.emitting = is_burning
	_updraft_vfx.visible = updraft_on
	for particles: GPUParticles3D in _updraft_vfx.find_children("*", "GPUParticles3D", true, false):
		particles.emitting = updraft_on
	_updraft_area.set_deferred(&"monitoring", updraft_on) # may run inside an Area3D signal (e.g. HitboxArea or WeatherZone)
	_updraft_area.set_deferred(&"monitorable", updraft_on)
	if _audio.playing != is_burning:
		_audio.playing = is_burning
	if is_instance_valid(_action_prompt):
		_action_prompt.visible = _player_nearby and enable_interaction and not is_charred
		_action_prompt.set(&"message_end", "to extinguish fire" if is_burning else "to ignite grass")
	_grass_mesh.scale = grass_scale * (0.6 if is_charred else 1.5)
	if is_burning:
		if burn_duration > 0.0 and _burn_timer.is_stopped():
			_burn_timer.start(burn_duration)
		if enable_fire_spread and _spread_timer.is_stopped():
			_spread_timer.start(spread_interval)
		if burn_duration <= 0.0:
			current_burn_progress = 0.5
	else:
		_burn_timer.stop()
		_spread_timer.stop()
	set_process(is_burning and burn_duration > 0.0)
	_update_shader_burn_progress()


func _on_body_entered(body: Node3D) -> void:
	if WeatherFX.is_player_node(body):
		_player_nearby = true
		if is_instance_valid(_action_prompt):
			_action_prompt.visible = enable_interaction and not is_charred


func _on_body_exited(body: Node3D) -> void:
	if WeatherFX.is_player_node(body):
		_player_nearby = false
		if is_instance_valid(_action_prompt):
			_action_prompt.hide()


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group(&"Fire"):
		ignite()
