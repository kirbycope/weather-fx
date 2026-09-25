extends GutTest
## Falling snow is drawn from two real snowflakes, not plain squares: an atlas of Lorc's two game-icons.net flakes,
## one frame picked at random per particle, each turning as it falls.

const WEATHER_SCENE: PackedScene = preload("res://addons/weather_fx/scenes/weather_fx.tscn")


func test_snow_draws_two_snowflakes_picked_at_random() -> void:
	var weather: Node = WEATHER_SCENE.instantiate()
	var snow: GPUParticles3D = weather.get_node("PrecipitationFX/SnowParticles")
	var quad: QuadMesh = snow.draw_pass_1 as QuadMesh
	var material: StandardMaterial3D = quad.material as StandardMaterial3D
	assert_not_null(material.albedo_texture, "The flakes are textured")
	assert_eq(material.albedo_texture.resource_path, "res://addons/weather_fx/assets/textures/snowflakes.svg")
	assert_eq(material.particles_anim_h_frames, 2, "The atlas holds two flakes")
	var process: ParticleProcessMaterial = snow.process_material as ParticleProcessMaterial
	assert_eq(process.anim_speed_max, 0.0, "A flake keeps the frame it was given")
	assert_gt(process.anim_offset_max, 0.5, "and each is given one of the two at random")
	assert_gt(process.angular_velocity_max, 0.0, "and they turn as they fall")
	weather.free()


func test_the_atlas_is_white_so_the_tint_shows() -> void:
	var source: String = FileAccess.get_file_as_string("res://addons/weather_fx/assets/textures/snowflakes.svg")
	assert_true(source.contains('fill="#ffffff"'), "The game-icons paths are black; the atlas fills them white, or the material's colour would multiply to black")
	assert_eq(source.count("<path"), 2, "Two flakes")
