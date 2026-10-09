class_name Weather
extends Node2D
## A spell's lasting effect drawn with the original weather graphics: the cloud forms
## (anim 0), rains, hails or storms for a while (anim 2), and dissolves (anim 4). `tick`
## is called every second while it lasts (lightning damage, for example).

const LIGHTNING_BOB := "global/gfx/blitzwolke/wolke_blitz.bob"
const HAIL_BOB := "global/gfx/hagelwolke/hagel.bob"
const RAIN_BOB := "global/gfx/regenwolke/regen.bob"
const SHIELD_BOB := "global/gfx/schutzschirm/schutzschirm.bob"

var _bob_path := ""
var _duration := 0.0
var _tick: Callable
var _age := 0.0
var _next_tick := 1.0
var _effect: OrderMarker


static func spawn(parent: Node, at: Vector2, bob_path: String, duration: float, tick := Callable()) -> Weather:
	var weather := Weather.new()
	weather.position = at
	weather._bob_path = bob_path
	weather._duration = duration
	weather._tick = tick
	weather.z_index = 6
	parent.add_child(weather)
	OrderMarker.effect(weather, Vector2.ZERO, bob_path, 0)  # the cloud gathers
	weather._effect = OrderMarker.effect_loop(weather, Vector2.ZERO, bob_path, 2)
	return weather


func _process(delta: float) -> void:
	_age += delta
	if _tick.is_valid() and _age >= _next_tick:
		_next_tick += 1.0
		_tick.call(global_position)
	if _age >= _duration:
		if is_instance_valid(_effect):
			_effect.queue_free()
		if _bob_path != SHIELD_BOB:
			OrderMarker.effect(get_parent(), global_position - get_parent().global_position, _bob_path, 4)
		queue_free()
