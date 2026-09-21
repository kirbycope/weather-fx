# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name BiomeAmbience
extends Resource
## The background sounds of a kind of place: one loop per weather and time of day, for the biomes listed in
## [member biomes]. [WeatherFX.bgs_sets] holds one of these per kind of place a game has; [code]resources/ambience/forest.tres[/code]
## is the addon's, the forest day and night loops for its wooded biomes. A set with no biomes listed is the fallback
## for every biome without a set of its own; a biome no set covers is silent.

@export var biomes: Array[ClimateData.BiomeZone] = [] ## Where these sounds belong; empty means any biome no other set covers.
@export_group("Day", "day_")
@export var day_clear: AudioStream ## Blue sky, cloudy, and snow.
@export var day_rain: AudioStream ## Rain and heavy rain.
@export var day_storm: AudioStream
@export_group("Night", "night_")
@export var night_clear: AudioStream
@export var night_rain: AudioStream
@export var night_storm: AudioStream


## True when these sounds are for [param biome].
func covers(biome: ClimateData.BiomeZone) -> bool:
	return biome in biomes


## The loop for [param weather] by day or by night, or null when the set has none for it.
func stream_for(weather: ClimateData.WeatherType, is_day: bool) -> AudioStream:
	match weather:
		ClimateData.WeatherType.STORM:
			return day_storm if is_day else night_storm
		ClimateData.WeatherType.RAIN, ClimateData.WeatherType.HEAVY_RAIN:
			return day_rain if is_day else night_rain
		_:
			return day_clear if is_day else night_clear


## Every loop the set carries, once each.
func get_streams() -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for stream: AudioStream in [day_clear, day_rain, day_storm, night_clear, night_rain, night_storm]:
		if stream and not out.has(stream):
			out.append(stream)
	return out
