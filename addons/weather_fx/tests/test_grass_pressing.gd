extends GutTest

## Purpose: whatever walks, rolls or slides through a field presses the grass.
##
## The blades are grown straight through the bodies that move (see test_grass_ground_probing.gd), so those
## same bodies are the ones that have to bend the grass at run time instead of clearing it. A `PressArea`
## sized to the field notices them coming and going, and each frame up to `MAX_PRESSERS` of them, the widest
## presses nearest the camera first, are handed to the shader as (x, y, z, radius). These tests cover who gets
## in the list, what radius each one presses, the cap and its order, and that an empty field says nothing to
## the shader at all.

const GRASS_FIELD_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/grass_field.tscn")

var root: Node3D
var field: GrassField


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	WeatherFX.active_wind_strength = 0.0
	WeatherFX.active_precipitation_strength = 0.0
	WeatherFX._player_cache = null
	WeatherFX._player_search_cooldown_frame = -1


## A field on flat ground of its own, so these tests are about the pressing and not the probing.
func _field(size: float = 20.0) -> GrassField:
	var grass: GrassField = GRASS_FIELD_SCENE.instantiate() as GrassField
	grass.ground_group = &""
	grass.field_size = Vector2(size, size)
	grass.instance_count = 50
	root.add_child(grass)
	return grass


## Physics frames so the press volume notices what is in it, then an idle frame so _process hands the
## shader the list. The two are not interchangeable: the bodies move in physics and the grass is drawn in idle.
func _settle() -> void:
	await wait_until(_no_field_growing, 10.0) # A probing field casts its rays a slice per physics frame
	await wait_physics_frames(2)
	await wait_process_frames(2)


func _no_field_growing() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"GrassField"):
		if (node as GrassField).is_growing():
			return false
	return true


func _walker(at: Vector3, radius: float = 0.4) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = maxf(1.8, radius * 2.0 + 0.2) # Height first: Godot clamps the radius to half of it
	capsule.radius = radius
	shape.shape = capsule
	body.add_child(shape)
	root.add_child(body)
	return body


func _points(grass: GrassField) -> PackedVector4Array:
	var material: ShaderMaterial = grass.material_override as ShaderMaterial
	return material.get_shader_parameter(&"press_points") as PackedVector4Array


func _count(grass: GrassField) -> int:
	var material: ShaderMaterial = grass.material_override as ShaderMaterial
	var sent: Variant = material.get_shader_parameter(&"press_count")
	return 0 if sent == null else int(sent)


func test_an_empty_field_never_writes_to_the_shader() -> void:
	field = _field()
	await _settle()
	var material: ShaderMaterial = field.material_override as ShaderMaterial
	assert_null(
		material.get_shader_parameter(&"press_count"),
		"A field nobody is standing in leaves press_count at the shader's own default of zero"
	)


func test_a_body_walking_in_presses_and_walking_out_stops() -> void:
	field = _field()
	var walker: CharacterBody3D = _walker(Vector3(1.0, 0.9, 1.0))
	await _settle()
	assert_eq(_count(field), 1, "The walker is pressing")
	var point: Vector4 = _points(field)[0]
	assert_almost_eq(point.x, 1.0, 0.01, "at its own x")
	assert_almost_eq(point.z, 1.0, 0.01, "and z")

	walker.position = Vector3(40.0, 0.9, 40.0) # Well outside the 20 x 20 field
	await _settle()
	assert_eq(_count(field), 0, "and stops pressing once it has left")


func test_only_the_bodies_the_blades_were_grown_through_press() -> void:
	# The ground is a StaticBody3D metres wide and it sits inside every field's press volume. Letting it
	# press flattened the whole field, which is what this test is here to stop coming back.
	field = _field()
	var character := CharacterBody3D.new()
	var rigid := RigidBody3D.new()
	rigid.freeze = true
	var platform := AnimatableBody3D.new()
	var ground := StaticBody3D.new()
	var placed: int = 0
	for body: PhysicsBody3D in [character, rigid, platform, ground]:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.5
		shape.shape = sphere
		body.add_child(shape)
		body.position = Vector3(float(placed) * 2.0 - 3.0, 0.5, 0.0)
		root.add_child(body)
		placed += 1
	await _settle()
	assert_eq(_count(field), 3, "The three that move press; the StaticBody3D does not")
	for i: int in 3:
		assert_almost_eq(_points(field)[i].w, 0.5, 0.01, "each at its own radius")
		assert_ne(snappedf(_points(field)[i].x, 0.01), 3.0, "and none of them is the StaticBody3D standing at x = 3")


func test_the_ground_under_the_field_never_presses_it() -> void:
	var ground := StaticBody3D.new()
	ground.add_to_group(&"GRASS")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(96.0, 1.0, 48.0) # The slab v3's world stands on
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(ground)
	field = _field()
	field.ground_group = &"GRASS"
	await _settle()
	assert_gt(field.get_instance_origins().size(), 0, "The field grew on the slab")
	assert_eq(_count(field), 0, "and the slab it grew on presses nothing")


func test_the_biggest_press_nearest_the_camera_wins_a_slot() -> void:
	field = _field(40.0)
	var horse: CharacterBody3D = _walker(Vector3(2.0, 0.9, 0.0), 1.3)
	var bones: Array[CharacterBody3D] = []
	for i: int in GrassField.MAX_PRESSERS + 2:
		bones.append(_walker(Vector3(float(i) * 0.3 - 1.5, 0.9, 1.0), 0.02))
	await _settle()
	assert_eq(_count(field), GrassField.MAX_PRESSERS, "The slots are full")
	var widest: float = 0.0
	for i: int in GrassField.MAX_PRESSERS:
		widest = maxf(widest, _points(field)[i].w)
	assert_almost_eq(widest, 1.3, 0.01, "and the one that presses widest kept its slot")
	assert_eq(bones.size(), GrassField.MAX_PRESSERS + 2, "even with more little ones than there are slots")
	assert_true(is_instance_valid(horse))

func test_the_radius_comes_off_the_body_own_shapes() -> void:
	field = _field()
	var slim: CharacterBody3D = _walker(Vector3(-4.0, 0.9, 0.0), 0.3)
	var wide: CharacterBody3D = _walker(Vector3(4.0, 0.9, 0.0), 1.2)
	await _settle()
	assert_eq(_count(field), 2, "Both are pressing")
	var radii: Array[float] = []
	for i: int in 2:
		radii.append(_points(field)[i].w)
	radii.sort()
	assert_almost_eq(radii[0], 0.3, 0.01, "The slim one presses its own radius")
	assert_almost_eq(radii[1], 1.2, 0.01, "and the wide one presses its own")
	assert_true(is_instance_valid(slim) and is_instance_valid(wide))


func test_a_body_with_no_radius_of_its_own_falls_back() -> void:
	field = _field()
	field.press_radius_fallback = 0.9
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var blob := ConvexPolygonShape3D.new() # A shape with no radius of its own
	blob.points = PackedVector3Array([
		Vector3(-0.4, -0.4, -0.4), Vector3(0.4, -0.4, -0.4), Vector3(0.4, -0.4, 0.4), Vector3(-0.4, -0.4, 0.4),
		Vector3(-0.4, 0.4, -0.4), Vector3(0.4, 0.4, -0.4), Vector3(0.4, 0.4, 0.4), Vector3(-0.4, 0.4, 0.4),
	])
	shape.shape = blob
	body.add_child(shape)
	body.position = Vector3(0.0, 0.5, 0.0)
	root.add_child(body)
	await _settle()
	assert_eq(_count(field), 1, "It still presses")
	assert_almost_eq(_points(field)[0].w, 0.9, 0.01, "at the fallback radius")


func test_no_more_than_the_shader_has_room_for() -> void:
	field = _field()
	for i: int in GrassField.MAX_PRESSERS + 4:
		_walker(Vector3(float(i) * 0.5 - 3.0, 0.9, 0.0))
	await _settle()
	assert_eq(_count(field), GrassField.MAX_PRESSERS, "The list is capped at what the uniform array holds")
	assert_eq(_points(field).size(), GrassField.MAX_PRESSERS, "and the array is always sent full length")


func test_turning_pressing_off_clears_what_the_shader_was_told() -> void:
	field = _field()
	_walker(Vector3(1.0, 0.9, 1.0))
	await _settle()
	assert_eq(_count(field), 1, "Pressing to begin with")
	field.enable_pressing = false
	await _settle()
	assert_eq(_count(field), 0, "and nothing once it is switched off")


func test_two_fields_from_the_same_scene_size_their_own_volumes() -> void:
	# The shape is a sub-resource of grass_field.tscn: without resource_local_to_scene both fields would
	# share one BoxShape3D and the second to be built would resize the first one's volume.
	var small: GrassField = _field(10.0)
	var large: GrassField = _field(40.0)
	await _settle()
	var small_box: BoxShape3D = small.get_node("PressArea/PressShape").shape as BoxShape3D
	var large_box: BoxShape3D = large.get_node("PressArea/PressShape").shape as BoxShape3D
	assert_ne(small_box, large_box, "Each field owns its own press shape")
	assert_almost_eq(small_box.size.x, 10.0, 0.01, "sized to its own field")
	assert_almost_eq(large_box.size.x, 40.0, 0.01, "and so is the other")


func test_the_press_volume_is_invisible_to_rays() -> void:
	# The player's crosshair ray collides with areas, so a press volume on a layer would sit between the
	# camera and every prompt over the grass, and the skateboard in v3's world stopped showing its prompt.
	field = _field()
	await _settle()
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.0, 10.0, 0.0), Vector3(0.0, -10.0, 0.0))
	query.collide_with_areas = true
	query.hit_from_inside = true
	var hit: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(query)
	assert_true(hit.is_empty(), "A ray through the field with areas on hits nothing: %s" % [hit.get("collider")])
	assert_eq(field.get_node("PressArea").collision_layer, 0, "because the volume is on no layer")
	field.get_node("PressArea").collision_layer = 1
	await wait_physics_frames(1)
	hit = field.get_world_3d().direct_space_state.intersect_ray(query)
	assert_eq(hit.get("collider"), field.get_node("PressArea"), "Put on a layer, the same ray lands on it")


func test_a_field_built_in_code_hides_its_volume_from_rays_too() -> void:
	var grass := GrassField.new()
	grass.ground_group = &""
	grass.field_size = Vector2(20.0, 20.0)
	root.add_child(grass)
	await _settle()
	var area: Area3D = grass.get_node_or_null("PressArea") as Area3D
	assert_not_null(area, "A field made in code builds its own press volume")
	assert_eq(area.collision_layer, 0, "on no layer, like the one in grass_field.tscn")


func test_a_player_presses_its_capsule_not_its_step_ray() -> void:
	# The Player carries a SeparationRayShape3D off to one side for climbing steps. It has no radius and must not
	# be counted as one, or the Player presses a circle nearly three times the width of its body.
	var body := CharacterBody3D.new()
	var capsule_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.3
	capsule_shape.shape = capsule
	body.add_child(capsule_shape)
	var step_ray := CollisionShape3D.new()
	step_ray.shape = SeparationRayShape3D.new()
	step_ray.position = Vector3(0.0, 0.4, -0.35)
	body.add_child(step_ray)
	var off := CollisionShape3D.new()
	var wide := SphereShape3D.new()
	wide.radius = 3.0
	off.shape = wide
	off.disabled = true
	body.add_child(off)
	root.add_child(body)
	assert_almost_eq(GrassField._press_radius_of(body, 0.5), 0.3, 0.001, "The capsule's own radius, not the ray's fallback nor the disabled sphere")


func test_a_scaled_shape_presses_its_scaled_radius() -> void:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	shape.scale = Vector3(2.0, 2.0, 2.0)
	body.add_child(shape)
	root.add_child(body)
	assert_almost_eq(GrassField._press_radius_of(body, 0.1), 1.0, 0.001, "A sphere of 0.5 scaled by two presses 1 m")


func test_a_body_high_above_the_grass_does_not_take_a_slot() -> void:
	field = _field()
	for i: int in GrassField.MAX_PRESSERS:
		_walker(Vector3(float(i) - 4.0, 2.5, -2.0)) # 2.5 m up: inside the volume (3 m), beyond press_height (1.5 m)
	_walker(Vector3(0.0, 0.9, 3.0)) # The one walking on the grass
	await _settle()
	assert_eq(_count(field), 1, "Only the walker on the grass presses; the ones overhead are left out of the slots")
	assert_almost_eq(_points(field)[0].z, 3.0, 0.01, "and it is the walker")


func test_the_nearer_of_two_equal_bodies_wins_the_last_slot() -> void:
	field = _field(40.0)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 10.0)
	root.add_child(camera)
	camera.make_current()
	for i: int in GrassField.MAX_PRESSERS - 1:
		_walker(Vector3(float(i) - 3.0, 0.9, 8.0))
	_walker(Vector3(0.0, 0.9, -15.0)) # Far from the camera
	_walker(Vector3(3.5, 0.9, 7.0)) # Close to it
	await _settle()
	assert_eq(_count(field), GrassField.MAX_PRESSERS, "The slots are full")
	var far_one_pressing: bool = false
	for i: int in GrassField.MAX_PRESSERS:
		if _points(field)[i].z < -10.0:
			far_one_pressing = true
	assert_false(far_one_pressing, "The body far from the camera is the one left out")


func test_a_field_that_grew_nothing_leaves_the_shared_material_alone() -> void:
	var empty: GrassField = GRASS_FIELD_SCENE.instantiate() as GrassField
	empty.ground_group = &""
	empty.instance_count = 0
	root.add_child(empty)
	_walker(Vector3(0.0, 0.9, 0.0))
	await _settle()
	var shared: ShaderMaterial = load("res://addons/weather_fx/resources/grass_material.tres") as ShaderMaterial
	assert_null(shared.get_shader_parameter(&"press_count"), "A walker in a field that grew nothing writes nothing into the shared material")


func test_the_press_volume_covers_the_grass_not_the_field_plane() -> void:
	# A field hung 10 m above its ground grows its blades 10 m below its own origin; the volume must be down there.
	var ground := StaticBody3D.new()
	ground.add_to_group(&"GRASS")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(ground)
	var high: GrassField = GRASS_FIELD_SCENE.instantiate() as GrassField
	high.field_size = Vector2(20.0, 20.0)
	high.instance_count = 200
	high.position = Vector3(0.0, 10.0, 0.0)
	root.add_child(high)
	await _settle()
	var volume: CollisionShape3D = high.get_node("PressArea/PressShape") as CollisionShape3D
	assert_almost_eq(volume.position.y, -10.0, 0.05, "The volume sits on the grass, 10 m below the field")
	assert_almost_eq((volume.shape as BoxShape3D).size.y, GrassField.PRESS_AREA_MARGIN * 2.0, 0.05, "and is only as tall as its margin, not stretched up to the field")


func test_the_shader_declares_what_the_field_writes() -> void:
	var shader: Shader = load("res://addons/weather_fx/resources/grass_wind.gdshader") as Shader
	var declared: Array[StringName] = []
	for uniform: Dictionary in shader.get_shader_uniform_list():
		declared.append(uniform["name"])
	assert_has(declared, &"press_points", "The shader takes the array the field fills")
	assert_has(declared, &"press_count", "and the count that bounds its loop")
	assert_string_contains(
		shader.code,
		"const int MAX_PRESS_POINTS = %d;" % GrassField.MAX_PRESSERS,
		"and the array is exactly as long as GrassField.MAX_PRESSERS"
	)
