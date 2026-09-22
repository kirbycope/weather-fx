extends GutTest

## Purpose: a GrassField grows blades only where there is ground to grow on.
##
## Every candidate blade drops a ray straight down and grows where the first thing it meets is a collider
## in `ground_group`. These tests build one scene carrying every case that decides a blade (a hole with no
## ground under it, something else standing on the ground, water over a solid bed, a slope too steep, a
## walker that happens to be standing there, and ground at another height) and check each patch of the
## field came out the way it should. They also pin the two properties the placement is built on: a field
## with no ground group is flat and grows everything, as it did before blades were probed at all, and a
## blade keeps its exact spot when something elsewhere on the field changes.

const FIELD_HALF: float = 20.0 ## The test field is 40 x 40 m centred on the origin.
const BLADES: int = 6000
const HEIGHT_EPSILON: float = 0.01

var root: Node3D
var field: GrassField
var blocker: StaticBody3D


func before_each() -> void:
	seed(20260922)
	root = Node3D.new()
	add_child_autofree(root)
	WeatherFX.active_wind_strength = 0.0
	WeatherFX.active_precipitation_strength = 0.0
	WeatherFX._player_cache = null
	WeatherFX._player_search_cooldown_frame = -1


func after_each() -> void:
	WeatherFX.active_precipitation_strength = 0.0
	WeatherFX._player_cache = null
	WeatherFX._player_search_cooldown_frame = -1


## Builds the test ground and everything standing on it, then a field over the lot, and waits for it to grow.
##
##   x -24..0    ground, top at y = 0            x 0..8   nothing at all, a hole through the field
##   x 8..20     ground, top at y = 0            water sits over it at x 11..17, z -15..-9
##   blocker     x -17..-11, z -15..-9, 2 m tall, not ground
##   plateau     x -18..-10, z 8..16, top at y = 3
##   ramp        around x -4, z 9..15, tilted 60 degrees, too steep to hold grass
##   bank        x -10..-2, z -3..3, tilted 25 degrees, rising to about 2.9 m and inside the limit
##   walker      a CharacterBody3D standing at x -14, z 0
func _build_scene() -> void:
	_ground(Vector3(-12.0, -0.5, 0.0), Vector3(24.0, 1.0, 40.0), &"GroundWest")
	_ground(Vector3(14.0, -0.5, 0.0), Vector3(12.0, 1.0, 40.0), &"GroundEast")
	_ground(Vector3(-14.0, 2.5, 12.0), Vector3(8.0, 1.0, 8.0), &"Plateau")

	var ramp: StaticBody3D = _ground(Vector3(-4.0, 2.0, 12.0), Vector3(4.0, 0.4, 6.0), &"Ramp")
	ramp.rotation = Vector3(0.0, 0.0, deg_to_rad(60.0))

	# Its west face falls in the middle of a 2 m cell, so that cell holds blades at both y = 0 and y = 3
	_ground(Vector3(-3.5, 1.5, -16.0), Vector3(7.0, 3.0, 6.0), &"Ledge")

	# A bank inside the slope limit, rising to about 2.9 m: grass grows on it and the fire has to be able to
	# walk up it, which is the thing a gate against climbing cliffs must not break.
	var bank: StaticBody3D = _ground(Vector3(-6.0, 1.2, 0.0), Vector3(8.0, 0.5, 6.0), &"Bank")
	bank.rotation = Vector3(0.0, 0.0, deg_to_rad(25.0))

	blocker = StaticBody3D.new()
	blocker.name = &"Blocker"
	blocker.position = Vector3(-14.0, 1.0, -12.0)
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(6.0, 2.0, 6.0)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	root.add_child(blocker) # Deliberately not in the GRASS group: it is standing on the ground, not part of it

	var water := Area3D.new()
	water.name = &"Pond"
	water.position = Vector3(14.0, 1.0, -12.0)
	water.add_to_group(&"WATER")
	var water_shape := CollisionShape3D.new()
	var water_box := BoxShape3D.new()
	water_box.size = Vector3(6.0, 2.0, 6.0)
	water_shape.shape = water_box
	water.add_child(water_shape)
	root.add_child(water)

	var walker := CharacterBody3D.new()
	walker.name = &"Walker"
	walker.position = Vector3(-14.0, 1.0, 0.0)
	var walker_shape := CollisionShape3D.new()
	var walker_box := BoxShape3D.new()
	walker_box.size = Vector3(4.0, 2.0, 4.0)
	walker_shape.shape = walker_box
	walker.add_child(walker_shape)
	root.add_child(walker)

	field = _field()


## A slab of ground in the group the field grows on.
func _ground(centre: Vector3, size: Vector3, node_name: StringName) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = centre
	body.add_to_group(&"GRASS")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	return body


func _field(ground_group: StringName = &"GRASS") -> GrassField:
	var grass := GrassField.new()
	grass.ground_group = ground_group
	grass.field_size = Vector2(FIELD_HALF * 2.0, FIELD_HALF * 2.0)
	grass.instance_count = BLADES
	root.add_child(grass)
	return grass


## Waits until [param grass] has finished growing. A probing field starts two physics frames after it enters
## the tree and casts its rays a slice per frame, so how many frames that takes depends on the field.
func _grown(grass: GrassField) -> void:
	await wait_until(func() -> bool: return not grass.is_growing(), 10.0)


## The blades whose x and z fall inside the rectangle, given as the two corners on the ground plane.
func _blades_in(from: Vector2, to: Vector2) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for origin: Vector3 in field.get_instance_origins():
		if origin.x >= from.x and origin.x <= to.x and origin.z >= from.y and origin.z <= to.y:
			found.append(origin)
	return found


func test_no_grass_grows_where_the_ray_finds_nothing() -> void:
	_build_scene()
	await _grown(field)
	assert_eq(_blades_in(Vector2(0.5, -19.0), Vector2(7.5, 19.0)).size(), 0, "The hole in the ground holds no grass")
	assert_gt(_blades_in(Vector2(9.0, -19.0), Vector2(19.0, -17.0)).size(), 0, "and the ground beyond it still does")


func test_no_grass_grows_under_something_standing_on_the_ground() -> void:
	_build_scene()
	await _grown(field)
	assert_eq(_blades_in(Vector2(-16.5, -14.5), Vector2(-11.5, -9.5)).size(), 0, "The blocker's footprint is bare")
	assert_gt(_blades_in(Vector2(-9.0, -14.5), Vector2(-5.0, -9.5)).size(), 0, "and the ground beside it is not")


func test_no_grass_grows_under_water() -> void:
	_build_scene()
	await _grown(field)
	assert_eq(_blades_in(Vector2(11.5, -14.5), Vector2(16.5, -9.5)).size(), 0, "The pond holds no grass")
	assert_gt(_blades_in(Vector2(9.0, -6.0), Vector2(19.0, 0.0)).size(), 0, "and the same ground beyond the water does")


func test_no_grass_grows_on_a_slope_past_the_limit() -> void:
	_build_scene()
	await _grown(field)
	assert_eq(_blades_in(Vector2(-4.8, 9.5), Vector2(-3.2, 14.5)).size(), 0, "A 60 degree ramp is too steep at the default 40")
	assert_gt(_blades_in(Vector2(-8.5, 9.5), Vector2(-7.0, 14.5)).size(), 0, "while the flat ground beside it grows")


func test_grass_grows_under_a_walker_standing_on_it() -> void:
	_build_scene()
	await _grown(field)
	var under: Array[Vector3] = _blades_in(Vector2(-15.5, -1.5), Vector2(-12.5, 1.5))
	assert_gt(under.size(), 0, "A CharacterBody3D standing on the field is looked past, not taken for ground")
	for origin: Vector3 in under:
		assert_almost_eq(origin.y, 0.0, HEIGHT_EPSILON, "and the blade sits on the ground, not on the walker")


func test_blades_stand_on_the_ground_they_find() -> void:
	_build_scene()
	await _grown(field)
	var raised: Array[Vector3] = _blades_in(Vector2(-17.5, 8.5), Vector2(-10.5, 15.5))
	assert_gt(raised.size(), 0, "The plateau holds grass")
	for origin: Vector3 in raised:
		assert_almost_eq(origin.y, 3.0, HEIGHT_EPSILON, "and it stands on top of it")
	for origin: Vector3 in _blades_in(Vector2(-19.0, -19.0), Vector2(-19.0 + 4.0, -5.0)):
		assert_almost_eq(origin.y, 0.0, HEIGHT_EPSILON, "while the flat ground's grass stays at its own height")


func test_a_flame_only_lights_the_grass_at_its_own_height() -> void:
	_build_scene()
	await _grown(field)
	assert_false(
		field.ignite_at(Vector3(-14.0, 0.0, 12.0), 2.0, 6.0),
		"A flame on the flat ground does not light the grass three metres up on the plateau"
	)
	assert_true(field.ignite_at(Vector3(-14.0, 3.0, 12.0), 2.0, 6.0), "A flame up on the plateau lights it")
	assert_gt(field._burning_cells.size(), 0, "and cells there are alight")


func test_a_field_with_no_ground_group_is_flat_and_grows_everything() -> void:
	_build_scene()
	await _grown(field)
	var flat: GrassField = _field(&"")
	await _grown(flat)
	assert_eq(flat.get_instance_origins().size(), BLADES, "Every blade grows when nothing is probed")
	assert_eq(flat.multimesh.instance_count, BLADES, "and the MultiMesh carries them all")
	for origin: Vector3 in flat.get_instance_origins():
		assert_almost_eq(origin.y, 0.0, HEIGHT_EPSILON, "on the field's own plane")


func test_a_blade_keeps_its_place_when_something_else_on_the_field_changes() -> void:
	_build_scene()
	await _grown(field)
	var before: Array[Vector3] = field.get_instance_origins().duplicate()
	var covered: int = _blades_in(Vector2(-16.5, -14.5), Vector2(-11.5, -9.5)).size()
	assert_eq(covered, 0, "Nothing grows under the blocker to begin with")

	blocker.queue_free()
	await wait_physics_frames(2)
	field.regenerate()

	var after: Dictionary[Vector3, bool] = {}
	for origin: Vector3 in field.get_instance_origins():
		after[origin] = true
	for origin: Vector3 in before:
		assert_true(after.has(origin), "Every blade that grew before still stands in the same spot: %s" % origin)
	assert_gt(
		_blades_in(Vector2(-16.5, -14.5), Vector2(-11.5, -9.5)).size(),
		0,
		"and the ground the blocker was standing on has grown its own"
	)


func test_water_has_to_reach_the_bed_to_clear_the_grass() -> void:
	# The check is a point just above the ground, so a WATER area holds no grass only where it contains that
	# point. Pinned rather than widened: a ray up the column would also find water merely overhead, and every
	# WATER area in these projects reaches the bed already, because swimming and water footsteps need it to.
	_build_scene()
	var perched := Area3D.new()
	perched.name = &"PerchedWater"
	perched.position = Vector3(14.0, 1.6, 6.0) # Bottom at y = 1.1, a metre clear of the bed at y = 0
	perched.add_to_group(&"WATER")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 1.0, 6.0)
	shape.shape = box
	perched.add_child(shape)
	root.add_child(perched)
	await _grown(field)
	assert_gt(
		_blades_in(Vector2(11.5, 3.5), Vector2(16.5, 8.5)).size(),
		0,
		"Water floating above the bed is not water the grass is under"
	)

func test_a_rigid_prop_is_looked_past_frozen_or_not() -> void:
	# A field is grown once. A prop taken for an obstacle would leave a grass-shaped hole the day it was
	# knocked over, so scenery that should clear grass is a StaticBody3D, as the campfire in the demo is.
	_build_scene()
	var parked: RigidBody3D = _prop(Vector3(-20.0, 1.0, -4.0), true)
	var loose: RigidBody3D = _prop(Vector3(-20.0, 1.0, 4.0), false)
	await _grown(field)
	field.regenerate()
	assert_gt(_blades_in(Vector2(-21.5, -5.5), Vector2(-18.5, -2.5)).size(), 0, "Grass grows under a frozen prop")
	assert_gt(_blades_in(Vector2(-21.5, 2.5), Vector2(-18.5, 5.5)).size(), 0, "and under a loose one")
	assert_true(parked.freeze and not loose.freeze, "whether or not the prop is frozen")

func test_a_moving_platform_is_looked_past_even_in_the_ground_group() -> void:
	# Blades baked on top of it would hang in the air the moment the platform moved.
	_build_scene()
	var platform := AnimatableBody3D.new()
	platform.name = &"Platform"
	platform.position = Vector3(-20.0, 1.5, 16.0)
	platform.add_to_group(&"GRASS")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.0, 4.0)
	shape.shape = box
	platform.add_child(shape)
	root.add_child(platform)
	await _grown(field)
	field.regenerate()
	var under: Array[Vector3] = _blades_in(Vector2(-21.5, 14.5), Vector2(-18.5, 17.5))
	assert_gt(under.size(), 0, "The grass grows on the floor the platform stands over")
	for origin: Vector3 in under:
		assert_almost_eq(origin.y, 0.0, HEIGHT_EPSILON, "not on top of the platform")

func test_a_cell_straddling_a_ledge_holds_two_levels() -> void:
	_build_scene()
	await _grown(field)
	var cell: Vector2i = field._cell_of(Vector3(-7.5, 0.0, -15.0)) # The ledge's west face (x = -7) runs through it
	assert_true(field._cell_levels.has(cell), "The straddling cell holds grass")
	var levels: PackedVector2Array = field._cell_levels[cell]
	assert_eq(levels.size(), 2, "on two levels, not one band spanning both")
	assert_almost_eq(levels[0].y, 0.0, 0.05, "the flat ground")
	assert_almost_eq(levels[1].x, 3.0, 0.05, "and the top of the ledge")
	assert_true(field.ignite_at(Vector3(-7.5, 0.0, -15.0), 1.0, 6.0), "A flame down on the flat lights it")
	assert_almost_eq(field._fire_levels[cell].x, 0.0, 0.05, "and the fire in it is on the level the flame was")

func test_the_fire_front_does_not_climb_a_ledge() -> void:
	_build_scene()
	await _grown(field)
	field.fire_spread_speed = GrassField.CREEP_SPEED_MAX
	assert_true(field.ignite_at(Vector3(-14.0, 0.0, 4.0), 1.0, 60.0), "The flat ground south of the plateau catches")
	for _step: int in 200:
		field._process(0.1) # 20 seconds, far longer than the front needs to reach the plateau's foot

	# What matters is the height the fire is burning at, not whether a cell that also holds flat grass is
	# alight: a cell the ledge's face runs through is meant to burn on its low level.
	var climbed: int = 0
	var high_cells: int = 0
	var climbed_a_bank: bool = false
	for cell: Vector2i in field._cell_levels:
		var levels: PackedVector2Array = field._cell_levels[cell]
		var burning_at: float = field._fire_levels.get(cell, Vector2(NAN, NAN)).x
		# The plateau (x -18..-10, z 8..16) sits on the cell grid; the ledge (x -7..0, z -19..-13) does not,
		# and its straddling cells are what a single min-max band per cell let the front bridge.
		var on_the_plateau: bool = _cell_within(cell, Vector3(-18.0, 0.0, 8.0), Vector3(-10.1, 0.0, 15.9))
		var on_the_ledge: bool = _cell_within(cell, Vector3(-7.0, 0.0, -19.0), Vector3(-0.1, 0.0, -13.1))
		var on_the_bank: bool = _cell_within(cell, Vector3(-9.7, 0.0, -3.0), Vector3(-2.3, 0.0, 2.9))
		if on_the_plateau or on_the_ledge:
			if levels[levels.size() - 1].x > 1.0:
				high_cells += 1
			if not is_nan(burning_at) and burning_at > 1.0:
				climbed += 1
		elif on_the_bank and not is_nan(burning_at) and burning_at > 1.0:
			climbed_a_bank = true

	assert_gt(high_cells, 0, "There is ground three metres up to climb to")
	assert_true(
		field._fire_levels.has(field._cell_of(Vector3(-7.5, 0.0, -15.0))),
		"The front reached the foot of the ledge, so it had the chance to climb it"
	)
	assert_gt(field._burnt_cells.size() + field._burning_cells.size(), 1, "and the front spread across the flat")
	assert_eq(climbed, 0, "but the fire never burns up on the plateau or the ledge, on the grid or off it")
	assert_true(climbed_a_bank, "while the 25 degree bank, which it could walk up, burns to the top")

func test_a_flame_over_bare_ground_reports_that_it_lit_nothing() -> void:
	_build_scene()
	await _grown(field)
	assert_false(
		field.ignite_at(Vector3(4.0, 0.0, 0.0), 1.0, 6.0),
		"There is no ground in the hole, so no grass, so nothing caught"
	)
	assert_eq(field._burning_cells.size(), 0, "and the field is not left thinking a fire is running")
	assert_almost_eq(field._spread_time_left, 0.0, 0.001, "nor with a front left to grow for six seconds")


func test_a_field_that_has_not_grown_yet_lights_nothing_and_says_so() -> void:
	_build_scene()
	var fresh: GrassField = _field()
	assert_false(
		fresh.ignite_at(Vector3(0.0, 0.0, 0.0), 2.0, 6.0),
		"A field still counting down to its first grow has no grass to light"
	)
	await _grown(fresh)
	assert_true(fresh.ignite_at(Vector3(0.0, 0.0, 0.0), 2.0, 6.0), "and lights it once it has grown")


func test_a_scaled_field_still_probes_the_full_height() -> void:
	_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0), &"Floor")
	var scaled: GrassField = _field()
	scaled.instance_count = 300
	scaled.position = Vector3(0.0, 8.0, 0.0)
	scaled.scale = Vector3(1.0, 0.25, 1.0)
	await _grown(scaled)
	assert_eq(scaled.get_instance_origins().size(), 300, "probe_height is metres whatever the node's scale")
	for origin: Vector3 in scaled.get_instance_origins():
		assert_almost_eq((scaled.global_transform * origin).y, 0.0, HEIGHT_EPSILON, "and the blades land on the floor")


## A rigid prop resting on the ground, frozen or loose.
func _prop(centre: Vector3, frozen: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = &"Prop%s" % ("Parked" if frozen else "Loose")
	body.position = centre
	body.freeze = frozen
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.0, 3.0)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	return body


func test_the_regrow_button_is_wired_to_a_live_method() -> void:
	# The inspector button calls this Callable. Nothing else would catch a rename of regenerate().
	_build_scene()
	await _grown(field)
	assert_true(field.regrow_action.is_valid(), "The Regrow button's Callable points at something")
	var before: int = field.get_instance_origins().size()
	blocker.queue_free()
	await wait_physics_frames(2)
	field.regrow_action.call()
	assert_gt(field.get_instance_origins().size(), before, "and pressing it regrows against the colliders as they now stand")


## Whether [param cell] lies within the grid cells covering the rectangle between two corners on the ground.
func _cell_within(cell: Vector2i, corner_a: Vector3, corner_b: Vector3) -> bool:
	var low: Vector2i = field._cell_of(corner_a)
	var high: Vector2i = field._cell_of(corner_b)
	return cell.x >= low.x and cell.x <= high.x and cell.y >= low.y and cell.y <= high.y


func test_a_fire_on_the_flat_leaves_the_ledge_above_it_alone() -> void:
	# Every cell the ledge's west face runs through holds grass on both levels. Lighting them on the flat must
	# put each flame down on the flat, and burn only the flat blades. (The blades' own fire data cannot be read
	# back headless, where the dummy renderer keeps no MultiMesh data, so the burning set is checked through
	# the filter _ignite_cell hands them to.)
	_build_scene()
	await _grown(field)
	var straddling: int = 0
	for z: float in [-18.5, -16.5, -14.5, -13.5]:
		var at: Vector3 = Vector3(-7.5, 0.0, z)
		var cell: Vector2i = field._cell_of(at)
		if field._cell_levels.get(cell, PackedVector2Array()).size() != 2:
			continue
		straddling += 1
		assert_true(field.ignite_at(at, 0.0, 6.0), "A flame on the flat lights cell %s" % cell)
		var burning: Array[int] = field._blades_on(cell, field._fire_levels[cell])
		assert_gt(burning.size(), 0, "on the flat grass in it")
		for idx: int in burning:
			if field._instance_origins[idx].y > 1.5:
				fail_test("Cell %s burning on the flat also burns a ledge-top blade at %s" % [cell, field._instance_origins[idx]])
				return
	assert_gt(straddling, 1, "The ledge's face runs through several cells holding both levels")
	assert_eq(field._trail_nodes.size(), straddling, "one flame for each")
	for node: FireTrailNode in field._trail_nodes:
		assert_lt(node.position.y, 1.0, "Each flame stands on the flat, not up on the ledge: %s" % node.position)

func test_a_cell_burning_on_one_level_does_not_count_for_the_other() -> void:
	_build_scene()
	await _grown(field)
	var straddling: Vector3 = Vector3(-7.5, 0.0, -15.0)
	assert_true(field.ignite_at(straddling, 0.0, 6.0), "The flat grass of the straddling cell catches")
	var above: Vector3 = Vector3(-6.5, 3.0, -15.0) # The same cell, up on the ledge
	assert_eq(field._cell_of(above), field._cell_of(straddling), "Both points are in one cell")
	assert_false(
		field.ignite_at(above, 0.0, 30.0),
		"A flame on the ledge top lit nothing: its level of the cell is not the one burning"
	)
	assert_almost_eq(field._spread_time_left, 6.0, 0.001, "so it did not stretch the fire's thirty seconds over the field")


func test_a_flame_between_two_levels_lights_the_nearer_one() -> void:
	_build_scene()
	await _grown(field)
	var cell := Vector2i(100, 100) # Off the field's grass: levels set by hand, 1.8 m apart
	field._cell_levels[cell] = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.8, 1.8)])
	assert_eq(field._level_at(cell, 1.0), 1, "A flame at 1.0 m is nearer the upper level (0.8 m) than the lower (1.0 m)")
	assert_eq(field._level_at(cell, 0.7), 0, "and one at 0.7 m is nearer the lower")
	assert_eq(field._level_at(cell, 3.0), -1, "and one 1.2 m above the upper is out of reach of both")
	assert_eq(field._level_beside(cell, Vector2(1.5, 1.7)), 1, "A front burning at 1.5 to 1.7 m crosses to the upper level")


func test_a_csg_ground_is_grown_on_once_its_collider_is_built() -> void:
	# CSG builds its collider in a deferred call, which is the whole reason the grow waits two physics frames.
	var ground := CSGBox3D.new()
	ground.use_collision = true
	ground.size = Vector3(30.0, 1.0, 30.0)
	ground.position = Vector3(0.0, -0.5, 0.0)
	ground.add_to_group(&"GRASS")
	root.add_child(ground)
	var csg_field: GrassField = GrassField.new()
	csg_field.field_size = Vector2(20.0, 20.0)
	csg_field.instance_count = 500
	root.add_child(csg_field)
	assert_eq(csg_field.get_instance_origins().size(), 0, "Nothing has grown in the frame the field was added")
	await _grown(csg_field)
	assert_eq(csg_field.get_instance_origins().size(), 500, "Every blade grows on the CSG box once it has a collider")
	for origin: Vector3 in csg_field.get_instance_origins():
		if absf(origin.y) > 0.01:
			fail_test("A blade at %s is not on the box's top" % origin)
			return
	assert_eq(csg_field._get_configuration_warnings().size(), 0, "and the field does not warn that it found no ground")


func _big_field() -> GrassField:
	var big: GrassField = GrassField.new()
	big.field_size = Vector2(FIELD_HALF * 2.0, FIELD_HALF * 2.0)
	big.instance_count = 30000 # Far more rays than one frame's budget, on any machine
	root.add_child(big)
	return big


func test_a_big_field_grows_over_several_frames_into_exactly_what_growing_at_once_gives() -> void:
	_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0), &"Floor")
	var big: GrassField = _big_field()
	var frames: int = 0
	while big.is_growing() and frames < 600:
		await wait_physics_frames(1)
		frames += 1
	assert_gt(frames, 4, "Its rays were spread over frames rather than cast in one (%d frames)" % frames)
	var spread: Array[Vector3] = big.get_instance_origins().duplicate()
	assert_eq(spread.size(), 30000, "and every blade grew on the floor")
	big.regenerate()
	var at_once: Array[Vector3] = big.get_instance_origins()
	assert_eq(at_once.size(), spread.size(), "Growing the same field in one go grows as many")
	var moved: int = 0
	for i: int in spread.size():
		if not at_once[i].is_equal_approx(spread[i]):
			moved += 1
	assert_eq(moved, 0, "and every blade in the same place")


func test_grown_fires_once_per_grow() -> void:
	_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0), &"Floor")
	var big: GrassField = _big_field()
	var fired: Array[int] = [0]
	big.grown.connect(func() -> void: fired[0] += 1)
	await _grown(big)
	assert_eq(fired[0], 1, "Once when the spread-out grow is done")
	big.regenerate()
	assert_eq(fired[0], 2, "and once for a grow done at once")


func test_changing_the_field_during_a_grow_wins_over_the_grow() -> void:
	_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0), &"Floor")
	var big: GrassField = _big_field()
	await wait_physics_frames(3) # Past the countdown and into the rays
	assert_true(big.is_growing(), "The 30 000 blade grow is under way")
	big.instance_count = 100 # The setter grows the field again, at once
	assert_false(big.is_growing(), "which ends the grow that was under way")
	assert_eq(big.get_instance_origins().size(), 100, "and the field holds what was asked for")
	await wait_physics_frames(10)
	assert_eq(big.get_instance_origins().size(), 100, "with nothing left of the old grow to overwrite it later")


func test_a_field_over_no_ground_at_all_says_so() -> void:
	_build_scene() # Plenty of colliders, just none in the group this field looks for
	var orphan: GrassField = _field(&"NoSuchGroundGroup")
	await _grown(orphan)
	assert_eq(orphan.get_instance_origins().size(), 0, "Nothing grows when no collider is in the ground group")
	var warnings: PackedStringArray = orphan._get_configuration_warnings()
	assert_eq(warnings.size(), 1, "and the node warns about it in the editor")
	assert_string_contains(warnings[0], "NoSuchGroundGroup", "naming the group it looked for")


func test_a_field_that_found_its_ground_does_not_warn() -> void:
	_build_scene()
	await _grown(field)
	assert_gt(field.get_instance_origins().size(), 0, "The field grew")
	assert_eq(field._get_configuration_warnings().size(), 0, "so there is nothing to warn about")


func test_growing_the_same_field_twice_puts_every_blade_back() -> void:
	_build_scene()
	await _grown(field)
	var first: Array[Vector3] = field.get_instance_origins().duplicate()
	field.regenerate()
	var second: Array[Vector3] = field.get_instance_origins()
	assert_eq(second.size(), first.size(), "A regrow against the same scene grows the same number of blades")
	for i: int in first.size():
		assert_eq(second[i], first[i], "and blade %d is in the same place" % i)
