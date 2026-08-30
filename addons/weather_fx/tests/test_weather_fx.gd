extends GutTest

const GaugeNeedleScript: Script = preload("res://addons/weather_fx/scripts/gauge_needle.gd")
const TemperatureGaugeDisplayScript: Script = preload("res://addons/weather_fx/scripts/temperature_gauge_display.gd")
const WindVFXScript: Script = preload("res://addons/weather_fx/scripts/wind_vfx.gd")

var wfx: WeatherFX


func before_each() -> void:
	wfx = WeatherFX.new()
	add_child_autofree(wfx)


func test_all_twenty_biomes_exist() -> void:
	assert_eq(ClimateData.BIOME_DEFINITIONS.size(), 20)
	for i in range(20):
		var zone: ClimateData.BiomeZone = i as ClimateData.BiomeZone
		var data = ClimateData.get_biome_data(zone)
		assert_not_null(data)
		assert_eq(data["day_temps"].size(), 11)
		assert_eq(data["night_temps"].size(), 11)


func test_temperature_interpolation_at_altitude() -> void:
	# Zone 0 Temperate Plains: 0m = 25°C, 100m = 20°C
	var temp_0 = ClimateData.get_temperature(ClimateData.BiomeZone.TEMPERATE_PLAINS, 0.0, true)
	var temp_50 = ClimateData.get_temperature(ClimateData.BiomeZone.TEMPERATE_PLAINS, 50.0, true)
	var temp_100 = ClimateData.get_temperature(ClimateData.BiomeZone.TEMPERATE_PLAINS, 100.0, true)
	assert_almost_eq(temp_0, 25.0, 0.01)
	assert_almost_eq(temp_50, 22.5, 0.01)
	assert_almost_eq(temp_100, 20.0, 0.01)


func test_freezing_point_conversion() -> void:
	assert_true(ClimateData.is_freezing(0.0))
	assert_true(ClimateData.is_freezing(-5.0))
	assert_false(ClimateData.is_freezing(0.1))


func test_forecast_queue_generation() -> void:
	var forecast = wfx.get_forecast()
	assert_eq(forecast.size(), wfx.forecast_length)


func test_advance_cycle() -> void:
	var initial_forecast = wfx.get_forecast()
	var next_expected = initial_forecast[1]
	wfx.advance_cycle()
	var new_forecast = wfx.get_forecast()
	assert_eq(new_forecast.size(), wfx.forecast_length)
	assert_eq(new_forecast[0], next_expected)


func test_manual_weather_override() -> void:
	wfx.set_weather(ClimateData.WeatherType.STORM)
	assert_true(wfx.force_weather)
	assert_eq(wfx.get_current_weather(), ClimateData.WeatherType.STORM)

	wfx.resume_forecast()
	assert_false(wfx.force_weather)


func test_play_pause_weather() -> void:
	wfx.play()
	assert_true(wfx.is_playing)
	wfx.pause()
	assert_false(wfx.is_playing)


func test_hud_forecast_display_updates_on_biome_change() -> void:
	var display = WeatherForecastDisplay.new()
	display.weather_fx_node = wfx
	add_child_autofree(display)

	# Initially TEMPERATE_PLAINS
	assert_true(display._info_label.text.contains("Temperate Plains"))

	# Change biome to ARCTIC_TUNDRA
	wfx.current_biome = ClimateData.BiomeZone.ARCTIC_TUNDRA
	assert_true(display._info_label.text.contains("Arctic Tundra"))


func test_temperature_unit_conversions() -> void:
	assert_almost_eq(ClimateData.celsius_to_fahrenheit(0.0), 32.0, 0.01)
	assert_almost_eq(ClimateData.celsius_to_fahrenheit(100.0), 212.0, 0.01)
	assert_almost_eq(ClimateData.celsius_to_fahrenheit(20.0), 68.0, 0.01)
	assert_almost_eq(ClimateData.fahrenheit_to_celsius(32.0), 0.0, 0.01)
	assert_almost_eq(ClimateData.fahrenheit_to_celsius(212.0), 100.0, 0.01)


func test_hud_forecast_display_temperature_unit_toggle() -> void:
	var display = WeatherForecastDisplay.new()
	display.weather_fx_node = wfx
	add_child_autofree(display)

	# By default should show Celsius
	assert_eq(display.temperature_unit, WeatherForecastDisplay.TemperatureUnit.CELSIUS)
	assert_true(display._info_label.text.contains("°C"))
	assert_false(display._info_label.text.contains("°F"))

	# Switch to Fahrenheit via temperature_unit enum
	display.temperature_unit = WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT
	assert_eq(display.temperature_unit, WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT)
	assert_true(display._info_label.text.contains("°F"))
	assert_false(display._info_label.text.contains("°C"))

	# Switch back to Celsius via temperature_unit enum
	display.temperature_unit = WeatherForecastDisplay.TemperatureUnit.CELSIUS
	assert_eq(display.temperature_unit, WeatherForecastDisplay.TemperatureUnit.CELSIUS)
	assert_true(display._info_label.text.contains("°C"))
	assert_false(display._info_label.text.contains("°F"))


func test_weather_fx_scene_audio_and_vfx() -> void:
	var scene = load("res://addons/weather_fx/scenes/weather_fx.tscn")
	assert_not_null(scene)
	var instance: WeatherFX = scene.instantiate()
	assert_not_null(instance)
	add_child_autofree(instance)

	assert_not_null(instance.rain_particles)
	assert_not_null(instance.rain_splash_particles)
	assert_not_null(instance.snow_particles)
	assert_not_null(instance.audio_rain_light)
	assert_not_null(instance.audio_rain_heavy)
	assert_not_null(instance.audio_storm)
	assert_not_null(instance.audio_wind)

	assert_not_null(instance.audio_rain_light.stream)
	assert_not_null(instance.audio_rain_heavy.stream)
	assert_not_null(instance.audio_storm.stream)
	assert_not_null(instance.audio_wind.stream)

	# Verify rain weather activates rain audio and particles
	instance.set_weather(ClimateData.WeatherType.RAIN)
	assert_true(instance.rain_particles.emitting)
	assert_true(instance.rain_splash_particles.emitting)
	assert_true(instance.audio_rain_light.playing)

	# Verify heavy rain
	instance.set_weather(ClimateData.WeatherType.HEAVY_RAIN)
	assert_true(instance.rain_particles.emitting)
	assert_true(instance.rain_splash_particles.emitting)
	assert_true(instance.audio_rain_heavy.playing)

	# Verify storm
	instance.set_weather(ClimateData.WeatherType.STORM)
	assert_true(instance.rain_particles.emitting)
	assert_true(instance.rain_splash_particles.emitting)
	assert_true(instance.audio_storm.playing)
	assert_true(instance.audio_wind.playing)

	# Verify blue sky clears all audio and particles
	instance.set_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_false(instance.rain_particles.emitting)
	assert_false(instance.rain_splash_particles.emitting)
	assert_false(instance.audio_rain_light.playing)
	assert_false(instance.audio_rain_heavy.playing)
	assert_false(instance.audio_storm.playing)
	assert_false(instance.audio_wind.playing)


func test_weather_fx_pause_stops_sfx_and_vfx() -> void:
	var scene = load("res://addons/weather_fx/scenes/weather_fx.tscn")
	assert_not_null(scene)
	var instance: WeatherFX = scene.instantiate()
	assert_not_null(instance)
	add_child_autofree(instance)

	# Set storm weather (both VFX and SFX active)
	instance.set_weather(ClimateData.WeatherType.STORM)
	assert_true(instance.rain_particles.emitting)
	assert_true(instance.rain_splash_particles.emitting)
	assert_true(instance.audio_storm.playing)
	assert_true(instance.audio_wind.playing)
	assert_gt(instance.current_wind_strength, 0.0)

	# Pausing should stop VFX, SFX, and zero wind strength
	instance.pause()
	assert_false(instance.is_playing)
	assert_false(instance.rain_particles.emitting)
	assert_false(instance.rain_splash_particles.emitting)
	assert_false(instance.audio_storm.playing)
	assert_false(instance.audio_wind.playing)
	assert_almost_eq(instance.current_wind_strength, 0.0, 0.001)

	# Resuming should restore VFX, SFX, and wind strength for active weather
	instance.play()
	assert_true(instance.is_playing)
	assert_true(instance.rain_particles.emitting)
	assert_true(instance.rain_splash_particles.emitting)
	assert_true(instance.audio_storm.playing)
	assert_true(instance.audio_wind.playing)
	assert_gt(instance.current_wind_strength, 0.0)

	# Setting is_playing = false should also stop VFX, SFX, and zero wind strength
	instance.is_playing = false
	assert_false(instance.rain_particles.emitting)
	assert_false(instance.rain_splash_particles.emitting)
	assert_false(instance.audio_storm.playing)
	assert_false(instance.audio_wind.playing)
	assert_almost_eq(instance.current_wind_strength, 0.0, 0.001)

	# Setting is_playing = true should resume VFX, SFX, and wind strength
	instance.is_playing = true
	assert_true(instance.rain_particles.emitting)
	assert_true(instance.rain_splash_particles.emitting)
	assert_true(instance.audio_storm.playing)
	assert_true(instance.audio_wind.playing)
	assert_gt(instance.current_wind_strength, 0.0)


func test_gauge_needle_angle_and_percentage() -> void:
	var needle = GaugeNeedleScript.new()
	needle.min_value = 0.0
	needle.max_value = 100.0
	needle.current_value = 50.0
	add_child_autofree(needle)

	assert_almost_eq(needle.get_percentage(), 50.0, 0.01)
	assert_almost_eq(needle.target_angle, needle.angle_start + 0.5 * needle.angle_range, 0.01)

	needle.set_percentage(100.0)
	assert_almost_eq(needle.current_value, 100.0, 0.01)
	assert_almost_eq(needle.target_angle, needle.angle_start + needle.angle_range, 0.01)


func test_temperature_gauge_display_updates_on_weather_fx() -> void:
	var gauge = TemperatureGaugeDisplayScript.new()
	gauge.weather_fx_node = wfx
	add_child_autofree(gauge)

	wfx.current_temperature = 35.0
	gauge._on_temperature_changed(35.0)

	var needle = gauge.get_needle()
	assert_not_null(needle)
	assert_almost_eq(needle.current_value, 35.0, 0.01)

	# Toggle Fahrenheit
	gauge.temperature_unit = WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT
	assert_almost_eq(needle.current_value, 95.0, 0.01)


func test_weather_forecast_display_botw_mode() -> void:
	var display: WeatherForecastDisplay = WeatherForecastDisplay.new()
	display.weather_fx_node = wfx
	display.botw_style = true
	add_child_autofree(display)

	assert_true(display.botw_style)
	assert_eq(display._icon_rects.size(), 7)
	# Current weather icon should have cyan tint
	assert_almost_eq(display._icon_rects[0].modulate.r, WeatherForecastDisplay.COLOR_CYAN.r, 0.01)
	assert_almost_eq(display._icon_rects[0].modulate.g, WeatherForecastDisplay.COLOR_CYAN.g, 0.01)
	assert_almost_eq(display._icon_rects[0].modulate.b, WeatherForecastDisplay.COLOR_CYAN.b, 0.01)


func test_weather_forecast_display_timeline_scroll() -> void:
	var display: WeatherForecastDisplay = WeatherForecastDisplay.new()
	display.weather_fx_node = wfx
	display.botw_style = true
	display.enable_scrolling = true
	display.scroll_offset_start = 12.0
	display.icon_size = Vector2(24, 24)
	display.icon_separation = 6
	add_child_autofree(display)

	# At cycle start (0s / progress 0.0), position should be scroll_offset_start (12.0)
	wfx._cycle_timer = 0.0
	display._update_scroll_position()
	assert_almost_eq(display._hbox.position.x, 12.0, 0.01)

	# Halfway through cycle (120s / 240s = progress 0.5)
	# Total step = 24 + 6 = 30px. Halfway is -15px.
	wfx._cycle_timer = 120.0
	display._update_scroll_position()
	assert_almost_eq(display._hbox.position.x, 12.0 - 15.0, 0.01)


func test_weather_forecast_display_pops_oldest_and_appends_newest_on_advance() -> void:
	var display: WeatherForecastDisplay = WeatherForecastDisplay.new()
	display.weather_fx_node = wfx
	display.botw_style = true
	display.enable_scrolling = true
	display.scroll_offset_start = 12.0
	add_child_autofree(display)

	var initial_forecast: Array = wfx.get_forecast()
	var expected_new_active = initial_forecast[1]
	var initial_second_rect = display._icon_rects[1]

	# Advance cycle
	wfx.advance_cycle()

	# Display should now have 7 icons
	assert_eq(display._icon_rects.size(), 7)
	assert_eq(display._hbox.get_child_count(), 7)

	# The new front icon is what was previously the second icon
	assert_eq(display._icon_rects[0], initial_second_rect)
	assert_almost_eq(display._icon_rects[0].modulate.r, WeatherForecastDisplay.COLOR_CYAN.r, 0.01)

	# Scroll offset reset to scroll_offset_start
	assert_almost_eq(display._hbox.position.x, 12.0, 0.01)


func test_weather_fx_demo_scene_instantiation() -> void:
	var scene = load("res://addons/weather_fx/scenes/demo/demo.tscn")
	assert_not_null(scene)
	var demo = scene.instantiate()
	assert_not_null(demo)
	add_child_autofree(demo)
	assert_not_null(demo.weather_fx)
	assert_not_null(demo.date_and_time)
	assert_not_null(demo.biome_option_button)
	assert_not_null(demo.weather_option_button)
	assert_eq(demo.biome_option_button.item_count, 20)


func test_weather_fx_renderer_compatibility_setup() -> void:
	var scene = load("res://addons/weather_fx/scenes/weather_fx.tscn")
	assert_not_null(scene)
	var instance: WeatherFX = scene.instantiate()
	assert_not_null(instance)
	add_child_autofree(instance)

	# Compatibility mode: sub-emitters & trails should be disabled
	instance._setup_renderer_compatibility(true)
	assert_eq(instance.rain_particles.sub_emitter, NodePath(""))
	assert_false(instance.rain_particles.trail_enabled)
	var mat_compat = instance.rain_particles.process_material as ParticleProcessMaterial
	assert_not_null(mat_compat)
	assert_eq(mat_compat.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_DISABLED)

	# Forward+ mode: sub-emitter is dynamically connected
	instance._setup_renderer_compatibility(false)
	assert_ne(instance.rain_particles.sub_emitter, NodePath(""))
	var mat_forward = instance.rain_particles.process_material as ParticleProcessMaterial
	assert_not_null(mat_forward)
	assert_eq(mat_forward.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_AT_END)


func test_global_shader_parameters_initialization_and_updates() -> void:
	WeatherFX.ensure_shader_globals()
	assert_true(ProjectSettings.has_setting("shader_globals/weather_wind_strength"))
	assert_true(ProjectSettings.has_setting("shader_globals/weather_wind_direction"))
	assert_true(ProjectSettings.has_setting("shader_globals/weather_precipitation_strength"))

	# Test setting altitude / weather updates wind shader globals without errors
	wfx.current_altitude = 250.0
	wfx.wind_direction = Vector3(0.0, 0.0, 1.0)
	wfx.set_weather(ClimateData.WeatherType.STORM)
	wfx._update_wind_globals()
	pass_test("Wind globals updated without errors")


func test_grass_field_generation_and_properties() -> void:
	var grass_field = GrassField.new()
	add_child_autofree(grass_field)
	
	grass_field.instance_count = 100
	grass_field.field_size = Vector2(20.0, 20.0)
	grass_field.mesh_type = GrassField.GrassMeshType.COMMON_SHORT
	grass_field.regenerate()
	
	assert_not_null(grass_field.multimesh)
	assert_eq(grass_field.multimesh.instance_count, 100)
	
	var mesh = grass_field.multimesh.mesh as ArrayMesh
	assert_not_null(mesh)
	assert_gt(mesh.get_surface_count(), 0)
	
	# Verify Quaternius mesh attributes
	var arrays = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	
	assert_gt(vertices.size(), 0)
	assert_eq(vertices.size(), normals.size())
	assert_eq(vertices.size(), uvs.size())
	
	# Check instance transforms
	var t0 = grass_field.multimesh.get_instance_transform(0)
	assert_almost_eq(t0.origin.y, 0.0, 0.01)

	# Test switching to other Quaternius types
	grass_field.mesh_type = GrassField.GrassMeshType.WISPY_SHORT
	grass_field.regenerate()
	assert_not_null(grass_field.multimesh.mesh)

	grass_field.mesh_type = GrassField.GrassMeshType.COMMON_TALL
	grass_field.regenerate()
	assert_not_null(grass_field.multimesh.mesh)

	grass_field.mesh_type = GrassField.GrassMeshType.WISPY_TALL
	grass_field.regenerate()
	assert_not_null(grass_field.multimesh.mesh)

	# Test exclusion radius clearing
	grass_field.exclusion_radius = 4.0
	grass_field.exclusion_center = Vector2(0.0, 0.0)
	grass_field.regenerate()
	var origins = grass_field.get_instance_origins()
	assert_eq(origins.size(), grass_field.instance_count)
	for org in origins:
		var dist = Vector2(org.x, org.z).length()
		assert_gt(dist, 3.99, "Grass instances should be outside exclusion radius")


func test_grass_material_resource() -> void:
	var mat = load("res://addons/weather_fx/resources/grass_material.tres") as ShaderMaterial
	assert_not_null(mat)
	assert_not_null(mat.shader)
	assert_not_null(mat.get_shader_parameter("color_base"))
	assert_not_null(mat.get_shader_parameter("color_tip"))
	assert_not_null(mat.get_shader_parameter("texture_albedo"))
	assert_not_null(mat.get_shader_parameter("wind_speed"))


func test_date_and_time_node_and_manual_time_synchronization() -> void:
	var clock_script = load("res://addons/weather_fx/scenes/demo/demo_date_and_time.gd")
	assert_not_null(clock_script)
	var clock = clock_script.new()
	add_child_autofree(clock)
	clock.current_time = 6.0

	var test_wfx = WeatherFX.new()
	add_child_autofree(test_wfx)

	# Assign date_and_time_node
	test_wfx.date_and_time_node = clock
	assert_almost_eq(test_wfx.get_current_time_hours(), 6.0, 0.01)

	# Modifying clock.current_time emits time_changed, updating test_wfx and manual_time_of_day
	clock.current_time = 18.0
	assert_almost_eq(test_wfx.get_current_time_hours(), 18.0, 0.01)
	assert_almost_eq(test_wfx.manual_time_of_day, 18.0, 0.01)

	# Modifying test_wfx.manual_time_of_day updates clock.current_time
	test_wfx.manual_time_of_day = 12.0
	assert_almost_eq(clock.current_time, 12.0, 0.01)
	assert_almost_eq(test_wfx.get_current_time_hours(), 12.0, 0.01)


func test_sun_light_time_and_biome_updates() -> void:
	var light = DirectionalLight3D.new()
	add_child_autofree(light)

	var test_wfx = WeatherFX.new()
	add_child_autofree(test_wfx)
	test_wfx.sun_light = light
	test_wfx.manual_time_of_day = 12.0 # Noon

	# Noon: energy 1.0 (daylight)
	test_wfx._update_sun_lighting()
	assert_almost_eq(light.light_energy, 1.0, 0.01)

	# Midnight (0.0): energy 0.15 (night)
	test_wfx.manual_time_of_day = 0.0
	assert_almost_eq(light.light_energy, 0.15, 0.01)

	# Biome change updates light tint
	test_wfx.set_biome(ClimateData.BiomeZone.VOLCANIC_CRATER)
	test_wfx.manual_time_of_day = 12.0
	assert_almost_eq(light.light_color.r, 1.0, 0.01)
	assert_almost_eq(light.light_color.g, 0.7, 0.01)
	assert_almost_eq(light.light_color.b, 0.5, 0.01)


func test_wind_vfx_instantiation_and_properties() -> void:
	var wind_scn = load("res://addons/weather_fx/scenes/wind_vfx.tscn") as PackedScene
	assert_not_null(wind_scn)
	var wind_inst = wind_scn.instantiate()
	add_child_autofree(wind_inst)
	assert_not_null(wind_inst)
	assert_true(is_instance_of(wind_inst, WindVFXScript))
	assert_true(wind_inst.enabled)
	
	# Test disabling and process handling
	wind_inst.enabled = false
	assert_false(wind_inst.visible)
	wind_inst.enabled = true
	assert_true(wind_inst.visible)
	
	# Test active emission when wind strength >= min_wind_threshold
	WeatherFX.active_wind_strength = 5.0
	wind_inst._process(0.1)
	for p in wind_inst._airflow_particles:
		assert_true(p.emitting)
		
	# Test shutdown when wind strength drops below threshold
	WeatherFX.active_wind_strength = 0.0
	wind_inst._process(0.1)
	for p in wind_inst._airflow_particles:
		assert_false(p.emitting)


func test_precipitation_particles_wind_physics() -> void:
	var wfx_scene = load("res://addons/weather_fx/scenes/weather_fx.tscn") as PackedScene
	assert_not_null(wfx_scene)
	var wfx_inst = wfx_scene.instantiate() as WeatherFX
	add_child_autofree(wfx_inst)
	wfx_inst.is_playing = true

	# Set blowing East with strong wind
	wfx_inst.wind_direction = Vector3(1.0, 0.0, 0.0)
	wfx_inst.wind_strength_multiplier = 2.0
	wfx_inst.apply_weather_effects(ClimateData.WeatherType.RAIN)

	# Rain should slant eastward and align with velocity
	var rain_mat = wfx_inst.rain_particles.process_material as ParticleProcessMaterial
	assert_not_null(rain_mat)
	assert_gt(rain_mat.direction.x, 0.2, "Rain fall direction should slant along wind direction")
	assert_true(rain_mat.particle_flag_align_y, "Rain particles should align Y axis along velocity")

	# Snow test: switch to snow and blow West
	wfx_inst.wind_direction = Vector3(-1.0, 0.0, 0.0)
	wfx_inst.apply_weather_effects(ClimateData.WeatherType.SNOW)

	var snow_mat = wfx_inst.snow_particles.process_material as ParticleProcessMaterial
	assert_not_null(snow_mat)
	assert_lt(snow_mat.direction.x, -0.2, "Snow fall direction should slant westward along wind")
	assert_lt(snow_mat.gravity.x, -0.5, "Snow gravity should pull westward")
	assert_true(snow_mat.turbulence_enabled, "Snow should have turbulence enabled")


func test_pond_water_shader_resource() -> void:
	var mat = load("res://addons/weather_fx/resources/pond_water_material.tres") as ShaderMaterial
	assert_not_null(mat, "Pond water material should load successfully")
	assert_not_null(mat.shader, "Pond water shader should be assigned")
	assert_not_null(mat.get_shader_parameter("shallow_color"))
	assert_not_null(mat.get_shader_parameter("deep_color"))
	assert_not_null(mat.get_shader_parameter("wave_amplitude"))
	assert_not_null(mat.get_shader_parameter("wave_frequency"))
	assert_not_null(mat.get_shader_parameter("normal_map"))


func test_bgs_audio_matching_weather_and_time() -> void:
	var wfx = WeatherFX.new()
	var bgs_dc = AudioStreamPlayer.new()
	var bgs_dr = AudioStreamPlayer.new()
	var bgs_ds = AudioStreamPlayer.new()
	var bgs_nc = AudioStreamPlayer.new()
	var bgs_nr = AudioStreamPlayer.new()
	var bgs_ns = AudioStreamPlayer.new()

	wfx.add_child(bgs_dc)
	wfx.add_child(bgs_dr)
	wfx.add_child(bgs_ds)
	wfx.add_child(bgs_nc)
	wfx.add_child(bgs_nr)
	wfx.add_child(bgs_ns)

	wfx.audio_bgs_day_clear = bgs_dc
	wfx.audio_bgs_day_rain = bgs_dr
	wfx.audio_bgs_day_storm = bgs_ds
	wfx.audio_bgs_night_clear = bgs_nc
	wfx.audio_bgs_night_rain = bgs_nr
	wfx.audio_bgs_night_storm = bgs_ns

	add_child_autofree(wfx)
	wfx.is_playing = true

	# Test Day Clear (12:00)
	wfx.manual_time_of_day = 12.0
	wfx.apply_weather_effects(ClimateData.WeatherType.BLUE_SKY)
	assert_eq(wfx.get_target_bgs_player(), bgs_dc, "Day clear should target bgs_day_clear player")

	# Test Day Rain
	wfx.apply_weather_effects(ClimateData.WeatherType.RAIN)
	assert_eq(wfx.get_target_bgs_player(), bgs_dr, "Day rain should target bgs_day_rain player")

	# Test Day Storm
	wfx.apply_weather_effects(ClimateData.WeatherType.STORM)
	assert_eq(wfx.get_target_bgs_player(), bgs_ds, "Day storm should target bgs_day_storm player")

	# Test Night Clear (22:00)
	wfx.manual_time_of_day = 22.0
	wfx.apply_weather_effects(ClimateData.WeatherType.BLUE_SKY)
	assert_eq(wfx.get_target_bgs_player(), bgs_nc, "Night clear should target bgs_night_clear player")

	# Test Night Rain
	wfx.apply_weather_effects(ClimateData.WeatherType.RAIN)
	assert_eq(wfx.get_target_bgs_player(), bgs_nr, "Night rain should target bgs_night_rain player")

	# Test Night Storm
	wfx.apply_weather_effects(ClimateData.WeatherType.STORM)
	assert_eq(wfx.get_target_bgs_player(), bgs_ns, "Night storm should target bgs_night_storm player")


func test_bgs_unassigned_optional_behavior() -> void:
	var wfx = WeatherFX.new()
	# Without any BGS nodes assigned, WeatherFX should operate cleanly with zero errors
	assert_null(wfx.audio_bgs_day_clear)
	assert_null(wfx.audio_bgs_day_rain)
	assert_null(wfx.audio_bgs_day_storm)
	assert_null(wfx.audio_bgs_night_clear)
	assert_null(wfx.audio_bgs_night_rain)
	assert_null(wfx.audio_bgs_night_storm)
	add_child_autofree(wfx)
	wfx.is_playing = true

	# Applying weather and changing time should execute without errors
	wfx.apply_weather_effects(ClimateData.WeatherType.RAIN)
	wfx.manual_time_of_day = 22.0
	wfx.apply_weather_effects(ClimateData.WeatherType.STORM)
	wfx.clear_all_effects()
	assert_null(wfx.get_target_bgs_player(), "Target BGS player should be null when unassigned")

















