extends GutTest

## Purpose: Unit tests for BotW gold-standard wildfire physics that live with the WeatherFX addon —
## fire front creep speed band, shared wind spread math, burnout group cleanup, scene-wired
## BurnableGrass ignition, BurnableGrass -> GrassField propagation delegation, bucketed grass
## consumption, and Player-class duck typing.

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
	field.ignite_at(Vector3.ZERO, 2.0, 8.0)
	assert_gt(field._creeper_heads.size(), 0, "Ignition should spawn creeper heads")
	for head in field._creeper_heads:
		assert_between(head.speed, GrassField.CREEP_SPEED_MIN, GrassField.CREEP_SPEED_MAX,
				"Fire front creep speed must stay within the BotW 1.2-1.8 m/s band regardless of wind strength")
	field._spawn_branch_head(Vector2.ZERO, Vector2.RIGHT, 0.4)
	var branch: GrassField.CreeperHead = field._creeper_heads[field._creeper_heads.size() - 1]
	assert_between(branch.speed, GrassField.CREEP_SPEED_MIN, GrassField.CREEP_SPEED_MAX, "Branch head creep speed must stay within the BotW band")


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
	var field := _field()
	var grass: BurnableGrass = BURNABLE_GRASS_SCENE.instantiate() as BurnableGrass
	root.add_child(grass)
	assert_eq(field._active_fires.size(), 0)
	grass.ignite()
	assert_gt(field._active_fires.size(), 0, "Igniting BurnableGrass should hand creeping propagation to the overlapping GrassField")


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
	var node: FireTrailNode = field._drop_trail_node(Vector3.ZERO, Vector3.ZERO)
	assert_eq(field._trail_nodes.size(), 1)
	node.free()
	assert_true(field._trail_nodes.is_empty(), "A freed trail node must erase itself so _process never sees a dead reference")
	field._process(0.1)
	assert_true(field._trail_nodes.is_empty())
