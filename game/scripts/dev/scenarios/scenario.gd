class_name Scenario
extends Node
## Developer test scenarios, started with --scenario=<name>: each sets up a situation in
## the running match and prints what happened, for headless checks
## (tools/check_scenarios.py) and screenshots. A scenario is a method _scenario_<name> in
## one of the groups below; they reach the match through `main`.

const GROUPS := ["economy", "combat", "water", "interface"]  # scripts *_scenarios.gd beside this one

var main: Main


static func start(main_node: Main, scenario: String) -> void:
	seed(GameData.cmdline_option("seed", "1").to_int())  # repeatable runs (--seed=n for others)
	var method := "_scenario_" + scenario.replace("-", "_")
	for group in GROUPS:
		var runner: Scenario = load("res://scripts/dev/scenarios/%s_scenarios.gd" % group).new()
		if runner.has_method(method):
			runner.main = main_node
			main_node.add_child(runner)
			runner.call_deferred(method)
			return
		runner.free()
	push_warning("Unknown scenario %s" % scenario)


func _snapshot() -> String:
	var units := Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team > 0)
	var buildings := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_building())
	var stumps := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_tree() and o.stock.tree_state != ObjectStock.TreeState.STANDING)
	return "units %d, buildings %d (%s), felled/stumps %d, p1 %s, time %d" % [units.size(), buildings.size(),
			", ".join(buildings.map(func(b: MapObject) -> String: return "%s %d%%" % [b.display_name(), int(b.build_progress * 100)])),
			stumps.size(), main.players[1].resources, main.game_time]


func _nearest_mine(from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.stock.resource == "gold" and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


## Wait until the orders just given have been carried out (Orders: on a coming game step).
func _orders_landed() -> void:
	for i in Orders.delay + 2:
		await get_tree().physics_frame


## Click the mouse at a map point the way a player does: the camera centres on it and the
## press and release go through the input system (selection, orders, the build ghost). The
## interface is hidden meanwhile: headless, the window is too small to see past it.
func _click(world: Vector2, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	main.camera.position = world
	main.hud.root.visible = false
	for i in 3:
		await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = main.get_viewport().get_canvas_transform() * world
		event.global_position = event.position
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
	main.hud.root.visible = true
