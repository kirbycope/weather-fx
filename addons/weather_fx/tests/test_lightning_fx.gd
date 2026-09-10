extends GutTest

## Purpose: Lightning in the thunderstorm: strikes only roll while a storm is on, a strike spawns a bolt, hurts
## what stands under it and reports itself, and an arc draws without thunder.

const WEATHER_SCENE = preload("res://addons/weather_fx/scenes/weather_fx.tscn")
const GRASS_SCENE = preload("res://addons/weather_fx/scenes/grass_field.tscn")

var weather: WeatherFX
var lightning: LightningFX
var root: Node3D


class Target extends StaticBody3D:
	var hits: Array = []
	func take_hit(damage: float, from: Vector3) -> void:
		hits.append([damage, from])


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	weather = WEATHER_SCENE.instantiate() as WeatherFX
	root.add_child(weather)
	lightning = weather.get_node("LightningFX") as LightningFX
	await wait_physics_frames(1)


func test_strikes_only_roll_in_a_storm() -> void:
	weather.set_weather(ClimateData.WeatherType.BLUE_SKY)
	assert_true(lightning.strike_timer.is_stopped(), "Clear skies have no lightning")
	weather.set_weather(ClimateData.WeatherType.STORM)
	assert_true(lightning.is_storming())
	assert_false(lightning.strike_timer.is_stopped(), "A storm starts the strike timer")
	weather.set_weather(ClimateData.WeatherType.RAIN)
	assert_true(lightning.strike_timer.is_stopped(), "Plain rain stops it again")


func test_a_strike_spawns_a_bolt_and_hurts_what_is_under_it() -> void:
	var target := Target.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	target.add_child(shape)
	root.add_child(target)
	target.global_position = Vector3(5, 0, 5)
	await wait_physics_frames(2)
	watch_signals(lightning)
	lightning.strike_at(Vector3(5, 0, 5))
	assert_signal_emitted_with_parameters(lightning, "struck", [Vector3(5, 0, 5)])
	assert_gt(lightning.get_child_count(), 1, "A bolt scene hangs under the node while it crackles")
	assert_eq(target.hits.size(), 1, "The body under the bolt takes the storm's damage")
	assert_eq(target.hits[0][0], lightning.damage)
	lightning.strike_at(Vector3(5, 0, 5), 0.0)
	assert_eq(target.hits.size(), 1, "A strike asked for with no damage only lights the sky")


func test_a_strike_lights_the_grass_even_in_the_rain() -> void:
	var field: GrassField = GRASS_SCENE.instantiate() as GrassField
	root.add_child(field)
	await wait_physics_frames(1)
	field._on_weather_changed(ClimateData.WeatherType.STORM, ClimateData.WeatherType.BLUE_SKY)
	assert_false(field.ignite_at(Vector3.ZERO, 2.0, 6.0), "A torch or a spell cannot light grass in the rain")
	assert_true(field._burning_cells.is_empty())
	lightning.strike_at(Vector3.ZERO, 0.0)
	assert_false(field._burning_cells.is_empty(), "A bolt is hot enough: the grass under it catches in the rain")


func test_an_arc_draws_a_bolt_between_two_points() -> void:
	var before: int = lightning.get_child_count()
	lightning.arc(Vector3(0, 1, 0), Vector3(4, 1, 0))
	assert_eq(lightning.get_child_count(), before + 1)
	var bolt: LightningBolt = lightning.get_child(lightning.get_child_count() - 1) as LightningBolt
	assert_not_null(bolt)
	assert_true(bolt.thunder_timer.is_stopped(), "An arc is silent")
	assert_false(bolt.life_timer.is_stopped(), "But it crackles for its life")
