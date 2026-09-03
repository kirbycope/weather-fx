extends GutTest

const WEATHER_FX_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/weather_fx.tscn")
const FORECAST_DISPLAY_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/weather_forecast_display.tscn")
const GAUGE_DISPLAY_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/temperature_gauge_display.tscn")
const WIND_VFX_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/wind_vfx.tscn")

var wfx: WeatherFX


func before_each() -> void:
	wfx = WeatherFX.new()
	add_child_autofree(wfx)


func _forecast_display() -> WeatherForecastDisplay:
	var display: WeatherForecastDisplay = FORECAST_DISPLAY_SCENE.instantiate() as WeatherForecastDisplay
	display.weather_fx = wfx
	add_child_autofree(display)
	return display


func test_all_twenty_biomes_exist() -> void:
	assert_eq(ClimateData.BIOME_DEFINITIONS.size(), 20)
	for i in range(20):
		var data = ClimateData.get_biome_data(i as ClimateData.BiomeZone)
		assert_not_null(data)
		assert_eq(data["day_temps"].size(), 11)
		assert_eq(data["night_temps"].size(), 11)


func test_temperature_interpolation_at_altitude() -> void:
	# Zone 0 Temperate Plains: 0m = 25°C, 100m = 20°C
	assert_almost_eq(ClimateData.get_temperature(ClimateData.BiomeZone.TEMPERATE_PLAINS, 0.0, true), 25.0, 0.01)
	assert_almost_eq(ClimateData.get_temperature(ClimateData.BiomeZone.TEMPERATE_PLAINS, 50.0, true), 22.5, 0.01)
	assert_almost_eq(ClimateData.get_temperature(ClimateData.BiomeZone.TEMPERATE_PLAINS, 100.0, true), 20.0, 0.01)


func test_freezing_point_conversion() -> void:
	assert_true(ClimateData.is_freezing(0.0))
	assert_true(ClimateData.is_freezing(-5.0))
	assert_false(ClimateData.is_freezing(0.1))


func test_forecast_queue_generation() -> void:
	assert_eq(wfx.get_forecast().size(), wfx.forecast_length)


func test_advance_cycle() -> void:
	var next_expected = wfx.get_forecast()[1]
	wfx.advance_cycle()
	var new_forecast = wfx.get_forecast()
	assert_eq(new_forecast.size(), wfx.forecast_length)
	assert_eq(new_forecast[0], next_expected)


func test_manual_weather_override() -> void:
	wfx.set_weather(ClimateData.WeatherType.STORM)
	assert_true(wfx.force_weather)
	assert_eq(wfx.active_weather, ClimateData.WeatherType.STORM)
	wfx.resume_forecast()
	assert_false(wfx.force_weather)


func test_playback_toggle_emits_playback_changed() -> void:
	watch_signals(wfx)
	wfx.is_playing = false
	assert_signal_emitted_with_parameters(wfx, "playback_changed", [false])
	assert_almost_eq(wfx.current_wind_strength, 0.0, 0.001)
	wfx.is_playing = true
	assert_signal_emitted_with_parameters(wfx, "playback_changed", [true])
	assert_gt(wfx.current_wind_strength, 0.0)


func test_weather_fx_registers_in_group() -> void:
	assert_true(wfx.is_in_group("WeatherFX"))
	assert_eq(get_tree().get_first_node_in_group("WeatherFX"), wfx)


func test_hud_forecast_display_updates_on_biome_change() -> void:
	var display := _forecast_display()
	assert_true(display._info_label.text.contains("Temperate Plains"))
	wfx.current_biome = ClimateData.BiomeZone.ARCTIC_TUNDRA
	assert_true(display._info_label.text.contains("Arctic Tundra"))


func test_hud_forecast_icons_match_new_forecast_on_biome_change() -> void:
	var display := _forecast_display()
	# DESERT_GLACIER locks daytime weather to blue sky; from 06:00 all 7 cycles (1.6 h each) stay in daylight,
	# so the regenerated forecast is deterministic
	wfx.manual_time_of_day = 6.0
	wfx.current_biome = ClimateData.BiomeZone.DESERT_GLACIER
	var forecast: Array = wfx.get_forecast()
	assert_eq(display._icon_rects.size(), forecast.size())
	for i in range(forecast.size()):
		assert_eq(forecast[i], ClimateData.WeatherType.BLUE_SKY)
		assert_eq(display._icon_rects[i].texture, ClimateData.get_weather_icon(forecast[i]),
				"Icon %d should show the regenerated forecast, not the stale one" % i)


func test_altitude_change_only_updates_temperature() -> void:
	watch_signals(wfx)
	wfx.current_altitude = 300.0
	assert_signal_emitted(wfx, "temperature_changed")
	assert_signal_not_emitted(wfx, "wind_changed")
	assert_signal_not_emitted(wfx, "weather_changed")


func test_time_change_emits_daylight_changed_once() -> void:
	watch_signals(wfx)
	wfx.manual_time_of_day = 13.0
	assert_signal_not_emitted(wfx, "daylight_changed", "Noon to 13:00 stays daytime")
	wfx.manual_time_of_day = 22.0
	assert_signal_emitted_with_parameters(wfx, "daylight_changed", [false])
	assert_signal_not_emitted(wfx, "wind_changed", "Time of day must not re-emit wind")


func test_temperature_unit_conversions() -> void:
	assert_almost_eq(ClimateData.celsius_to_fahrenheit(0.0), 32.0, 0.01)
	assert_almost_eq(ClimateData.celsius_to_fahrenheit(100.0), 212.0, 0.01)
	assert_almost_eq(ClimateData.celsius_to_fahrenheit(20.0), 68.0, 0.01)
	assert_almost_eq(ClimateData.fahrenheit_to_celsius(32.0), 0.0, 0.01)
	assert_almost_eq(ClimateData.fahrenheit_to_celsius(212.0), 100.0, 0.01)


func test_hud_forecast_display_temperature_unit_toggle() -> void:
	var display := _forecast_display()
	assert_eq(display.temperature_unit, WeatherForecastDisplay.TemperatureUnit.CELSIUS)
	assert_true(display._info_label.text.contains("°C"))
	assert_false(display._info_label.text.contains("°F"))

	display.temperature_unit = WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT
	assert_true(display._info_label.text.contains("°F"))
	assert_false(display._info_label.text.contains("°C"))

	display.temperature_unit = WeatherForecastDisplay.TemperatureUnit.CELSIUS
	assert_true(display._info_label.text.contains("°C"))
	assert_false(display._info_label.text.contains("°F"))


func test_weather_fx_scene_audio_and_vfx() -> void:
	var instance: WeatherFX = WEATHER_FX_SCENE.instantiate() as WeatherFX
	add_child_autofree(instance)
	var precip: PrecipitationFX = instance.get_node("PrecipitationFX") as PrecipitationFX
	var audio: WeatherAudio = instance.get_node("WeatherAudio") as WeatherAudio
	var wind_vfx: WindVFX = instance.get_node("WindVFX") as WindVFX
	assert_not_null(precip.rain_particles)
	assert_not_null(precip.rain_splash_particles)
	assert_not_null(precip.snow_particles)
	assert_not_null(audio.audio_rain_light.stream)
	assert_not_null(audio.audio_rain_heavy.stream)
	assert_not_null(audio.audio_storm.stream)
	assert_not_null(audio.audio_wind.stream)
	assert_eq(instance.get_node("CycleTimer"), instance.cycle_timer)

	instance.set_weather(ClimateData.WeatherType.RAIN)
	assert_true(precip.rain_particles.emitting)
	assert_true(precip.rain_splash_particles.emitting)
	assert_true(audio.audio_rain_light.playing)
	assert_true(wind_vfx.visible)

	instance.set_weather(ClimateData.WeatherType.HEAVY_RAIN)
	assert_true(precip.rain_particles.emitting)
	assert_true(audio.audio_rain_heavy.playing)
	assert_false(audio.audio_rain_light.playing)

	instance.set_weather(ClimateData.WeatherType.STORM)
	assert_true(precip.rain_particles.emitting)
	assert_true(audio.audio_storm.playing)
	assert_true(audio.audio_wind.playing)
	assert_true(wind_vfx.visible)

	instance.set_weather(ClimateData.WeatherType.SNOW)
	assert_false(precip.rain_particles.emitting)
	assert_true(precip.snow_particles.emitting)

	# Blue sky clears all audio and particles, and disables wind vfx
	instance.set_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_false(precip.rain_particles.emitting)
	assert_false(precip.rain_splash_particles.emitting)
	assert_false(precip.snow_particles.emitting)
	assert_false(audio.audio_rain_light.playing)
	assert_false(audio.audio_rain_heavy.playing)
	assert_false(audio.audio_storm.playing)
	assert_false(audio.audio_wind.playing)
	assert_false(wind_vfx.visible)


func test_weather_fx_pause_stops_sfx_and_vfx() -> void:
	var instance: WeatherFX = WEATHER_FX_SCENE.instantiate() as WeatherFX
	add_child_autofree(instance)
	var precip: PrecipitationFX = instance.get_node("PrecipitationFX") as PrecipitationFX
	var audio: WeatherAudio = instance.get_node("WeatherAudio") as WeatherAudio

	instance.set_weather(ClimateData.WeatherType.STORM)
	assert_true(precip.rain_particles.emitting)
	assert_true(audio.audio_storm.playing)
	assert_gt(instance.current_wind_strength, 0.0)
	assert_false(instance.cycle_timer.paused)

	instance.is_playing = false
	assert_false(precip.rain_particles.emitting)
	assert_false(precip.rain_splash_particles.emitting)
	assert_false(audio.audio_storm.playing)
	assert_false(audio.audio_wind.playing)
	assert_almost_eq(instance.current_wind_strength, 0.0, 0.001)
	assert_true(instance.cycle_timer.paused, "Pausing must pause the cycle timer")

	instance.is_playing = true
	assert_true(precip.rain_particles.emitting)
	assert_true(precip.rain_splash_particles.emitting)
	assert_true(audio.audio_storm.playing)
	assert_true(audio.audio_wind.playing)
	assert_gt(instance.current_wind_strength, 0.0)
	assert_false(instance.cycle_timer.paused)


func test_gauge_needle_angle_and_percentage() -> void:
	var needle := GaugeNeedle.new()
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
	var gauge: TemperatureGaugeDisplay = GAUGE_DISPLAY_SCENE.instantiate() as TemperatureGaugeDisplay
	gauge.weather_fx = wfx
	add_child_autofree(gauge)
	assert_is(gauge._needle, GaugeNeedle)
	assert_eq(gauge.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	wfx.current_altitude = 300.0
	assert_almost_eq(gauge._needle.current_value, wfx.current_temperature, 0.01, "Needle follows temperature_changed")

	gauge._on_temperature_changed(35.0)
	assert_almost_eq(gauge._needle.current_value, 35.0, 0.01)
	gauge.temperature_unit = WeatherForecastDisplay.TemperatureUnit.FAHRENHEIT
	assert_almost_eq(gauge._needle.current_value, 95.0, 0.01)


func test_weather_forecast_display_scene_shows_seven_icons() -> void:
	var display := _forecast_display()
	assert_true(display.botw_style)
	assert_eq(display._icon_rects.size(), 7)
	assert_eq(display._hbox.get_child_count(), 7)
	assert_eq(display.get_theme_stylebox("panel"), WeatherForecastDisplay.BOTW_PANEL_STYLE)
	await wait_process_frames(1)
	assert_eq(display.size.y, 56.0, "The strip grows to fit its label and icon rows, as the original code-built widget did")
	# Current weather icon should have cyan tint
	assert_almost_eq(display._icon_rects[0].modulate.r, WeatherForecastDisplay.COLOR_CYAN.r, 0.01)
	assert_almost_eq(display._icon_rects[0].modulate.g, WeatherForecastDisplay.COLOR_CYAN.g, 0.01)
	assert_almost_eq(display._icon_rects[0].modulate.b, WeatherForecastDisplay.COLOR_CYAN.b, 0.01)


func test_weather_forecast_display_timeline_scroll() -> void:
	var instance: WeatherFX = WEATHER_FX_SCENE.instantiate() as WeatherFX
	add_child_autofree(instance)
	var display: WeatherForecastDisplay = FORECAST_DISPLAY_SCENE.instantiate() as WeatherForecastDisplay
	display.weather_fx = instance
	display.scroll_offset_start = 12.0
	add_child_autofree(display)

	# Cycle just started: strip sits at scroll_offset_start and a tween drives it one icon step over the cycle
	assert_almost_eq(instance.get_cycle_progress(), 0.0, 0.01)
	assert_almost_eq(display._hbox.position.x, 12.0, 0.01)
	assert_true(display._scroll_tween != null and display._scroll_tween.is_valid(), "Scroll tween should run while simulating")

	instance.is_playing = false
	assert_false(display._scroll_tween.is_valid(), "Pausing kills the scroll tween")


func test_weather_forecast_display_matches_forecast_on_advance() -> void:
	var display := _forecast_display()
	wfx.advance_cycle()
	var forecast: Array = wfx.get_forecast()
	assert_eq(display._icon_rects.size(), 7)
	assert_eq(display._hbox.get_child_count(), 7)
	for i in range(forecast.size()):
		assert_eq(display._icon_rects[i].texture, ClimateData.get_weather_icon(forecast[i]))
	assert_almost_eq(display._icon_rects[0].modulate.r, WeatherForecastDisplay.COLOR_CYAN.r, 0.01)
	assert_almost_eq(display._hbox.position.x, 12.0, 0.01)


func test_weather_fx_demo_scene_instantiation() -> void:
	var demo = load("res://addons/weather_fx/scenes/demo/demo.tscn").instantiate()
	add_child_autofree(demo)
	assert_not_null(demo.weather_fx)
	assert_not_null(demo.date_and_time)
	assert_eq(demo.biome_option_button.item_count, 20)
	assert_is(demo.forecast_display, WeatherForecastDisplay)
	assert_is(demo.gauge_display, TemperatureGaugeDisplay)
	var audio: WeatherAudio = demo.weather_fx.get_node("WeatherAudio") as WeatherAudio
	assert_not_null(audio.bgs_day_clear, "Demo wires BGS players into WeatherFX/WeatherAudio")
	assert_true(demo.weather_fx.weather_changed.is_connected(demo._update_ui_state.unbind(2)), "Demo signals are wired in demo.tscn")


func test_weather_fx_renderer_compatibility_setup() -> void:
	var instance: WeatherFX = WEATHER_FX_SCENE.instantiate() as WeatherFX
	add_child_autofree(instance)
	var precip: PrecipitationFX = instance.get_node("PrecipitationFX") as PrecipitationFX

	# Compatibility mode: sub-emitters & trails should be disabled
	precip._setup_renderer_compatibility(true)
	assert_eq(precip.rain_particles.sub_emitter, NodePath(""))
	assert_false(precip.rain_particles.trail_enabled)
	var mat_compat = precip.rain_particles.process_material as ParticleProcessMaterial
	assert_eq(mat_compat.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_DISABLED)

	# Forward+ mode: sub-emitter is dynamically connected
	precip._setup_renderer_compatibility(false)
	assert_ne(precip.rain_particles.sub_emitter, NodePath(""))
	assert_eq(mat_compat.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_AT_END)


func test_global_shader_parameters_initialization_and_updates() -> void:
	WeatherFX.ensure_shader_globals()
	assert_true(ProjectSettings.has_setting("shader_globals/weather_wind_strength"))
	assert_true(ProjectSettings.has_setting("shader_globals/weather_wind_direction"))
	assert_true(ProjectSettings.has_setting("shader_globals/weather_precipitation_strength"))
	wfx.current_altitude = 250.0
	wfx.wind_direction = Vector3(0.0, 0.0, 1.0)
	wfx.set_weather(ClimateData.WeatherType.STORM)
	assert_almost_eq(WeatherFX.get_precipitation_strength(), 1.2, 0.001)
	assert_eq(WeatherFX.get_wind_direction(), Vector3(0.0, 0.0, 1.0))


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
	var arrays = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_gt(vertices.size(), 0)
	assert_eq(vertices.size(), (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size())
	assert_eq(vertices.size(), (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size())
	assert_almost_eq(grass_field.multimesh.get_instance_transform(0).origin.y, 0.0, 0.01)

	for mesh_type in [GrassField.GrassMeshType.WISPY_SHORT, GrassField.GrassMeshType.COMMON_TALL, GrassField.GrassMeshType.WISPY_TALL]:
		grass_field.mesh_type = mesh_type
		assert_eq(grass_field.multimesh.mesh, GrassField.GRASS_MESHES[mesh_type])

	# Exclusion radius clearing
	grass_field.exclusion_radius = 4.0
	grass_field.exclusion_center = Vector2(0.0, 0.0)
	var origins = grass_field.get_instance_origins()
	assert_eq(origins.size(), grass_field.instance_count)
	for org in origins:
		assert_gt(Vector2(org.x, org.z).length(), 3.99, "Grass instances should be outside exclusion radius")


func test_grass_material_resource() -> void:
	var mat = load("res://addons/weather_fx/resources/grass_material.tres") as ShaderMaterial
	assert_not_null(mat.shader)
	assert_not_null(mat.get_shader_parameter("color_base"))
	assert_not_null(mat.get_shader_parameter("color_tip"))
	assert_not_null(mat.get_shader_parameter("texture_albedo"))
	assert_not_null(mat.get_shader_parameter("wind_speed"))


func test_date_and_time_node_and_manual_time_synchronization() -> void:
	var clock = load("res://addons/weather_fx/scenes/demo/demo_date_and_time.gd").new()
	add_child_autofree(clock)
	clock.current_time = 6.0
	wfx.date_and_time_node = clock
	assert_almost_eq(wfx.get_current_time_hours(), 6.0, 0.01)

	# Modifying clock.current_time emits time_changed, updating wfx and manual_time_of_day
	clock.current_time = 18.0
	assert_almost_eq(wfx.get_current_time_hours(), 18.0, 0.01)
	assert_almost_eq(wfx.manual_time_of_day, 18.0, 0.01)

	# Modifying wfx.manual_time_of_day updates clock.current_time
	wfx.manual_time_of_day = 12.0
	assert_almost_eq(clock.current_time, 12.0, 0.01)
	assert_almost_eq(wfx.get_current_time_hours(), 12.0, 0.01)


func test_sun_light_time_and_biome_updates() -> void:
	var light = DirectionalLight3D.new()
	add_child_autofree(light)
	wfx.sun_light = light
	wfx.manual_time_of_day = 12.0
	assert_almost_eq(light.light_energy, 1.0, 0.01)
	wfx.manual_time_of_day = 0.0
	assert_almost_eq(light.light_energy, 0.15, 0.01)
	wfx.current_biome = ClimateData.BiomeZone.VOLCANIC_CRATER
	wfx.manual_time_of_day = 12.0
	assert_almost_eq(light.light_color.r, 1.0, 0.01)
	assert_almost_eq(light.light_color.g, 0.7, 0.01)
	assert_almost_eq(light.light_color.b, 0.5, 0.01)


func test_wind_vfx_reacts_to_weather_signals() -> void:
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY) # the procedural forecast is random
	var wind_inst: WindVFX = WIND_VFX_SCENE.instantiate() as WindVFX
	wind_inst.weather_fx = wfx
	add_child_autofree(wind_inst)
	assert_eq(wind_inst.airflow_particles.size(), 2)
	assert_eq(wind_inst.leaf_particles.size(), 1)
	assert_true(wind_inst.get_node("GustTimer").timeout.is_connected(wind_inst._on_gust_timer_timeout))

	# Blue sky keeps the ribbons off even though biome wind exceeds the threshold
	assert_false(wind_inst.visible)
	for p in wind_inst.airflow_particles:
		assert_false(p.emitting)

	wfx.set_weather(ClimateData.WeatherType.STORM)
	assert_true(wind_inst.visible)
	for p in wind_inst.airflow_particles:
		assert_true(p.emitting)
	assert_false(wind_inst.get_node("TreeCheckTimer").is_stopped())

	wind_inst.enabled = false
	assert_false(wind_inst.visible)
	for p in wind_inst.airflow_particles:
		assert_false(p.emitting)
	assert_true(wind_inst.get_node("TreeCheckTimer").is_stopped())


func test_precipitation_particles_wind_physics() -> void:
	var instance: WeatherFX = WEATHER_FX_SCENE.instantiate() as WeatherFX
	add_child_autofree(instance)
	var precip: PrecipitationFX = instance.get_node("PrecipitationFX") as PrecipitationFX

	# Blowing East with strong wind: rain slants eastward and aligns with velocity
	instance.wind_direction = Vector3(1.0, 0.0, 0.0)
	instance.wind_strength_multiplier = 2.0
	instance.set_weather(ClimateData.WeatherType.RAIN)
	var rain_mat = precip.rain_particles.process_material as ParticleProcessMaterial
	assert_gt(rain_mat.direction.x, 0.2, "Rain fall direction should slant along wind direction")
	assert_true(rain_mat.particle_flag_align_y, "Rain particles should align Y axis along velocity")

	# Snow blowing West
	instance.wind_direction = Vector3(-1.0, 0.0, 0.0)
	instance.set_weather(ClimateData.WeatherType.SNOW)
	var snow_mat = precip.snow_particles.process_material as ParticleProcessMaterial
	assert_lt(snow_mat.direction.x, -0.2, "Snow fall direction should slant westward along wind")
	assert_lt(snow_mat.gravity.x, -0.5, "Snow gravity should pull westward")
	assert_true(snow_mat.turbulence_enabled, "Snow should have turbulence enabled")


func test_pond_water_shader_resource() -> void:
	var mat = load("res://addons/weather_fx/resources/pond_water_material.tres") as ShaderMaterial
	assert_not_null(mat, "Pond water material should load successfully")
	assert_not_null(mat.shader, "Pond water shader should be assigned")
	assert_eq(mat.shader.resource_path, "res://addons/weather_fx/resources/pond_water.gdshader")
	assert_not_null(mat.get_shader_parameter("shallow_color"))
	assert_not_null(mat.get_shader_parameter("deep_color"))
	assert_not_null(mat.get_shader_parameter("wave_amplitude"))
	assert_not_null(mat.get_shader_parameter("wave_frequency"))
	assert_not_null(mat.get_shader_parameter("normal_map"))
