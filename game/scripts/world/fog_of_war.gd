class_name FogOfWar
extends Node2D
## Fog of war for the local player on the map's 32 px cell grid.
##
## Each cell is unexplored (black), explored (dimmed: terrain and last-seen buildings show,
## units don't) or visible (in sight of one of the player's units or buildings). The cell
## grid is uploaded as a small texture and stretched over the map with linear filtering,
## which gives soft edges; a little noise breaks up the grid.

const CELL := AlfMap.CELL_SIZE
const UPDATE_SECONDS := 0.2
const BUILDING_SIGHT := 256.0
const UNEXPLORED := 255
const EXPLORED := 140
const VISIBLE := 0
const FogShader := preload("res://shaders/fog.gdshader")

static var current: FogOfWar

var player_team := 1
var enabled := true
var columns := 0
var rows := 0
var explored := PackedByteArray()
var visible_cells := PackedByteArray()

## The two cell grids as textures (0/1 bytes; the shaders scale them up).
var _visible_image: Image
var _visible_texture: ImageTexture
var _explored_image: Image
var _explored_texture: ImageTexture
var _sprite := Sprite2D.new()
var _timer := 0.0
var _circles := {}  # radius in cells -> PackedVector2Array of offsets


func setup(map: AlfMap, team: int) -> void:
	current = self
	player_team = team
	columns = map.columns
	rows = map.rows
	explored.resize(columns * rows)
	visible_cells.resize(columns * rows)
	_visible_image = Image.create_from_data(columns, rows, false, Image.FORMAT_L8, visible_cells)
	_visible_texture = ImageTexture.create_from_image(_visible_image)
	_explored_image = Image.create_from_data(columns, rows, false, Image.FORMAT_L8, explored)
	_explored_texture = ImageTexture.create_from_image(_explored_image)
	_sprite.texture = _visible_texture
	_sprite.centered = false
	_sprite.scale = Vector2(CELL, CELL)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = FogShader
	material.set_shader_parameter("map_cells", Vector2(columns, rows))
	material.set_shader_parameter("explored_cells", _explored_texture)
	_sprite.material = material
	z_index = 90  # above units and buildings, below health bars and the HUD
	z_as_relative = false
	add_child(_sprite)
	update_now()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_SECONDS
		update_now()


func update_now() -> void:
	visible_cells.fill(0)
	if not enabled:
		visible_cells.fill(1)
		explored.fill(1)
	else:
		# Units standing in the same cell with the same sight reveal the same circle: once.
		var stamped := {}
		for unit in Unit.all_units:
			if unit.team == player_team and unit.is_alive():
				var sight := unit.sight()
				var key := _index(unit.position) * 64 + int(sight / CELL)
				if not stamped.has(key):
					stamped[key] = true
					_reveal(unit.position, sight)
		for object in MapObject.structures:
			if object.is_building() and object.owner_index == player_team and object.is_alive():
				var owner: Player = Player.by_index.get(player_team)
				var sharper := owner.bonus(object.guid, "sight_pct") if owner else 0.0  # tower Sight upgrades
				_reveal(object.footprint_rect().get_center(), BUILDING_SIGHT * (1.0 + sharper / 100.0))
		var now := Time.get_ticks_msec()
		_reveals = _reveals.filter(func(r: Dictionary) -> bool: return r.until > now)
		for r in _reveals:
			_reveal(r.at, r.radius)
	_visible_image.set_data(columns, rows, false, Image.FORMAT_L8, visible_cells)
	_visible_texture.update(_visible_image)
	_explored_image.set_data(columns, rows, false, Image.FORMAT_L8, explored)
	_explored_texture.update(_explored_image)
	_apply_to_objects()


## Eagle eye: a spot kept in sight for a while.
var _reveals: Array[Dictionary] = []


func reveal_for(point: Vector2, radius_px: float, seconds: float) -> void:
	_reveals.append({"at": point, "radius": radius_px, "until": Time.get_ticks_msec() + seconds * 1000.0})
	update_now()


func is_visible_at(point: Vector2) -> bool:
	var i := _index(point)
	return i >= 0 and visible_cells[i] != 0


func is_explored_at(point: Vector2) -> bool:
	var i := _index(point)
	return i >= 0 and explored[i] != 0


## The cell grids for the minimap's fog (see minimap_fog.gdshader).
func visible_texture() -> Texture2D:
	return _visible_texture


func explored_texture() -> Texture2D:
	return _explored_texture


func _index(point: Vector2) -> int:
	var x := floori(point.x / CELL)
	var y := floori(point.y / CELL)
	if x < 0 or y < 0 or x >= columns or y >= rows:
		return -1
	return y * columns + x


func _reveal(centre: Vector2, radius_px: float) -> void:
	var radius := int(ceil(radius_px / CELL))
	var cx := floori(centre.x / CELL)
	var cy := floori(centre.y / CELL)
	for offset in _circle(radius):
		var x := cx + int(offset.x)
		var y := cy + int(offset.y)
		if x >= 0 and y >= 0 and x < columns and y < rows:
			var i := y * columns + x
			visible_cells[i] = 1
			explored[i] = 1


func _circle(radius: int) -> PackedVector2Array:
	if not _circles.has(radius):
		var offsets := PackedVector2Array()
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if x * x + y * y <= radius * radius:
					offsets.append(Vector2(x, y))
		_circles[radius] = offsets
	return _circles[radius]


## A detector of ours (arrow shooter, militiaman, hunter, trapper) with `point` in sight.
func _detects(point: Vector2) -> bool:
	for unit in Unit.all_units:
		if unit.team == player_team and unit.is_alive() and unit.unit_type.guid() in UnitStealth.DETECTORS \
				and unit.position.distance_to(point) <= unit.sight():
			return true
	return false


## Enemy units only show while in sight; enemy buildings once explored. Own things always.
func _apply_to_objects() -> void:
	for unit in Unit.all_units:
		unit.fogged = unit.team != player_team and ((enabled and not is_visible_at(unit.position)) \
				or (unit.stealth.concealed and not unit.stealth.detected_by(player_team)))
	for object in MapObject.structures:
		if object.is_building() and object.owner_index != player_team:
			object.visible = not enabled or is_explored_at(object.footprint_rect().get_center())
			if object.is_trap():
				object.visible = object.visible and is_visible_at(object.position) and _detects(object.position)
