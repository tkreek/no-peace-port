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
## A command waiting for its target click: "patrol", "follow" or "rally" ("" = none).
var pending := ""
var _rally_flag: OrderMarker


## Wait for the next left click to give the command (right click cancels).
func begin_targeting(command: String) -> void:
	pending = command
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func cancel_targeting() -> void:
	pending = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(_delta: float) -> void:
	# The selected building's assembly location shows as a waving flag.
	var rally := Vector2.INF
	if is_instance_valid(selected_building) and selected_building.owner_index == player_team:
		rally = selected_building.rally_point
	if rally == Vector2.INF:
		if is_instance_valid(_rally_flag):
			_rally_flag.queue_free()
		_rally_flag = null
	elif not is_instance_valid(_rally_flag):
		_rally_flag = OrderMarker.flag(units_root, rally, player_team)
	else:
		_rally_flag.position = rally


func _give_targeted(world: Vector2) -> void:
	var command := pending
	cancel_targeting()
	var units := selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	match command:
		"patrol":
			for unit: Unit in units:
				unit.patrol(world + (unit.position - _centre(units)))
			OrderMarker.spawn(units_root, world, player_team)
		"follow":
			var leader := _unit_at(world)
			if leader == null:
				leader = _unit_at(world, false)
			if leader:
				leader.flash(Color(0.5, 0.9, 1.0))
				for unit: Unit in units:
					unit.follow(leader)
		"quarters":
			var building := _building_at(world)
			if building and building.capacity() > 0:
				order_quarters(building)
		"rally":
			if is_instance_valid(selected_building):
				selected_building.rally_point = world
				OrderMarker.spawn(units_root, world, player_team)
	if not units.is_empty() and command != "rally":
		Sound.play_event(units[0].unit_type.guid(), Sound.Event.ORDER)


static func _centre(units: Array) -> Vector2:
	var centre := Vector2.ZERO
	for unit: Unit in units:
		centre += unit.position
	return centre / maxf(1.0, units.size())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var world := get_global_mouse_position()
		if not pending.is_empty() and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_give_targeted(world)
			else:
				cancel_targeting()
			get_viewport().set_input_as_handled()
			return
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
						if building == null:
							building = _object_at(world)  # enemy buildings, mines, trees, fields
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
			var animal := _animal_at(world)
			var site := _building_at(world)
			if site and not site.complete and selection.any(_is_builder):
				order_build(site)
			elif site and site.capacity() > 0 and selection.any(_can_quarter):
				order_quarters(site)
			elif animal and selection.any(func(u: Unit) -> bool: return u.unit_type.is_hunter()):
				for unit in selection:
					if is_instance_valid(unit) and unit.unit_type.is_hunter():
						unit.hunt(animal)
				Sound.play_event(selection[0].unit_type.guid(), Sound.Event.ORDER)
			elif enemy:
				order_attack(enemy)
			elif source and selection.any(func(u: Unit) -> bool: return u.unit_type.can_gather(source.resource)):
				order_gather(source)
			else:
				_order_move(world)
				if not selection.is_empty():
					OrderMarker.spawn(units_root, world, player_team)
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
				and not child.fogged and not child.inside:
			out.append(child)
	return out


func _animal_at(point: Vector2) -> Unit:
	for unit in Unit.all_units:
		if unit.has_meat() and point.distance_to(unit.position + Vector2(0, -12)) < CLICK_RADIUS:
			return unit
	return null


## The resource under the cursor. Forests overlap, so take the front-most object whose
## picture is under the point (canopies count, not just the ground footprint).
func _resource_at(point: Vector2) -> MapObject:
	var best: MapObject = null
	var best_score := INF
	for object in MapObject.all_objects:
		if object.resource == "" or (object.is_field() and object.owner_index != player_team):
			continue
		var footprint := object.footprint_rect()
		var hit := object.work_rect().grow(6).has_point(point)
		if object.is_tree():
			var canopy := object.visual_rect()
			hit = hit or canopy.grow_individual(-canopy.size.x * 0.2, -4, -canopy.size.x * 0.2, 0).has_point(point)
		elif object.is_field():
			hit = footprint.has_point(point)
		else:
			hit = hit or footprint.grow(6).has_point(point)
		if not hit:
			continue
		# Front-most first (drawn on top), then closest to the trunk / centre.
		var score := -object.position.y * 4.0 + point.distance_to(object.work_rect().get_center())
		if score < best_score:
			best_score = score
			best = object
	return best


func _is_builder(u: Unit, guid := -1) -> bool:
	return is_instance_valid(u) and u.is_alive() and u.unit_type.can_build(guid)


## Workers and women keep working; soldiers, hunters and commanders can take quarters.
func _can_quarter(u: Unit) -> bool:
	return is_instance_valid(u) and u.is_alive() and not u.unit_type.can_gather("wood") \
			and not u.unit_type.is_farmer()


## Selected units walk into a fort or tower, as many as there is room for.
func order_quarters(building: MapObject) -> void:
	var units := selection.filter(_can_quarter)
	var room := building.capacity() - building.garrison.size()
	if units.is_empty() or room <= 0:
		Sound.play_sound(80)
		return
	building.flash()
	Sound.play_event(units[0].unit_type.guid(), Sound.Event.ORDER)
	for unit: Unit in units:
		if room <= 0:
			break
		unit.take_quarters(building)
		room -= 1


## Send the selected builders to help finish a construction site.
func order_build(site: MapObject) -> void:
	var builders := selection.filter(func(u: Unit) -> bool: return _is_builder(u, site.guid))
	if builders.is_empty():
		return
	site.flash()
	Sound.play_event(builders[0].unit_type.guid(), Sound.Event.ORDER)
	for unit: Unit in builders:
		unit.build(site)
	# Anyone else selected just walks over.
	for unit in selection:
		if is_instance_valid(unit) and unit.is_alive() and not _is_builder(unit, site.guid):
			unit.move_to(site.position)


func order_gather(source: MapObject) -> void:
	var gatherers := selection.filter(func(u: Unit) -> bool:
		return is_instance_valid(u) and u.is_alive() and u.unit_type.can_gather(source.resource))
	if gatherers.is_empty():
		return
	source.flash()
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
	enemy.flash(Color(1.0, 0.35, 0.3))
	Sound.play_event(selection[0].unit_type.guid(), Sound.Event.ORDER)
	for unit in selection:
		unit.attack(enemy, true)


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
		if object.is_building() and object.owner_index == player_team and _click_rect(object).has_point(point):
			return object
	return null


## Buildings stand taller than their ground footprint; accept clicks on the walls and roof too.
static func _click_rect(object: MapObject) -> Rect2:
	var rect := object.footprint_rect()
	return rect.grow_individual(8, rect.size.y * 0.6, 8, 8)


func select_building(building: MapObject) -> void:
	_select([], false)
	selected_building = building
	building.selected = true
	if building.is_tree():
		Sound.play_named("holz hacken")  # trees have no selection sound of their own
	elif building.is_mine():
		Sound.play_event(MapObject.GOLD_MINE_GUID, Sound.Event.SELECT)
	else:
		Sound.play_event(building.guid, Sound.Event.SELECT)


## Something to look at that isn't ours: an enemy building in sight or a resource.
func _object_at(point: Vector2) -> MapObject:
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index != player_team and object.visible \
				and object.is_alive() and _click_rect(object).has_point(point):
			return object
	return _resource_at(point)


## Select exactly these units (e.g. from the HUD's group portraits).
func select_units(units: Array) -> void:
	_select(units, false)


func deselect(unit: Unit) -> void:
	if unit in selection:
		selection.erase(unit)
		unit.selected = false


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
	var centre := _centre(selection)
	Sound.play_event(selection[0].unit_type.guid(), Sound.Event.ORDER)
	var facing := (target - centre).normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	var side := facing.orthogonal()
	# Keep each unit's relative slot stable: sort by projection onto the formation axes.
	var ordered := selection.duplicate()
	ordered.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.dot(-facing) < b.position.dot(-facing))
	var slots := formation_slots(count, selection[0].formation)
	for i in count:
		var offset := (side * slots[i].x - facing * slots[i].y) * FORMATION_SPACING
		ordered[i].move_to(target + offset)


## Re-form the selection on the spot in its new formation, facing down the screen.
func reform() -> void:
	var units := selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	if units.size() > 1:
		_order_move(_centre(units))


## Slot positions (x across, y back from the front, in spacing units) for `count` units.
static func formation_slots(count: int, formation: Unit.Formation) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var columns := ceili(sqrt(count))
	if formation == Unit.Formation.DOUBLE_LINE:
		columns = ceili(count / 2.0)
	for i in count:
		match formation:
			Unit.Formation.COLUMN:
				slots.append(Vector2(0, i))
			Unit.Formation.DOUBLE_COLUMN:
				slots.append(Vector2((i % 2) - 0.5, i / 2))
			Unit.Formation.WEDGE:
				var rank := (i + 1) / 2
				slots.append(Vector2(rank * (-1 if i % 2 else 1) if i > 0 else 0, rank))
			Unit.Formation.RELAXED:
				# Loose and uneven: a wider grid with some scatter.
				var jitter := Vector2(sin(i * 12.9898), cos(i * 78.233)) * 0.3
				slots.append((Vector2(i % columns - (columns - 1) / 2.0, i / columns)) * 1.35 + jitter)
			_:
				slots.append(Vector2(i % columns - (columns - 1) / 2.0, i / columns))
	return slots
