extends GutTest

## Purpose: Unit tests for BotW gold-standard wildfire physics that live with the WeatherFX addon —
## the cell front's creep speed band and wind lean, shared wind spread math, burnout group cleanup,
## scene-wired BurnableGrass ignition, BurnableGrass -> GrassField propagation delegation, bucketed
## grass lookup, and Player-class duck typing.

const GRASS_FIELD_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/grass_field.tscn")
const BURNABLE_GRASS_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/burnable_grass.tscn")
const FIRE_TRAIL_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/fire_trail_node.tscn")

var root: Node3D


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	WeatherFX.active_wind_strength = 0.0
	WeatherFX.active_wind_direction = Vector3(1.0, 0.0, 0.0)
	WeatherFX.active_precipitation_strength = 0.0
	WeatherFX._player_cache = null
	WeatherFX._player_search_cooldown_frame = -1


func after_each() -> void:
	WeatherFX.active_wind_strength = 0.0
	WeatherFX.active_precipitation_strength = 0.0
	WeatherFX._player_cache = null
	WeatherFX._player_search_cooldown_frame = -1


func _field(count: int = 20, size: float = 40.0) -> GrassField:
	var field: GrassField = GRASS_FIELD_SCENE.instantiate() as GrassField
	field.field_size = Vector2(size, size)
	field.instance_count = count
	root.add_child(field)
	return field


func test_creep_speed_stays_in_botw_band_even_in_storm_wind() -> void:
	WeatherFX.active_wind_strength = 16.0
	var field := _field()
	field.fire_spread_speed = 9.0
	var speed: float = clampf(field.fire_spread_speed, GrassField.CREEP_SPEED_MIN, GrassField.CREEP_SPEED_MAX)
	assert_eq(speed, GrassField.CREEP_SPEED_MAX, "The front never creeps faster than the BotW 1.2-1.8 m/s band")
	var downwind: float = field._seconds_to_catch(Vector2i(1, 0), speed)
	var crosswind: float = field._seconds_to_catch(Vector2i(0, 1), speed)
	var upwind: float = field._seconds_to_catch(Vector2i(-1, 0), speed)
	assert_almost_eq(downwind, GrassField.BUCKET_SIZE / GrassField.CREEP_SPEED_MAX, 0.001, "Downwind the front crosses a cell at the creep speed; a storm does not hurry it")
	assert_gt(crosswind, downwind, "Across the wind is slower")
	assert_gt(upwind, crosswind, "Upwind is slowest, so the front leans downwind")
	assert_almost_eq(upwind, downwind / GrassField.UPWIND_SPEED_FACTOR, 0.001)
	assert_gt(field._seconds_to_catch(Vector2i(1, 1), speed), downwind, "A diagonal step is longer")
	field._on_wind_changed(0.0, Vector3.ZERO)
	assert_almost_eq(field._seconds_to_catch(Vector2i(-1, 0), speed), downwind, 0.001, "Without wind the front is a ring")


func test_the_front_grows_as_a_ring_leaning_downwind_then_burns_out() -> void:
	WeatherFX.active_wind_strength = 8.0
	var field := _field(1600, 40.0)
	assert_true(field.ignite_at(Vector3.ZERO, 2.0, 5.0))
	assert_gt(field._burning_cells.size(), 0, "The cells around the ignition point catch")
	var origin: Vector2i = field._cell_of(Vector3.ZERO)
	for _i: int in 120: # 6 s of spreading (wind blows +X)
		field._process(0.05)
	var lit: Array = field._burning_cells.keys() + field._burnt_cells.keys()
	var downwind: int = 0
	var upwind: int = 0
	var north: int = 0
	var south: int = 0
	for cell: Vector2i in lit:
		downwind += 1 if cell.x > origin.x else 0
		upwind += 1 if cell.x < origin.x else 0
		north += 1 if cell.y > origin.y else 0
		south += 1 if cell.y < origin.y else 0
	assert_gt(lit.size(), 12, "The fire covers ground")
	assert_gt(downwind, upwind, "It leans downwind")
	assert_gt(north, 0, "It spreads across the wind too, not as a line")
	assert_gt(south, 0, "It spreads across the wind too, not as a line")
	assert_gt(field._trail_nodes.size(), 0, "Flame nodes sit on the lit cells")
	assert_lte(field._trail_nodes.size(), GrassField.MAX_TRAIL_NODES)
	for _i: int in 200: # The duration is over: nothing new catches, lit cells burn out
		field._process(0.05)
	assert_lte(field._spread_time_left, 0.0)
	assert_true(field._burning_cells.is_empty(), "Every lit cell has turned to ash")
	assert_eq(field._burnt_cells.size(), lit.size(), "Ash never catches again and the front stopped growing")
	assert_false(field.ignite_at(Vector3(500.0, 0.0, 500.0)), "Off the field there is nothing to light")


func test_rain_douses_the_front_and_chars_what_was_lit() -> void:
	var field := _field(400, 20.0)
	field.ignite_at(Vector3.ZERO, 3.0, 10.0)
	var lit: int = field._burning_cells.size()
	assert_gt(lit, 0)
	field._on_weather_changed(ClimateData.WeatherType.HEAVY_RAIN, ClimateData.WeatherType.BLUE_SKY)
	assert_true(field._burning_cells.is_empty(), "Rain puts the front out")
	assert_eq(field._burnt_cells.size(), lit, "What was lit is ash")
	assert_lte(field._spread_time_left, 0.0)
	assert_true(field._trail_nodes.is_empty())


func test_wind_spread_factor_math() -> void:
	assert_almost_eq(WeatherFX.get_wind_spread_factor(0.0, 6.0), 1.0, 0.001, "Crosswind should not change spread range")
	assert_almost_eq(WeatherFX.get_wind_spread_factor(1.0, 6.0, 0.35), 3.1, 0.001, "Downwind should boost spread range")
	assert_almost_eq(WeatherFX.get_wind_spread_factor(-1.0, 6.0), 0.5, 0.001, "Upwind should suppress spread range")
	assert_almost_eq(WeatherFX.get_wind_spread_factor(1.0, 100.0), 3.5, 0.001, "Downwind boost must be capped")


func test_fire_trail_burnout_removes_updraft_groups() -> void:
	var fire: FireTrailNode = FIRE_TRAIL_SCENE.instantiate() as FireTrailNode
	root.add_child(fire)
	var area: Area3D = fire.get_node("ThermalUpdraftArea") as Area3D
	assert_true(area.is_in_group("Updraft"), "Burning trail node should register an Updraft area")
	assert_true(area.is_in_group("Thermal"), "Burning trail node should register a Thermal area")
	assert_true(fire._life.is_valid(), "Life cycle runs as a Tween")

	fire.extinguish()
	await wait_process_frames(1) # Area3D monitoring toggles are deferred
	assert_false(area.monitoring, "Burned-out updraft area should stop monitoring")
	assert_false(area.is_in_group("Updraft"), "Burned-out updraft area must leave the Updraft group (no ghost lift)")
	assert_false(area.is_in_group("Thermal"), "Burned-out updraft area must leave the Thermal group")
	assert_false(fire._life.is_valid(), "Extinguishing kills the life tween")


func test_fire_trail_extinguishes_on_rain_signal() -> void:
	var wfx := WeatherFX.new()
	root.add_child(wfx)
	var fire: FireTrailNode = FIRE_TRAIL_SCENE.instantiate() as FireTrailNode
	root.add_child(fire)
	assert_true(wfx.weather_changed.is_connected(fire._on_weather_changed))
	wfx.set_weather(ClimateData.WeatherType.HEAVY_RAIN)
	assert_false(fire._light.visible, "Rain via weather_changed extinguishes the trail node")


func test_burnable_grass_ignites_via_scene_wired_hitbox() -> void:
	var grass: BurnableGrass = BURNABLE_GRASS_SCENE.instantiate() as BurnableGrass
	root.add_child(grass)
	var hitbox: Area3D = grass.get_node("HitboxArea") as Area3D
	assert_true(hitbox.body_entered.is_connected(grass._on_body_entered))
	assert_true(grass.get_node("BurnTimer").timeout.is_connected(grass.burn_out))

	var player := CharacterBody3D.new()
	player.add_to_group("Player")
	root.add_child(player)
	hitbox.body_entered.emit(player)
	assert_true(grass._player_nearby, "Scene-wired body_entered tracks the player")

	var torch_area := Area3D.new()
	torch_area.add_to_group("Fire")
	root.add_child(torch_area)
	hitbox.area_entered.emit(torch_area)
	await wait_process_frames(1) # Area3D monitoring toggles are deferred
	assert_true(grass.is_burning, "Scene-wired area_entered ignites from a Fire-group area")
	assert_false(grass.get_node("BurnTimer").is_stopped(), "Burn timer runs while burning")
	assert_true((grass.get_node("ThermalUpdraftArea") as Area3D).monitoring)
	assert_ne(grass.get_node("GrassMesh").material_override, load("res://addons/weather_fx/resources/grass_material.tres"), "Material is duplicated per patch")

	grass.burn_out()
	assert_true(grass.is_charred)
	assert_eq(grass.current_burn_progress, 1.0)
	assert_true(grass.get_node("BurnTimer").is_stopped())


func test_burnable_grass_delegates_creeping_to_grass_field() -> void:
	var field := _field(400, 20.0)
	var grass: BurnableGrass = BURNABLE_GRASS_SCENE.instantiate() as BurnableGrass
	root.add_child(grass)
	assert_eq(field._burning_cells.size(), 0)
	grass.ignite()
	assert_gt(field._burning_cells.size(), 0, "Igniting BurnableGrass should hand the creeping front to the overlapping GrassField")


func test_grass_field_bucketed_lookup_matches_brute_force() -> void:
	# Headless Godot's dummy renderer discards MultiMesh transforms, so compare the index sets instead
	var field := _field(300, 20.0)
	var center := Vector3(1.5, 0.0, -2.0)
	var radius := 3.0
	var expected: Array[int] = []
	for i in range(field._instance_origins.size()):
		var p: Vector3 = field._instance_origins[i]
		if Vector2(p.x - center.x, p.z - center.z).length_squared() <= radius * radius:
			expected.append(i)
	assert_gt(expected.size(), 0, "Test field should have grass inside the radius")
	assert_gt(field._origin_buckets.size(), 1, "Origins are bucketed on the coarse grid")

	var found: Array[int] = field.get_grass_indices_in_radius(center, radius)
	found.sort()
	assert_eq(found, expected, "Grid-bucketed lookup must return exactly the instances within the radius")
	assert_eq(field.get_grass_indices_in_radius(Vector3(500.0, 0.0, 500.0), radius).size(), 0)


func test_is_player_node_prefers_group_then_class() -> void:
	var body := CharacterBody3D.new()
	root.add_child(body)
	body.name = "Player" # A node merely NAMED Player must not match
	assert_false(WeatherFX.is_player_node(body), "Plain CharacterBody3D must not be detected as the Player")
	assert_false(WeatherFX.is_player_node(null))
	body.add_to_group("Player")
	assert_true(WeatherFX.is_player_node(body), "Any node in the Player group must be detected (clean decoupling)")
	assert_eq(WeatherFX.find_player(get_tree()), body, "find_player should use the O(1) Player group lookup")
	body.remove_from_group("Player")


func test_updraft_vfx_falls_back_to_camera_proximity_without_player() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.global_position = Vector3(2.0, 1.0, 0.0)
	var fire: FireTrailNode = FIRE_TRAIL_SCENE.instantiate() as FireTrailNode
	root.add_child(fire)
	fire.global_position = Vector3.ZERO
	fire._process(0.05)
	var updraft_vfx: Node3D = fire.get_node("UpdraftVFX") as Node3D
	assert_true(updraft_vfx.visible, "Without a Player class in the tree, updraft VFX proximity should fall back to the camera")


func test_freed_trail_node_leaves_the_field_list_before_process() -> void:
	var field: GrassField = _field()
	var node: FireTrailNode = field._drop_trail_node(Vector3.ZERO)
	assert_eq(field._trail_nodes.size(), 1)
	node.free()
	assert_true(field._trail_nodes.is_empty(), "A freed trail node must erase itself so _process never sees a dead reference")
	field._process(0.1)
	assert_true(field._trail_nodes.is_empty())
