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
					_select([unit] if unit else [], event.shift_pressed)
				_dragging = false
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not selection.is_empty():
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
	var out: Array[Unit] = []
	for child in units_root.get_children():
		if child is Unit and child.team == player_team:
			out.append(child)
	return out


func _units_in(rect: Rect2) -> Array[Unit]:
	return _own_units().filter(func(u: Unit) -> bool: return rect.has_point(u.position))


func _unit_at(point: Vector2) -> Unit:
	var best: Unit = null
	var best_distance := CLICK_RADIUS
	for unit in _own_units():
		# Units are tall; test against the body centre rather than the feet.
		var distance := point.distance_to(unit.position + Vector2(0, -20))
		if distance < best_distance:
			best = unit
			best_distance = distance
	return best


func _select(units: Array, add: bool) -> void:
	if not add:
		for unit in selection:
			if is_instance_valid(unit):
				unit.selected = false
		selection.clear()
	for unit: Unit in units:
		if unit not in selection:
			selection.append(unit)
			unit.selected = true


func _order_move(target: Vector2) -> void:
	var count := selection.size()
	var columns := ceili(sqrt(count))
	var centre := Vector2.ZERO
	for unit in selection:
		centre += unit.position
	centre /= count
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
