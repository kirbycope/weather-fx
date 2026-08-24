# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WeatherZone
extends Area3D

## WeatherZone defines a spatial region in 3D that automatically transitions
## the WeatherFX system to this biome when the target (Player) enters.

signal zone_entered(zone_name: String, biome: ClimateData.BiomeZone)
signal zone_exited(zone_name: String, biome: ClimateData.BiomeZone)

@export var biome: ClimateData.BiomeZone = ClimateData.BiomeZone.TEMPERATE_PLAINS
@export var priority_level: int = 0
@export var weather_fx_path: NodePath = ^""

var _weather_fx: WeatherFX


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if not weather_fx_path.is_empty():
		_weather_fx = get_node_or_null(weather_fx_path) as WeatherFX
	if _weather_fx == null:
		var found = get_tree().root.find_child("WeatherFX", true, false)
		if found is WeatherFX:
			_weather_fx = found


func _on_body_entered(body: Node3D) -> void:
	if _is_target_player(body):
		if is_instance_valid(_weather_fx):
			_weather_fx.current_biome = biome
		emit_signal("zone_entered", ClimateData.get_biome_name(biome), biome)


func _on_body_exited(body: Node3D) -> void:
	if _is_target_player(body):
		emit_signal("zone_exited", ClimateData.get_biome_name(biome), biome)


func _is_target_player(body: Node3D) -> bool:
	if _weather_fx and _weather_fx.target_node:
		return body == _weather_fx.target_node
	return body.name == "Player" or body.is_in_group("player")
