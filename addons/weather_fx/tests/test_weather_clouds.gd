extends GutTest

## Purpose: WeatherClouds drives the Binbun sky shader from the weather: cloud density and colour per weather type,
## the wind's heading and strength as the scroll, eased over time on a copy of the sky so the asset is untouched,
## and it only processes while the sky is on its way somewhere.

const SKY: Sky = preload("res://addons/weather_fx/assets/BinbunSky/skies/stylized/stylized_sky_01.tres")

var environment: WorldEnvironment
var clouds: WeatherClouds


func before_each() -> void:
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.sky = SKY
	add_child_autofree(environment)
	clouds = WeatherClouds.new()
	clouds.world_environment = environment
	add_child_autofree(clouds)


func _param(name: StringName) -> Variant:
	return clouds.sky_material().get_shader_parameter(name)


func test_it_works_on_a_copy_of_the_sky_and_starts_clear() -> void:
	assert_ne(environment.environment.sky, SKY, "The sky was copied")
	assert_ne(environment.environment.sky.sky_material, SKY.sky_material, "and so was its material")
	assert_almost_eq(float(_param(&"cloud_density")), clouds.clear_density, 0.001)
	assert_almost_eq(float(SKY.sky_material.get_shader_parameter(&"cloud_density")), 0.5, 0.001, "The asset keeps its own value")
	assert_false(clouds.is_processing(), "Snapped to clear at start, nothing to ease")


func test_it_writes_to_one_cached_copy_of_the_material() -> void:
	var material: ShaderMaterial = clouds._material
	assert_not_null(material)
	assert_eq(material, environment.environment.sky.sky_material, "The copy in the environment is the one it holds")
	clouds.apply_weather(ClimateData.WeatherType.CLOUDY)
	clouds.snap()
	clouds._on_wind_changed(5.0, Vector3.FORWARD)
	await wait_process_frames(2)
	assert_eq(clouds._material, material, "The same object across writes, never resolved again")
	assert_eq(clouds.sky_material(), material)


func test_density_and_colour_follow_the_weather() -> void:
	clouds.apply_weather(ClimateData.WeatherType.CLOUDY)
	clouds.snap()
	assert_almost_eq(float(_param(&"cloud_density")), clouds.cloudy_density, 0.001, "Overcast")
	assert_eq(_param(&"cloud_color"), clouds.cloudy_color)
	clouds.apply_weather(ClimateData.WeatherType.RAIN)
	clouds.snap()
	assert_almost_eq(float(_param(&"cloud_density")), clouds.rain_density, 0.001, "Rain")
	assert_eq(_param(&"cloud_color"), clouds.rain_color)
	assert_lt(clouds.clear_density, clouds.cloudy_density)
	assert_lt(clouds.cloudy_density, clouds.rain_density)
	assert_lt(clouds.rain_color.get_luminance(), clouds.clear_color.get_luminance(), "Rain clouds are darker")


func test_a_change_rolls_in_over_time() -> void:
	clouds.transition_seconds = 0.5
	clouds.apply_weather(ClimateData.WeatherType.CLOUDY)
	assert_true(clouds.is_processing(), "A new target starts the easing")
	await wait_process_frames(2)
	var partway: float = _param(&"cloud_density")
	assert_gt(partway, clouds.clear_density, "On its way")
	assert_lt(partway, clouds.cloudy_density, "but not there yet")
	assert_true(clouds.is_processing(), "and still easing")


func test_it_settles_on_the_target_and_stops_processing() -> void:
	clouds.transition_seconds = 0.02
	clouds.apply_weather(ClimateData.WeatherType.RAIN)
	clouds._on_wind_changed(10.0, Vector3(1.0, 0.0, 0.0))
	assert_true(clouds.is_processing())
	await wait_process_frames(20)
	assert_false(clouds.is_processing(), "Within reach of the target it snaps and stops")
	assert_eq(float(_param(&"cloud_density")), clouds.rain_density, "exactly on the target")
	assert_eq(_param(&"cloud_color"), clouds.rain_color)
	assert_eq(_param(&"wind_speed"), Vector2(10.0 * clouds.wind_scroll_scale, 0.0))
	clouds.apply_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_true(clouds.is_processing(), "The next change starts it again")
	clouds.snap()
	assert_false(clouds.is_processing(), "and a snap ends it at once")
	assert_eq(float(_param(&"cloud_density")), clouds.clear_density)


func test_the_wind_scrolls_the_clouds() -> void:
	clouds._on_wind_changed(10.0, Vector3(0.0, 0.3, -1.0))
	clouds.snap()
	var scroll: Vector2 = _param(&"wind_speed")
	assert_almost_eq(scroll.x, 0.0, 0.001)
	assert_almost_eq(scroll.y, -10.0 * clouds.wind_scroll_scale, 0.001, "Down the wind, as fast as it blows")
	clouds._on_wind_changed(0.0, Vector3.ZERO)
	clouds.snap()
	scroll = _param(&"wind_speed")
	assert_almost_eq(scroll.length(), clouds.wind_min_scroll, 0.001, "Never dead still")
	assert_lt(scroll.y, 0.0, "and keeps its last heading")


func test_it_stays_quiet_without_a_binbun_sky() -> void:
	var plain: WorldEnvironment = WorldEnvironment.new()
	plain.environment = Environment.new()
	add_child_autofree(plain)
	var quiet: WeatherClouds = WeatherClouds.new()
	quiet.world_environment = plain
	add_child_autofree(quiet)
	quiet.apply_weather(ClimateData.WeatherType.RAIN)
	assert_false(quiet.is_processing(), "Nothing to drive, so nothing to ease")
	quiet.snap()
	assert_null(quiet.sky_material())
	assert_null(quiet._material)
	assert_false(quiet.is_processing())


func test_the_clouds_dim_with_the_sun_down() -> void:
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	clouds.night_sun = sun
	sun.rotation_degrees = Vector3(-60.0, 0.0, 0.0) # Light pointing down: the sun is well up
	clouds.apply_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_almost_eq(clouds.night_factor(), 1.0, 0.001, "Full brightness with the sun overhead")
	assert_eq(clouds.target_color, clouds.clear_color, "so the clouds head for the weather colour")
	sun.rotation_degrees = Vector3(30.0, 0.0, 0.0) # Light pointing up: the sun is below the horizon
	clouds._on_time_changed(2.0)
	assert_almost_eq(clouds.night_factor(), clouds.night_dim, 0.001, "Night keeps only night_dim of the colour")
	var dark: Color = Color(clouds.clear_color.r * clouds.night_dim, clouds.clear_color.g * clouds.night_dim, clouds.clear_color.b * clouds.night_dim, clouds.clear_color.a)
	assert_eq(clouds.target_color, dark, "so the clouds head for a dark grey, not white, at full alpha")
	assert_true(clouds.is_processing(), "and ease there")
	sun.rotation_degrees = Vector3(-8.0, 0.0, 0.0) # Dusk: part way
	clouds._on_time_changed(19.0)
	assert_gt(clouds.night_factor(), clouds.night_dim)
	assert_lt(clouds.night_factor(), 1.0)
	clouds.night_sun = null
	clouds._on_time_changed(3.0)
	assert_almost_eq(clouds.night_factor(), 1.0, 0.001, "No sun given: no dimming")

