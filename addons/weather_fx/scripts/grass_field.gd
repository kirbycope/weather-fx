# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name GrassField
extends MultiMeshInstance3D

## High-performance, wind-reactive grass field populated using MultiMesh.
## Blades grow only on ground: each drops a ray straight down and grows where the first thing it meets is a
## collider in [member ground_group], so rocks, walls, campfires and ponds keep themselves clear with no
## per-field setup (see [member ground_group]).
## Instances sway via the WeatherFX global shader uniforms. A wildfire is a cellular front on the
## origin grid: every burning cell catches its neighbours after a delay set by the creep speed and
## the wind (fast downwind, slow upwind), so the fire grows as a ragged ring that leans downwind
## instead of a line. Blades char through the grass shader's per-instance custom data (when each
## caught, read against the material's fire_clock). Wind comes from WeatherFX.wind_changed and rain
## douses everything on weather_changed.

## Emitted each time the field finishes growing, whether all at once or over several physics frames.
signal grown

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
const PROBE_MAX_PASSES: int = 8 ## Moving bodies (a Player, a ball) one ray looks past before it gives the blade up.
const WATER_PROBE_LIFT: float = 0.05 ## The water check looks this far above the ground, inside a volume that sits on the bed.
const MAX_PRESSERS: int = 8 ## Bodies pressing one field at once; matches MAX_PRESS_POINTS in grass_wind.gdshader.
const PRESS_AREA_MARGIN: float = 3.0 ## Metres above and below the blades the press volume notices bodies in.
## Microseconds all probing fields together may spend casting their rays in one physics frame. A level's
## fields grow a slice at a time within it, so casting tens of thousands of rays never stalls one frame
## long enough to leave the engine catching up on physics with no frame drawn in between.
const GROW_BUDGET_USEC: int = 4000
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

@export_group("Placement")
## Grass grows on colliders in this group: the Player's footstep group, so ground that sounds like grass
## grows it. Every blade drops a ray straight down through the field and grows where the first thing the ray
## meets is in this group. Anything else met first (a rock, a wall, a trunk, a campfire) is standing there,
## and a ray that meets nothing (a pond with no bed, a hole, past the edge of the ground) has no ground under
## it; either way that blade is left out. Players, NPCs, rigid props and moving platforms are looked past:
## where they happen to be when the field grows says nothing about the ground.
## Empty: nothing is probed and every blade sits flat on the field's plane.
@export var ground_group: StringName = &"GRASS":
	set(val):
		ground_group = val
		if is_inside_tree():
			regenerate()

## Areas in this group hold no grass either: the water of a pond with a solid bed under it.
@export var water_group: StringName = &"WATER":
	set(val):
		water_group = val
		if is_inside_tree():
			regenerate()

## Ground steeper than this stays bare: a pond's banks, a cliff face.
@export_range(0.0, 90.0, 0.5, "suffix:°") var max_slope_degrees: float = 40.0:
	set(val):
		max_slope_degrees = val
		if is_inside_tree():
			regenerate()

## The rays run from this far above the field's plane to this far below it, so the ground has to lie in that
## band. Something taller than the band still blocks: a ray that starts inside a solid meets it there.
@export_range(0.5, 200.0, 0.1, "or_greater", "suffix:m") var probe_height: float = 20.0:
	set(val):
		probe_height = maxf(0.5, val)
		if is_inside_tree():
			regenerate()

## Physics layers the rays see. Grass grows straight through whatever is only on the other layers.
@export_flags_3d_physics var probe_mask: int = 0xFFFFFFFF:
	set(val):
		probe_mask = val
		if is_inside_tree():
			regenerate()

## Regrows the field against the colliders as they stand now (after moving a rock in the editor, say).
## Saving the scene regrows it too.
@export_tool_button("Regrow", "Reload") var regrow_action: Callable = regenerate

@export_group("Pressing")
## Bodies standing in the field tread the grass down and lean it away from them: the Player, an NPC, a
## rideable, a rolling ball, a moving platform. These are the same bodies the blades are grown straight
## through (see [member ground_group]), so anything that does not clear the grass bends it instead.
## A [PressArea] child, on no collision layer so an interaction or projectile ray passes straight through
## it, notices them coming and going, and the nearest [constant MAX_PRESSERS] are handed to
## the shader each frame. How hard they press is on the material: press_strength, press_flatten, press_height.
@export var enable_pressing: bool = true:
	set(val):
		enable_pressing = val
		if is_inside_tree():
			_fit_press_area()

## Radius pressed by a body whose collision shape is not a sphere, capsule, cylinder or box.
@export_range(0.1, 5.0, 0.05, "or_greater", "suffix:m") var press_radius_fallback: float = 0.5

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

var _pressers: Array[Node3D] = [] ## Bodies inside the press volume, in no order until they are sorted.
var _press_radii: Dictionary[Node3D, float] = {} ## Body -> the radius it presses, measured from its shapes once.
var _press_area: Area3D = null
var _pressers_sent: int = 0 ## How many the shader was last told about, so a field nobody is standing in writes nothing.
var _blade_band: Vector2 = Vector2.ZERO ## Lowest and highest blade in the field, which the press volume is sized to.
var _own_material: ShaderMaterial = null ## This field's own copy of the material at run time; pressing writes to nothing else.
var _grown_at: Transform3D ## Where the field stood when it last grew, so the editor only regrows it when it has really moved.
static var _budget_frame: int = -1 ## The physics frame _budget_spent_usec is counting.
static var _budget_spent_usec: int = 0 ## Growing already done this physics frame, by every field together.

var _slice_rng: RandomNumberGenerator = null ## Non-null while a grow is under way; the candidates' draws continue from it.
var _slice_next: int = 0 ## The next candidate the grow under way will try.
var _slice_blades: Array[Transform3D] = [] ## The blades the grow under way has grown so far.
var _slice_space: PhysicsDirectSpaceState3D = null ## The space its rays are cast in, or null for a flat field.
var _slice_ray: PhysicsRayQueryParameters3D = null
var _slice_water: PhysicsPointQueryParameters3D = null ## Null when there is no water to look for.
var _instance_origins: Array[Vector3] = []
var _origin_buckets: Dictionary[Vector2i, Array] = {}
var _cell_levels: Dictionary[Vector2i, PackedVector2Array] = {} ## Cell -> the levels of grass in it, each a (lowest, highest) pair. A cell the edge of a ledge runs through holds two.
var _fire_levels: Dictionary[Vector2i, Vector2] = {} ## Burning cell -> the level of it the fire is on, which is the only one it can pass along.
var _grow_countdown: int = 0 ## Physics frames until a probing field grows (see _grow_when_ground_ready).
var _ground_seen: bool = true ## Whether the last grow met ground at all; the editor warns on the node when it did not.
var _probe_xform: Transform3D ## The field's global transform for the grow in progress, read once rather than per blade.
var _probe_to_local: Transform3D ## Its inverse, which brings each hit back into the field's space.
var _probe_up: Vector3 ## The field's unit up, which the rays run along and the slope is measured against.
var _probe_min_dot: float ## cos(max_slope_degrees): a hit whose normal is below it is too steep for grass.
var _probe_water_bounds: Array[AABB] = [] ## World bounds of the water areas; the point query only runs inside one.
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
	if not Engine.is_editor_hint():
		return
	set_notify_transform(true) # Moved onto other ground in the editor, the field regrows against it
	if _instance_origins.is_empty():
		_grow_when_ground_ready()


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _instance_origins.is_empty(): # A baked MultiMesh is no use on its own: the fire reads the caches regenerate() fills
		_grow_when_ground_ready()
	set_physics_process(_grow_countdown > 0)
	if Engine.is_editor_hint():
		return
	_press_area = get_node_or_null("PressArea") as Area3D
	if _press_area == null:
		_press_area = _build_press_area() # A field made in code rather than from grass_field.tscn
	if not _press_area.body_entered.is_connected(_on_body_entered):
		_press_area.body_entered.connect(_on_body_entered)
		_press_area.body_exited.connect(_on_body_exited)
	_fit_press_area()
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.wind_changed.connect(_on_wind_changed)
		weather_fx.weather_changed.connect(_on_weather_changed)
		_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)
		_is_raining = weather_fx.is_simulating() and ClimateData.get_precipitation_strength(weather_fx.active_weather) > 0.4


## Grows the field once its ground can be probed: at once on a flat field, else starting two physics frames
## on and spread over as many frames as the rays need (see [constant GROW_BUDGET_USEC]). Rays cast from _ready
## would miss a CSG collider, which is built in a deferred call, and would see any body a level script moved
## in its own _ready where it stood before, because a physics body only learns its new transform when the
## frame's transform notifications are flushed. [signal grown] fires when the grass is there.
func _grow_when_ground_ready() -> void:
	if ground_group == &"":
		regenerate()
		return
	_grow_later()


## Grows the field two physics frames from now, and pushes that back each time it is asked again, so a run of
## requests (every frame of a drag in the editor) collapses into one grow at the end of it.
func _grow_later() -> void:
	_end_grow() # A grow already under way is for where the field used to be
	_grow_countdown = 2
	set_physics_process(true)


## Whether a grow is still to come or under way: the countdown after the field entered the tree or was moved,
## or the rays of a grow spread over physics frames. [signal grown] fires when it is done.
func is_growing() -> bool:
	return _grow_countdown > 0 or _slice_rng != null


## Counts down to a deferred grow, then grows the field a slice per physics frame within the budget every
## field shares, and builds the grass once the last candidate is done.
func _physics_process(_delta: float) -> void:
	if _grow_countdown > 0:
		_grow_countdown -= 1
		if _grow_countdown > 0:
			return
		if Engine.is_editor_hint():
			set_physics_process(false)
			regenerate() # The editor grows in one go: a drag has already collapsed into this single call
			return
		_begin_grow()
	if _slice_rng == null:
		set_physics_process(false)
		return
	var left: int = _grow_budget_left()
	if left <= 0:
		return # Other fields have spent this frame's budget; carry on next frame
	var started: int = Time.get_ticks_usec()
	var done: bool = _grow_some(started + left)
	_budget_spent_usec += Time.get_ticks_usec() - started
	if done:
		var blades: Array[Transform3D] = _slice_blades
		_end_grow()
		set_physics_process(false)
		_commit(blades)


## Microseconds of growing still allowed this physics frame, shared by every field.
static func _grow_budget_left() -> int:
	var frame: int = Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_spent_usec = 0
	return GROW_BUDGET_USEC - _budget_spent_usec


func _get_configuration_warnings() -> PackedStringArray:
	if _ground_seen:
		return PackedStringArray()
	return PackedStringArray(["No collider in the group \"%s\" lies under the field, so no grass grows. Add the ground's collider (the StaticBody3D, the CSG root, the terrain) to that group, or clear Ground Group for a flat field." % ground_group])


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	var h_wind: Vector2 = Vector2(direction.x, direction.z)
	_h_wind = h_wind.normalized() if h_wind.length_squared() > 0.001 else Vector2.ZERO
	_wind_strength = strength


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_is_raining = ClimateData.get_precipitation_strength(new_weather) > 0.4
	if _is_raining:
		extinguish_all_fires()


## Hands the shader the bodies standing in the field, then advances the fire front: lit cells age, pass the
## fire to neighbours and turn to ash.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_feed_pressers()
	if not enable_wildfire:
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
			var reached: int = _level_beside(next, _fire_levels[cell])
			if reached < 0:
				continue # The neighbour's grass is on another level: no climbing a cliff, no dropping off a ledge
			# The fire arrives when this cell has burned for the creep time of the step, give or take the
			# neighbour's own reluctance, so the front keeps the creep speed and gets ragged edges
			if age >= _seconds_to_catch(offset, speed) * _catch_jitter.get_or_add(next, randf_range(0.7, 1.4)):
				_ignite_cell(next, _cell_levels[next][reached])


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


## Lights one grid cell on [param on_level], the level of it the fire is on: its blades catch (each with
## its own jitter) and a flame node lands on it while the node budget allows. The height travels with the
## level travels with the front, so a cell the edge of a ledge runs through burns on the level the fire came
## in on and passes only that one along.
func _ignite_cell(cell: Vector2i, on_level: Vector2) -> void:
	_burning_cells[cell] = 0.0
	_fire_levels[cell] = on_level
	_clock_until = _fire_clock + CELL_BURN_SECONDS + BLADE_CATCH_JITTER + 0.5
	var blades: Array[int] = _blades_on(cell, on_level)
	if multimesh:
		for idx: int in blades:
			multimesh.set_instance_custom_data(idx, Color(_fire_clock, randf() * BLADE_CATCH_JITTER, 0.0, 1.0))
	if _trail_nodes.size() < MAX_TRAIL_NODES and not blades.is_empty():
		# On one of the burning blades, so the flame stands in the grass and not over the pond or the rock beside
		# it, nor up on the ledge above a fire that is burning on the flat
		_drop_trail_node(_instance_origins[blades[randi() % blades.size()]])


## The blades of [param cell] that stand on [param level], which is all of them unless the edge of a ledge runs
## through the cell.
func _blades_on(cell: Vector2i, level: Vector2) -> Array[int]:
	var on_level: Array[int] = []
	for idx: int in _origin_buckets.get(cell, []):
		var height: float = _instance_origins[idx].y
		if height >= level.x and height <= level.y:
			on_level.append(idx)
	return on_level


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
	if absf(local_p.x) > field_size.x * 0.5 + 2.0 or absf(local_p.z) > field_size.y * 0.5 + 2.0:
		return false
	var origin_cell: Vector2i = _cell_of(local_p)
	var reach: int = ceili(initial_radius / BUCKET_SIZE)
	var touched: int = 0
	for cx: int in range(origin_cell.x - reach, origin_cell.x + reach + 1):
		for cz: int in range(origin_cell.y - reach, origin_cell.y + reach + 1):
			var cell: Vector2i = Vector2i(cx, cz)
			if _burnt_cells.has(cell) or not _origin_buckets.has(cell):
				continue # Ash never catches again, and a cell with no grass has nothing to catch
			var reached: int = _level_at(cell, local_p.y)
			if reached < 0:
				continue # Grass on another level: below the ledge the flame is on, or up the bank from it
			var centre: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * BUCKET_SIZE
			if cell != origin_cell and centre.distance_to(Vector2(local_p.x, local_p.z)) > initial_radius:
				continue
			var level: Vector2 = _cell_levels[cell][reached]
			if not _burning_cells.has(cell):
				_ignite_cell(cell, level)
				touched += 1
			elif _fire_levels[cell] == level:
				touched += 1 # Already alight on this level still counts: the flame is on burning grass either way
	if touched == 0:
		return false # Nothing there to light: a bare patch, ash, or a field that has not grown yet
	_spread_time_left = maxf(_spread_time_left, duration)
	return true


## The volume that notices bodies walking into the field, for a field built in code rather than instanced
## from grass_field.tscn, where it is a node with its signals wired in the scene.
func _build_press_area() -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = &"PressArea"
	area.collision_layer = 0 # On no layer: it notices bodies through its mask, but no ray can land on it
	area.monitorable = false
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = &"PressShape"
	shape.shape = BoxShape3D.new()
	area.add_child(shape)
	add_child(area)
	return area


## Sizes the press volume to the grass it covers, and switches it off when nothing is to press the field.
func _fit_press_area() -> void:
	if not is_instance_valid(_press_area):
		return
	_press_area.monitoring = enable_pressing
	if not enable_pressing:
		_pressers.clear()
		_press_radii.clear()
		_feed_pressers()
		return
	var shape: CollisionShape3D = _press_area.get_node_or_null("PressShape") as CollisionShape3D
	var box: BoxShape3D = shape.shape as BoxShape3D if shape else null
	if box == null:
		return
	var height: float = _blade_band.y - _blade_band.x + PRESS_AREA_MARGIN * 2.0
	box.size = Vector3(field_size.x, height, field_size.y)
	shape.position = Vector3(0.0, (_blade_band.x + _blade_band.y) * 0.5, 0.0)


func _on_body_entered(body: Node3D) -> void:
	if not _moves(body):
		return # The ground, a wall, a rock: it cleared the grass where it stands, it does not also press it
	if body in _pressers:
		return
	_pressers.append(body)
	_press_radii[body] = _press_radius_of(body as CollisionObject3D, press_radius_fallback)


func _on_body_exited(body: Node3D) -> void:
	_pressers.erase(body)
	_press_radii.erase(body)


## Hands the shader [constant MAX_PRESSERS] of the bodies standing in the field as (x, y, z, radius). A field
## nobody is standing in writes nothing at all, and the shader's loop then runs zero times, so it is free
## until someone walks in.
func _feed_pressers() -> void:
	if _pressers.is_empty() and _pressers_sent == 0:
		return
	if _own_material == null or material_override != _own_material:
		return # Not grown yet, or a material set from outside: the shared resource would carry this field's presses to every other
	var points: PackedVector4Array = PackedVector4Array()
	points.resize(MAX_PRESSERS) # The uniform is a fixed-size array; press_count says how much of it to read
	var sent: int = 0
	if not _pressers.is_empty():
		_pressers = _pressers.filter(is_instance_valid)
		_pressers.sort_custom(_presses_more)
		var reach: float = _press_reach()
		for body: Node3D in _pressers:
			if sent == MAX_PRESSERS:
				break
			var local_y: float = to_local(body.global_position).y
			if local_y < _blade_band.x - reach or local_y > _blade_band.y + reach:
				continue # Too far above or below the grass for the shader to press it: do not spend a slot on it
			var at: Vector3 = body.global_position
			points[sent] = Vector4(at.x, at.y, at.z, _press_radii.get(body, press_radius_fallback))
			sent += 1
	_pressers_sent = sent
	_own_material.set_shader_parameter(&"press_points", points)
	_own_material.set_shader_parameter(&"press_count", _pressers_sent)


## How far above or below the blades a body still presses them: the material's press_height.
func _press_reach() -> float:
	var reach: Variant = _own_material.get_shader_parameter(&"press_height")
	return float(reach) if reach != null else 1.5


## Which of two bodies gets one of the shader's [constant MAX_PRESSERS] slots when more than that many are
## standing in one field: the widest press nearest the camera. A horse beside you beats a ragdoll's finger
## bone, and both beat the same horse across the field, which is the order they matter on screen.
func _presses_more(a: Node3D, b: Node3D) -> bool:
	return _press_weight(a) > _press_weight(b)


## How much a body's press is worth on screen: its radius, falling off with how far away it is being watched
## from. Measured from the middle of the field when there is no camera, as in a headless test.
func _press_weight(body: Node3D) -> float:
	var eye: Vector3 = global_position
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		eye = camera.global_position
	return _press_radii.get(body, press_radius_fallback) / (1.0 + body.global_position.distance_to(eye))


## The radius a body presses: the widest of its enabled collision shapes, offset and scale included, or
## [param fallback] when none of them has a radius.
static func _press_radius_of(body: CollisionObject3D, fallback: float) -> float:
	if body == null:
		return fallback
	var widest: float = 0.0
	for owner_id: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var offset: Transform3D = body.shape_owner_get_transform(owner_id)
		var reach: float = Vector2(offset.origin.x, offset.origin.z).length()
		var scale: Vector3 = offset.basis.get_scale()
		for i: int in body.shape_owner_get_shape_count(owner_id):
			# Only shapes with a radius count. A Player's SeparationRayShape3D, a step ray off to one side, would
			# otherwise take the fallback plus its offset and outgrow the capsule the Player actually stands in.
			var radius: float = _shape_radius(body.shape_owner_get_shape(owner_id, i))
			if radius > 0.0:
				widest = maxf(widest, radius * maxf(scale.x, scale.z) + reach)
	return widest if widest > 0.0 else fallback


## The horizontal radius of one shape, or 0.0 for a shape with no sensible one (a height map, a concave mesh).
static func _shape_radius(shape: Shape3D) -> float:
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return Vector2(size.x, size.z).length() * 0.5
	return 0.0


## Custom data for a blade doused mid-burn: well past a full burn, so it reads as ash on the clock the
## shader last saw (a frame behind the field's) rather than glowing as an ember for good.
func doused_blade_data() -> Color:
	return Color(_fire_clock - 2.0 * CELL_BURN_SECONDS, 0.0, 0.0, 1.0)


## The origin-grid cell holding a local-space point.
func _cell_of(local_pos: Vector3) -> Vector2i:
	return Vector2i(floori(local_pos.x / BUCKET_SIZE), floori(local_pos.z / BUCKET_SIZE))


## Which level of [param cell] a flame at [param height] can light, or -1 for none. Where two are in reach,
## the one nearer the flame.
func _level_at(cell: Vector2i, height: float) -> int:
	return _nearest_level(cell, Vector2(height, height))


## Which level of [param cell] the fire can cross to from [param from_level] in the cell beside it, or -1 for
## none. The two levels are measured end to end rather than by their middles, so the front walks up a bank
## one cell at a time however long the slope is, and a cliff face, whose levels are a storey apart, stops it.
func _level_beside(cell: Vector2i, from_level: Vector2) -> int:
	return _nearest_level(cell, from_level)


## The level of [param cell] closest to [param span] (a height range; a single height is a range of one),
## measured end to end and only counting levels within [constant IGNITE_HEIGHT], or -1 when none is.
func _nearest_level(cell: Vector2i, span: Vector2) -> int:
	var levels: PackedVector2Array = _cell_levels.get(cell, PackedVector2Array())
	var nearest: int = -1
	var nearest_gap: float = IGNITE_HEIGHT
	for i: int in levels.size():
		var gap: float = maxf(0.0, maxf(levels[i].x - span.y, span.x - levels[i].y))
		if gap <= nearest_gap:
			nearest_gap = gap
			nearest = i
	return nearest


## Groups a cell's blade heights into levels: heights closer together than [constant IGNITE_HEIGHT] are one
## level, so a bank is a single wide level a flame anywhere on it can light, while the edge of a ledge gives
## the cell two and the fire can only ever be on one of them.
static func _levels_of(heights: PackedFloat32Array) -> PackedVector2Array:
	var levels: PackedVector2Array = PackedVector2Array()
	if heights.is_empty():
		return levels
	heights.sort()
	var low: float = heights[0]
	var high: float = heights[0]
	for i: int in range(1, heights.size()):
		if heights[i] - high > IGNITE_HEIGHT:
			levels.append(Vector2(low, high))
			low = heights[i]
		high = heights[i]
	levels.append(Vector2(low, high))
	return levels


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
	var doused: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _burning_cells.keys():
		if ((Vector2(cell) + Vector2(0.5, 0.5)) * BUCKET_SIZE).distance_to(centre) <= radius:
			_douse_cell(cell)
			doused[cell] = true
	# A flame stands on one of its cell's blades, anywhere in the cell, so it goes out with its cell rather than
	# by its own distance, which would leave a flame burning over ash or put out one whose cell is still alight
	for node: FireTrailNode in _trail_nodes.duplicate():
		if is_instance_valid(node) and doused.has(_cell_of(node.position)):
			node.extinguish()


## A lit cell put out: ash for good, its blades charred at once.
func _douse_cell(cell: Vector2i) -> void:
	_burning_cells.erase(cell)
	_burnt_cells[cell] = true
	if multimesh:
		for idx: int in _blades_on(cell, _fire_levels[cell]):
			multimesh.set_instance_custom_data(idx, doused_blade_data())


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		match what:
			NOTIFICATION_EDITOR_PRE_SAVE:
				multimesh = null
			NOTIFICATION_EDITOR_POST_SAVE:
				regenerate()
			NOTIFICATION_TRANSFORM_CHANGED:
				# Dragged onto other ground. A flat field is placed in its own space and does not care where
				# that is; a probing one regrows, and the countdown collapses the drag into one regrow at the
				# end of it rather than one per frame of it. The notification also comes on every re-entry to
				# the tree (switching scene tabs back), which is no reason to cast every ray again.
				if ground_group != &"" and not global_transform.is_equal_approx(_grown_at):
					_grow_later()


## Returns the active mesh based on mesh_type or custom_mesh.
func get_active_mesh() -> Mesh:
	if custom_mesh and (mesh_type == GrassMeshType.CUSTOM or not GRASS_MESHES.has(mesh_type)):
		return custom_mesh
	return GRASS_MESHES.get(mesh_type, GRASS_MESHES[GrassMeshType.COMMON_SHORT])


## Returns the cached 3D origin points of all grass instances.
func get_instance_origins() -> Array[Vector3]:
	return _instance_origins


## Rebuilds the MultiMesh instances within field boundaries, keeping the blades that land on ground (see
## [member ground_group]). Every blade gets custom data for the fire (zero until it catches), and at runtime
## the field gets its own copy of the material so its fire clock is its own.
func regenerate() -> void:
	# A grow under way was for the field as it was, so it goes. A countdown still waiting stays: a field set up
	# right after it was added (sized, moved, scaled) grows here with each change and then once more where it
	# finally stands, as it always has.
	_end_grow()
	set_physics_process(_grow_countdown > 0)
	var blades: Array[Transform3D] = []
	if instance_count > 0:
		blades = _grow_blades()
	_commit(blades)


## Builds the grass from the blades a grow produced: the MultiMesh, the fire's caches and, at run time, the
## field's own copy of the material. Until this runs, the field keeps the grass it had.
func _commit(blades: Array[Transform3D]) -> void:
	_instance_origins.clear()
	_origin_buckets.clear()
	_cell_levels.clear()
	_fire_levels.clear()
	_burning_cells.clear()
	_burnt_cells.clear()
	_catch_jitter.clear()
	if instance_count <= 0:
		if multimesh:
			multimesh.instance_count = 0
		grown.emit()
		return
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = get_active_mesh()
	mm.instance_count = blades.size()
	_instance_origins.resize(blades.size())
	_blade_band = Vector2(INF, -INF)
	var cell_heights: Dictionary[Vector2i, PackedFloat32Array] = {}
	for i: int in blades.size():
		var t: Transform3D = blades[i]
		mm.set_instance_transform(i, t)
		_instance_origins[i] = t.origin
		var cell: Vector2i = _cell_of(t.origin)
		var bucket: Array = _origin_buckets.get(cell, [])
		bucket.append(i)
		_origin_buckets[cell] = bucket
		var heights: PackedFloat32Array = cell_heights.get(cell, PackedFloat32Array())
		heights.append(t.origin.y)
		cell_heights[cell] = heights
		_blade_band = Vector2(minf(_blade_band.x, t.origin.y), maxf(_blade_band.y, t.origin.y))
	for cell: Vector2i in cell_heights:
		_cell_levels[cell] = _levels_of(cell_heights[cell])
	if blades.is_empty():
		_blade_band = Vector2.ZERO # Nothing grew: size the press volume on the field's own plane
	_fit_press_area()
	multimesh = mm
	# After the multimesh: swapping the base drops the override the renderer holds, so set it last
	var base_material: Material = custom_grass_material if custom_grass_material else GRASS_MATERIAL
	material_override = base_material if Engine.is_editor_hint() else base_material.duplicate()
	_own_material = null if Engine.is_editor_hint() else material_override as ShaderMaterial
	_grown_at = global_transform if is_inside_tree() else transform
	var shader_material: ShaderMaterial = material_override as ShaderMaterial
	if shader_material and not Engine.is_editor_hint():
		shader_material.set_shader_parameter(&"burn_seconds", CELL_BURN_SECONDS)
		shader_material.set_shader_parameter(&"fire_clock", _fire_clock)
	grown.emit()
	if Engine.is_editor_hint():
		update_configuration_warnings()
	elif not _ground_seen:
		push_warning("GrassField \"%s\": no collider in the group \"%s\" lies under the field, so no grass grew. Add the ground's collider to that group, or clear ground_group for a flat field." % [name, ground_group])


## Scatters instance_count candidate blades over the field and returns the transforms of those that grow: all of
## them on a flat field, else the ones whose ray finds ground (see [member ground_group]). All at once.
func _grow_blades() -> Array[Transform3D]:
	_begin_grow()
	_grow_some(0)
	var blades: Array[Transform3D] = _slice_blades
	_end_grow()
	return blades


## Sets a grow up: the candidates' random numbers from [member seed_value], the queries, and everything the
## rays share. [method _grow_some] then works through the candidates, in one call or over several frames.
func _begin_grow() -> void:
	_slice_rng = RandomNumberGenerator.new()
	_slice_rng.seed = seed_value
	_slice_next = 0
	_slice_blades = []
	_slice_space = null
	if ground_group != &"" and is_inside_tree():
		_slice_space = get_world_3d().direct_space_state
	_slice_ray = PhysicsRayQueryParameters3D.new()
	_slice_ray.collision_mask = probe_mask
	_slice_ray.hit_from_inside = true # A ray that starts inside a convex solid (a building taller than probe_height) meets it there; a concave one (CSG, a trimesh) it does not
	_slice_water = null
	if _slice_space and water_group != &"" and get_tree().has_group(water_group):
		_probe_water_bounds = _water_bounds()
		if not _probe_water_bounds.is_empty():
			_slice_water = PhysicsPointQueryParameters3D.new()
			_slice_water.collision_mask = probe_mask
			_slice_water.collide_with_areas = true
			_slice_water.collide_with_bodies = false
	if _slice_space:
		# Everything the rays need that does not change from one blade to the next
		_probe_xform = global_transform
		_probe_to_local = _probe_xform.affine_inverse()
		_probe_up = _probe_xform.basis.y.normalized()
		_probe_min_dot = cos(deg_to_rad(max_slope_degrees))
	_ground_seen = _slice_space == null


## Tries candidates until they are all done or the clock passes [param deadline_usec] (0 for no deadline),
## and says whether the last one is done. Every candidate takes all its draws, grown or not, in the order it
## always did, so a grow spread over frames grows exactly what one done at once would.
func _grow_some(deadline_usec: int) -> bool:
	var half_x: float = field_size.x * 0.5
	var half_z: float = field_size.y * 0.5
	while _slice_next < instance_count:
		if deadline_usec > 0 and _slice_next % 32 == 0 and Time.get_ticks_usec() >= deadline_usec:
			return false
		_slice_next += 1
		var pos_x: float = _slice_rng.randf_range(-half_x, half_x)
		var pos_z: float = _slice_rng.randf_range(-half_z, half_z)
		var scl: float = _slice_rng.randf_range(min_scale, max_scale)
		var angle: float = _slice_rng.randf_range(0.0, TAU)
		var pos_y: float = 0.0
		if _slice_space:
			pos_y = _ground_height(_slice_space, _slice_ray, _slice_water, pos_x, pos_z)
			if is_nan(pos_y):
				continue
		var t: Transform3D = Transform3D().rotated(Vector3.UP, angle).scaled(Vector3(scl, scl, scl))
		t.origin = Vector3(pos_x, pos_y, pos_z)
		_slice_blades.append(t)
	return true


## Drops a grow, finished or not.
func _end_grow() -> void:
	_slice_rng = null
	_slice_blades = []
	_slice_space = null
	_slice_ray = null
	_slice_water = null


## The height, in the field's space, of the ground under the local point ([param x], [param z]), or NAN where no
## grass grows there: the first thing the ray meets is not ground, the ground is too steep or under water, or
## the ray meets nothing at all. [param water] is null when there is no water to look for.
func _ground_height(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, water: PhysicsPointQueryParameters3D, x: float, z: float) -> float:
	var base: Vector3 = _probe_xform * Vector3(x, 0.0, z)
	# Along the unit up rather than through the transform, or a scaled field silently probes a shorter band
	ray.from = base + _probe_up * probe_height
	ray.to = base - _probe_up * probe_height
	var looked_past: Array[RID] = []
	ray.exclude = looked_past
	for _pass: int in PROBE_MAX_PASSES:
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			return NAN # No ground: a pond with no bed, a hole, past the edge of the ground
		var collider: Object = hit.collider
		if _moves(collider):
			looked_past.append(hit.rid)
			ray.exclude = looked_past # The property hands back a copy, so set it again
			continue
		if not (collider is Node and (collider as Node).is_in_group(ground_group)):
			return NAN # Something else stands here: a rock, a wall, a trunk, a campfire
		_ground_seen = true
		if (hit.normal as Vector3).dot(_probe_up) < _probe_min_dot:
			return NAN # Too steep: a bank, a cliff face, or ground risen above the ray's start
		var point: Vector3 = hit.position
		if water and _near_water(point):
			water.position = point + _probe_up * WATER_PROBE_LIFT
			for overlap: Dictionary in space.intersect_point(water):
				if overlap.collider is Node and (overlap.collider as Node).is_in_group(water_group):
					return NAN # Under water
		return (_probe_to_local * point).y
	return NAN


## The world-space bounds of every shape of every area in [member water_group], grown a little, so the point
## query that decides whether a blade is under water only runs where water could possibly be. A field with no
## pond under it then pays nothing for the check.
func _water_bounds() -> Array[AABB]:
	var bounds: Array[AABB] = []
	for node: Node in get_tree().get_nodes_in_group(water_group):
		var area: CollisionObject3D = node as CollisionObject3D
		if area == null:
			continue
		for owner_id: int in area.get_shape_owners():
			var to_world: Transform3D = area.global_transform * area.shape_owner_get_transform(owner_id)
			for i: int in area.shape_owner_get_shape_count(owner_id):
				var outline: ArrayMesh = area.shape_owner_get_shape(owner_id, i).get_debug_mesh()
				if outline:
					bounds.append((to_world * outline.get_aabb()).grow(WATER_PROBE_LIFT * 2.0))
	return bounds


## Whether a point lies inside the bounds of any water area, which is the only place worth asking properly.
func _near_water(point: Vector3) -> bool:
	for bounds: AABB in _probe_water_bounds:
		if bounds.has_point(point):
			return true
	return false


## Whether a collider moves (a Player, an NPC, a rigid prop, a platform): where it stands when the field grows
## is no clue to the ground under it, and the field is grown once, so a prop taken for an obstacle would leave
## a grass-shaped hole the day it was knocked over. Scenery that should clear grass is a StaticBody3D.
static func _moves(collider: Object) -> bool:
	return collider is CharacterBody3D or collider is RigidBody3D or collider is AnimatableBody3D or collider is PhysicalBone3D
