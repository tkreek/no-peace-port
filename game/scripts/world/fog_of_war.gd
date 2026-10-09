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

var _image: Image
var _texture: ImageTexture
var _overview_image: Image
var _overview: ImageTexture  # RGBA: black with fog as alpha, for the minimap
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
	_image = Image.create_empty(columns, rows, false, Image.FORMAT_L8)
	_image.fill(Color(1, 1, 1))
	_texture = ImageTexture.create_from_image(_image)
	_overview_image = Image.create_empty(columns, rows, false, Image.FORMAT_RGBA8)
	_overview = ImageTexture.create_from_image(_overview_image)
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.scale = Vector2(CELL, CELL)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = FogShader
	material.set_shader_parameter("map_cells", Vector2(columns, rows))
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
		for unit in Unit.all_units:
			if unit.team == player_team and unit.is_alive():
				_reveal(unit.position, unit.sight())
		for object in MapObject.all_objects:
			if object.is_building() and object.owner_index == player_team and object.is_alive():
				_reveal(object.footprint_rect().get_center(), BUILDING_SIGHT)
	var bytes := PackedByteArray()
	bytes.resize(columns * rows)
	var rgba := PackedByteArray()
	rgba.resize(columns * rows * 4)
	for i in bytes.size():
		var value := VISIBLE if visible_cells[i] else (EXPLORED if explored[i] else UNEXPLORED)
		bytes[i] = value
		rgba[i * 4 + 3] = mini(255, value * 3 / 4 + (64 if value == UNEXPLORED else 0))
	_image.set_data(columns, rows, false, Image.FORMAT_L8, bytes)
	_texture.update(_image)
	_overview_image.set_data(columns, rows, false, Image.FORMAT_RGBA8, rgba)
	_overview.update(_overview_image)
	_apply_to_objects()


func is_visible_at(point: Vector2) -> bool:
	var i := _index(point)
	return i >= 0 and visible_cells[i] != 0


func is_explored_at(point: Vector2) -> bool:
	var i := _index(point)
	return i >= 0 and explored[i] != 0


func overview_texture() -> Texture2D:
	return _overview


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


## Enemy units only show while in sight; enemy buildings once explored. Own things always.
func _apply_to_objects() -> void:
	for unit in Unit.all_units:
		unit.fogged = enabled and unit.team != player_team and not is_visible_at(unit.position)
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index != player_team:
			object.visible = not enabled or is_explored_at(object.footprint_rect().get_center())
