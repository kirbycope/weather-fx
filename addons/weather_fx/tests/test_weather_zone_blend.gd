extends GutTest

## Purpose: biomes blend where zones overlap instead of cutting from one to the other. A zone's weight is 1 deep
## inside its footprint and fades to 0 over blend_distance from its sides (height ignored); with a target, WeatherFX
## makes the heaviest zone the biome and blends temperature, wind, sun colour and the grass and foliage tints toward
## the runner-up by their weights, continuously across the switch. Without a target the old entry switch still works.

var wfx: WeatherFX
var target: Node3D


func before_each() -> void:
	wfx = WeatherFX.new()
	wfx.enable_biome_tinting = true
	add_child_autofree(wfx)
	target = Node3D.new()
	add_child_autofree(target)


func _zone(biome: ClimateData.BiomeZone, at: Vector3, size: Vector3 = Vector3(40.0, 20.0, 40.0), blend: float = 8.0) -> WeatherZone:
	var zone := WeatherZone.new()
	zone.biome = biome
	zone.blend_distance = blend
	zone.weather_fx = wfx
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	zone.add_child(shape)
	zone.position = at
	add_child_autofree(zone)
	return zone


func test_a_zone_weighs_one_inside_fading_to_nothing_at_its_sides_whatever_the_height() -> void:
	var zone: WeatherZone = _zone(ClimateData.BiomeZone.DESERT_DUNES, Vector3.ZERO)
	assert_almost_eq(zone.get_weight(Vector3.ZERO), 1.0, 0.001, "Full weight in the middle")
	assert_almost_eq(zone.get_weight(Vector3(0.0, 40.0, 0.0)), 1.0, 0.001, "Height never counts")
	assert_almost_eq(zone.get_weight(Vector3(16.0, 0.0, 0.0)), 0.5, 0.001, "Halfway through the fade, 4 m from the side")
	assert_almost_eq(zone.get_weight(Vector3(0.0, 0.0, -18.0)), 0.25, 0.001, "2 m in from the far side")
	assert_almost_eq(zone.get_weight(Vector3(20.0, 0.0, 0.0)), 0.0, 0.001, "Nothing on the edge")
	assert_almost_eq(zone.get_weight(Vector3(25.0, 0.0, 0.0)), 0.0, 0.001, "Nothing outside")
	zone.blend_distance = 0.0
	assert_almost_eq(zone.get_weight(Vector3(19.0, 0.0, 0.0)), 1.0, 0.001, "No fade: full to the edge")
	assert_true(zone.is_in_group(&"WeatherZone"), "WeatherFX finds zones through their group")


func test_overlapping_zones_blend_the_climate_and_hand_over_midway() -> void:
	_zone(ClimateData.BiomeZone.TEMPERATE_PLAINS, Vector3.ZERO) # x from -20 to 20
	_zone(ClimateData.BiomeZone.ARCTIC_TUNDRA, Vector3(-25.0, 0.0, 0.0)) # x from -45 to -5
	wfx.target_node = target
	wfx.manual_time_of_day = 12.0
	assert_true(wfx.is_blending_zones())
	target.position = Vector3.ZERO
	wfx._update_biome_blend()
	assert_eq(wfx.current_biome, ClimateData.BiomeZone.TEMPERATE_PLAINS, "Deep in the plains")
	assert_almost_eq(wfx.blend_weight, 0.0, 0.001, "nothing of the tundra")
	var plains_temp: float = wfx.current_temperature
	var plains_grass: Color = wfx.get_target_grass_tint()

	target.position = Vector3(-8.0, 0.0, 0.0) # plains 12 m in (1.0), tundra 3 m in (0.375)
	wfx._update_biome_blend()
	assert_eq(wfx.current_biome, ClimateData.BiomeZone.TEMPERATE_PLAINS, "Still mostly plains")
	assert_eq(wfx.blend_biome, ClimateData.BiomeZone.ARCTIC_TUNDRA, "blending toward the tundra")
	assert_almost_eq(wfx.blend_weight, 0.375 / 1.375, 0.011, "by its share of the weights")
	assert_lt(wfx.current_temperature, plains_temp, "It is getting colder")
	assert_ne(wfx.get_target_grass_tint(), plains_grass, "and the grass is turning")
	var edge_temp: float = wfx.current_temperature

	target.position = Vector3(-12.5, 0.0, 0.0) # both 7.5 m in: a dead heat
	wfx._update_biome_blend()
	assert_almost_eq(wfx.blend_weight, 0.5, 0.011, "Halfway: an even blend")
	assert_lt(wfx.current_temperature, edge_temp)

	target.position = Vector3(-18.0, 0.0, 0.0) # plains 2 m in (0.25), tundra 13 m in (1.0)
	wfx._update_biome_blend()
	assert_eq(wfx.current_biome, ClimateData.BiomeZone.ARCTIC_TUNDRA, "Past the middle the tundra takes over")
	assert_eq(wfx.blend_biome, ClimateData.BiomeZone.TEMPERATE_PLAINS, "with the plains fading out")
	assert_almost_eq(wfx.blend_weight, 0.25 / 1.25, 0.011)
	var tundra_temp: float = ClimateData.get_smooth_temperature(ClimateData.BiomeZone.ARCTIC_TUNDRA, 0.0, 12.0)
	assert_gt(wfx.current_temperature, tundra_temp, "Warmer than the tundra proper")

	target.position = Vector3(-30.0, 0.0, 0.0) # tundra alone
	wfx._update_biome_blend()
	assert_eq(wfx.current_biome, ClimateData.BiomeZone.ARCTIC_TUNDRA)
	assert_almost_eq(wfx.blend_weight, 0.0, 0.001, "Deep in the tundra, nothing of the plains")
	assert_almost_eq(wfx.current_temperature, tundra_temp, 0.01)

	target.position = Vector3(0.0, 0.0, 60.0) # outside every zone
	wfx._update_biome_blend()
	assert_eq(wfx.current_biome, ClimateData.BiomeZone.ARCTIC_TUNDRA, "Outside every zone the last biome stays")
	assert_almost_eq(wfx.blend_weight, 0.0, 0.001)


func test_the_sun_and_the_wind_blend_too() -> void:
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	wfx.sun_light = sun
	wfx.manual_time_of_day = 12.0
	_zone(ClimateData.BiomeZone.TEMPERATE_PLAINS, Vector3.ZERO)
	_zone(ClimateData.BiomeZone.DESERT_DUNES, Vector3(25.0, 0.0, 0.0))
	wfx.target_node = target
	target.position = Vector3.ZERO
	wfx._update_biome_blend()
	var plains_sun: Color = WeatherFX.get_sun_color(ClimateData.BiomeZone.TEMPERATE_PLAINS, true)
	var desert_sun: Color = WeatherFX.get_sun_color(ClimateData.BiomeZone.DESERT_DUNES, true)
	assert_true(sun.light_color.is_equal_approx(plains_sun), "Plains sun in the plains")
	var plains_wind: float = wfx.current_wind_strength
	target.position = Vector3(12.5, 0.0, 0.0)
	wfx._update_biome_blend()
	assert_true(sun.light_color.is_equal_approx(plains_sun.lerp(desert_sun, 0.5)), "Halfway, half of each")
	var desert_wind: float = ClimateData.get_biome_data(ClimateData.BiomeZone.DESERT_DUNES).get("wind_power", 7.5)
	var plains_power: float = ClimateData.get_biome_data(ClimateData.BiomeZone.TEMPERATE_PLAINS).get("wind_power", 7.5)
	if not is_equal_approx(desert_wind, plains_power):
		assert_ne(wfx.current_wind_strength, plains_wind, "and the wind is between the two")


func test_without_a_target_stepping_into_a_zone_still_switches_the_biome() -> void:
	var zone: WeatherZone = _zone(ClimateData.BiomeZone.DESERT_DUNES, Vector3.ZERO)
	assert_false(wfx.is_blending_zones(), "No target: nothing to weigh the zones around")
	var player := CharacterBody3D.new()
	player.add_to_group(&"Player") # what WeatherFX.is_player_node looks for
	add_child_autofree(player)
	zone._on_body_entered(player)
	assert_eq(wfx.current_biome, ClimateData.BiomeZone.DESERT_DUNES, "The entry switch of old")
	wfx.target_node = target
	zone._on_body_entered(player)
	assert_true(wfx.is_blending_zones())
