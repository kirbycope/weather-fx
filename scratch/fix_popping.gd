extends SceneTree

func _init():
	var weather_gd = "res://addons/weather_fx/scripts/weather_fx.gd"
	var text = FileAccess.get_file_as_string(weather_gd)
	
	# Replace clear_all_effects
	var old_clear = """func clear_all_effects() -> void:
	if is_instance_valid(rain_particles):
		rain_particles.emitting = false
		rain_particles.visible = false
	if is_instance_valid(rain_splash_particles):
		rain_splash_particles.emitting = false
		rain_splash_particles.visible = false
	if is_instance_valid(snow_particles):
		snow_particles.emitting = false
		snow_particles.visible = false
	if is_instance_valid(wind_vfx_node):
		if "enabled" in wind_vfx_node:
			wind_vfx_node.enabled = false
		wind_vfx_node.visible = false
		for child in wind_vfx_node.find_children("*", "GPUParticles3D", true, false):
			if child is GPUParticles3D:
				child.emitting = false
				child.visible = false"""
				
	var new_clear = """func clear_all_effects() -> void:
	if is_instance_valid(rain_particles):
		if rain_particles.emitting:
			rain_particles.emitting = false
			rain_particles.restart()
		rain_particles.visible = false
		if Engine.is_editor_hint():
			rain_particles.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(rain_splash_particles):
		if rain_splash_particles.emitting:
			rain_splash_particles.emitting = false
			rain_splash_particles.restart()
		rain_splash_particles.visible = false
		if Engine.is_editor_hint():
			rain_splash_particles.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(snow_particles):
		if snow_particles.emitting:
			snow_particles.emitting = false
			snow_particles.restart()
		snow_particles.visible = false
		if Engine.is_editor_hint():
			snow_particles.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(wind_vfx_node):
		if "enabled" in wind_vfx_node:
			wind_vfx_node.enabled = false
		wind_vfx_node.visible = false
		for child in wind_vfx_node.find_children("*", "GPUParticles3D", true, false):
			if child is GPUParticles3D:
				if child.emitting:
					child.emitting = false
					child.restart()
				child.visible = false
				if Engine.is_editor_hint():
					child.process_mode = Node.PROCESS_MODE_DISABLED"""
					
	text = text.replace(old_clear, new_clear)
	
	# Replace _apply_rain
	var old_apply_rain = """func _apply_rain(amount: int) -> void:
	if not _can_simulate():
		if is_instance_valid(rain_particles):
			rain_particles.emitting = false
			rain_particles.visible = false
		if is_instance_valid(rain_splash_particles):
			rain_splash_particles.emitting = false
			rain_splash_particles.visible = false
		return
	if is_instance_valid(rain_particles):
		rain_particles.visible = true
		rain_particles.amount = amount
		rain_particles.emitting = true
	if is_instance_valid(rain_splash_particles):
		rain_splash_particles.visible = true
		rain_splash_particles.amount = int(amount * 1.5)
		rain_splash_particles.emitting = true"""
		
	var new_apply_rain = """func _apply_rain(amount: int) -> void:
	if not _can_simulate():
		clear_all_effects()
		return
	if is_instance_valid(rain_particles):
		if Engine.is_editor_hint():
			rain_particles.process_mode = Node.PROCESS_MODE_INHERIT
		rain_particles.visible = true
		rain_particles.amount = amount
		rain_particles.emitting = true
	if is_instance_valid(rain_splash_particles):
		if Engine.is_editor_hint():
			rain_splash_particles.process_mode = Node.PROCESS_MODE_INHERIT
		rain_splash_particles.visible = true
		rain_splash_particles.amount = int(amount * 1.5)
		rain_splash_particles.emitting = true"""
		
	text = text.replace(old_apply_rain, new_apply_rain)
	
	# Replace _apply_snow
	var old_apply_snow = """func _apply_snow(amount: int, gravity_y: float) -> void:
	if not _can_simulate():
		if is_instance_valid(snow_particles):
			snow_particles.emitting = false
			snow_particles.visible = false
		return
	if is_instance_valid(snow_particles):
		snow_particles.visible = true
		snow_particles.amount = amount
		if snow_particles.process_material is ParticleProcessMaterial:
			(snow_particles.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, gravity_y, 0.0)
		snow_particles.emitting = true"""
		
	var new_apply_snow = """func _apply_snow(amount: int, gravity_y: float) -> void:
	if not _can_simulate():
		clear_all_effects()
		return
	if is_instance_valid(snow_particles):
		if Engine.is_editor_hint():
			snow_particles.process_mode = Node.PROCESS_MODE_INHERIT
		snow_particles.visible = true
		snow_particles.amount = amount
		if snow_particles.process_material is ParticleProcessMaterial:
			(snow_particles.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, gravity_y, 0.0)
		snow_particles.emitting = true"""
		
	text = text.replace(old_apply_snow, new_apply_snow)
	
	var f = FileAccess.open(weather_gd, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	
	print("weather_fx.gd updated.")
	
	var falling_gd = "res://addons/weather_fx/scripts/falling_leaves.gd"
	var fl_text = FileAccess.get_file_as_string(falling_gd)
	var fl_old = """func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if emitting or visible:
			emitting = false
			visible = false
		return"""
	var fl_new = """func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if emitting:
			emitting = false
			restart()
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return"""
		
	var fl_old2 = """	if not emitting:
		visible = true
		emitting = true"""
	var fl_new2 = """	if not emitting:
		if Engine.is_editor_hint():
			process_mode = Node.PROCESS_MODE_INHERIT
		visible = true
		emitting = true"""
		
	fl_text = fl_text.replace(fl_old, fl_new)
	fl_text = fl_text.replace(fl_old2, fl_new2)
	
	var f2 = FileAccess.open(falling_gd, FileAccess.WRITE)
	f2.store_string(fl_text)
	f2.close()
	print("falling_leaves.gd updated.")
	
	var wind_gd = "res://addons/weather_fx/scripts/wind_vfx.gd"
	var wd_text = FileAccess.get_file_as_string(wind_gd)
	var wd_old = """func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		visible = false
		for p in _airflow_particles:
			if is_instance_valid(p):
				p.emitting = false
				p.visible = false
		return"""
	var wd_new = """func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		visible = false
		for p in _airflow_particles:
			if is_instance_valid(p):
				if p.emitting:
					p.emitting = false
					p.restart()
				p.visible = false
				p.process_mode = Node.PROCESS_MODE_DISABLED
		return"""
		
	var wd_old2 = """	for p in _airflow_particles:
		if is_instance_valid(p):
			if not p.emitting:
				p.emitting = true"""
	var wd_new2 = """	for p in _airflow_particles:
		if is_instance_valid(p):
			if not p.emitting:
				if Engine.is_editor_hint():
					p.process_mode = Node.PROCESS_MODE_INHERIT
				p.emitting = true"""
				
	wd_text = wd_text.replace(wd_old, wd_new)
	wd_text = wd_text.replace(wd_old2, wd_new2)
	
	var f3 = FileAccess.open(wind_gd, FileAccess.WRITE)
	f3.store_string(wd_text)
	f3.close()
	print("wind_vfx.gd updated.")
	quit()
