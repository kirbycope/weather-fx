# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
@icon("res://addons/weather_fx/assets/icons/weather_zone_icon.svg")
class_name WeatherZone
extends Area3D

## WeatherZone defines a spatial region in 3D that automatically transitions
## the WeatherFX system to this biome when the target (Player) enters.
##
## With a WeatherFX that has a target and blends zones ([member WeatherFX.blend_zones]), the zone is weighed
## instead: [method get_weight] is 1 deep inside the zone's footprint and fades to 0 over [member blend_distance]
## from its edge, and WeatherFX makes the heaviest zone the biome while blending the climate toward the runner-up
## where zones overlap. Without that (no target, blending off), stepping in switches the biome outright as before.

signal zone_entered(zone_name: String, biome: ClimateData.BiomeZone)
signal zone_exited(zone_name: String, biome: ClimateData.BiomeZone)

@export var biome: ClimateData.BiomeZone = ClimateData.BiomeZone.TEMPERATE_PLAINS
## Falls back to the first node in the "WeatherFX" group when unset.
@export var weather_fx: WeatherFX
## Metres inside the zone's edge over which its climate fades in, for the blend; 0 keeps the whole zone at full weight.
@export_range(0.0, 100.0, 0.5, "suffix:m") var blend_distance: float = 8.0


func _enter_tree() -> void:
	add_to_group(&"WeatherZone")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX


## How much of this zone's climate applies at [param position]: 0 outside its footprint (height ignored: a zone is
## a region of the map, not a layer of the air), rising to 1 [member blend_distance] in from the nearest side. A box
## measures to its sides, a sphere or cylinder to its rim; any other shape counts full inside its bounds.
func get_weight(position: Vector3) -> float:
	var shape_node: CollisionShape3D
	for child: Node in get_children():
		if child is CollisionShape3D:
			shape_node = child
			break
	if shape_node == null or shape_node.shape == null:
		return 0.0
	var local: Vector3 = shape_node.to_local(position)
	var inside: float = -1.0 # metres in from the nearest edge, negative outside
	var shape: Shape3D = shape_node.shape
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		inside = minf(half.x - absf(local.x), half.z - absf(local.z))
	elif shape is SphereShape3D:
		inside = (shape as SphereShape3D).radius - Vector2(local.x, local.z).length()
	elif shape is CylinderShape3D:
		inside = (shape as CylinderShape3D).radius - Vector2(local.x, local.z).length()
	else:
		var bounds: AABB = shape.get_debug_mesh().get_aabb()
		inside = 1.0 if bounds.has_point(Vector3(local.x, bounds.get_center().y, local.z)) else -1.0
		return 1.0 if inside > 0.0 else 0.0
	if inside <= 0.0:
		return 0.0
	return clampf(inside / blend_distance, 0.0, 1.0) if blend_distance > 0.0 else 1.0


func _on_body_entered(body: Node3D) -> void:
	if not _is_target_player(body):
		return
	if is_instance_valid(weather_fx) and not weather_fx.is_blending_zones():
		weather_fx.current_biome = biome
	zone_entered.emit(ClimateData.get_biome_name(biome), biome)


func _on_body_exited(body: Node3D) -> void:
	if _is_target_player(body):
		zone_exited.emit(ClimateData.get_biome_name(biome), biome)


func _is_target_player(body: Node3D) -> bool:
	if is_instance_valid(weather_fx) and is_instance_valid(weather_fx.target_node):
		return body == weather_fx.target_node
	return WeatherFX.is_player_node(body)
