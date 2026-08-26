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

@export_group("Tuft Geometry")
@export_range(1, 16) var blades_per_tuft: int = 6:
	set(val):
		blades_per_tuft = clampi(val, 1, 16)
		if is_inside_tree():
			regenerate()

@export_range(2, 6) var blade_segments: int = 4:
	set(val):
		blade_segments = clampi(val, 2, 6)
		if is_inside_tree():
			regenerate()

@export_range(0.05, 1.0, 0.01) var tuft_radius: float = 0.18:
	set(val):
		tuft_radius = maxf(0.01, val)
		if is_inside_tree():
			regenerate()

@export_range(0.1, 3.0, 0.05) var blade_height: float = 0.85:
	set(val):
		blade_height = maxf(0.05, val)
		if is_inside_tree():
			regenerate()

@export_range(0.02, 0.5, 0.01) var blade_width: float = 0.09:
	set(val):
		blade_width = maxf(0.01, val)
		if is_inside_tree():
			regenerate()

@export_range(0.0, 1.0, 0.05) var blade_curve: float = 0.35:
	set(val):
		blade_curve = clampf(val, 0.0, 1.0)
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


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_grass_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null or multimesh.instance_count == 0:
		regenerate()


## Generates an optimized stylized 3D grass tuft mesh with curved, tapered blades and volumetric spherical normals.
static func create_stylized_grass_mesh(
	height: float = 0.85,
	width: float = 0.09,
	blades_count: int = 6,
	segments_per_blade: int = 4,
	tuft_rad: float = 0.18,
	curve_strength: float = 0.35
) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for b in range(blades_count):
		# Distribute blades around the tuft with organic angle and radius jitter
		var base_angle = (float(b) / float(blades_count)) * TAU
		var jitter_angle = (float((b * 17) % 7) / 7.0 - 0.5) * 0.45
		var angle = base_angle + jitter_angle
		
		var r = tuft_rad * (0.35 + 0.65 * (float((b * 13) % 5) / 5.0))
		var dir = Vector2(cos(angle), sin(angle))
		var base_pos = Vector3(dir.x * r, 0.0, dir.y * r)
		
		var outward = Vector3(dir.x, 0.0, dir.y).normalized()
		var tangent = Vector3(-dir.y, 0.0, dir.x).normalized()
		
		# Organic height, width, and outward curvature multipliers per blade
		var h_mult = 0.75 + 0.35 * (float((b * 23) % 7) / 7.0)
		var w_mult = 0.85 + 0.30 * (float((b * 11) % 5) / 5.0)
		var c_mult = curve_strength * (0.7 + 0.6 * (float((b * 31) % 7) / 7.0))
		
		var cur_height = height * h_mult
		var cur_width = width * w_mult
		
		# Generate vertices along the curved blade spine
		var left_verts: Array[Vector3] = []
		var right_verts: Array[Vector3] = []
		var normals: Array[Vector3] = []
		var uvs_left: Array[Vector2] = []
		var uvs_right: Array[Vector2] = []
		
		for s in range(segments_per_blade + 1):
			var t = float(s) / float(segments_per_blade) # 0.0 (base) to 1.0 (tip)
			var y = cur_height * t
			
			# Parabolic outward arch curve
			var disp = outward * (c_mult * pow(t, 1.5))
			var center = base_pos + disp + Vector3(0.0, y, 0.0)
			
			# Taper width towards a sharp pointy tip
			var half_w = (cur_width * 0.5) * maxf(0.0, 1.0 - pow(t, 1.15))
			if s == segments_per_blade:
				half_w = 0.0
				
			var v_l = center - tangent * half_w
			var v_r = center + tangent * half_w
			
			# Volumetric normal: blend upward with outward radial vector from clump center
			var radial = (Vector3(center.x, 0.0, center.z).normalized() * 0.4 + Vector3.UP * 0.6).normalized()
			
			left_verts.append(v_l)
			right_verts.append(v_r)
			normals.append(radial)
			uvs_left.append(Vector2(0.0, 1.0 - t))
			uvs_right.append(Vector2(1.0, 1.0 - t))
		
		# Triangulate quad segments and tip
		for s in range(segments_per_blade):
			var v0 = left_verts[s]
			var v1 = right_verts[s]
			var v2 = left_verts[s + 1]
			var v3 = right_verts[s + 1]
			
			var n0 = normals[s]
			var n1 = normals[s + 1]
			
			var uv0_l = uvs_left[s]
			var uv0_r = uvs_right[s]
			var uv1_l = uvs_left[s + 1]
			var uv1_r = uvs_right[s + 1]
			
			if s == segments_per_blade - 1:
				# Apex triangle (v0, v1, v2 where v2 == v3 is the tip point)
				st.set_normal(n0)
				st.set_uv(uv0_l)
				st.add_vertex(v0)
				
				st.set_normal(n0)
				st.set_uv(uv0_r)
				st.add_vertex(v1)
				
				st.set_normal(n1)
				st.set_uv(uv1_l)
				st.add_vertex(v2)
			else:
				# Quad segment (v0, v1, v3, v2)
				# Triangle 1
				st.set_normal(n0)
				st.set_uv(uv0_l)
				st.add_vertex(v0)
				
				st.set_normal(n0)
				st.set_uv(uv0_r)
				st.add_vertex(v1)
				
				st.set_normal(n1)
				st.set_uv(uv1_r)
				st.add_vertex(v3)
				
				# Triangle 2
				st.set_normal(n0)
				st.set_uv(uv0_l)
				st.add_vertex(v0)
				
				st.set_normal(n1)
				st.set_uv(uv1_r)
				st.add_vertex(v3)
				
				st.set_normal(n1)
				st.set_uv(uv1_l)
				st.add_vertex(v2)
				
	var mesh = st.commit()
	return mesh


## Rebuilds the MultiMesh instances within field boundaries.
func regenerate() -> void:
	if instance_count <= 0:
		if multimesh:
			multimesh.instance_count = 0
		return
	
	var mesh_to_use: Mesh = custom_mesh
	if mesh_to_use == null:
		mesh_to_use = create_stylized_grass_mesh(
			blade_height,
			blade_width,
			blades_per_tuft,
			blade_segments,
			tuft_radius,
			blade_curve
		)
		
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
