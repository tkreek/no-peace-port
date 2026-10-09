@tool
extends Panel
class_name RTSMinimapPanel

var content: Control
var view_rect: ColorRect

func _ready() -> void:
	_build_ui()

func update_blips(tree: SceneTree, camera_rig: Node3D) -> void:
	if content == null or view_rect == null or camera_rig == null:
		return

	for child in content.get_children():
		if child.name.begins_with("UnitBlip"):
			child.queue_free()

	var map_size := 100.0
	var minimap_size := content.size
	for node in tree.get_nodes_in_group("units"):
		var unit := node as Node3D
		if unit == null:
			continue
		_add_blip("UnitBlip", unit.global_position, Color(0.25, 0.55, 1.0, 1.0), Vector2(5.0, 5.0), map_size, minimap_size)

	for node in tree.get_nodes_in_group("resource_nodes"):
		var resource := node as Node3D
		if resource == null:
			continue
		var resource_type := str(resource.get_meta("resource_type", "wood"))
		_add_blip("UnitBlipResource", resource.global_position, _resource_color(resource_type), Vector2(7.0, 7.0), map_size, minimap_size)

	for node in tree.get_nodes_in_group("enemy_units"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		_add_blip("UnitBlipEnemy", enemy.global_position, Color(0.86, 0.14, 0.10, 1.0), Vector2(6.0, 6.0), map_size, minimap_size)

	var view_center := _world_to_minimap(camera_rig.global_position, map_size, minimap_size)
	view_rect.size = Vector2(44.0, 30.0)
	view_rect.position = view_center - view_rect.size * 0.5

func _build_ui() -> void:
	add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.05, 0.035, 0.94), Color(0.27, 0.16, 0.08, 1.0)))

	content = Control.new()
	content.name = "MiniMapContent"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14.0
	content.offset_top = 14.0
	content.offset_right = -14.0
	content.offset_bottom = -14.0
	add_child(content)

	var background := ColorRect.new()
	background.color = Color(0.13, 0.28, 0.18, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(background)

	var river_strip := ColorRect.new()
	river_strip.color = Color(0.10, 0.26, 0.39, 1.0)
	river_strip.anchor_left = 0.55
	river_strip.anchor_top = 0.0
	river_strip.anchor_right = 0.68
	river_strip.anchor_bottom = 1.0
	content.add_child(river_strip)

	view_rect = ColorRect.new()
	view_rect.color = Color(1.0, 0.92, 0.36, 0.18)
	content.add_child(view_rect)

func _add_blip(blip_name: String, world_position: Vector3, color: Color, size: Vector2, map_size: float, minimap_size: Vector2) -> void:
	var blip := ColorRect.new()
	blip.name = blip_name
	blip.color = color
	blip.size = size
	blip.position = _world_to_minimap(world_position, map_size, minimap_size) - blip.size * 0.5
	content.add_child(blip)

func _world_to_minimap(world_position: Vector3, map_size: float, minimap_size: Vector2) -> Vector2:
	return Vector2(
		(world_position.x / map_size + 0.5) * minimap_size.x,
		(world_position.z / map_size + 0.5) * minimap_size.y
	)

func _resource_color(resource_type: String) -> Color:
	match resource_type:
		"food":
			return Color(0.90, 0.24, 0.22, 1.0)
		"wood":
			return Color(0.72, 0.43, 0.18, 1.0)
		"gold":
			return Color(0.94, 0.73, 0.22, 1.0)
	return Color(0.9, 0.9, 0.9, 1.0)

func _make_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
