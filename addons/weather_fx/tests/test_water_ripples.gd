extends GutTest

## Purpose: WaterRipples sizes its mask camera and simulation to the water mesh, hands the simulation
## to the surface material, and shows bodies in the water to the mask camera only while they are in.

const RIPPLES_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/water_ripples.tscn")
const POND_MATERIAL: Material = preload("res://addons/weather_fx/resources/pond_water_material.tres")

var root: Node3D
var surface: MeshInstance3D
var ripples: WaterRipples


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(20.0, 10.0)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = POND_MATERIAL.duplicate()
	surface.mesh = quad
	surface.position = Vector3(5.0, 2.0, -3.0)
	root.add_child(surface)
	ripples = RIPPLES_SCENE.instantiate() as WaterRipples
	ripples.water_mesh = surface
	root.add_child(ripples)


func test_simulation_covers_the_water_mesh() -> void:
	var material: ShaderMaterial = surface.mesh.surface_get_material(0) as ShaderMaterial
	var area: Vector4 = material.get_shader_parameter("ripple_area")
	assert_almost_eq(area.x, -5.0, 0.01, "ripple_area starts at the mesh's minimum world X")
	assert_almost_eq(area.y, -8.0, 0.01, "ripple_area starts at the mesh's minimum world Z")
	assert_almost_eq(area.z, 20.0, 0.01, "ripple_area spans the mesh width")
	assert_almost_eq(area.w, 10.0, 0.01, "ripple_area spans the mesh depth")
	assert_not_null(material.get_shader_parameter("ripple_texture"), "The surface reads the simulation texture")
	assert_almost_eq(float(material.get_shader_parameter("ripple_height")), ripples.ripple_height, 0.001)

	var camera_depth: float = ripples.depth_below + WaterRipples.MASK_NEAR
	assert_lt(ripples.mask_camera.global_position.distance_to(Vector3(5.0, 2.0 - camera_depth, -3.0)), 0.01, "The mask camera sits below the centre of the water")
	assert_lt(ripples.mask_camera.global_basis.z.distance_to(Vector3.DOWN), 0.01, "The mask camera looks straight up at the surface")
	assert_lt(ripples.mask_camera.global_basis.x.distance_to(Vector3.RIGHT), 0.01, "Screen-right is world +X")
	assert_lt(ripples.mask_camera.global_basis.y.distance_to(Vector3.BACK), 0.01, "Screen-up is world +Z, so texture V runs along -Z")
	assert_eq(ripples.mask_camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_almost_eq(ripples.mask_camera.size, 10.0, 0.01, "The orthographic height matches the water depth")
	assert_eq(ripples.mask_camera.cull_mask, 1 << (WaterRipples.INTERACTION_LAYER - 1), "The mask camera renders only the interaction layer")
	assert_almost_eq(ripples.mask_camera.near, WaterRipples.MASK_NEAR, 0.001)
	assert_almost_eq(ripples.mask_camera.far, WaterRipples.MASK_NEAR + ripples.depth_below + ripples.depth_above, 0.001, "The mask reaches from depth_below to depth_above over the water line")

	assert_eq(ripples.mask_viewport.size, Vector2i(int(20.0 * ripples.texels_per_metre), int(10.0 * ripples.texels_per_metre)), "The mask covers the water at texels_per_metre")
	assert_eq(ripples.simulation_viewport.size, ripples.mask_viewport.size, "Mask and simulation share one texel grid")
	var simulation_material: ShaderMaterial = ripples.simulation.material as ShaderMaterial
	assert_not_null(simulation_material.get_shader_parameter("mask_texture"), "The simulation reads the mask")


func test_bodies_in_the_water_are_shown_to_the_mask_camera() -> void:
	var boat := StaticBody3D.new()
	var hull := MeshInstance3D.new()
	hull.mesh = BoxMesh.new()
	boat.add_child(hull)
	var mast := MeshInstance3D.new()
	mast.mesh = BoxMesh.new()
	mast.set_layer_mask_value(WaterRipples.INTERACTION_LAYER, true)
	boat.add_child(mast)
	root.add_child(boat)

	ripples._on_body_entered(boat)
	assert_true(hull.get_layer_mask_value(WaterRipples.INTERACTION_LAYER), "A body in the water is put on the interaction layer")
	assert_true(hull.get_layer_mask_value(1), "It keeps its normal layers, so it still renders in the game")

	ripples._on_body_exited(boat)
	assert_false(hull.get_layer_mask_value(WaterRipples.INTERACTION_LAYER), "Leaving the water takes it off the layer again")
	assert_true(mast.get_layer_mask_value(WaterRipples.INTERACTION_LAYER), "A mesh that was already on the layer is left alone")


func test_a_body_that_is_itself_a_mesh_is_shown() -> void:
	var float_mesh := MeshInstance3D.new()
	float_mesh.mesh = SphereMesh.new()
	root.add_child(float_mesh)
	ripples._on_body_entered(float_mesh)
	assert_true(float_mesh.get_layer_mask_value(WaterRipples.INTERACTION_LAYER), "A MeshInstance3D body is marked itself")
	ripples._on_body_exited(float_mesh)
	assert_false(float_mesh.get_layer_mask_value(WaterRipples.INTERACTION_LAYER))
