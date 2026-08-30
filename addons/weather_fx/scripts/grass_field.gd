@tool
class_name GrassField
extends MultiMeshInstance3D

## High-performance, wind-reactive grass field populated using MultiMesh.
## Instances sway dynamically in response to WeatherFX global shader uniforms.

enum GrassMeshType {
	COMMON_SHORT,
	COMMON_TALL,
	WISPY_SHORT,
	WISPY_TALL,
	CUSTOM
}

const QUATERNIUS_MESH_PATHS = {
	GrassMeshType.COMMON_SHORT: "res://addons/weather_fx/resources/mesh_grass_common_short.tres",
	GrassMeshType.COMMON_TALL: "res://addons/weather_fx/resources/mesh_grass_common_tall.tres",
	GrassMeshType.WISPY_SHORT: "res://addons/weather_fx/resources/mesh_grass_wispy_short.tres",
	GrassMeshType.WISPY_TALL: "res://addons/weather_fx/resources/mesh_grass_wispy_tall.tres",
}

@export var mesh_type: GrassMeshType = GrassMeshType.COMMON_SHORT:
	set(val):
		mesh_type = val
		if is_inside_tree():
			regenerate()

@export var instance_count: int = 1000:
	set(val):
		instance_count = max(0, val)
		if is_inside_tree():
			regenerate()

@export var field_size: Vector2 = Vector2(30.0, 30.0):
	set(val):
		field_size = val
		if is_inside_tree():
			regenerate()

@export var min_scale: float = 0.7:
	set(val):
		min_scale = maxf(0.1, val)
		if is_inside_tree():
			regenerate()

@export var max_scale: float = 1.3:
	set(val):
		max_scale = maxf(min_scale, val)
		if is_inside_tree():
			regenerate()

@export var seed_value: int = 12345:
	set(val):
		seed_value = val
		if is_inside_tree():
			regenerate()

@export var custom_mesh: Mesh = null:
	set(val):
		custom_mesh = val
		if is_inside_tree():
			regenerate()

@export_group("Rendering")
@export var cast_grass_shadows: bool = false:
	set(val):
		cast_grass_shadows = val
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

@export var custom_grass_material: ShaderMaterial:
	set(val):
		custom_grass_material = val
		if custom_grass_material:
			material_override = custom_grass_material


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		if multimesh == null or multimesh.instance_count == 0:
			regenerate()


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null or multimesh.instance_count == 0:
		regenerate()


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		match what:
			NOTIFICATION_EDITOR_PRE_SAVE:
				multimesh = null
			NOTIFICATION_EDITOR_POST_SAVE:
				regenerate()


## Returns the active mesh based on mesh_type or custom_mesh.
func get_active_mesh() -> Mesh:
	if mesh_type == GrassMeshType.CUSTOM and custom_mesh:
		return custom_mesh
	if QUATERNIUS_MESH_PATHS.has(mesh_type):
		var res_path: String = QUATERNIUS_MESH_PATHS[mesh_type]
		var loaded_mesh = load(res_path) as Mesh
		if loaded_mesh:
			return loaded_mesh
	if custom_mesh:
		return custom_mesh
	return load("res://addons/weather_fx/resources/mesh_grass_common_short.tres") as Mesh


## Rebuilds the MultiMesh instances within field boundaries.
func regenerate() -> void:
	if instance_count <= 0:
		if multimesh:
			multimesh.instance_count = 0
		return
	
	var mesh_to_use: Mesh = get_active_mesh()
		
	var mat: Material = custom_grass_material
	if mat == null:
		mat = load("res://addons/weather_fx/resources/grass_material.tres")
	if mat:
		material_override = mat
		if mesh_to_use and mesh_to_use.get_surface_count() > 0:
			mesh_to_use.surface_set_material(0, mat)

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_to_use
	mm.instance_count = instance_count
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var half_x = field_size.x * 0.5
	var half_z = field_size.y * 0.5
	
	for i in range(instance_count):
		var pos_x = rng.randf_range(-half_x, half_x)
		var pos_z = rng.randf_range(-half_z, half_z)
		var rot_y = rng.randf_range(0.0, TAU)
		var scl = rng.randf_range(min_scale, max_scale)
		
		var t = Transform3D()
		t = t.rotated(Vector3.UP, rot_y)
		t = t.scaled(Vector3(scl, scl, scl))
		t.origin = Vector3(pos_x, 0.0, pos_z)
		
		mm.set_instance_transform(i, t)
		
	multimesh = mm
