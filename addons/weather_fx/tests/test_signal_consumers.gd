extends GutTest

## Purpose: consumers subscribe to WeatherFX signals instead of polling statics, BGS players
## never restart while they stay the target, and plugin registration does not duplicate classes.

const FALLING_LEAVES_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/falling_leaves.tscn")
const BGS_STREAM: AudioStream = preload("res://addons/weather_fx/assets/audio/tommusic/bgs/Forest Day/Forest Day.ogg")


## Counts how many times something assigns `playing` through Object.set(), which is how
## WeatherAudio drives the untyped BGS nodes. A restart would show up as a second assignment.
class CountingPlayer extends AudioStreamPlayer:
	var play_sets: int = 0

	func _set(property: StringName, value: Variant) -> bool:
		if property == &"playing" and value:
			play_sets += 1
		return false


var wfx: WeatherFX


func before_each() -> void:
	wfx = WeatherFX.new()
	add_child_autofree(wfx)


func test_falling_leaves_update_material_on_wind_changed_only() -> void:
	var leaves: FallingLeaves = FALLING_LEAVES_SCENE.instantiate() as FallingLeaves
	leaves.weather_fx = wfx
	leaves.min_wind_threshold = 1.0
	add_child_autofree(leaves)
	var mat: ParticleProcessMaterial = leaves.process_material as ParticleProcessMaterial
	assert_true(wfx.wind_changed.is_connected(leaves._on_wind_changed))
	assert_true(leaves.emitting, "Biome wind above the threshold should emit leaves on ready")

	wfx.wind_direction = Vector3(0.0, 0.0, -1.0)
	assert_lt(mat.direction.z, -0.5, "Material direction follows wind_changed")

	mat.direction = Vector3.UP
	wfx.current_altitude = 200.0
	assert_eq(mat.direction, Vector3.UP, "Temperature-only updates must not touch the leaf material")

	wfx.is_playing = false
	assert_false(leaves.emitting, "Pausing drops wind to 0 and stops the leaves")


func test_bgs_player_does_not_restart_when_target_is_unchanged() -> void:
	var audio := WeatherAudio.new()
	var day_rain := CountingPlayer.new()
	day_rain.stream = BGS_STREAM
	var day_clear := CountingPlayer.new()
	day_clear.stream = BGS_STREAM
	audio.add_child(day_rain)
	audio.add_child(day_clear)
	audio.bgs_day_rain = day_rain
	audio.bgs_day_clear = day_clear
	audio.weather_fx = wfx
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY) # the procedural forecast is random; force it before the audio node listens
	add_child_autofree(audio)
	wfx.manual_time_of_day = 12.0
	assert_eq(day_clear.play_sets, 1, "Clear daytime BGS starts once")

	wfx.set_weather(ClimateData.WeatherType.RAIN)
	assert_true(day_rain.playing)
	assert_false(day_clear.playing)
	assert_eq(day_rain.play_sets, 1)

	wfx.set_weather(ClimateData.WeatherType.HEAVY_RAIN)
	assert_eq(audio.get_target_bgs_player(), day_rain)
	assert_true(day_rain.playing)
	assert_eq(day_rain.play_sets, 1, "RAIN -> HEAVY_RAIN keeps the same BGS player without restarting it")

	wfx.manual_time_of_day = 22.0
	assert_false(day_rain.playing, "Night has no player assigned, so the day player stops")


func test_bgs_audio_matching_weather_and_time() -> void:
	var audio := WeatherAudio.new()
	var players: Dictionary = {}
	for key in ["bgs_day_clear", "bgs_day_rain", "bgs_day_storm", "bgs_night_clear", "bgs_night_rain", "bgs_night_storm"]:
		var player := AudioStreamPlayer.new()
		audio.add_child(player)
		audio.set(key, player)
		players[key] = player
	audio.weather_fx = wfx
	add_child_autofree(audio)

	wfx.manual_time_of_day = 12.0
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_eq(audio.get_target_bgs_player(), players["bgs_day_clear"])
	wfx.set_weather(ClimateData.WeatherType.RAIN)
	assert_eq(audio.get_target_bgs_player(), players["bgs_day_rain"])
	wfx.set_weather(ClimateData.WeatherType.STORM)
	assert_eq(audio.get_target_bgs_player(), players["bgs_day_storm"])
	wfx.manual_time_of_day = 22.0
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_eq(audio.get_target_bgs_player(), players["bgs_night_clear"])
	wfx.set_weather(ClimateData.WeatherType.RAIN)
	assert_eq(audio.get_target_bgs_player(), players["bgs_night_rain"])
	wfx.set_weather(ClimateData.WeatherType.STORM)
	assert_eq(audio.get_target_bgs_player(), players["bgs_night_storm"])


func test_bgs_unassigned_optional_behavior() -> void:
	var audio := WeatherAudio.new()
	audio.weather_fx = wfx
	add_child_autofree(audio)
	wfx.set_weather(ClimateData.WeatherType.RAIN)
	wfx.manual_time_of_day = 22.0
	wfx.set_weather(ClimateData.WeatherType.STORM)
	wfx.is_playing = false
	assert_null(audio.get_target_bgs_player(), "Target BGS player should be null when unassigned")


func test_plugin_registers_each_class_once() -> void:
	var classes: Array = ProjectSettings.get_global_class_list()
	for class_name_str in ["WeatherFX", "WeatherZone", "WeatherForecastDisplay", "TemperatureGaugeDisplay", "GaugeNeedle", "PrecipitationFX", "WeatherAudio"]:
		var matches: Array = classes.filter(func(entry: Dictionary) -> bool: return entry["class"] == class_name_str)
		assert_eq(matches.size(), 1, "%s must be registered exactly once via class_name" % class_name_str)
	var plugin_script: Script = load("res://addons/weather_fx/plugin.gd") as Script
	assert_false(plugin_script.source_code.contains("add_custom_type"), "plugin.gd must not duplicate class_name nodes in the Create Node dialog")


func test_rain_splashes_land_where_drops_hit_the_scenery() -> void:
	var fx: WeatherFX = load("res://addons/weather_fx/scenes/weather_fx.tscn").instantiate()
	add_child_autofree(fx)
	var target := Node3D.new()
	add_child_autofree(target)
	fx.target_node = target
	var precipitation: PrecipitationFX = fx.get_node("PrecipitationFX")
	assert_true(precipitation.rain_ground is GPUParticlesCollisionHeightField3D, "A heightfield of the scenery follows the target")
	precipitation._setup_renderer_compatibility(false)
	var rain_mat: ParticleProcessMaterial = precipitation.rain_particles.process_material
	assert_eq(rain_mat.collision_mode, ParticleProcessMaterial.COLLISION_RIGID, "Drops stop on the surface they hit (a hidden drop would not sub-emit)")
	assert_eq(rain_mat.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION, "And spawn their splash right there")
	assert_eq(precipitation.rain_splash_particles.draw_passes, 1, "Only the droplet splash draws; the ground ripple decal is switched off (the water shader keeps its own ripples)")
	target.global_position = Vector3(9.0, 3.0, -6.0)
	precipitation.set_process(true)
	precipitation._process(0.0)
	assert_eq(precipitation.rain_ground.global_position, target.global_position, "The heightfield follows the target")
	assert_eq(precipitation.rain_splash_particles.global_position, target.global_position + Vector3(0.0, -500.0, 0.0), "The splash emitter keeps emitting 500 m down, out of sight, so its sub-emissions can land on the scenery")
	precipitation._setup_renderer_compatibility(true)
	assert_eq(rain_mat.collision_mode, ParticleProcessMaterial.COLLISION_DISABLED, "Compatibility has no particle collision")
	assert_eq(rain_mat.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_DISABLED)
