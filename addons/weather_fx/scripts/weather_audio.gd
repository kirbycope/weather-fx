# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WeatherAudio
extends Node

## Weather SFX and the background ambience (BGS) for the biome, the weather and the time of day, driven by WeatherFX
## signals. The SFX players are this node's children in weather_fx.tscn. The ambience is WeatherFX's own: its bgs_sets
## are one [BiomeAmbience] per kind of place, and at ready this node makes one non-positional player per loop they
## carry. BGS is only re-evaluated on weather_changed / biome_changed / daylight_changed / playback_changed, and a
## player that is already the target keeps playing without restarting.

@export var weather_fx: WeatherFX

@export_group("Weather SFX")
@export var audio_rain_light: AudioStreamPlayer
@export var audio_rain_heavy: AudioStreamPlayer
@export var audio_storm: AudioStreamPlayer
@export var audio_wind: AudioStreamPlayer

var _bgs_players: Dictionary[AudioStream, AudioStreamPlayer] = {} ## One per loop the ambience sets carry, by stream.
var _weather: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY
var _biome: ClimateData.BiomeZone = ClimateData.BiomeZone.TEMPERATE_PLAINS
var _active: bool = false
var _is_day: bool = true


func _ready() -> void:
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if not is_instance_valid(weather_fx):
		return
	if not Engine.is_editor_hint():
		_build_bgs_players()
	weather_fx.weather_changed.connect(_on_weather_changed)
	weather_fx.biome_changed.connect(_on_biome_changed)
	weather_fx.daylight_changed.connect(_on_daylight_changed)
	weather_fx.playback_changed.connect(_on_playback_changed)
	_weather = weather_fx.active_weather
	_biome = weather_fx.current_biome
	_active = weather_fx.is_simulating()
	_is_day = weather_fx.is_daylight()
	_apply()


## One player per loop across WeatherFX's ambience sets and its default; a loop shared between sets gets one.
func _build_bgs_players() -> void:
	var sets: Array[BiomeAmbience] = weather_fx.bgs_sets.duplicate()
	if weather_fx.bgs_default:
		sets.append(weather_fx.bgs_default)
	for ambience: BiomeAmbience in sets:
		if ambience == null:
			continue
		for stream: AudioStream in ambience.get_streams():
			if _bgs_players.has(stream):
				continue
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.name = stream.resource_path.get_file().get_basename().to_pascal_case() if not stream.resource_path.is_empty() else "Bgs%d" % (_bgs_players.size() + 1)
			player.stream = stream
			player.bus = weather_fx.bgs_bus
			player.volume_db = weather_fx.bgs_volume_db
			add_child(player)
			_bgs_players[stream] = player


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_weather = new_weather
	_apply()


func _on_biome_changed(new_biome: ClimateData.BiomeZone, _old_biome: ClimateData.BiomeZone) -> void:
	_biome = new_biome
	_update_bgs()


func _on_daylight_changed(is_day: bool) -> void:
	_is_day = is_day
	_update_bgs()


func _on_playback_changed(active: bool) -> void:
	_active = active
	_apply()


func _apply() -> void:
	var w: int = _weather if _active else -1
	var wanted: Dictionary = {
		audio_rain_light: w == ClimateData.WeatherType.RAIN,
		audio_rain_heavy: w == ClimateData.WeatherType.HEAVY_RAIN or (w == ClimateData.WeatherType.STORM and audio_storm == null),
		audio_storm: w == ClimateData.WeatherType.STORM,
		audio_wind: w == ClimateData.WeatherType.STORM or w == ClimateData.WeatherType.HEAVY_SNOW,
	}
	for player: AudioStreamPlayer in wanted:
		if is_instance_valid(player) and player.is_inside_tree() and player.playing != wanted[player]:
			player.playing = wanted[player]
	_update_bgs()


## The loop the cached biome, weather and time of day call for, or null when no set covers the biome or has one for it.
func get_target_bgs_stream() -> AudioStream:
	var ambience: BiomeAmbience = weather_fx.ambience_for(_biome) if is_instance_valid(weather_fx) else null
	return ambience.stream_for(_weather, _is_day) if ambience else null


## The player for [method get_target_bgs_stream], or null when there is none.
func get_target_bgs_player() -> AudioStreamPlayer:
	return _bgs_players.get(get_target_bgs_stream())


## The player made for [param stream], or null when no set carries it.
func get_bgs_player(stream: AudioStream) -> AudioStreamPlayer:
	return _bgs_players.get(stream)


func _update_bgs() -> void:
	var target: AudioStreamPlayer = get_target_bgs_player() if _active else null
	for player: AudioStreamPlayer in _bgs_players.values():
		# Through set(), so a player that stays the target is never assigned again and never restarts
		if is_instance_valid(player) and player.is_inside_tree() and bool(player.get(&"playing")) != (player == target):
			player.set(&"playing", player == target)
