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


func setup(alf_map: AlfMap, map_camera: Camera2D, objects: Node2D, overview: Image) -> void:
	map = alf_map
	camera = map_camera
	objects_root = objects
	_texture = ImageTexture.create_from_image(overview)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	var to_mini := size / Vector2(map.pixel_size())
	for node in objects_root.get_children():
		if not node.visible:
			continue  # hidden by the fog of war
		if node is Unit:
			var u: Unit = node
			draw_rect(Rect2(u.position * to_mini - Vector2.ONE, Vector2(2, 2)), Player.TEAM_COLORS[u.team])
		elif node is MapObject and node.owner_index > 0:
			var o: MapObject = node
			draw_rect(Rect2(o.position * to_mini - Vector2(2, 2), Vector2(4, 4)), Player.TEAM_COLORS[o.owner_index])
	if FogOfWar.current and FogOfWar.current.enabled:
		draw_texture_rect(FogOfWar.current.overview_texture(), Rect2(Vector2.ZERO, size), false)
	var view := camera.get_viewport_rect().size / camera.zoom
	draw_rect(Rect2((camera.position - view / 2.0) * to_mini, view * to_mini), Color(1, 1, 1, 0.9), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		move_ordered.emit(_to_world(event.position))
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			camera.position = _to_world(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera.position = _to_world(event.position)
		accept_event()


func _to_world(local: Vector2) -> Vector2:
	return (local / size) * Vector2(map.pixel_size())
