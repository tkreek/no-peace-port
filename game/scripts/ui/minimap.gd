class_name Minimap
extends Control
## Map overview (one pixel per terrain cell, from Terrain.overview_image) with units,
## buildings and the camera view. Click or drag to move the camera; right-click to order a move.

signal move_ordered(world_position: Vector2)

var map: AlfMap
var camera: Camera2D
var objects_root: Node2D
var _texture: ImageTexture
var _dragging := false
## Map modes (manual 3.1): everything; civilian units and buildings only; military only.
enum Mode { REGULAR, ECONOMIC, MILITARY }
var mode := Mode.REGULAR


const REDRAW_SECONDS := 0.2  # units and buildings; the camera frame follows every frame
const FogShader := preload("res://shaders/minimap_fog.gdshader")

var _fog := TextureRect.new()
var _view := Control.new()  # the camera frame, drawn above the fog
var _redraw := 0.0


func setup(alf_map: AlfMap, map_camera: Camera2D, objects: Node2D, overview: Image) -> void:
	map = alf_map
	camera = map_camera
	objects_root = objects
	_texture = ImageTexture.create_from_image(overview)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for layer: Control in [_fog, _view]:
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
	_fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fog.stretch_mode = TextureRect.STRETCH_SCALE
	_fog.material = ShaderMaterial.new()
	_fog.material.shader = FogShader
	_view.draw.connect(_draw_view)


func _process(delta: float) -> void:
	_view.queue_redraw()
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = REDRAW_SECONDS
		queue_redraw()
	var fog := FogOfWar.current
	_fog.visible = fog != null and fog.enabled
	if _fog.visible and _fog.texture != fog.visible_texture():
		_fog.texture = fog.visible_texture()
		(_fog.material as ShaderMaterial).set_shader_parameter("explored_cells", fog.explored_texture())


func _draw() -> void:
	if map == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	var to_mini := size / Vector2(map.pixel_size())
	for u in Unit.all_units:
		if u.visible and u.is_alive() and _shown(_is_military_unit(u)):
			draw_rect(Rect2(u.position * to_mini - Vector2.ONE, Vector2(2, 2)), Player.TEAM_COLORS[u.team])
	for o in MapObject.structures:
		if o.visible and o.owner_index > 0 and _shown(_is_military_building(o)):
			draw_rect(Rect2(o.position * to_mini - Vector2(2, 2), Vector2(4, 4)), Player.TEAM_COLORS[o.owner_index])


func _draw_view() -> void:
	var to_mini := size / Vector2(map.pixel_size())
	var view := camera.get_viewport_rect().size / camera.zoom
	_view.draw_rect(Rect2((camera.position - view / 2.0) * to_mini, view * to_mini), Color(1, 1, 1, 0.9), false, 1.0)


func _shown(military: bool) -> bool:
	match mode:
		Mode.ECONOMIC:
			return not military
		Mode.MILITARY:
			return military
	return true


static func _is_military_unit(u: Unit) -> bool:
	return not u.unit_type.attack_anims.is_empty() and not u.unit_type.can_gather("wood") \
			and not u.unit_type.is_farmer() and not u.unit_type.is_transport()


static var _military_kinds := {}  # building GUID -> trains soldiers


static func _is_military_building(o: MapObject) -> bool:
	if not o.is_building():
		return false
	if o.defence.capacity() > 0 and o.guid not in MapObject.MAIN_BUILDINGS:
		return true  # forts and towers
	if not _military_kinds.has(o.guid):
		_military_kinds[o.guid] = false
		for unit_guid in GameData.stats_guids():
			var stats := GameData.stats(unit_guid)
			if stats.get("kind") == "unit" and int(stats.get("produced_at", -1)) == o.guid \
					and stats.get("damage", 0) >= 5 and unit_guid not in Player.COMMANDERS:
				_military_kinds[o.guid] = true
	return _military_kinds[o.guid]


func is_dragging() -> bool:
	return _dragging


## Input from the HUD frame drawn over the minimap (positions in minimap coordinates).
func handle_input(event: InputEvent) -> void:
	_gui_input(event)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		move_ordered.emit(_to_world(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			camera.position = _to_world(event.position)
	elif event is InputEventMouseMotion and _dragging:
		camera.position = _to_world(event.position.clamp(Vector2.ZERO, size))


func _to_world(local: Vector2) -> Vector2:
	return (local / size) * Vector2(map.pixel_size())
