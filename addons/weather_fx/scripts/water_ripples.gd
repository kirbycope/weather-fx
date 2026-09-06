# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@icon("res://addons/weather_fx/assets/icons/weather_fx_icon.svg")
class_name WaterRipples
extends Node3D
## Real ripples on a pond_water surface: swimmers, floaters and boats push the water where they move.
##
## Wire the water's [Area3D] signals [signal Area3D.body_entered] and [signal Area3D.body_exited] to
## [method _on_body_entered] and [method _on_body_exited]. Every body in the water has its meshes put on
## visual layer [constant INTERACTION_LAYER]; [member mask_camera] sits [member depth_below] under the
## surface looking straight up, renders only that layer between itself and just above the water line,
## and so draws into [member mask_viewport] the underside outline of everything in the water. (Looking
## down from above would not work: the near plane would slice the tops off the bodies and leave only
## culled back faces.) [member simulation_viewport]
## runs a height-field wave simulation (water_ripples_sim.gdshader): wherever that outline changed
## since the last frame the water is pushed, and the wave equation carries it outward as ripples, bow
## waves and wakes in the shape of the bodies themselves. A body sitting still makes nothing.
## The surface mesh reads the result through the `ripple_texture`, `ripple_area` and `ripple_height`
## uniforms of pond_water.gdshader, which this node fills in on ready.

const INTERACTION_LAYER: int = 10 ## Visual layer the mask camera renders; bodies in the water are put on it while they are in.
const MASK_NEAR: float = 0.05 ## Near plane of the mask camera (m); it sits this far below depth_below.

@export var water_mesh: MeshInstance3D ## Surface drawn with pond_water.gdshader; its bounds size and place the simulation.
@export var ripple_height: float = 0.04 ## Metres of surface displacement per unit of simulated height.
@export var texels_per_metre: float = 32.0 ## Resolution of the mask and simulation; 32 gives 3 cm texels, fine enough for a swimmer's arm.
@export var depth_above: float = 0.1 ## The mask sees bodies up to this far above the water line (m)...
@export var depth_below: float = 1.2 ## ...and down to this far below it; a diver deeper than this stops rippling the surface.
@export var mask_viewport: SubViewport
@export var mask_camera: Camera3D
@export var simulation_viewport: SubViewport
@export var simulation: ColorRect ## Draws the wave simulation; its material reads the mask.

var _marked_meshes: Dictionary[Node, Array] = {} ## Body in the water -> the meshes this node put on the interaction layer.


func _ready() -> void:
	if not is_instance_valid(water_mesh) or water_mesh.mesh == null:
		push_warning("WaterRipples needs a water_mesh to size itself to.")
		return
	var bounds: AABB = water_mesh.global_transform * water_mesh.mesh.get_aabb()
	var centre: Vector3 = bounds.get_center()
	var extent: Vector2 = Vector2(bounds.size.x, bounds.size.z)
	# One texel grid for both viewports, sized to the water
	mask_viewport.size = Vector2i(maxi(int(round(extent.x * texels_per_metre)), 1), maxi(int(round(extent.y * texels_per_metre)), 1))
	simulation_viewport.size = mask_viewport.size
	# From below, straight up at the water line: screen-right along +X, screen-up along +Z
	mask_camera.global_transform = Transform3D(Basis.looking_at(Vector3.UP, Vector3.BACK), centre - Vector3.UP * (depth_below + MASK_NEAR))
	mask_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	mask_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	mask_camera.size = extent.y
	mask_camera.near = MASK_NEAR
	mask_camera.far = MASK_NEAR + depth_below + depth_above
	mask_camera.cull_mask = 1 << (INTERACTION_LAYER - 1)
	var simulation_material: ShaderMaterial = simulation.material as ShaderMaterial
	simulation_material.set_shader_parameter("mask_texture", mask_viewport.get_texture())
	var surface_material: ShaderMaterial = _surface_material()
	if surface_material == null:
		push_warning("WaterRipples: the water mesh has no ShaderMaterial to write the ripples into.")
		return
	surface_material.set_shader_parameter("ripple_texture", simulation_viewport.get_texture())
	surface_material.set_shader_parameter("ripple_area", Vector4(bounds.position.x, bounds.position.z, extent.x, extent.y))
	surface_material.set_shader_parameter("ripple_height", ripple_height)


## The material the surface is drawn with: an override first, else the mesh's own.
func _surface_material() -> ShaderMaterial:
	if water_mesh.material_override is ShaderMaterial:
		return water_mesh.material_override as ShaderMaterial
	if water_mesh.mesh.get_surface_count() > 0:
		return water_mesh.mesh.surface_get_material(0) as ShaderMaterial
	return null


## Wire to the water Area3D's body_entered: the body's meshes are shown to the mask camera.
func _on_body_entered(body: Node3D) -> void:
	var meshes: Array = body.find_children("*", "MeshInstance3D", true, false)
	if body is MeshInstance3D:
		meshes.append(body)
	var marked: Array = []
	for mesh: MeshInstance3D in meshes:
		if not mesh.get_layer_mask_value(INTERACTION_LAYER):
			mesh.set_layer_mask_value(INTERACTION_LAYER, true)
			marked.append(mesh)
	_marked_meshes[body] = marked


## Wire to the water Area3D's body_exited: the body's meshes leave the mask again.
func _on_body_exited(body: Node3D) -> void:
	var marked: Array = _marked_meshes.get(body, [])
	for mesh: MeshInstance3D in marked:
		if is_instance_valid(mesh):
			mesh.set_layer_mask_value(INTERACTION_LAYER, false)
	_marked_meshes.erase(body)
