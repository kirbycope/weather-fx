class_name WeatherClouds
extends Node
## Drives the sky shader's clouds from [WeatherFX]: the Binbun sky scrolls two layers of noise cloud, and this sets
## its [code]cloud_density[/code], [code]cloud_color[/code] and [code]wind_speed[/code] for the weather and the wind,
## easing between values so a change rolls in. A sky shader runs on every renderer, the web export included, which
## is what makes this the layer that works everywhere. The sky material is copied first, so the asset stays as is.
## It only processes while the sky is on its way somewhere: once every value is within [constant SETTLED] of its
## target it snaps there, writes once and stops until the next change.

const SETTLED: float = 0.005 ## How close every channel must be to its target for the easing to stop.

@export var weather: WeatherFX
@export var world_environment: WorldEnvironment ## Whose Environment holds the Binbun sky.
@export var transition_seconds: float = 8.0 ## How long a change in the weather takes to roll across the sky.
@export_group("Clear", "clear_")
@export_range(0.0, 5.0) var clear_density: float = 0.5
@export var clear_color: Color = Color(0.92, 0.92, 0.94)
@export_group("Cloudy", "cloudy_")
@export_range(0.0, 5.0) var cloudy_density: float = 1.4
@export var cloudy_color: Color = Color(0.66, 0.68, 0.72)
@export_group("Rain", "rain_")
@export_range(0.0, 5.0) var rain_density: float = 2.0 ## Rain, snow and storms.
@export var rain_color: Color = Color(0.45, 0.47, 0.52)
@export_group("Night", "night_")
@export var night_sun: DirectionalLight3D ## The sun; the clouds dim as it sets (empty: no dimming).
@export_range(0.0, 1.0) var night_dim: float = 0.22 ## How bright the clouds stay with the sun fully down, as a share of the weather colour.
@export_range(0.0, 1.0) var night_dusk_height: float = 0.25 ## Sun height (its -Z dropped on Y, 1 = overhead) above which the clouds are at full brightness; dimming runs from a little below the horizon up to here.
@export_group("Wind", "wind_")
@export var wind_scroll_scale: float = 0.002 ## Sky scroll per unit of the weather's wind strength; the shader scrolls at wind_speed * 0.1 per second, so a strong wind drifts the clouds rather than racing them.
@export var wind_min_scroll: float = 0.006 ## The clouds never sit dead still.

var target_density: float = 0.5
var target_color: Color = Color(0.92, 0.92, 0.94)
var _weather_type: ClimateData.WeatherType = ClimateData.WeatherType.BLUE_SKY ## The last weather applied, for the night retarget.
var target_wind: Vector2 = Vector2(0.01, 0.01)
var _density: float = 0.5
var _color: Color = Color(0.92, 0.92, 0.94)
var _wind: Vector2 = Vector2(0.01, 0.01)
var _material: ShaderMaterial ## This node's own copy of the sky material, the one the values are written to.


func _ready() -> void:
	var material: ShaderMaterial = sky_material()
	if material == null:
		set_process(false)
		return
	# Work on a copy: the sky and its material are shared assets on disk
	var sky: Sky = world_environment.environment.sky.duplicate()
	_material = material.duplicate()
	sky.sky_material = _material
	world_environment.environment.sky = sky
	if weather:
		weather.weather_changed.connect(_on_weather_changed)
		weather.wind_changed.connect(_on_wind_changed)
		var clock: Node = weather.get("date_and_time_node")
		if is_instance_valid(clock) and clock.has_signal(&"time_changed"):
			clock.connect(&"time_changed", _on_time_changed)
		apply_weather(weather.active_weather)
		_on_wind_changed(weather.current_wind_strength, weather.wind_direction)
	snap()


func _process(delta: float) -> void:
	if _is_settled():
		snap()
		return
	var weight: float = 1.0 if transition_seconds <= 0.0 else clampf(delta / transition_seconds, 0.0, 1.0)
	_density = lerpf(_density, target_density, weight)
	_color = _color.lerp(target_color, weight)
	_wind = _wind.lerp(target_wind, weight)
	_write()


## The Binbun sky's material, or null when the environment's sky is something else.
func sky_material() -> ShaderMaterial:
	if world_environment == null or world_environment.environment == null or world_environment.environment.sky == null:
		return null
	var material: ShaderMaterial = world_environment.environment.sky.sky_material as ShaderMaterial
	if material == null or material.get_shader_parameter(&"cloud_density") == null:
		return null
	return material


func density_for(weather_type: ClimateData.WeatherType) -> float:
	match weather_type:
		ClimateData.WeatherType.BLUE_SKY:
			return clear_density
		ClimateData.WeatherType.CLOUDY:
			return cloudy_density
		_:
			return rain_density


func color_for(weather_type: ClimateData.WeatherType) -> Color:
	match weather_type:
		ClimateData.WeatherType.BLUE_SKY:
			return clear_color
		ClimateData.WeatherType.CLOUDY:
			return cloudy_color
		_:
			return rain_color


## How much of the weather colour the clouds keep for the sun's height: 1 by day, [member night_dim] with the sun down,
## eased in between so dusk rolls in with the sky.
func night_factor() -> float:
	if not is_instance_valid(night_sun):
		return 1.0
	var sun_height: float = night_sun.global_basis.z.y # The light travels along -Z; up when the sun is above the horizon
	var day: float = smoothstep(-0.08, maxf(night_dusk_height, 0.001), sun_height)
	return lerpf(night_dim, 1.0, day)


## The clock moved: the sun has, so the clouds head for their new brightness.
func _on_time_changed(_current_time: float) -> void:
	target_color = dimmed(color_for(_weather_type))
	_start_easing()


## [param color] with its brightness scaled by [method night_factor]; the alpha is left alone.
func dimmed(color: Color) -> Color:
	var factor: float = night_factor()
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


## Sets where the sky is heading for [param weather_type]; [method _process] eases it there.
func apply_weather(weather_type: ClimateData.WeatherType) -> void:
	target_density = density_for(weather_type)
	_weather_type = weather_type
	target_color = dimmed(color_for(weather_type))
	_start_easing()


## Jumps the sky to its targets at once and stops easing.
func snap() -> void:
	_density = target_density
	_color = target_color
	_wind = target_wind
	_write()
	set_process(false)


func _start_easing() -> void:
	set_process(_material != null)


func _is_settled() -> bool:
	var gap: Color = target_color - _color
	return absf(target_density - _density) < SETTLED \
		and Vector3(gap.r, gap.g, gap.b).length() < SETTLED \
		and (target_wind - _wind).length() < SETTLED


func _write() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"cloud_density", _density)
	_material.set_shader_parameter(&"cloud_color", _color)
	_material.set_shader_parameter(&"wind_speed", _wind)


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	apply_weather(new_weather)


## Scrolls the clouds down the wind, faster in a stronger one.
func _on_wind_changed(strength: float, direction: Vector3) -> void:
	var heading: Vector2 = Vector2(direction.x, direction.z)
	if heading.length() < 0.001:
		heading = target_wind.normalized() if target_wind.length() > 0.001 else Vector2.ONE.normalized()
	target_wind = heading.normalized() * maxf(wind_min_scroll, strength * wind_scroll_scale)
	_start_easing()
