class_name SelectionController
extends Node2D
## Click / box selection, control groups (Ctrl+0-9 to set, 0-9 to recall) and
## right-click move orders in a loose formation.

const CLICK_RADIUS := 22.0
const DRAG_THRESHOLD := 6.0
const FORMATION_SPACING := 26.0

@export var player_team := 1

var units_root: Node2D
var selection: Array[Unit] = []
var selected_building: MapObject
var groups := {}
var _drag_start := Vector2.ZERO
var _dragging := false
var _pressed := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var world := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_drag_start = world
			elif _pressed:
				_pressed = false
				if _dragging:
					_select(_units_in(Rect2(_drag_start, world - _drag_start).abs()), event.shift_pressed)
				else:
					var unit := _unit_at(world)
					if unit == null and not event.shift_pressed:
						var building := _building_at(world)
						if building:
							select_building(building)
							return
					_select([unit] if unit else [], event.shift_pressed)
				_dragging = false
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not selection.is_empty():
			var enemy: Node2D = _unit_at(world, false)
			if enemy == null:
				enemy = _enemy_building_at(world)
			var source := _resource_at(world)
			if enemy:
				order_attack(enemy)
			elif source and selection.any(func(u: Unit) -> bool: return u.unit_type.can_gather(source.resource)):
				order_gather(source)
			else:
				_order_move(world)
	elif event is InputEventMouseMotion and _pressed:
		_dragging = _dragging or get_global_mouse_position().distance_to(_drag_start) > DRAG_THRESHOLD / get_viewport().get_canvas_transform().get_scale().x
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		var digit: int = event.keycode - KEY_0
		if digit >= 0 and digit <= 9:
			if event.ctrl_pressed:
				groups[digit] = selection.duplicate()
			elif groups.has(digit):
				_select(groups[digit].filter(is_instance_valid), false)
		elif event.keycode == KEY_H:
			for unit in selection:
				unit.stop()


func _draw() -> void:
	if _dragging:
		var rect := Rect2(_drag_start, get_global_mouse_position() - _drag_start).abs()
		draw_rect(rect, Color(1, 1, 1, 0.12))
		draw_rect(rect, Color(1, 1, 1, 0.9), false, 1.0 / get_viewport().get_canvas_transform().get_scale().x)


func _own_units() -> Array[Unit]:
	return _units(true)


func _units(own: bool) -> Array[Unit]:
	var out: Array[Unit] = []
	for child in units_root.get_children():
		if child is Unit and child.is_alive() and (child.team == player_team) == own and child.team > 0 \
				and not child.fogged:
			out.append(child)
	return out


func _resource_at(point: Vector2) -> MapObject:
	for object in MapObject.all_objects:
		if object.resource != "" and object.footprint_rect().grow(6).has_point(point):
			return object
	return null


func order_gather(source: MapObject) -> void:
	var gatherers := selection.filter(func(u: Unit) -> bool:
		return is_instance_valid(u) and u.is_alive() and u.unit_type.can_gather(source.resource))
	if gatherers.is_empty():
		return
	Sound.play_event(gatherers[0].unit_type.guid(), Sound.Event.ORDER)
	for unit: Unit in gatherers:
		unit.gather(source)


func _enemy_building_at(point: Vector2) -> MapObject:
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player_team \
				and object.is_alive() and object.visible and object.footprint_rect().has_point(point):
			return object
	return null


func order_attack(enemy: Node2D) -> void:
	selection = selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	if selection.is_empty():
		return
	Sound.play_event(selection[0].unit_type.guid(), Sound.Event.ORDER)
	for unit in selection:
		unit.attack(enemy)


func _units_in(rect: Rect2) -> Array[Unit]:
	return _own_units().filter(func(u: Unit) -> bool: return rect.has_point(u.position))


func _unit_at(point: Vector2, own := true) -> Unit:
	var best: Unit = null
	var best_distance := CLICK_RADIUS
	for unit in _units(own):
		# Units are tall; test against the body centre rather than the feet.
		var distance := point.distance_to(unit.position + Vector2(0, -20))
		if distance < best_distance:
			best = unit
			best_distance = distance
	return best


func _building_at(point: Vector2) -> MapObject:
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == player_team and object.footprint_rect().has_point(point):
			return object
	return null


func select_building(building: MapObject) -> void:
	_select([], false)
	selected_building = building
	building.selected = true
	Sound.play_event(building.guid, Sound.Event.SELECT)


func _select(units: Array, add: bool) -> void:
	if is_instance_valid(selected_building):
		selected_building.selected = false
	selected_building = null
	if not add:
		for unit in selection:
			if is_instance_valid(unit):
				unit.selected = false
		selection.clear()
	for unit: Unit in units:
		if unit not in selection:
			selection.append(unit)
			unit.selected = true
	if not units.is_empty():
		Sound.play_event(units[0].unit_type.guid(), Sound.Event.SELECT)


func _order_move(target: Vector2) -> void:
	selection = selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	var count := selection.size()
	if count == 0:
		return
	var columns := ceili(sqrt(count))
	var centre := Vector2.ZERO
	for unit in selection:
		centre += unit.position
	centre /= count
	Sound.play_event(selection[0].unit_type.guid(), Sound.Event.ORDER)
	var facing := (target - centre).normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	var side := facing.orthogonal()
	# Keep each unit's relative slot stable: sort by projection onto the formation axes.
	var ordered := selection.duplicate()
	ordered.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.dot(-facing) < b.position.dot(-facing))
	for i in count:
		var row := i / columns
		var column := i % columns
		var offset := side * (column - (columns - 1) / 2.0) * FORMATION_SPACING - facing * row * FORMATION_SPACING
		ordered[i].move_to(target + offset)
