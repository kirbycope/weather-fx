class_name LightningBolt
extends Node3D
## One bolt of lightning between two points: a jagged ribbon that crackles for a moment, a flash of light at its
## foot, and thunder that arrives once the sound has covered the distance to the listener. [LightningFX] spawns
## one per strike and per arc; it frees itself when the thunder has played.

@export var color: Color = Color(1.0, 1.0, 1.0)
@export var width: float = 0.35 ## Metres across the white core at the foot; it thins toward the top.
@export var glow_width: float = 2.0 ## Metres across the soft blue glow around the core.
@export var segments: int = 14
@export var jitter: float = 1.6 ## Metres the path wanders sideways per segment, scaled by the bolt's length.
@export var life: float = 0.3 ## Seconds the bolt stays visible, crackling.
@export var flash_energy: float = 24.0
@export var thunder_sounds: Array[AudioStream] = []
@export var speed_of_sound: float = 343.0 ## Metres per second: how late the thunder is.

var _from: Vector3 = Vector3.ZERO ## Local start of the bolt, relative to the foot.
var _time: float = 0.0

@onready var ribbon: MeshInstance3D = $Ribbon
@onready var glow: MeshInstance3D = $Glow
@onready var flash: OmniLight3D = $Flash
@onready var thunder: AudioStreamPlayer3D = $Thunder
@onready var thunder_timer: Timer = $ThunderTimer
@onready var life_timer: Timer = $LifeTimer


## Draws the bolt from [param from] down to [param to] and starts the flash; with thunder it rumbles at
## [param listener] after the sound has travelled from the foot.
func strike(from: Vector3, to: Vector3, listener: Vector3, with_thunder: bool = true) -> void:
	global_position = to
	_from = from - to
	_time = 0.0
	flash.light_energy = flash_energy
	life_timer.start(life)
	if with_thunder and not thunder_sounds.is_empty():
		thunder.stream = thunder_sounds.pick_random()
		thunder_timer.start(maxf(listener.distance_to(to) / speed_of_sound, 0.05))
	elif not with_thunder or thunder_sounds.is_empty():
		thunder_timer.stop()
	_draw()


## Redraws with fresh jitter every frame so the bolt crackles, and fades the flash out over [member life].
func _process(delta: float) -> void:
	_time += delta
	if _time < life:
		flash.light_energy = flash_energy * (1.0 - _time / life) * randf_range(0.6, 1.0)
		_draw()


func _on_life_timer_timeout() -> void:
	ribbon.hide()
	glow.hide()
	flash.light_energy = 0.0
	if thunder_timer.is_stopped() and not thunder.playing:
		queue_free()


func _on_thunder_timer_timeout() -> void:
	thunder.play()


func _on_thunder_finished() -> void:
	queue_free()


## The ribbon: a strip of quads from the foot up to the start, each corner nudged sideways, facing the camera;
## a white core with a wide soft glow around the same path.
func _draw() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var toward_camera: Vector3 = (camera.global_position - global_position).normalized() if camera else Vector3.FORWARD
	var length: float = _from.length()
	var axis: Vector3 = _from / maxf(length, 0.001)
	var side: Vector3 = axis.cross(toward_camera).normalized()
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	var across: Vector3 = side.cross(axis).normalized()
	var points: PackedVector3Array = PackedVector3Array()
	for i: int in segments + 1:
		var t: float = float(i) / segments
		var point: Vector3 = axis * length * t
		if i > 0 and i < segments:
			var wander: float = jitter * clampf(length / 40.0, 0.2, 1.0)
			point += side * randf_range(-wander, wander) + across * randf_range(-wander, wander)
		points.append(point)
	_strip(ribbon.mesh as ImmediateMesh, points, side, width, color)
	_strip(glow.mesh as ImmediateMesh, points, side, glow_width, Color(0.5, 0.7, 1.0, 0.35))
	ribbon.show()
	glow.show()


func _strip(mesh: ImmediateMesh, points: PackedVector3Array, side: Vector3, full_width: float, tint: Color) -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in points.size():
		var half: float = full_width * 0.5 * lerpf(1.0, 0.3, float(i) / segments)
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(points[i] - side * half)
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(points[i] + side * half)
	mesh.surface_end()
