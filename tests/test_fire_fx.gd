# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

extends GutTest

var _wfx: WeatherFX
var _fire_scene: PackedScene
var _fire_node: FireFX


func before_each() -> void:
	_wfx = WeatherFX.new()
	add_child_autofree(_wfx)
	_wfx.is_playing = true

	_fire_scene = load("res://addons/weather_fx/assets/models/loop_box/Scenes/Fire.tscn") as PackedScene
	if _fire_scene:
		var inst = _fire_scene.instantiate()
		_fire_node = inst as FireFX
		add_child_autofree(_fire_node)


func test_fire_node_instantiation() -> void:
	assert_not_null(_fire_node, "Fire node should be successfully instantiated")
	assert_not_null(_fire_node.smoke_particles, "Smoke particles should be found")
	assert_not_null(_fire_node.spark_particles, "Sparks particles should be found")
	assert_not_null(_fire_node.fire_light, "Light should be found")


func test_smoke_follows_wind_direction() -> void:
	if _fire_node == null or _fire_node.smoke_particles == null:
		pass_test("Fire scene not available")
		return

	# Set wind East (+X)
	_wfx.wind_direction = Vector3(1.0, 0.0, 0.0)
	_wfx.wind_strength_multiplier = 2.0
	_wfx._update_wind_globals()

	# Process frames for lerp to catch up
	for _i in range(5):
		_fire_node._process(0.5)

	var s_mat = _fire_node.smoke_particles.process_material as ParticleProcessMaterial
	assert_not_null(s_mat, "Smoke process material should be ParticleProcessMaterial")
	assert_gt(s_mat.gravity.x, 0.2, "Smoke gravity X should drift eastward along wind")

	# Rotate wind to North (-Z)
	_wfx.wind_direction = Vector3(0.0, 0.0, -1.0)
	_wfx._update_wind_globals()

	for _i in range(5):
		_fire_node._process(0.5)
	assert_lt(s_mat.gravity.z, -0.2, "Smoke gravity Z should drift northward along wind")


func test_sparks_follow_wind_direction() -> void:
	if _fire_node == null or _fire_node.spark_particles == null:
		pass_test("Fire scene not available")
		return

	_wfx.wind_direction = Vector3(1.0, 0.0, 0.0)
	_wfx.wind_strength_multiplier = 2.0
	_wfx._update_wind_globals()

	for _i in range(5):
		_fire_node._process(0.5)

	var sp_mat = _fire_node.spark_particles.process_material as ParticleProcessMaterial
	assert_not_null(sp_mat, "Sparks process material should be ParticleProcessMaterial")
	assert_gt(sp_mat.gravity.x, 0.3, "Sparks gravity X should drift eastward along wind")
