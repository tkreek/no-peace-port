class_name BuildController
extends Node2D
## Building placement: a ghost of the finished building follows the mouse (snapped to the
## 16 px collision grid), tinted green or red by whether the footprint is free. Left click
## places a construction site and sends the selected builders; right click / Esc cancels.
## With Shift held the placing goes on, and the builders take the sites in turn.

signal placed(site: MapObject)

const VALID := Color(0.6, 1.0, 0.6, 0.7)
const INVALID := Color(1.0, 0.4, 0.4, 0.7)
const CANNOT_BUILD_SOUND := 80  # "not_buildable" in the sound table

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
	return can_place_for(placing_type, at, player.index, _unpacker != null)


## Whether people `owner` may put a site of `type` at `at` now (`free`: an unpacked tepee).
static func can_place_for(type: ObjectTypes.ObjectType, at: Vector2, owner: int, free := false) -> bool:
	var nav := NavGrid.current
	var rect := MapObject.footprint_rect_for(type, at)
	var origin := nav.cell_of(rect.position)
	for i in type.footprint_cells.size():
		if (type.footprint_cells[i] & NavGrid.BLOCKED) == 0:
			continue
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if not nav.can_build_on(cell, type.footprint_cells[i]):
			return false
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team != owner and rect.has_point(unit.position):
			return false
	var guid := GameData.guid_for_type(type.id)
	if guid == MapObject.FIELD_GUID and MapObject.field_allowance(owner) <= 0:
		return false
	if guid in MapObject.SHIPYARDS and not MapObject.by_water(type, at):
		return false
	var people: Player = Player.by_index.get(owner)
	return free or (people != null and people.can_afford(_cost_of(type)))


func _cost() -> Dictionary:
	return _cost_of(placing_type)


static func _cost_of(type: ObjectTypes.ObjectType) -> Dictionary:
	var cost: Dictionary = GameData.stats(GameData.guid_for_type(type.id)).get("cost", {}).duplicate()
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


## A left click with the ghost: the order to put the site there (Orders) is given once the
## spot and the stockpile allow it.
func _place(at: Vector2, keep_placing: bool) -> void:
	var unpacker := _unpacker
	if unpacker == null and player.alert_shortage(_cost()):
		return
	if not can_place(at):
		Sound.play_sound(CANNOT_BUILD_SOUND)
		return
	if unpacker != null and not is_instance_valid(unpacker):
		cancel()
		return
	var builders := selection.selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	Orders.place(placing_type.id, at, keep_placing, unpacker, builders)
	var type_id := placing_type.id
	cancel()
	if keep_placing and unpacker == null:
		start(type_id)


## Carry out a placing order (on a game step): pay, put the site down, move aside whoever
## stands on it, and send the builders; or the travois `unpacker` sets up its tepee there.
func place_site(owner: int, type_id: int, at: Vector2, keep_placing: bool, unpacker: Unit, builders: Array) -> MapObject:
	var type := ObjectTypes.get_type(type_id)
	var people: Player = Player.by_index.get(owner)
	if type == null or people == null or not can_place_for(type, at, owner, unpacker != null):
		return null
	if unpacker == null and not people.spend(_cost_of(type)):
		return null
	var site := MapObject.new()
	site.position = at
	if not site.setup(type, owner, 0, true):
		site.free()
		return null
	objects_root.add_child(site)
	var is_field := site.is_field() or site.is_trap()  # neither blocks the way
	if not is_field:
		NavGrid.current.block_footprint(type, at)
	# Units now standing inside the footprint step out to the nearest free cell.
	for unit in Unit.all_units:
		if not is_field and site.footprint_rect().has_point(unit.position) and not unit.inside:
			var cell := NavGrid.current.nearest_walkable(NavGrid.current.cell_of(unit.position), 24, unit.water.nav_layer())
			unit.position = (Vector2(cell) + Vector2(0.5, 0.5)) * NavGrid.CELL
			unit.reset_physics_interpolation()
	if unpacker:
		unpacker.unpack(site)
		placed.emit(site)
		return site
	for unit: Unit in builders:
		if is_field:
			unit.gather(site)
		elif keep_placing:
			unit.work.queue_build(site)
		else:
			unit.build(site)
	placed.emit(site)
	return site
