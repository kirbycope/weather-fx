extends GutTest

## Purpose: Unit tests for biome foliage/grass tinting — tint targets, transition lerp,
## disable behavior, and a regression guard for the shader global `source_color` binding bug
## (color-typed shader globals silently bind as (0,0,0,0) without the hint, which the
## shaders' fallback guard then turns into an untinted white — no visible tinting).

var wfx: WeatherFX


func before_each() -> void:
	wfx = WeatherFX.new()
	add_child_autofree(wfx)


func test_color_globals_declare_source_color_hint() -> void:
	var shader_paths: Array[String] = [
		"res://addons/weather_fx/resources/grass_wind.gdshader",
		"res://addons/weather_fx/resources/foliage_wind.gdshader",
	]
	var regex := RegEx.new()
	regex.compile("global uniform vec4 (weather_\\w+_tint)([^;]*);")
	for path in shader_paths:
		var shader: Shader = load(path) as Shader
		assert_not_null(shader, "Shader should load: " + path)
		for m in regex.search_all(shader.code):
			assert_string_contains(m.get_string(2), "source_color",
					"%s: color-typed shader global '%s' must declare ': source_color' or it binds as (0,0,0,0)" % [path, m.get_string(1)])


func test_all_biome_tints_are_valid_colors() -> void:
	for i in range(ClimateData.BIOME_DEFINITIONS.size()):
		var zone: ClimateData.BiomeZone = i as ClimateData.BiomeZone
		var foliage: Color = ClimateData.get_biome_foliage_tint(zone)
		var grass: Color = ClimateData.get_biome_grass_tint(zone)
		# Tints darker than the shaders' length<0.01 fallback guard would silently disable tinting
		assert_gt(Vector3(foliage.r, foliage.g, foliage.b).length(), 0.01, "Biome %d foliage tint must not be near-black" % i)
		assert_gt(Vector3(grass.r, grass.g, grass.b).length(), 0.01, "Biome %d grass tint must not be near-black" % i)
		assert_eq(foliage.a, 1.0, "Biome %d foliage tint alpha should be 1.0" % i)
		assert_eq(grass.a, 1.0, "Biome %d grass tint alpha should be 1.0" % i)


func test_tints_lerp_toward_active_biome_targets() -> void:
	wfx.enable_biome_tinting = true
	wfx.current_biome = ClimateData.BiomeZone.AUTUMN_HIGHLANDS
	# Large delta clamps to a full lerp step
	wfx._update_biome_tinting(10.0)
	var target_foliage: Color = wfx.get_target_foliage_tint()
	var target_grass: Color = wfx.get_target_grass_tint()
	assert_almost_eq(wfx.current_foliage_tint.r, target_foliage.r, 0.001, "Foliage tint should reach the biome target")
	assert_almost_eq(wfx.current_foliage_tint.g, target_foliage.g, 0.001)
	assert_almost_eq(wfx.current_grass_tint.r, target_grass.r, 0.001, "Grass tint should reach the biome target")
	assert_almost_eq(wfx.current_grass_tint.g, target_grass.g, 0.001)


func test_temperate_plains_tint_is_identity() -> void:
	wfx.enable_biome_tinting = true
	wfx.current_biome = ClimateData.BiomeZone.TEMPERATE_PLAINS
	var target: Color = wfx.get_target_grass_tint()
	# Materials are authored in temperate colors, so the default biome must render untinted
	assert_almost_eq(target.r, 1.0, 0.001, "Temperate grass tint should be identity (white)")
	assert_almost_eq(target.g, 1.0, 0.001)
	assert_almost_eq(target.b, 1.0, 0.001)
	assert_almost_eq(wfx.get_target_foliage_tint().r, 1.0, 0.001, "Temperate foliage tint should be identity (white)")


func test_normalized_tints_shift_hue_not_just_darken() -> void:
	wfx.enable_biome_tinting = true
	wfx.current_biome = ClimateData.BiomeZone.AUTUMN_HIGHLANDS
	var autumn: Color = wfx.get_target_grass_tint()
	assert_gt(autumn.r, 1.0, "Autumn grass should push the red channel above identity (warm shift)")
	assert_lt(autumn.g, 1.0, "Autumn grass should pull the green channel below identity")


func test_tint_transition_is_gradual() -> void:
	wfx.enable_biome_tinting = true
	wfx.current_grass_tint = Color(1.0, 1.0, 1.0, 1.0)
	wfx.current_biome = ClimateData.BiomeZone.AUTUMN_HIGHLANDS
	wfx._update_biome_tinting(0.05)
	var target: Color = wfx.get_target_grass_tint()
	assert_ne(wfx.current_grass_tint, target, "A single small step should not snap to the target")
	assert_lt(wfx.current_grass_tint.b, 1.0, "Tint should have started moving toward the target")


func test_disabled_tinting_blends_back_to_white() -> void:
	wfx.enable_biome_tinting = false
	wfx.current_biome = ClimateData.BiomeZone.AUTUMN_HIGHLANDS
	wfx._update_biome_tinting(10.0)
	assert_almost_eq(wfx.current_foliage_tint.r, 1.0, 0.001, "Disabled tinting should return foliage tint to white")
	assert_almost_eq(wfx.current_grass_tint.r, 1.0, 0.001, "Disabled tinting should return grass tint to white")
	assert_almost_eq(wfx.current_grass_tint.g, 1.0, 0.001)
	assert_almost_eq(wfx.current_grass_tint.b, 1.0, 0.001)


func test_biome_switch_changes_tint_targets() -> void:
	var plains_grass: Color = ClimateData.get_biome_grass_tint(ClimateData.BiomeZone.TEMPERATE_PLAINS)
	var autumn_grass: Color = ClimateData.get_biome_grass_tint(ClimateData.BiomeZone.AUTUMN_HIGHLANDS)
	assert_ne(plains_grass, autumn_grass, "Distinct biomes should define distinct grass tints")
