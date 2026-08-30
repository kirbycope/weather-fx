@tool
class_name WindVFX
extends Node3D

## High-level Wind Visual Effects manager for WeatherFX.
## Aligns environmental wind ribbons, air flows, and gust sweeps with global wind physics.

@export var enabled: bool = true:
	set(val):
		enabled = val
		if not enabled:
			for p in _airflow_particles:
				if is_instance_valid(p):
					p.emitting = false
		_update_visibility()

@export var min_wind_threshold: float = 4.5:
	set(val):
		min_wind_threshold = val

@export var max_wind_reference: float = 12.0:
	set(val):
		max_wind_reference = val

@export var follow_target: Node3D:
	set(val):
		follow_target = val

@export_group("Gust Sweeps")
@export var enable_gust_sweeps: bool = true
@export var gust_interval_min: float = 12.0
@export var gust_interval_max: float = 24.0

var _airflow_particles: Array[GPUParticles3D] = []
var _gust_sweep_scene: PackedScene
var _gust_timer: float = 0.0
var _next_gust_time: float = 8.0


func _ready() -> void:
	_airflow_particles.clear()
	for child in get_children():
		if child is GPUParticles3D:
			_airflow_particles.append(child)
			child.emitting = false
			child.visible = true
			
	# Preload gust sweep
	if ResourceLoader.exists("res://addons/weather_fx/assets/vfx/wind/Scenes/VFX_WindBlow_1.tscn"):
		_gust_sweep_scene = load("res://addons/weather_fx/assets/vfx/wind/Scenes/VFX_WindBlow_1.tscn") as PackedScene
		
	_next_gust_time = randf_range(gust_interval_min, gust_interval_max)
	visible = enabled


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		visible = false
		for p in _airflow_particles:
			if is_instance_valid(p):
				p.emitting = false
		return
		
	var wind_strength: float = WeatherFX.get_wind_strength()
	var is_active = enabled and (wind_strength >= min_wind_threshold)
	
	if not is_active:
		visible = false
		for p in _airflow_particles:
			if is_instance_valid(p):
				p.emitting = false
		return
		
	visible = true
		
	# Follow target position if assigned
	if follow_target and is_instance_valid(follow_target):
		global_position = follow_target.global_position
		
	var wind_dir: Vector3 = WeatherFX.get_wind_direction()
	if wind_dir.length_squared() < 0.001:
		wind_dir = Vector3.RIGHT
	else:
		wind_dir = wind_dir.normalized()
			
	# Rotate entire wind VFX node so its +X forward axis aligns exactly with wind_dir
	var yaw_angle = atan2(-wind_dir.z, wind_dir.x)
	rotation = Vector3(0.0, yaw_angle, 0.0)
		
	var wind_factor = clampf((wind_strength - min_wind_threshold) / (max_wind_reference - min_wind_threshold), 0.0, 1.0)
	
	# Update continuous airflow particle systems
	for p in _airflow_particles:
		if is_instance_valid(p):
			p.visible = true
			p.emitting = true
			p.amount_ratio = 0.25 + 0.75 * wind_factor
			p.speed_scale = 0.8 + 1.2 * wind_factor
				
	# Periodic gust sweep wave
	if enable_gust_sweeps and is_active and _gust_sweep_scene:
		_gust_timer += delta
		if _gust_timer >= _next_gust_time:
			_gust_timer = 0.0
			_next_gust_time = randf_range(gust_interval_min / (1.0 + wind_factor), gust_interval_max / (1.0 + wind_factor))
			_spawn_gust_sweep(wind_dir, wind_factor)


func _spawn_gust_sweep(wind_dir: Vector3, wind_factor: float) -> void:
	if not _gust_sweep_scene:
		return
	var gust = _gust_sweep_scene.instantiate() as Node3D
	if not gust:
		return
	add_child(gust)
	
	# Place upwind (-X in local space) and let it blow across downwind (+X)
	var offset_x = randf_range(-18.0, -12.0)
	var offset_y = randf_range(1.5, 4.0)
	var offset_z = randf_range(-8.0, 8.0)
	gust.position = Vector3(offset_x, offset_y, offset_z)
	gust.scale = Vector3.ONE * (0.8 + 0.6 * wind_factor)
	
	# Auto-clean after lifetime
	var timer = get_tree().create_timer(5.0)
	timer.timeout.connect(func():
		if is_instance_valid(gust):
			gust.queue_free()
	)


func _update_visibility() -> void:
	visible = enabled
	if not enabled:
		for p in _airflow_particles:
			if is_instance_valid(p):
				p.emitting = false
