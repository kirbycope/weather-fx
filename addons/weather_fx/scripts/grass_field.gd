# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name GrassField
extends MultiMeshInstance3D

## High-performance, wind-reactive grass field populated using MultiMesh.
## Instances sway via the WeatherFX global shader uniforms. A wildfire is a cellular front on the
## origin grid: every burning cell catches its neighbours after a delay set by the creep speed and
## the wind (fast downwind, slow upwind), so the fire grows as a ragged ring that leans downwind
## instead of a line. Blades char through the grass shader's per-instance custom data (when each
## caught, read against the material's fire_clock). Wind comes from WeatherFX.wind_changed and rain
## douses everything on weather_changed.

enum GrassMeshType {
	COMMON_SHORT,
	COMMON_TALL,
	WISPY_SHORT,
	WISPY_TALL,
	CUSTOM
}

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
## Cell size of the origin grid; grass lookups and the fire front both work on it.
const BUCKET_SIZE: float = 2.0
const MAX_TRAIL_NODES: int = 48
const CELL_BURN_SECONDS: float = 6.0 ## A cell flames for this long, then it is ash.
const UPWIND_SPEED_FACTOR: float = 0.25 ## Creep speed dead upwind in a full-strength wind, as a fraction of the downwind speed.
const FULL_WIND_STRENGTH: float = 8.0 ## Wind strength at which the front leans as far downwind as it gets.
const BLADE_CATCH_JITTER: float = 1.0 ## Each blade in a cell catches up to this many seconds after its cell.
const IGNITE_HEIGHT: float = 1.0 ## A flame more than this far above or below the blades (a torch on a platform, a bolt overhead) lights nothing.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

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
@export var fire_spread_speed: float = 1.5 ## Fire front creep speed in m/s downwind, clamped to the BotW 1.2-1.8 band. Wind shapes the front; it never makes it faster.
@export var weather_fx: WeatherFX

var _instance_origins: Array[Vector3] = []
var _origin_buckets: Dictionary[Vector2i, Array] = {}
var _trail_nodes: Array[FireTrailNode] = []
var _burning_cells: Dictionary[Vector2i, float] = {} ## Cell -> seconds since it caught.
var _burnt_cells: Dictionary[Vector2i, bool] = {} ## Ash; never catches again.
var _catch_jitter: Dictionary[Vector2i, float] = {} ## How reluctant each cell is to catch (0.7 quick, 1.4 slow), for ragged edges.
var _spread_time_left: float = 0.0 ## Seconds the front may still grow (an ignition's duration); lit cells finish regardless.
var _fire_clock: float = 0.0 ## Seconds since the field's first ignition, mirrored into the shader's fire_clock.
var _clock_until: float = 0.0 ## The clock keeps running until the last lit blade has turned to ash.
var _h_wind: Vector2 = Vector2(WeatherFX.active_wind_direction.x, WeatherFX.active_wind_direction.z).normalized()
var _wind_strength: float = WeatherFX.active_wind_strength
var _is_raining: bool = WeatherFX.active_precipitation_strength > 0.4 ## Nothing catches in the rain.


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
		_is_raining = weather_fx.is_simulating() and ClimateData.get_precipitation_strength(weather_fx.active_weather) > 0.4


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	var h_wind: Vector2 = Vector2(direction.x, direction.z)
	_h_wind = h_wind.normalized() if h_wind.length_squared() > 0.001 else Vector2.ZERO
	_wind_strength = strength


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_is_raining = ClimateData.get_precipitation_strength(new_weather) > 0.4
	if _is_raining:
		extinguish_all_fires()


## Advances the fire front: lit cells age, pass the fire to neighbours and turn to ash.
func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not enable_wildfire:
		return
	if _burning_cells.is_empty() and _fire_clock >= _clock_until:
		return
	_fire_clock += delta
	_spread_time_left -= delta
	var shader_material: ShaderMaterial = material_override as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter(&"fire_clock", _fire_clock)
	var speed: float = clampf(fire_spread_speed, CREEP_SPEED_MIN, CREEP_SPEED_MAX)
	for cell: Vector2i in _burning_cells.keys():
		var age: float = _burning_cells[cell] + delta
		if age >= CELL_BURN_SECONDS:
			_burning_cells.erase(cell)
			_burnt_cells[cell] = true
			continue
		_burning_cells[cell] = age
		if _spread_time_left <= 0.0:
			continue
		for offset: Vector2i in NEIGHBOURS:
			var next: Vector2i = cell + offset
			if _burning_cells.has(next) or _burnt_cells.has(next) or not _origin_buckets.has(next):
				continue # Already alight, ash, or nothing there to burn
			# The fire arrives when this cell has burned for the creep time of the step, give or take the
			# neighbour's own reluctance, so the front keeps the creep speed and gets ragged edges
			if age >= _seconds_to_catch(offset, speed) * _catch_jitter.get_or_add(next, randf_range(0.7, 1.4)):
				_ignite_cell(next)


## Seconds the front takes to cross [param offset] on the grid: the creep time for the distance,
## stretched upwind and across the wind in proportion to the wind's strength.
func _seconds_to_catch(offset: Vector2i, speed: float) -> float:
	var step: Vector2 = Vector2(offset) * BUCKET_SIZE
	var factor: float = 1.0
	if not _h_wind.is_zero_approx():
		var alignment: float = step.normalized().dot(_h_wind)
		var lean: float = clampf(_wind_strength / FULL_WIND_STRENGTH, 0.0, 1.0)
		factor = lerpf(1.0, remap(alignment, -1.0, 1.0, UPWIND_SPEED_FACTOR, 1.0), lean)
	return step.length() / (speed * factor)


## Lights one grid cell: its blades catch (each with its own jitter) and a flame node lands on it
## while the node budget allows.
func _ignite_cell(cell: Vector2i) -> void:
	_burning_cells[cell] = 0.0
	_clock_until = _fire_clock + CELL_BURN_SECONDS + BLADE_CATCH_JITTER + 0.5
	if multimesh:
		for idx: int in _origin_buckets.get(cell, []):
			multimesh.set_instance_custom_data(idx, Color(_fire_clock, randf() * BLADE_CATCH_JITTER, 0.0, 1.0))
	if _trail_nodes.size() < MAX_TRAIL_NODES:
		var centre: Vector3 = Vector3((cell.x + 0.5) * BUCKET_SIZE, 0.0, (cell.y + 0.5) * BUCKET_SIZE)
		_drop_trail_node(centre + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)))


func _drop_trail_node(local_pos: Vector3) -> FireTrailNode:
	var node: FireTrailNode = FIRE_TRAIL_SCENE.instantiate() as FireTrailNode
	node.weather_fx = weather_fx
	node.position = local_pos
	add_child(node)
	_trail_nodes.append(node)
	node.tree_exiting.connect(_trail_nodes.erase.bind(node)) # Drop the reference before the node is freed
	return node


## Starts a wildfire: every grass cell within [param initial_radius] of [param world_pos] catches and the
## front keeps growing for [param duration] seconds (lit cells burn out on their own after that).
## Returns false when the point is off-field, too far above or below the blades, or it is raining.
## Lights the grass around [param world_pos]. Nothing catches in the rain unless [param force] is on: a lightning
## strike is hot enough to light wet grass, and the fire then burns as long as the rain does not douse it.
func ignite_at(world_pos: Vector3, initial_radius: float = 2.0, duration: float = 6.0, force: bool = false) -> bool:
	if not enable_wildfire or (_is_raining and not force):
		return false
	var local_p: Vector3 = to_local(world_pos)
	if absf(local_p.x) > field_size.x * 0.5 + 2.0 or absf(local_p.z) > field_size.y * 0.5 + 2.0 or absf(local_p.y) > IGNITE_HEIGHT:
		return false
	_spread_time_left = maxf(_spread_time_left, duration)
	var origin_cell: Vector2i = _cell_of(local_p)
	var reach: int = ceili(initial_radius / BUCKET_SIZE)
	for cx: int in range(origin_cell.x - reach, origin_cell.x + reach + 1):
		for cz: int in range(origin_cell.y - reach, origin_cell.y + reach + 1):
			var cell: Vector2i = Vector2i(cx, cz)
			if _burning_cells.has(cell) or _burnt_cells.has(cell) or not _origin_buckets.has(cell):
				continue
			var centre: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * BUCKET_SIZE
			if cell == origin_cell or centre.distance_to(Vector2(local_p.x, local_p.z)) <= initial_radius:
				_ignite_cell(cell)
	return true


## Custom data for a blade doused mid-burn: well past a full burn, so it reads as ash on the clock the
## shader last saw (a frame behind the field's) rather than glowing as an ember for good.
func doused_blade_data() -> Color:
	return Color(_fire_clock - 2.0 * CELL_BURN_SECONDS, 0.0, 0.0, 1.0)


## The origin-grid cell holding a local-space point.
func _cell_of(local_pos: Vector3) -> Vector2i:
	return Vector2i(floori(local_pos.x / BUCKET_SIZE), floori(local_pos.z / BUCKET_SIZE))


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


## Douses the fire: the front stops, every lit cell is ash and its blades char out at once.
func extinguish_all_fires() -> void:
	_spread_time_left = 0.0
	for cell: Vector2i in _burning_cells.keys():
		_douse_cell(cell)
	_clock_until = _fire_clock
	for node: FireTrailNode in _trail_nodes.duplicate(): # extinguish() may free nodes, which erase themselves
		if is_instance_valid(node):
			node.extinguish()
	_trail_nodes.clear()


## Douses the fire within [param radius] of [param world_pos] (a water spell, a bucket): those cells are ash, their
## blades char out, their flames go out, and the front keeps burning everywhere else.
func douse_at(world_pos: Vector3, radius: float) -> void:
	var local_p: Vector3 = to_local(world_pos)
	var centre: Vector2 = Vector2(local_p.x, local_p.z)
	for cell: Vector2i in _burning_cells.keys():
		if ((Vector2(cell) + Vector2(0.5, 0.5)) * BUCKET_SIZE).distance_to(centre) <= radius:
			_douse_cell(cell)
	for node: FireTrailNode in _trail_nodes.duplicate():
		if is_instance_valid(node) and node.global_position.distance_to(world_pos) <= radius:
			node.extinguish()


## A lit cell put out: ash for good, its blades charred at once.
func _douse_cell(cell: Vector2i) -> void:
	_burning_cells.erase(cell)
	_burnt_cells[cell] = true
	if multimesh:
		for idx: int in _origin_buckets.get(cell, []):
			multimesh.set_instance_custom_data(idx, doused_blade_data())


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


## Rebuilds the MultiMesh instances within field boundaries. Every blade gets custom data for the
## fire (zero until it catches), and at runtime the field gets its own copy of the material so its
## fire clock is its own.
func regenerate() -> void:
	_instance_origins.clear()
	_origin_buckets.clear()
	_burning_cells.clear()
	_burnt_cells.clear()
	_catch_jitter.clear()
	if instance_count <= 0:
		if multimesh:
			multimesh.instance_count = 0
		return
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
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
	# After the multimesh: swapping the base drops the override the renderer holds, so set it last
	var base_material: Material = custom_grass_material if custom_grass_material else GRASS_MATERIAL
	material_override = base_material if Engine.is_editor_hint() else base_material.duplicate()
	var shader_material: ShaderMaterial = material_override as ShaderMaterial
	if shader_material and not Engine.is_editor_hint():
		shader_material.set_shader_parameter(&"burn_seconds", CELL_BURN_SECONDS)
		shader_material.set_shader_parameter(&"fire_clock", _fire_clock)
