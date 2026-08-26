@tool
class_name GrassField
extends MultiMeshInstance3D

## High-performance, wind-reactive grass field populated using MultiMesh.
## Instances sway dynamically in response to WeatherFX global shader uniforms.

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

@export var cast_grass_shadows: bool = false:
	set(val):
		cast_grass_shadows = val
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

@export var custom_grass_material: ShaderMaterial:
	set(val):
		custom_grass_material = val
		if custom_grass_material:
			material_override = custom_grass_material


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null or multimesh.instance_count == 0:
		regenerate()


## Generates an optimized stylized 3D grass tuft mesh with cross-blades and vertex UVs.
static func create_stylized_grass_mesh(width: float = 0.7, height: float = 0.9) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var blade_angles = [0.0, PI / 3.0, 2.0 * PI / 3.0]
	var half_w = width * 0.5
	
	for angle in blade_angles:
		var dir = Vector2(cos(angle), sin(angle))
		var offset = Vector3(dir.x * half_w, 0.0, dir.y * half_w)
		
		var p0 = -offset # Bottom Left
		var p1 = offset  # Bottom Right
		var p2 = offset + Vector3(0.0, height, 0.0) # Top Right
		var p3 = -offset + Vector3(0.0, height, 0.0) # Top Left
		
		var norm = Vector3(0.0, 0.9, 0.0).normalized()
		
		# Quad (p0, p1, p2, p3)
		# Triangle 1
		st.set_normal(norm)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p0)
		
		st.set_normal(norm)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(p1)
		
		st.set_normal(norm)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(p2)
		
		# Triangle 2
		st.set_normal(norm)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p0)
		
		st.set_normal(norm)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(p2)
		
		st.set_normal(norm)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(p3)
		
	var mesh = st.commit()
	return mesh


## Rebuilds the MultiMesh instances within field boundaries.
func regenerate() -> void:
	if instance_count <= 0:
		if multimesh:
			multimesh.instance_count = 0
		return
	
	var mesh_to_use: Mesh = null
	if multimesh and multimesh.mesh:
		mesh_to_use = multimesh.mesh
	else:
		mesh_to_use = create_stylized_grass_mesh()
		
	var mat: Material = custom_grass_material
	if mat == null:
		mat = load("res://addons/weather_fx/materials/grass_material.tres")
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
