class_name FallingLeaves
extends GPUParticles3D

## Falling leaves particle effect that drifts with the wind reported by WeatherFX.wind_changed.
## Emits only while wind strength is at or above min_wind_threshold.

@export var weather_fx: WeatherFX
@export var min_wind_threshold: float = 4.0
@export var max_wind_reference: float = 10.0
@export var base_speed: float = 3.5

var _mat: ParticleProcessMaterial


func _ready() -> void:
	emitting = false
	_mat = process_material as ParticleProcessMaterial
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if not is_instance_valid(weather_fx):
		return
	weather_fx.wind_changed.connect(_on_wind_changed)
	_on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)


func _on_wind_changed(strength: float, direction: Vector3) -> void:
	emitting = strength >= min_wind_threshold
	if not emitting:
		return
	var wind_factor: float = clampf((strength - min_wind_threshold) / (max_wind_reference - min_wind_threshold), 0.0, 1.0)
	amount_ratio = 0.2 + 0.8 * wind_factor
	if _mat == null:
		return
	_mat.direction = Vector3(direction.x, -0.35, direction.z).normalized()
	_mat.initial_velocity_min = base_speed * (0.8 + 1.2 * wind_factor)
	_mat.initial_velocity_max = base_speed * (1.2 + 1.8 * wind_factor)
	_mat.gravity = Vector3(direction.x * 2.0 * wind_factor, -3.5 - 1.5 * wind_factor, direction.z * 2.0 * wind_factor)
	_mat.turbulence_noise_strength = 0.5 + 1.5 * wind_factor
