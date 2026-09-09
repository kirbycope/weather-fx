# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name WeatherAudio
extends Node

## Weather SFX and day/night background ambience (BGS) driven by WeatherFX signals.
## BGS is only re-evaluated on weather_changed / daylight_changed / playback_changed,
## and a player that is already the target keeps playing without restarting.

@export var weather_fx: WeatherFX

@export_group("Weather SFX")
@export var audio_rain_light: AudioStreamPlayer
@export var audio_rain_heavy: AudioStreamPlayer
@export var audio_storm: AudioStreamPlayer
@export var audio_wind: AudioStreamPlayer

@export_group("Background Sounds (BGS)")
## AudioStreamPlayer or AudioStreamPlayer3D per ambient condition. Unassigned players are skipped.
@export var bgs_day_clear: Node
@export var bgs_day_rain: Node
@export var bgs_day_storm: Node
@export var bgs_night_clear: Node
@export var bgs_night_rain: Node
@export var bgs_night_storm: Node

var _weather: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY
var _active: bool = false
var _is_day: bool = true


func _ready() -> void:
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if not is_instance_valid(weather_fx):
		return
	weather_fx.weather_changed.connect(_on_weather_changed)
	weather_fx.daylight_changed.connect(_on_daylight_changed)
	weather_fx.playback_changed.connect(_on_playback_changed)
	_weather = weather_fx.active_weather
	_active = weather_fx.is_simulating()
	_is_day = weather_fx.is_daylight()
	_apply()


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_weather = new_weather
	_apply()


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


## Returns the BGS player matching the cached weather and time of day.
func get_target_bgs_player() -> Node:
	match _weather:
		ClimateData.WeatherType.STORM:
			return bgs_day_storm if _is_day else bgs_night_storm
		ClimateData.WeatherType.RAIN, ClimateData.WeatherType.HEAVY_RAIN:
			return bgs_day_rain if _is_day else bgs_night_rain
		_:
			return bgs_day_clear if _is_day else bgs_night_clear


func _update_bgs() -> void:
	var target: Node = get_target_bgs_player() if _active else null
	for player: Node in [bgs_day_clear, bgs_day_rain, bgs_day_storm, bgs_night_clear, bgs_night_rain, bgs_night_storm]:
		if is_instance_valid(player) and player.is_inside_tree() and bool(player.get(&"playing")) != (player == target):
			player.set(&"playing", player == target)
