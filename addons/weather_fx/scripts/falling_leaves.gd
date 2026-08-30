@tool
class_name FallingLeaves
extends GPUParticles3D

## Dynamic falling leaves particle effect that responds to WeatherFX global wind uniforms.
## Automatically activates and blows drifting leaves when wind strength is elevated.

@export var min_wind_threshold: float = 4.0:
	set(val):
		min_wind_threshold = val

@export var max_wind_reference: float = 10.0:
	set(val):
		max_wind_reference = val

@export var base_speed: float = 3.5:
	set(val):
		base_speed = val

var _mat: ParticleProcessMaterial


func _ready() -> void:
	emitting = false
	visible = true
	if process_material is ParticleProcessMaterial:
		_mat = process_material as ParticleProcessMaterial


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		emitting = false
		return
		
	var wind_strength: float = WeatherFX.get_wind_strength()
	if wind_strength < min_wind_threshold:
		emitting = false
		return
		
	var wind_dir: Vector3 = WeatherFX.get_wind_direction()
	emitting = true
		
	var wind_factor = clampf((wind_strength - min_wind_threshold) / (max_wind_reference - min_wind_threshold), 0.0, 1.0)
	amount_ratio = 0.2 + 0.8 * wind_factor
	
	if _mat:
		_mat.direction = Vector3(wind_dir.x, -0.35, wind_dir.z).normalized()
		_mat.initial_velocity_min = base_speed * (0.8 + 1.2 * wind_factor)
		_mat.initial_velocity_max = base_speed * (1.2 + 1.8 * wind_factor)
		_mat.gravity = Vector3(wind_dir.x * 2.0 * wind_factor, -3.5 - 1.5 * wind_factor, wind_dir.z * 2.0 * wind_factor)
		_mat.turbulence_noise_strength = 0.5 + 1.5 * wind_factor
