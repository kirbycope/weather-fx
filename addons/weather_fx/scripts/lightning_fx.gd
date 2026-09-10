class_name LightningFX
extends Node3D
## Lightning for the thunderstorm: while [member weather_fx] reports a storm, bolts come down at random around
## its target every few seconds, each with a flash and thunder that arrives late by distance. A strike hurts
## anything with a `take_hit` method under it and lights the grass. [method strike_at] and [method arc] are
## also the game's lightning: a spell can call a bolt onto a target or draw an arc between two points, so the
## storm and the spells share one look. Random strikes roll on the multiplayer authority and replicate.

signal struck(position: Vector3) ## A bolt came down here (random or asked for).

@export var weather_fx: WeatherFX ## Found through the WeatherFX group when empty.
@export var bolt_scene: PackedScene = preload("res://addons/weather_fx/scenes/lightning_bolt.tscn")
@export var strike_interval: Vector2 = Vector2(5.0, 14.0) ## Seconds between random strikes in a storm.
@export var strike_distance: Vector2 = Vector2(12.0, 60.0) ## Metres from the target a random strike lands.
@export var strike_height: float = 60.0 ## Where a sky bolt starts above the ground.
@export var damage: float = 40.0 ## Dealt by a random strike to anything with take_hit within [member damage_radius].
@export var damage_radius: float = 2.5
@export var ignite_radius: float = 2.0 ## Grass around a strike catches fire; 0 leaves it alone.

@onready var strike_timer: Timer = $StrikeTimer


func _ready() -> void:
	add_to_group(&"LightningFX")
	if weather_fx == null:
		weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
	if not is_instance_valid(weather_fx):
		return
	weather_fx.weather_changed.connect(_on_weather_changed)
	weather_fx.playback_changed.connect(_on_playback_changed)
	_refresh()


func _on_weather_changed(_new_weather: ClimateData.WeatherType, _old_weather: ClimateData.WeatherType) -> void:
	_refresh()


func _on_playback_changed(_active: bool) -> void:
	_refresh()


## Whether the storm is on: random strikes run only then, and only on the authority.
func is_storming() -> bool:
	return is_instance_valid(weather_fx) and weather_fx.active_weather == ClimateData.WeatherType.STORM and weather_fx.is_simulating()


func _refresh() -> void:
	if is_storming() and is_multiplayer_authority():
		if strike_timer.is_stopped():
			strike_timer.start(randf_range(strike_interval.x, strike_interval.y))
	else:
		strike_timer.stop()


## A bolt somewhere around the target, on the ground.
func _on_strike_timer_timeout() -> void:
	if not is_storming():
		return
	var centre: Vector3 = weather_fx.target_node.global_position if is_instance_valid(weather_fx.target_node) else global_position
	var angle: float = randf() * TAU
	var distance: float = randf_range(strike_distance.x, strike_distance.y)
	var foot: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * distance
	foot.y = _find_ground_y(foot)
	strike_at.rpc(foot, damage)
	strike_timer.start(randf_range(strike_interval.x, strike_interval.y))


## A sky bolt onto [param position] on every peer; the authority deals [param hit_damage] around it (the storm's
## own [member damage] when negative, none when 0) and lights the grass, wet or not: a storm always rains, and a bolt
## is hot enough for wet grass.
@rpc("authority", "call_local", "reliable")
func strike_at(position: Vector3, hit_damage: float = -1.0) -> void:
	var bolt: LightningBolt = bolt_scene.instantiate() as LightningBolt
	add_child(bolt)
	bolt.strike(position + Vector3.UP * strike_height, position, _listener_position(position))
	var dealt: float = damage if hit_damage < 0.0 else hit_damage
	if dealt > 0.0 and is_multiplayer_authority():
		for body: Node in bodies_near(position, damage_radius):
			body.call(&"take_hit", dealt, position)
	if ignite_radius > 0.0:
		get_tree().call_group(&"GrassField", &"ignite_at", position, ignite_radius, 6.0, true)
		for grass: Node in get_tree().get_nodes_in_group(&"BurnableGrass"):
			if grass is Node3D and (grass as Node3D).global_position.distance_to(position) <= ignite_radius + 1.0 and grass.has_method(&"ignite"):
				grass.call(&"ignite", true)
	struck.emit(position)


## An arc between two points on every peer, without thunder: the jump of a chain of lightning.
@rpc("authority", "call_local", "reliable")
func arc(from: Vector3, to: Vector3) -> void:
	var bolt: LightningBolt = bolt_scene.instantiate() as LightningBolt
	add_child(bolt)
	bolt.strike(from, to, _listener_position(to), false)


## Physics bodies within [param radius] of [param position] that can take a hit, nearest first, the handler
## being the body or the first ancestor with take_hit.
func bodies_near(position: Vector3, radius: float) -> Array[Node]:
	var found: Array[Node] = []
	var world3d: World3D = get_world_3d()
	if world3d == null or world3d.direct_space_state == null:
		return found
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), position)
	query.collide_with_areas = false
	for hit: Dictionary in world3d.direct_space_state.intersect_shape(query, 32):
		var node: Node = hit.get("collider") as Node
		while node and not node.has_method(&"take_hit"):
			node = node.get_parent()
		if node and not found.has(node):
			found.append(node)
	found.sort_custom(func(a: Node, b: Node) -> bool:
		return (a as Node3D).global_position.distance_squared_to(position) < (b as Node3D).global_position.distance_squared_to(position))
	return found


func _listener_position(fallback: Vector3) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera:
		return camera.global_position
	if is_instance_valid(weather_fx) and is_instance_valid(weather_fx.target_node):
		return weather_fx.target_node.global_position
	return fallback


## The ground under a point, or the point's own height with nothing below.
func _find_ground_y(origin: Vector3) -> float:
	var world3d: World3D = get_world_3d()
	if world3d == null or world3d.direct_space_state == null:
		return origin.y
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin + Vector3(0.0, 80.0, 0.0), origin - Vector3(0.0, 120.0, 0.0))
	var result: Dictionary = world3d.direct_space_state.intersect_ray(query)
	return (result["position"] as Vector3).y if result.has("position") else origin.y
