# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
extends Node

signal time_changed(time_hours: float)

@export_range(0.0, 24.0, 0.1) var current_time: float = 12.0 :
	set(value):
		if is_equal_approx(current_time, value):
			return
		current_time = value
		emit_signal("time_changed", current_time)
