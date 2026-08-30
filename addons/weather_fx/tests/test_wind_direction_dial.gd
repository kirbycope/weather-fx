# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

extends GutTest

var _wfx: WeatherFX
var _dial: WindDirectionDial


func before_each() -> void:
	_wfx = WeatherFX.new()
	add_child_autofree(_wfx)
	_wfx.is_playing = true

	_dial = WindDirectionDial.new()
	_dial.weather_fx_node = _wfx
	add_child_autofree(_dial)


func test_initial_direction() -> void:
	assert_eq(_dial.get_direction(), Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(_dial.get_angle_degrees(), 0.0, 0.01)
	assert_eq(_dial.get_cardinal_name(), "East")


func test_set_direction_updates_weather_fx() -> void:
	var north = Vector3(0.0, 0.0, -1.0)
	_dial.set_direction(north, true)
	
	assert_almost_eq(_wfx.wind_direction.x, north.x, 0.01)
	assert_almost_eq(_wfx.wind_direction.z, north.z, 0.01)
	assert_almost_eq(_dial.get_angle_degrees(), 270.0, 0.01)
	assert_eq(_dial.get_cardinal_name(), "North")


func test_set_angle_degrees() -> void:
	# 90 degrees corresponds to South (+Z)
	_dial.set_angle_degrees(90.0, true)
	
	assert_almost_eq(_wfx.wind_direction.x, 0.0, 0.01)
	assert_almost_eq(_wfx.wind_direction.z, 1.0, 0.01)
	assert_almost_eq(_dial.get_angle_degrees(), 90.0, 0.01)
	assert_eq(_dial.get_cardinal_name(), "South")


func test_weather_fx_updates_dial() -> void:
	# 180 degrees corresponds to West (-X)
	var west = Vector3(-1.0, 0.0, 0.0)
	_wfx.wind_direction = west
	
	assert_almost_eq(_dial.get_direction().x, -1.0, 0.01)
	assert_almost_eq(_dial.get_angle_degrees(), 180.0, 0.01)
	assert_eq(_dial.get_cardinal_name(), "West")


func test_cardinal_directions() -> void:
	var expected_angles = [
		{"angle": 0.0, "cardinal": "East"},
		{"angle": 45.0, "cardinal": "SE"},
		{"angle": 90.0, "cardinal": "South"},
		{"angle": 135.0, "cardinal": "SW"},
		{"angle": 180.0, "cardinal": "West"},
		{"angle": 225.0, "cardinal": "NW"},
		{"angle": 270.0, "cardinal": "North"},
		{"angle": 315.0, "cardinal": "NE"}
	]
	
	for tc in expected_angles:
		_dial.set_angle_degrees(tc["angle"], true)
		assert_eq(_dial.get_cardinal_name(), tc["cardinal"], "Angle %f should be %s" % [tc["angle"], tc["cardinal"]])
