class_name BuildController
extends Node2D
## Building placement: a ghost of the finished building follows the mouse (snapped to the
## 16 px collision grid), tinted green or red by whether the footprint is free. Left click
## places a construction site and sends the selected builders; right click / Esc cancels.

signal placed(site: MapObject)

const VALID := Color(0.6, 1.0, 0.6, 0.7)
const INVALID := Color(1.0, 0.4, 0.4, 0.7)

var player: Player
var selection: SelectionController
var objects_root: Node2D
var placing_type: ObjectTypes.ObjectType
var _ghost: MapObject
## The travois whose packed tepee is being placed (free: it was paid for once).
var _unpacker: Unit


func is_placing() -> bool:
	return placing_type != null


func start(type_id: int, unpacker: Unit = null) -> void:
	cancel()
	_unpacker = unpacker
	placing_type = ObjectTypes.get_type(type_id)
	if placing_type == null:
		return
	_ghost = MapObject.new()
	_ghost.is_ghost = true
	if not _ghost.setup(placing_type, player.index):
		_ghost.free()
		placing_type = null
		return
	_ghost.set_process(false)
	add_child(_ghost)


func cancel() -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost = null
	placing_type = null
	_unpacker = null


func _process(_delta: float) -> void:
	if _ghost == null:
		return
	var grid := float(NavGrid.CELL)
	_ghost.position = (get_global_mouse_position() / grid).round() * grid
	_ghost.modulate = VALID if can_place(_ghost.position) else INVALID


func can_place(at: Vector2) -> bool:
	var nav := NavGrid.current
	var rect := MapObject.footprint_rect_for(placing_type, at)
	var origin := nav.cell_of(rect.position)
	for i in placing_type.footprint_cells.size():
		if (placing_type.footprint_cells[i] & NavGrid.BLOCKED) == 0:
			continue
		var cell := origin + Vector2i(i % placing_type.footprint_grid.x, i / placing_type.footprint_grid.x)
		if not nav.can_build_on(cell, placing_type.footprint_cells[i]):
			return false
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team != player.index and rect.has_point(unit.position):
			return false
	if GameData.guid_for_type(placing_type.id) == MapObject.FIELD_GUID and MapObject.field_allowance(player.index) <= 0:
		return false
	if GameData.guid_for_type(placing_type.id) in MapObject.SHIPYARDS and not MapObject.by_water(placing_type, at):
		return false
	return _unpacker != null or player.can_afford(_cost())


func _cost() -> Dictionary:
	var cost: Dictionary = GameData.stats(GameData.guid_for_type(placing_type.id)).get("cost", {}).duplicate()
	cost.erase("population")
	return cost


func _unhandled_input(event: InputEvent) -> void:
	if _ghost == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place(_ghost.position, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()


func _place(at: Vector2, keep_placing: bool) -> void:
	var unpacker := _unpacker
	if not can_place(at) or (unpacker == null and not player.spend(_cost())):
		Sound.play_sound(_cannot_build_sound())
		return
	if unpacker != null and not is_instance_valid(unpacker):
		cancel()
		return
	var site := MapObject.new()
	site.position = at
	if not site.setup(placing_type, player.index, 0, true):
		site.free()
		return
	objects_root.add_child(site)
	var is_field := site.is_field() or site.is_trap()  # neither blocks the way
	if not is_field:
		NavGrid.current.block_footprint(placing_type, at)
	# Units now standing inside the footprint step out to the nearest free cell.
	for unit in Unit.all_units:
		if not is_field and site.footprint_rect().has_point(unit.position):
			var cell := NavGrid.current.nearest_walkable(NavGrid.current.cell_of(unit.position))
			unit.position = (Vector2(cell) + Vector2(0.5, 0.5)) * NavGrid.CELL
	if unpacker:
		unpacker.unpack(site)
		placed.emit(site)
		cancel()
		return
	for unit in selection.selection:
		if is_instance_valid(unit) and unit.is_alive():
			if is_field:
				unit.gather(site)
			else:
				unit.build(site)
	placed.emit(site)
	var type_id := placing_type.id
	cancel()
	if keep_placing:
		start(type_id)


## "not_buildable" in the sound table.
func _cannot_build_sound() -> int:
	return 80
