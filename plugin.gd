# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
extends EditorPlugin

## Registers the shader globals WeatherFX writes to. Node types and editor icons come from the
## scripts' class_name / @icon annotations, so nothing is added to the Create Node dialog here.

const SHADER_GLOBALS: Dictionary = {
	"shader_globals/weather_wind_strength": {"type": "float", "value": 0.0},
	"shader_globals/weather_wind_direction": {"type": "vec3", "value": Vector3(1, 0, 0)},
	"shader_globals/weather_precipitation_strength": {"type": "float", "value": 0.0},
	"shader_globals/weather_foliage_tint": {"type": "color", "value": Color(1, 1, 1, 1)},
	"shader_globals/weather_grass_tint": {"type": "color", "value": Color(1, 1, 1, 1)},
}


func _enter_tree() -> void:
	_ensure_shader_globals()


func _ensure_shader_globals() -> void:
	var modified: bool = false
	for path: String in SHADER_GLOBALS:
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, SHADER_GLOBALS[path])
			modified = true
	if modified:
		ProjectSettings.save()
