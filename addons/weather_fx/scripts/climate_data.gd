# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
class_name ClimateData
extends RefCounted

## Climate and weather definition data for 20 universal biomes.
## Contains probabilities, altitude-based temperature curves, wind power, and weather conversion logic.

# ------------------------------------------------------------------------------
# Enums
# ------------------------------------------------------------------------------
enum BiomeZone {
	TEMPERATE_PLAINS = 0,
	NORTHERN_PLAINS = 1,
	ARCTIC_TUNDRA = 2,
	ARID_CANYON = 3,
	ALPINE_PEAKS = 4,
	DESERT_DUNES = 5,
	DESERT_PLATEAU = 6,
	VOLCANIC_FOOTHILLS = 7,
	AUTUMN_HIGHLANDS = 8,
	WETLANDS_VALLEY = 9,
	COASTAL_PLAINS = 10,
	TROPICAL_RAINFOREST = 11,
	HUMID_COAST = 12,
	VOLCANIC_CRATER = 13,
	VOLCANIC_CALDERA = 14,
	SHADOW_WOODS = 15,
	MISTY_WOODS = 16,
	DESERT_GLACIER = 17,
	ANCIENT_FOREST = 18,
	DEEP_DESERT = 19,
}

enum WeatherType {
	BLUE_SKY = 0,    ## Clear skies / Sunny
	CLOUDY = 1,      ## Overcast / Clouds
	RAIN = 2,        ## Light Rain
	HEAVY_RAIN = 3,  ## Heavy Rain / Downpour
	STORM = 4,       ## Thunderstorm with lightning
	SNOW = 5,        ## Light Snow
	HEAVY_SNOW = 6   ## Heavy Snow / Blizzard
}

# ------------------------------------------------------------------------------
# Biome Data Table (Derived from climate definitions)
# ------------------------------------------------------------------------------
const BIOME_DEFINITIONS: Dictionary = {
	BiomeZone.TEMPERATE_PLAINS: {
		"id": 0,
		"name": "TEMPERATE_PLAINS",
		"display_name": "Temperate Plains",
		"bluesky_rate": 60, "cloudy_rate": 20, "rain_rate": 10, "heavy_rain_rate": 5, "storm_rate": 5,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 1, "wind_power": 7.5,
		"day_temps": [25.0, 20.0, 18.0, 15.0, 9.0, 3.0, -5.0, -10.0, -20.0, -28.0, -28.0],
		"night_temps": [23.0, 18.0, 16.0, 13.0, 6.0, -2.0, -5.0, -14.0, -23.0, -28.0, -28.0]
	},
	BiomeZone.NORTHERN_PLAINS: {
		"id": 1,
		"name": "NORTHERN_PLAINS",
		"display_name": "Northern Plains",
		"bluesky_rate": 40, "cloudy_rate": 30, "rain_rate": 15, "heavy_rain_rate": 5, "storm_rate": 10,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 1, "wind_power": 10.0,
		"day_temps": [25.0, 23.0, 20.0, 12.0, 3.0, -7.0, -13.0, -28.0, -28.0, -28.0, -28.0],
		"night_temps": [23.0, 20.0, 17.0, 7.0, -1.0, -9.0, -15.0, -28.0, -28.0, -28.4, -28.4]
	},
	BiomeZone.ARCTIC_TUNDRA: {
		"id": 2,
		"name": "ARCTIC_TUNDRA",
		"display_name": "Arctic Tundra",
		"bluesky_rate": 20, "cloudy_rate": 10, "rain_rate": 35, "heavy_rain_rate": 35, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [-10.0, -10.0, -10.0, -14.0, -20.0, -23.0, -25.0, -28.0, -29.0, -29.0, -29.0],
		"night_temps": [-10.0, -10.0, -10.0, -16.0, -22.0, -25.0, -26.0, -28.4, -29.2, -29.2, -29.2]
	},
	BiomeZone.ARID_CANYON: {
		"id": 3,
		"name": "ARID_CANYON",
		"display_name": "Arid Canyon",
		"bluesky_rate": 94, "cloudy_rate": 4, "rain_rate": 2, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [20.0, 18.0, 14.0, 8.0, 2.0, -5.0, -10.0, -18.0, -28.0, -28.0, -28.0],
		"night_temps": [15.0, 12.0, 8.0, 3.0, -4.0, -10.0, -16.0, -23.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.ALPINE_PEAKS: {
		"id": 4,
		"name": "ALPINE_PEAKS",
		"display_name": "Alpine Peaks",
		"bluesky_rate": 10, "cloudy_rate": 20, "rain_rate": 20, "heavy_rain_rate": 50, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [-10.0, -10.0, -10.0, -14.0, -20.0, -23.0, -25.0, -28.0, -29.0, -29.0, -29.0],
		"night_temps": [-10.0, -10.0, -10.0, -16.0, -22.0, -25.0, -26.0, -28.4, -29.2, -29.2, -29.2]
	},
	BiomeZone.DESERT_DUNES: {
		"id": 5,
		"name": "DESERT_DUNES",
		"display_name": "Desert Dunes",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [47.5, 45.0, 43.0, 38.0, 30.0, 0.0, -7.0, -15.0, -28.0, -28.0, -28.0],
		"night_temps": [-5.0, -6.0, -7.0, -9.0, -11.0, -14.0, -17.0, -20.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.DESERT_PLATEAU: {
		"id": 6,
		"name": "DESERT_PLATEAU",
		"display_name": "Desert Plateau",
		"bluesky_rate": 95, "cloudy_rate": 5, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [23.0, 20.0, 18.0, 12.0, 5.0, -2.0, -7.0, -15.0, -28.0, -28.0, -28.0],
		"night_temps": [18.0, 15.0, 12.0, 5.0, -2.0, -8.0, -13.0, -20.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.VOLCANIC_FOOTHILLS: {
		"id": 7,
		"name": "VOLCANIC_FOOTHILLS",
		"display_name": "Volcanic Foothills",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 5.0,
		"day_temps": [40.0, 40.0, 40.0, 30.0, 20.0, 10.0, 0.0, -10.0, -28.0, -28.0, -28.0],
		"night_temps": [35.0, 35.0, 35.0, 25.0, 15.0, 5.0, -5.0, -15.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.AUTUMN_HIGHLANDS: {
		"id": 8,
		"name": "AUTUMN_HIGHLANDS",
		"display_name": "Autumn Highlands",
		"bluesky_rate": 35, "cloudy_rate": 40, "rain_rate": 10, "heavy_rain_rate": 5, "storm_rate": 10,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 1, "wind_power": 10.0,
		"day_temps": [23.0, 20.0, 15.0, 10.0, 4.0, -2.0, -8.0, -16.0, -28.0, -28.0, -28.0],
		"night_temps": [19.0, 16.0, 11.0, 5.0, -1.0, -7.0, -12.0, -19.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.WETLANDS_VALLEY: {
		"id": 9,
		"name": "WETLANDS_VALLEY",
		"display_name": "Wetlands Valley",
		"bluesky_rate": 50, "cloudy_rate": 20, "rain_rate": 20, "heavy_rain_rate": 10, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 1, "wind_power": 10.0,
		"day_temps": [24.0, 20.0, 16.0, 12.0, 8.0, 0.0, -5.0, -15.0, -28.0, -28.0, -28.0],
		"night_temps": [20.0, 16.0, 12.0, 8.0, 4.0, -5.0, -9.0, -18.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.COASTAL_PLAINS: {
		"id": 10,
		"name": "COASTAL_PLAINS",
		"display_name": "Coastal Plains",
		"bluesky_rate": 50, "cloudy_rate": 35, "rain_rate": 10, "heavy_rain_rate": 5, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 1, "wind_power": 10.0,
		"day_temps": [24.0, 20.0, 16.0, 12.0, 8.0, 0.0, -5.0, -15.0, -28.0, -28.0, -28.0],
		"night_temps": [20.0, 16.0, 12.0, 8.0, 4.0, -5.0, -9.0, -18.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.TROPICAL_RAINFOREST: {
		"id": 11,
		"name": "TROPICAL_RAINFOREST",
		"display_name": "Tropical Rainforest",
		"bluesky_rate": 35, "cloudy_rate": 35, "rain_rate": 10, "heavy_rain_rate": 10, "storm_rate": 10,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 2, "wind_power": 7.5,
		"day_temps": [28.0, 25.0, 21.0, 16.0, 10.0, 0.0, -8.0, -18.0, -28.0, -28.0, -28.0],
		"night_temps": [24.0, 21.0, 17.0, 12.0, 7.0, -4.0, -11.0, -20.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.HUMID_COAST: {
		"id": 12,
		"name": "HUMID_COAST",
		"display_name": "Humid Coast",
		"bluesky_rate": 65, "cloudy_rate": 5, "rain_rate": 15, "heavy_rain_rate": 15, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 2, "wind_power": 7.5,
		"day_temps": [25.0, 22.0, 19.0, 15.0, 9.0, 2.0, -6.0, -15.0, -28.0, -28.0, -28.0],
		"night_temps": [21.0, 18.0, 15.0, 11.0, 5.0, -2.0, -10.0, -18.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.VOLCANIC_CRATER: {
		"id": 13,
		"name": "VOLCANIC_CRATER",
		"display_name": "Volcanic Crater",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 5.0,
		"day_temps": [80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0],
		"night_temps": [70.0, 70.0, 70.0, 70.0, 70.0, 70.0, 70.0, 70.0, 70.0, 70.0, 70.0]
	},
	BiomeZone.VOLCANIC_CALDERA: {
		"id": 14,
		"name": "VOLCANIC_CALDERA",
		"display_name": "Volcanic Caldera",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 5.0,
		"day_temps": [150.0, 150.0, 150.0, 150.0, 150.0, 150.0, 150.0, 150.0, 150.0, 150.0, 150.0],
		"night_temps": [140.0, 140.0, 140.0, 140.0, 140.0, 140.0, 140.0, 140.0, 140.0, 140.0, 140.0]
	},
	BiomeZone.SHADOW_WOODS: {
		"id": 15,
		"name": "SHADOW_WOODS",
		"display_name": "Shadow Woods",
		"bluesky_rate": 40, "cloudy_rate": 30, "rain_rate": 15, "heavy_rain_rate": 5, "storm_rate": 10,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 1, "wind_power": 10.0,
		"day_temps": [20.0, 17.0, 14.0, 9.0, 2.0, -6.0, -12.0, -20.0, -28.0, -28.0, -28.0],
		"night_temps": [17.0, 14.0, 11.0, 6.0, -1.0, -8.0, -14.0, -22.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.MISTY_WOODS: {
		"id": 16,
		"name": "MISTY_WOODS",
		"display_name": "Misty Woods",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 3.0,
		"day_temps": [18.0, 15.0, 12.0, 8.0, 2.0, -5.0, -10.0, -18.0, -28.0, -28.0, -28.0],
		"night_temps": [14.0, 11.0, 8.0, 3.0, -2.0, -8.0, -13.0, -20.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.DESERT_GLACIER: {
		"id": 17,
		"name": "DESERT_GLACIER",
		"display_name": "Desert Glacier",
		"bluesky_rate": 5, "cloudy_rate": 20, "rain_rate": 40, "heavy_rain_rate": 35, "storm_rate": 0,
		"day_lock_bluesky": true, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [-5.0, -5.0, -5.0, -9.0, -15.0, -20.0, -24.0, -28.0, -29.0, -29.0, -29.0],
		"night_temps": [-8.0, -8.0, -8.0, -12.0, -18.0, -23.0, -26.0, -29.0, -29.5, -29.5, -29.5]
	},
	BiomeZone.ANCIENT_FOREST: {
		"id": 18,
		"name": "ANCIENT_FOREST",
		"display_name": "Ancient Forest",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 5.0,
		"day_temps": [20.0, 18.0, 15.0, 10.0, 4.0, -2.0, -8.0, -16.0, -28.0, -28.0, -28.0],
		"night_temps": [17.0, 14.0, 11.0, 6.0, 0.0, -5.0, -11.0, -18.0, -28.0, -28.0, -28.0]
	},
	BiomeZone.DEEP_DESERT: {
		"id": 19,
		"name": "DEEP_DESERT",
		"display_name": "Deep Desert",
		"bluesky_rate": 100, "cloudy_rate": 0, "rain_rate": 0, "heavy_rain_rate": 0, "storm_rate": 0,
		"day_lock_bluesky": false, "night_lock_bluesky": false, "bluesky_rain_pat": 0, "wind_power": 10.0,
		"day_temps": [55.0, 52.0, 48.0, 42.0, 32.0, 0.0, -8.0, -18.0, -28.0, -28.0, -28.0],
		"night_temps": [-8.0, -9.0, -11.0, -13.0, -16.0, -20.0, -23.0, -26.0, -28.0, -28.0, -28.0]
	}
}

# ------------------------------------------------------------------------------
# Icon Paths
# ------------------------------------------------------------------------------
const WEATHER_ICON_PATHS: Dictionary = {
	WeatherType.BLUE_SKY: "res://addons/weather_fx/assets/icons/bluesky.svg",
	WeatherType.CLOUDY: "res://addons/weather_fx/assets/icons/cloudy.svg",
	WeatherType.RAIN: "res://addons/weather_fx/assets/icons/rain.svg",
	WeatherType.HEAVY_RAIN: "res://addons/weather_fx/assets/icons/heavy_rain.svg",
	WeatherType.STORM: "res://addons/weather_fx/assets/icons/storm.svg",
	WeatherType.SNOW: "res://addons/weather_fx/assets/icons/snow.svg",
	WeatherType.HEAVY_SNOW: "res://addons/weather_fx/assets/icons/heavy_snow.svg",
}

# ------------------------------------------------------------------------------
# Static Helper Methods
# ------------------------------------------------------------------------------
## Returns the biome dictionary definition for the specified zone.
static func get_biome_data(zone: BiomeZone) -> Dictionary:
	return BIOME_DEFINITIONS.get(zone, BIOME_DEFINITIONS[BiomeZone.TEMPERATE_PLAINS])


## Returns the enum string name of the biome zone.
static func get_biome_name(zone: BiomeZone) -> String:
	var data = get_biome_data(zone)
	return data.get("name", "UNKNOWN_BIOME")


## Returns a human-friendly display name of the biome zone.
static func get_biome_display_name(zone: BiomeZone) -> String:
	var data = get_biome_data(zone)
	return data.get("display_name", "Unknown Biome")


## Returns string name of a WeatherType enum.
static func get_weather_name(type: WeatherType) -> String:
	match type:
		WeatherType.BLUE_SKY: return "Blue Sky (Clear)"
		WeatherType.CLOUDY: return "Cloudy"
		WeatherType.RAIN: return "Light Rain"
		WeatherType.HEAVY_RAIN: return "Heavy Rain"
		WeatherType.STORM: return "Thunderstorm"
		WeatherType.SNOW: return "Light Snow"
		WeatherType.HEAVY_SNOW: return "Heavy Snow"
		_: return "Unknown Weather"


## Returns icon resource path for a WeatherType.
static func get_weather_icon_path(type: WeatherType) -> String:
	return WEATHER_ICON_PATHS.get(type, "res://addons/weather_fx/assets/icons/bluesky.svg")


## Returns true if temperature is at or below freezing (0°C).
static func is_freezing(temperature: float) -> bool:
	return temperature <= 0.0


## Calculates interpolated temperature for a given biome, altitude, and is_day flag.
## Altitudes are in meters (0 to 1000m curve). Values below 0 clamp to 0; above 1000 clamp to 1000.
static func get_temperature(zone: BiomeZone, altitude: float, is_day: bool) -> float:
	var data = get_biome_data(zone)
	var temps: Array = data["day_temps"] if is_day else data["night_temps"]
	
	var clamped_alt = clampf(altitude, 0.0, 1000.0)
	var index_float = clamped_alt / 100.0
	var low_idx = int(floor(index_float))
	var high_idx = int(ceil(index_float))
	
	if low_idx >= temps.size() - 1:
		return float(temps[-1])
	if low_idx == high_idx:
		return float(temps[low_idx])
		
	var frac = index_float - float(low_idx)
	var temp_low = float(temps[low_idx])
	var temp_high = float(temps[high_idx])
	return lerpf(temp_low, temp_high, frac)


## Calculates temperature with a smooth day/night curve according to time_of_day (0.0 to 24.0 hours).
## Peaks around 14:00 (2 PM), coldest around 04:00 (4 AM).
static func get_smooth_temperature(zone: BiomeZone, altitude: float, time_of_day: float) -> float:
	var day_temp = get_temperature(zone, altitude, true)
	var night_temp = get_temperature(zone, altitude, false)
	
	# Diurnal factor: 1.0 = full daytime peak (~14:00), 0.0 = full night trough (~02:00-05:00)
	var normalized_time = fmod(time_of_day - 4.0 + 24.0, 24.0) / 24.0 # 0 at 4 AM, 0.5 at 4 PM
	var diurnal_factor = 0.5 - 0.5 * cos(normalized_time * TAU)
	
	return lerpf(night_temp, day_temp, diurnal_factor)


## Converts temperature in Celsius to Fahrenheit.
static func celsius_to_fahrenheit(celsius: float) -> float:
	return (celsius * 1.8) + 32.0


## Converts temperature in Fahrenheit to Celsius.
static func fahrenheit_to_celsius(fahrenheit: float) -> float:
	return (fahrenheit - 32.0) / 1.8
