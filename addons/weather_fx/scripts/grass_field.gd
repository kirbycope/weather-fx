# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name GrassField
extends MultiMeshInstance3D

## High-performance, wind-reactive grass field populated using MultiMesh.
## Instances sway via the WeatherFX global shader uniforms; wildfire creeper heads advance
## downwind using the wind cached from WeatherFX.wind_changed and douse on weather_changed.

enum GrassMeshType {
	COMMON_SHORT,
	COMMON_TALL,
	WISPY_SHORT,
	WISPY_TALL,
	CUSTOM
}

## Wildfire creeper head advancing a fire front across the field.
class CreeperHead extends RefCounted:
	var pos: Vector2
	var heading: Vector2
	var speed: float
	var max_life: float
	var angle_offset: float
	var branches_left: int
	var dist_since_drop: float
	var age: float = 0.0
	var noise_seed: float = randf() * 100.0

	func _init(p_pos: Vector2, p_heading: Vector2, p_speed: float, p_max_life: float, p_angle_offset: float, p_branches_left: int, p_dist_since_drop: float = 0.0) -> void:
		pos = p_pos
		heading = p_heading
		speed = p_speed
		max_life = p_max_life
		angle_offset = p_angle_offset
		branches_left = p_branches_left
		dist_since_drop = p_dist_since_drop


const GRASS_MESHES: Dictionary = {
	GrassMeshType.COMMON_SHORT: preload("res://addons/weather_fx/resources/mesh_grass_common_short.tres"),
	GrassMeshType.COMMON_TALL: preload("res://addons/weather_fx/resources/mesh_grass_common_tall.tres"),
	GrassMeshType.WISPY_SHORT: preload("res://addons/weather_fx/resources/mesh_grass_wispy_short.tres"),
	GrassMeshType.WISPY_TALL: preload("res://addons/weather_fx/resources/mesh_grass_wispy_tall.tres"),
}
const GRASS_MATERIAL: Material = preload("res://addons/weather_fx/resources/grass_material.tres")
const FIRE_TRAIL_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/fire_trail_node.tscn")
## BotW decomp fire front creep speed band (m/s).
const CREEP_SPEED_MIN: float = 1.2
const CREEP_SPEED_MAX: float = 1.8
## Cell size of the spatial grid used to consume grass around trail nodes.
const BUCKET_SIZE: float = 2.0
const MAX_TRAIL_NODES: int = 48
const MAX_CREEPER_HEADS: int = 8

@export var mesh_type: GrassMeshType = GrassMeshType.COMMON_SHORT:
	set(val):
		mesh_type = val
		if is_inside_tree():
			regenerate()

@export var instance_count: int = 1000:
	set(val):
		instance_count = maxi(0, val)
		if is_inside_tree():
			regenerate()

@export var field_size: Vector2 = Vector2(30.0, 30.0):
	set(val):
		field_size = val
		if is_inside_tree():
			regenerate()

@export var min_scale: float = 0.7:
	set(val):
		min_scale = maxf(0.1, val)
		if is_inside_tree():
			regenerate()

@export var max_scale: float = 1.3:
	set(val):
		max_scale = maxf(min_scale, val)
		if is_inside_tree():
			regenerate()

@export var seed_value: int = 12345:
	set(val):
		seed_value = val
		if is_inside_tree():
			regenerate()

@export var custom_mesh: Mesh:
	set(val):
		custom_mesh = val
		if is_inside_tree():
			regenerate()

@export_group("Exclusion Zones")
## Primary circular clearing radius where no grass will spawn (e.g. campfire).
@export_range(0.0, 50.0, 0.1) var exclusion_radius: float = 0.0:
	set(val):
		exclusion_radius = maxf(0.0, val)
		if is_inside_tree():
			regenerate()

## 2D center position (X, Z) in local space of primary exclusion circle.
@export var exclusion_center: Vector2 = Vector2.ZERO:
	set(val):
		exclusion_center = val
		if is_inside_tree():
			regenerate()

## Additional circular exclusion zones as Vector3(center_x, center_z, radius) for ponds, paths, etc.
@export var additional_exclusion_zones: Array[Vector3] = []:
	set(val):
		additional_exclusion_zones = val
		if is_inside_tree():
			regenerate()

@export_group("Rendering")
@export var cast_grass_shadows: bool = false:
	set(val):
		cast_grass_shadows = val
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

@export var custom_grass_material: ShaderMaterial:
	set(val):
		custom_grass_material = val
		if custom_grass_material:
			material_override = custom_grass_material

@export_group("Wildfire Physics")
@export var enable_wildfire: bool = true ## Enables wind-reactive grass fires and thermal updrafts across the field.
@export var fire_spread_speed: float = 1.5 ## Fire front creep speed in m/s, clamped to the BotW 1.2-1.8 band. Wind biases direction, not speed.
@export var weather_fx: WeatherFX

var _instance_origins: Array[Vector3] = []
var _origin_buckets: Dictionary[Vector2i, Array] = {}
var _active_fires: Array[Dictionary] = []
var _creeper_heads: Array[CreeperHead] = []
var _trail_nodes: Array[FireTrailNode] = []
var _h_wind: Vector2 = Vector2(WeatherFX.active_wind_direction.x, WeatherFX.active_wind_direction.z).normalized()


func _enter_tree() -> void:
	if Engine.is_editor_hint() and (multimesh == null or multimesh.instance_count == 0):
		regenerate()


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null or multimesh.instance_count == 0:
		regenerate()
	if Engine.is_editor_hint():
		return
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.wind_changed.connect(_on_wind_changed)
		weather_fx.weather_changed.connect(_on_weather_changed)
		_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)


func _on_wind_changed(_strength: float, direction: Vector3) -> void:
	var h_wind: Vector2 = Vector2(direction.x, direction.z)
	_h_wind = h_wind.normalized() if h_wind.length_squared() > 0.001 else Vector2.ZERO


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	if ClimateData.get_precipitation_strength(new_weather) > 0.4:
		extinguish_all_fires()


## Advances creeper heads (continuous fire front animation).
func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not enable_wildfire:
		return
	if _creeper_heads.is_empty():
		return
	var has_wind: bool = not _h_wind.is_zero_approx()
	for h_idx: int in range(_creeper_heads.size() - 1, -1, -1):
		var head: CreeperHead = _creeper_heads[h_idx]
		head.age += delta
		if head.age >= head.max_life or _trail_nodes.size() >= MAX_TRAIL_NODES:
			_creeper_heads.remove_at(h_idx)
			continue
		# Wind bias with organic meandering
		if has_wind:
			var target_heading: Vector2 = _h_wind.rotated(head.angle_offset + sin(head.age * 3.5 + head.noise_seed) * 0.35)
			head.heading = head.heading.slerp(target_heading, delta * 3.0).normalized()
		else:
			head.heading = head.heading.rotated(sin(head.age * 2.0 + head.noise_seed) * delta * 0.8).normalized()
		var move_dist: float = head.speed * delta
		head.pos += head.heading * move_dist
		head.dist_since_drop += move_dist
		var local_p: Vector3 = to_local(Vector3(head.pos.x, 0.0, head.pos.y))
		if absf(local_p.x) > field_size.x * 0.5 or absf(local_p.z) > field_size.y * 0.5:
			_creeper_heads.remove_at(h_idx)
			continue
		# Drop connected FireTrailNodes along the path (0.35m spacing for seamless overlap)
		if head.dist_since_drop >= 0.35:
			head.dist_since_drop = 0.0
			_drop_trail_node(local_p, Vector3(head.pos.x, 0.0, head.pos.y))
			# Occasional lateral branch (trail split / combining)
			if head.branches_left > 0 and head.age > 0.8 and randf() < delta * 1.2:
				head.branches_left -= 1
				_spawn_branch_head(head.pos, head.heading, -head.angle_offset)


func _drop_trail_node(local_pos: Vector3, world_pos: Vector3) -> FireTrailNode:
	var node: FireTrailNode = FIRE_TRAIL_SCENE.instantiate() as FireTrailNode
	node.weather_fx = weather_fx
	node.position = local_pos
	add_child(node)
	_trail_nodes.append(node)
	node.tree_exiting.connect(_trail_nodes.erase.bind(node)) # Drop the reference before the node is freed
	_consume_grass_in_radius(world_pos, 1.2)
	return node


func _spawn_branch_head(pos_2d: Vector2, parent_heading: Vector2, angle_offset: float) -> void:
	if _creeper_heads.size() >= MAX_CREEPER_HEADS:
		return
	var speed: float = clampf(fire_spread_speed * randf_range(0.75, 0.95), CREEP_SPEED_MIN, CREEP_SPEED_MAX)
	_creeper_heads.append(CreeperHead.new(pos_2d, parent_heading.rotated(angle_offset).normalized(), speed, randf_range(3.5, 5.5), angle_offset, 0))


## Ignites a trailing, spreading wildfire on this grass field. Returns false when the point is off-field.
func ignite_at(world_pos: Vector3, initial_radius: float = 2.0, duration: float = 6.0) -> bool:
	if not enable_wildfire:
		return false
	var local_p: Vector3 = to_local(world_pos)
	if absf(local_p.x) > field_size.x * 0.5 + 2.0 or absf(local_p.z) > field_size.y * 0.5 + 2.0:
		return false
	var initial_node: FireTrailNode = _drop_trail_node(local_p, world_pos)

	# Spawn trailing creeper heads biased downwind (or a symmetric fan without wind)
	var has_wind: bool = not _h_wind.is_zero_approx()
	var base_dir: Vector2 = _h_wind if has_wind else Vector2.RIGHT
	var pos_2d: Vector2 = Vector2(world_pos.x, world_pos.z)
	var angle_spreads: Array[float] = [-0.4, 0.0, 0.4]
	if not has_wind:
		angle_spreads = [0.0, 2.1, 4.2]
	for offset_angle: float in angle_spreads:
		var head_dir: Vector2 = base_dir.rotated(offset_angle).normalized()
		var speed: float = clampf(fire_spread_speed * randf_range(0.9, 1.1), CREEP_SPEED_MIN, CREEP_SPEED_MAX)
		_creeper_heads.append(CreeperHead.new(pos_2d + head_dir * 0.3, head_dir, speed, duration, offset_angle, 2, 0.3))

	# Compatibility record for tests
	_active_fires.append({
		"origin": world_pos,
		"current_pos": world_pos,
		"radius": initial_radius,
		"age": 0.0,
		"duration": duration,
		"patch_node": initial_node,
		"updraft_area": initial_node.get_node_or_null(^"ThermalUpdraftArea"),
		"vfx_node": initial_node,
	})
	return true


## Flattens grass instances within radius of world_pos.
func _consume_grass_in_radius(world_pos: Vector3, radius: float) -> void:
	if multimesh == null:
		return
	for idx: int in get_grass_indices_in_radius(to_local(world_pos), radius):
		var t: Transform3D = multimesh.get_instance_transform(idx)
		t.basis = t.basis.scaled(Vector3(1.0, 0.25, 1.0))
		multimesh.set_instance_transform(idx, t)


## Returns the instance indices within radius of a local-space point, looked up through the coarse origin grid.
func get_grass_indices_in_radius(center: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var r_sq: float = radius * radius
	var min_cell: Vector2i = Vector2i(floori((center.x - radius) / BUCKET_SIZE), floori((center.z - radius) / BUCKET_SIZE))
	var max_cell: Vector2i = Vector2i(floori((center.x + radius) / BUCKET_SIZE), floori((center.z + radius) / BUCKET_SIZE))
	for cx: int in range(min_cell.x, max_cell.x + 1):
		for cz: int in range(min_cell.y, max_cell.y + 1):
			for idx: int in _origin_buckets.get(Vector2i(cx, cz), []):
				var p: Vector3 = _instance_origins[idx]
				if (p.x - center.x) ** 2 + (p.z - center.z) ** 2 <= r_sq:
					result.append(idx)
	return result


## Extinguishes all active wildfire fronts on this field.
func extinguish_all_fires() -> void:
	_creeper_heads.clear()
	_active_fires.clear()
	for node: FireTrailNode in _trail_nodes.duplicate(): # extinguish() may free nodes, which erase themselves
		if is_instance_valid(node):
			node.extinguish()
	_trail_nodes.clear()


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		match what:
			NOTIFICATION_EDITOR_PRE_SAVE:
				multimesh = null
			NOTIFICATION_EDITOR_POST_SAVE:
				regenerate()


## Returns the active mesh based on mesh_type or custom_mesh.
func get_active_mesh() -> Mesh:
	if custom_mesh and (mesh_type == GrassMeshType.CUSTOM or not GRASS_MESHES.has(mesh_type)):
		return custom_mesh
	return GRASS_MESHES.get(mesh_type, GRASS_MESHES[GrassMeshType.COMMON_SHORT])


## Returns the cached 3D origin points of all grass instances.
func get_instance_origins() -> Array[Vector3]:
	return _instance_origins


## Checks whether a 2D local coordinate (px, pz) falls within any exclusion zone.
func is_point_excluded(px: float, pz: float) -> bool:
	if exclusion_radius > 0.0 and Vector2(px - exclusion_center.x, pz - exclusion_center.y).length() < exclusion_radius:
		return true
	for zone: Vector3 in additional_exclusion_zones:
		if zone.z > 0.0 and Vector2(px - zone.x, pz - zone.y).length() < zone.z:
			return true
	return false


## Rebuilds the MultiMesh instances within field boundaries.
func regenerate() -> void:
	_instance_origins.clear()
	_origin_buckets.clear()
	if instance_count <= 0:
		if multimesh:
			multimesh.instance_count = 0
		return
	material_override = custom_grass_material if custom_grass_material else GRASS_MATERIAL

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = get_active_mesh()
	mm.instance_count = instance_count

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var half_x: float = field_size.x * 0.5
	var half_z: float = field_size.y * 0.5
	var max_r: float = maxf(half_x, half_z)
	var has_exclusions: bool = exclusion_radius > 0.0 or not additional_exclusion_zones.is_empty()
	_instance_origins.resize(instance_count)

	for i: int in instance_count:
		var pos_x: float = rng.randf_range(-half_x, half_x)
		var pos_z: float = rng.randf_range(-half_z, half_z)
		if has_exclusions:
			var attempts: int = 0
			var excluded: bool = is_point_excluded(pos_x, pos_z)
			while attempts < 40 and excluded:
				pos_x = rng.randf_range(-half_x, half_x)
				pos_z = rng.randf_range(-half_z, half_z)
				excluded = is_point_excluded(pos_x, pos_z)
				attempts += 1
			if excluded:
				var ang: float = rng.randf_range(0.0, TAU)
				var r: float = rng.randf_range(exclusion_radius + 0.5, maxf(exclusion_radius + 1.0, max_r))
				pos_x = clampf(exclusion_center.x + cos(ang) * r, -half_x, half_x)
				pos_z = clampf(exclusion_center.y + sin(ang) * r, -half_z, half_z)

		var scl: float = rng.randf_range(min_scale, max_scale)
		var t: Transform3D = Transform3D().rotated(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scl, scl, scl))
		t.origin = Vector3(pos_x, 0.0, pos_z)
		_instance_origins[i] = t.origin
		mm.set_instance_transform(i, t)
		var cell: Vector2i = Vector2i(floori(pos_x / BUCKET_SIZE), floori(pos_z / BUCKET_SIZE))
		var bucket: Array = _origin_buckets.get(cell, [])
		bucket.append(i)
		_origin_buckets[cell] = bucket

	multimesh = mm
