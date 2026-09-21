extends GutTest

## Purpose: WeatherFX drives the Binbun sky shader of its world_environment itself: cloud density and colour per
## weather type, the wind's heading and strength as the scroll, dimmed as the sun sets, eased over time on a copy
## of the sky so the asset is untouched, and it only eases while the sky is on its way somewhere.

const SKY: Sky = preload("res://addons/weather_fx/assets/BinbunSky/skies/stylized/stylized_sky_01.tres")

var environment: WorldEnvironment
var wfx: WeatherFX


func before_each() -> void:
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.sky = SKY
	add_child_autofree(environment)
	wfx = WeatherFX.new()
	wfx.world_environment = environment
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY) # the procedural forecast is random; start clear
	add_child_autofree(wfx)


func _param(name: StringName) -> Variant:
	return wfx.sky_material().get_shader_parameter(name)


func test_it_works_on_a_copy_of_the_sky_and_starts_clear() -> void:
	assert_ne(environment.environment.sky, SKY, "The sky was copied")
	assert_eq(SKY.sky_material.get_shader_parameter(&"cloud_density"), 0.5, "and the shared sky keeps its own material")
	assert_ne(environment.environment.sky.sky_material, SKY.sky_material, "and so was its material")
	assert_almost_eq(float(_param(&"cloud_density")), wfx.cloud_clear_density, 0.001)
	assert_almost_eq(float(SKY.sky_material.get_shader_parameter(&"cloud_density")), 0.5, 0.001, "The asset keeps its own value")
	assert_false(wfx.is_easing_clouds(), "Snapped to clear at start, nothing to ease")


func test_it_writes_to_one_cached_copy_of_the_material() -> void:
	var material: ShaderMaterial = wfx.sky_material()
	assert_not_null(material)
	assert_eq(material, environment.environment.sky.sky_material, "The copy in the environment is the one it holds")
	wfx.set_weather(ClimateData.WeatherType.CLOUDY)
	wfx.snap_clouds()
	wfx.wind_direction = Vector3.FORWARD
	await wait_process_frames(2)
	assert_eq(wfx.sky_material(), material, "The same object across writes, never resolved again")


func test_density_and_colour_follow_the_weather() -> void:
	wfx.set_weather(ClimateData.WeatherType.CLOUDY)
	wfx.snap_clouds()
	assert_almost_eq(float(_param(&"cloud_density")), wfx.cloud_cloudy_density, 0.001, "Overcast")
	assert_eq(_param(&"cloud_color"), wfx.cloud_cloudy_color)
	wfx.set_weather(ClimateData.WeatherType.RAIN)
	wfx.snap_clouds()
	assert_almost_eq(float(_param(&"cloud_density")), wfx.cloud_rain_density, 0.001, "Rain")
	assert_eq(_param(&"cloud_color"), wfx.cloud_rain_color)
	assert_lt(wfx.cloud_clear_density, wfx.cloud_cloudy_density)
	assert_lt(wfx.cloud_cloudy_density, wfx.cloud_rain_density)
	assert_lt(wfx.cloud_rain_color.get_luminance(), wfx.cloud_clear_color.get_luminance(), "Rain clouds are darker")


func test_a_change_rolls_in_over_time() -> void:
	wfx.cloud_transition_seconds = 0.5
	wfx.set_weather(ClimateData.WeatherType.CLOUDY)
	assert_true(wfx.is_easing_clouds(), "A new target starts the easing")
	await wait_process_frames(2)
	var partway: float = _param(&"cloud_density")
	assert_gt(partway, wfx.cloud_clear_density, "On its way")
	assert_lt(partway, wfx.cloud_cloudy_density, "but not there yet")
	assert_true(wfx.is_easing_clouds(), "and still easing")


func test_it_settles_on_the_target_and_stops_easing() -> void:
	wfx.cloud_transition_seconds = 0.02
	wfx.set_weather(ClimateData.WeatherType.RAIN)
	wfx.wind_direction = Vector3.RIGHT
	assert_true(wfx.is_easing_clouds())
	await wait_process_frames(20)
	assert_false(wfx.is_easing_clouds(), "Within reach of the target it snaps and stops")
	assert_eq(float(_param(&"cloud_density")), wfx.cloud_rain_density, "exactly on the target")
	assert_eq(_param(&"cloud_color"), wfx.cloud_rain_color)
	assert_eq(_param(&"wind_speed"), Vector2(wfx.current_wind_strength * wfx.cloud_wind_scroll_scale, 0.0), "scrolling down the wind at its strength")
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_true(wfx.is_easing_clouds(), "The next change starts it again")
	wfx.snap_clouds()
	assert_false(wfx.is_easing_clouds(), "and a snap ends it at once")
	assert_eq(float(_param(&"cloud_density")), wfx.cloud_clear_density)


func test_the_wind_scrolls_the_clouds() -> void:
	wfx.wind_direction = Vector3(0.0, 0.3, -1.0)
	wfx.snap_clouds()
	var scroll: Vector2 = _param(&"wind_speed")
	assert_gt(wfx.current_wind_strength, 0.0, "The biome blows")
	assert_almost_eq(scroll.x, 0.0, 0.001)
	assert_almost_eq(scroll.y, -wfx.current_wind_strength * wfx.cloud_wind_scroll_scale, 0.001, "Down the wind, as fast as it blows")
	wfx.is_playing = false # paused: no wind
	wfx.snap_clouds()
	scroll = _param(&"wind_speed")
	assert_almost_eq(scroll.length(), wfx.cloud_wind_min_scroll, 0.001, "Never dead still")
	assert_lt(scroll.y, 0.0, "and keeps its last heading")


func test_it_stays_quiet_without_a_binbun_sky() -> void:
	var plain: WorldEnvironment = WorldEnvironment.new()
	plain.environment = Environment.new()
	add_child_autofree(plain)
	var quiet: WeatherFX = WeatherFX.new()
	quiet.world_environment = plain
	add_child_autofree(quiet)
	quiet.set_weather(ClimateData.WeatherType.RAIN)
	assert_false(quiet.is_easing_clouds(), "Nothing to drive, so nothing to ease")
	assert_null(quiet.sky_material())
	assert_null(WeatherFX.binbun_sky_material(plain))
	assert_true(plain.environment.fog_enabled, "The fog still follows the weather")


func test_the_clouds_dim_with_the_sun_down() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(sun)
	wfx.sun_light = sun
	wfx.manual_time_of_day = 12.0 # noon: the sun overhead
	assert_almost_eq(wfx.cloud_night_factor(), 1.0, 0.001, "Full brightness with the sun overhead")
	assert_eq(wfx.cloud_target_color, wfx.cloud_clear_color, "so the clouds head for the weather colour")
	wfx.manual_time_of_day = 2.0 # the sun well below the horizon
	assert_almost_eq(wfx.cloud_night_factor(), wfx.cloud_night_dim, 0.001, "Night keeps only cloud_night_dim of the colour")
	var dark: Color = Color(wfx.cloud_clear_color.r * wfx.cloud_night_dim, wfx.cloud_clear_color.g * wfx.cloud_night_dim, wfx.cloud_clear_color.b * wfx.cloud_night_dim, wfx.cloud_clear_color.a)
	assert_eq(wfx.cloud_target_color, dark, "so the clouds head for a dark grey, not white, at full alpha")
	assert_true(wfx.is_easing_clouds(), "and ease there")
	wfx.manual_time_of_day = 18.2 # dusk: the sun just under the horizon
	assert_gt(wfx.cloud_night_factor(), wfx.cloud_night_dim)
	assert_lt(wfx.cloud_night_factor(), 1.0)
	wfx.sun_light = null
	wfx.manual_time_of_day = 3.0
	assert_almost_eq(wfx.cloud_night_factor(), 1.0, 0.001, "No sun given: no dimming")


func test_the_sky_shader_never_reverses_clamp_which_whites_out_gl_and_webgl() -> void:
	var shader: Shader = load("res://addons/weather_fx/assets/BinbunSky/src/shader/main.gdshader")
	var regex := RegEx.new()
	regex.compile("clamp[(][ ]*0[.]0[ ]*,[ ]*1[.]0[ ]*,") # no backslashes: GDScript and GLSL escaping both stay out of it
	assert_null(regex.search(shader.code), "clamp(0.0, 1.0, x) is undefined in GLSL and renders white on the Compatibility renderer; write clamp(x, 0.0, 1.0)")


func test_the_weathers_fog_leaves_the_sky_in_view() -> void:
	var plain := WorldEnvironment.new()
	plain.environment = Environment.new()
	add_child_autofree(plain)
	var weather := WeatherFX.new()
	weather.world_environment = plain
	add_child_autofree(weather)
	weather.set_weather(ClimateData.WeatherType.RAIN)
	assert_true(plain.environment.fog_enabled, "Rain brings fog")
	assert_almost_eq(plain.environment.fog_sky_affect, 0.3, 0.001, "that tints the sky a little instead of replacing it (Godot's default of 1 hides the clouds)")
	weather.fog_sky_affect = 0.0
	assert_almost_eq(plain.environment.fog_sky_affect, 0.0, 0.001, "and the export drives it")
