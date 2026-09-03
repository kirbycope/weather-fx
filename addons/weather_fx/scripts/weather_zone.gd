# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
@icon("res://addons/weather_fx/assets/icons/weather_zone_icon.svg")
class_name WeatherZone
extends Area3D

## WeatherZone defines a spatial region in 3D that automatically transitions
## the WeatherFX system to this biome when the target (Player) enters.

signal zone_entered(zone_name: String, biome: ClimateData.BiomeZone)
signal zone_exited(zone_name: String, biome: ClimateData.BiomeZone)

@export var biome: ClimateData.BiomeZone = ClimateData.BiomeZone.TEMPERATE_PLAINS
## Falls back to the first node in the "WeatherFX" group when unset.
@export var weather_fx: WeatherFX


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX


func _on_body_entered(body: Node3D) -> void:
	if not _is_target_player(body):
		return
	if is_instance_valid(weather_fx):
		weather_fx.current_biome = biome
	zone_entered.emit(ClimateData.get_biome_name(biome), biome)


func _on_body_exited(body: Node3D) -> void:
	if _is_target_player(body):
		zone_exited.emit(ClimateData.get_biome_name(biome), biome)


func _is_target_player(body: Node3D) -> bool:
	if is_instance_valid(weather_fx) and is_instance_valid(weather_fx.target_node):
		return body == weather_fx.target_node
	return WeatherFX.is_player_node(body)
