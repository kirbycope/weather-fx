@tool
class_name WindVFX
extends Node3D

## Environmental wind ribbons, leaf streams and periodic gust sweeps driven by WeatherFX signals.
## Leaves only blow in tree biomes and, optionally, near nodes in the Tree/Trees/Foliage/Choppable groups.

const GUST_SWEEP_SCENE: PackedScene = preload("res://addons/weather_fx/assets/vfx/wind/Scenes/VFX_WindBlow_1.tscn")
const TREE_GROUPS: Array[StringName] = [&"Tree", &"Trees", &"Foliage", &"Choppable"]

@export var enabled: bool = true:
	set(val):
		enabled = val
		_apply()

@export var weather_fx: WeatherFX
@export var min_wind_threshold: float = 4.5
@export var max_wind_reference: float = 12.0
## Optional node to follow; falls back to weather_fx.target_node.
@export var follow_target: Node3D
@export var airflow_particles: Array[GPUParticles3D] = []
@export var leaf_particles: Array[GPUParticles3D] = []

@export_group("Foliage & Leaves")
@export var enable_wind_leaves: bool = true ## Enable or disable leaf particles in wind.
@export var require_nearby_trees: bool = true ## When true, leaves only blow if trees are physically nearby.
@export var tree_detection_radius: float = 35.0 ## Maximum distance to a tree for leaves to appear in wind.

@export_group("Gust Sweeps")
@export var enable_gust_sweeps: bool = true
@export var gust_interval_min: float = 12.0
@export var gust_interval_max: float = 24.0

@onready var _gust_timer: Timer = $GustTimer
@onready var _tree_check_timer: Timer = $TreeCheckTimer

var _wind_strength: float = 0.0
var _wind_direction: Vector3 = Vector3.RIGHT
var _wind_factor: float = 0.0
var _clear_weather: bool = true
var _playing: bool = false
var _is_active: bool = false
var _trees_nearby_cached: bool = false


func _ready() -> void:
	for particles: GPUParticles3D in airflow_particles + leaf_particles:
		particles.emitting = false
	if Engine.is_editor_hint():
		set_process(false)
		return
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if is_instance_valid(weather_fx):
		weather_fx.wind_changed.connect(_on_wind_changed)
		weather_fx.weather_changed.connect(_on_weather_changed)
		weather_fx.playback_changed.connect(_on_playback_changed)
		_clear_weather = weather_fx.active_weather == ClimateData.WeatherType.BLUE_SKY
		_playing = weather_fx.is_simulating()
		_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)


func _process(_delta: float) -> void:
	var target: Node3D = follow_target if is_instance_valid(follow_target) else (weather_fx.target_node if is_instance_valid(weather_fx) else null)
	if is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position + Vector3(0.0, 1.5, 0.0)


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	_wind_strength = strength
	_wind_direction = direction.normalized() if not direction.is_zero_approx() else Vector3.RIGHT
	_apply()


func _on_weather_changed(new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_clear_weather = new_weather == ClimateData.WeatherType.BLUE_SKY
	_apply()


func _on_playback_changed(active: bool) -> void:
	_playing = active
	_apply()


func _apply() -> void:
	var timers_ready: bool = is_instance_valid(_gust_timer) and is_instance_valid(_tree_check_timer)
	_is_active = enabled and _playing and not _clear_weather and _wind_strength >= min_wind_threshold
	visible = _is_active
	set_process(_is_active)
	if not _is_active:
		for particles: GPUParticles3D in airflow_particles + leaf_particles:
			particles.emitting = false
		if timers_ready:
			_gust_timer.stop()
			_tree_check_timer.stop()
		return
	# Rotate so the +X forward axis aligns with the wind direction
	rotation = Vector3(0.0, atan2(-_wind_direction.z, _wind_direction.x), 0.0)
	_wind_factor = clampf((_wind_strength - min_wind_threshold) / (max_wind_reference - min_wind_threshold), 0.0, 1.0)
	for particles: GPUParticles3D in airflow_particles:
		particles.emitting = true
		particles.amount_ratio = 0.25 + 0.75 * _wind_factor
		particles.speed_scale = 0.8 + 1.2 * _wind_factor
	_trees_nearby_cached = _check_nearby_trees()
	_apply_leaves()
	if timers_ready and _tree_check_timer.is_stopped():
		_tree_check_timer.start()
	if timers_ready and enable_gust_sweeps and _gust_timer.is_stopped():
		_gust_timer.start(randf_range(gust_interval_min, gust_interval_max) / (1.0 + _wind_factor))


func _apply_leaves() -> void:
	var allow_leaves: bool = _is_active and _can_spawn_leaves()
	for particles: GPUParticles3D in leaf_particles:
		particles.emitting = allow_leaves
		particles.visible = allow_leaves
		particles.amount_ratio = 0.25 + 0.75 * _wind_factor
		particles.speed_scale = 0.8 + 1.2 * _wind_factor


func _on_tree_check_timer_timeout() -> void:
	_trees_nearby_cached = _check_nearby_trees()
	_apply_leaves()


func _on_gust_timer_timeout() -> void:
	var gust: Node3D = GUST_SWEEP_SCENE.instantiate() as Node3D
	add_child(gust)
	# Place upwind (-X in local space) and let it blow across downwind (+X)
	gust.position = Vector3(randf_range(-18.0, -12.0), randf_range(1.5, 4.0), randf_range(-8.0, 8.0))
	gust.scale = Vector3.ONE * (0.8 + 0.6 * _wind_factor)
	get_tree().create_timer(5.0).timeout.connect(gust.queue_free)
	_gust_timer.start(randf_range(gust_interval_min, gust_interval_max) / (1.0 + _wind_factor))


## Determines whether leaves are allowed to appear based on settings, biome, and tree proximity.
func _can_spawn_leaves() -> bool:
	if not enable_wind_leaves:
		return false
	if is_instance_valid(weather_fx) and not ClimateData.biome_has_trees(weather_fx.current_biome):
		return false
	return _trees_nearby_cached or not require_nearby_trees


## Checks if any node in the tree groups is located within tree_detection_radius.
func _check_nearby_trees() -> bool:
	if not is_inside_tree():
		return false
	var check_pos: Vector3 = follow_target.global_position if is_instance_valid(follow_target) else global_position
	for group: StringName in TREE_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is Node3D and (node as Node3D).global_position.distance_to(check_pos) <= tree_detection_radius:
				return true
	return false
