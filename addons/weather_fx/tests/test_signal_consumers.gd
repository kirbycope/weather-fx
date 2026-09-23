extends GutTest

## Purpose: consumers subscribe to WeatherFX signals instead of polling statics, the BGS players WeatherAudio makes
## for WeatherFX's ambience sets follow the biome and never restart while they stay the target, and plugin
## registration does not duplicate classes.

const FALLING_LEAVES_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/falling_leaves.tscn")
const BGS_STREAM: AudioStream = preload("res://addons/weather_fx/assets/audio/tommusic/bgs/Forest Day/Forest Day.ogg")
const BGS_RAIN_STREAM: AudioStream = preload("res://addons/weather_fx/assets/audio/tommusic/bgs/Forest Day/Forest Day Rain.ogg")
const FOREST: BiomeAmbience = preload("res://addons/weather_fx/resources/ambience/forest.tres")
const BEACH: BiomeAmbience = preload("res://addons/weather_fx/resources/ambience/beach.tres")


## Counts how many times something assigns `playing` through Object.set(), which is how WeatherAudio drives its
## BGS players. A restart would show up as a second assignment.
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
	var here := BiomeAmbience.new()
	here.day_clear = BGS_STREAM
	here.day_rain = BGS_RAIN_STREAM
	wfx.bgs_default = here # any biome
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY) # the procedural forecast is random; force it before the audio node listens
	wfx.manual_time_of_day = 12.0
	var audio := WeatherAudio.new()
	audio.weather_fx = wfx
	add_child_autofree(audio)
	var day_clear: AudioStreamPlayer = audio.get_bgs_player(BGS_STREAM)
	assert_not_null(day_clear, "A player per loop the sets carry")
	assert_true(day_clear.playing, "Clear daytime BGS plays")
	# A player that counts its starts, put in for the rain loop
	var day_rain := CountingPlayer.new()
	day_rain.stream = BGS_RAIN_STREAM
	audio.add_child(day_rain)
	audio._bgs_players[BGS_RAIN_STREAM] = day_rain

	wfx.set_weather(ClimateData.WeatherType.RAIN)
	assert_true(day_rain.playing)
	assert_false(day_clear.playing)
	assert_eq(day_rain.play_sets, 1)

	wfx.set_weather(ClimateData.WeatherType.HEAVY_RAIN)
	assert_eq(audio.get_target_bgs_player(), day_rain)
	assert_true(day_rain.playing)
	assert_eq(day_rain.play_sets, 1, "RAIN -> HEAVY_RAIN keeps the same BGS player without restarting it")

	wfx.manual_time_of_day = 22.0
	assert_false(day_rain.playing, "Night has no loop in this set, so the day player stops")


func test_bgs_audio_matching_weather_and_time() -> void:
	wfx.bgs_default = FOREST # six distinct loops
	var audio := WeatherAudio.new()
	audio.weather_fx = wfx
	add_child_autofree(audio)
	var players: Dictionary = {}
	for slot: String in ["day_clear", "day_rain", "day_storm", "night_clear", "night_rain", "night_storm"]:
		players["bgs_" + slot] = audio.get_bgs_player(FOREST.get(slot))
		assert_not_null(players["bgs_" + slot], "%s got a player" % slot)

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
	assert_null(audio.get_target_bgs_player(), "Target BGS player should be null when WeatherFX carries no ambience")
	assert_eq(audio.get_child_count(), 0, "and no players were made")


func test_the_ambience_follows_the_biome() -> void:
	wfx.blend_zones = false
	wfx.bgs_sets = [FOREST, BEACH]
	wfx.set_weather(ClimateData.WeatherType.BLUE_SKY)
	wfx.manual_time_of_day = 12.0
	var audio := WeatherAudio.new()
	audio.weather_fx = wfx
	add_child_autofree(audio)
	assert_true(FOREST.covers(ClimateData.BiomeZone.ANCIENT_FOREST), "The forest loops are for the wooded biomes")
	assert_false(FOREST.covers(ClimateData.BiomeZone.TEMPERATE_PLAINS))
	assert_true(BEACH.covers(ClimateData.BiomeZone.COASTAL_PLAINS))
	assert_null(audio.get_target_bgs_player(), "The plains: no set covers them and there is no default, so silence")
	wfx.current_biome = ClimateData.BiomeZone.ANCIENT_FOREST
	assert_eq(audio.get_target_bgs_stream(), FOREST.day_clear, "In the forest by day: the forest's clear loop")
	assert_true(audio.get_bgs_player(FOREST.day_clear).playing)
	wfx.current_biome = ClimateData.BiomeZone.COASTAL_PLAINS
	assert_eq(audio.get_target_bgs_stream(), BEACH.day_clear, "On the coast: the beach")
	assert_false(audio.get_bgs_player(FOREST.day_clear).playing, "and the forest stops")
	assert_eq(BEACH.night_storm, BEACH.day_storm, "A set with no night loops uses its day ones at night")
	wfx.bgs_default = FOREST
	wfx.current_biome = ClimateData.BiomeZone.DESERT_DUNES
	assert_eq(wfx.ambience_for(ClimateData.BiomeZone.DESERT_DUNES), FOREST, "A default covers what no set does")


func test_the_shipped_sets_give_every_biome_one_looping_ambience() -> void:
	var fx: WeatherFX = load("res://addons/weather_fx/scenes/weather_fx.tscn").instantiate()
	add_child_autofree(fx)
	for zone: int in ClimateData.BiomeZone.values():
		var covering: Array[BiomeAmbience] = fx.bgs_sets.filter(func(a: BiomeAmbience) -> bool: return a.covers(zone))
		assert_eq(covering.size(), 1, "%s has exactly one ambience set" % ClimateData.get_biome_name(zone))
	for ambience: BiomeAmbience in fx.bgs_sets:
		for stream: AudioStream in ambience.get_streams():
			assert_true((stream as AudioStreamOggVorbis).loop, "%s loops" % stream.resource_path.get_file())
	assert_eq(fx.ambience_for(ClimateData.BiomeZone.TROPICAL_RAINFOREST).resource_name, "Jungle", "The rainforest plays the jungle, not the forest")


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
