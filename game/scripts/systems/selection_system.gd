@tool
extends Node
class_name SelectionSystem

func select_single_unit(unit: Node) -> Array[Node]:
	unit.set("selected", true)
	return [unit]

func select_units_in_rect(tree: SceneTree, camera: Camera3D, rect: Rect2) -> Array[Node]:
	var selected: Array[Node] = []
	for node in tree.get_nodes_in_group("units"):
		var unit := node as Node
		var unit_3d := node as Node3D
		if unit == null or unit_3d == null:
			continue
		var screen_position: Vector2 = camera.unproject_position(unit_3d.global_position + Vector3.UP * 0.8)
		if rect.has_point(screen_position):
			unit.set("selected", true)
			selected.append(unit)
	return selected

func clear_units(units: Array[Node]) -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.set("selected", false)

func set_building_selected(building: Node3D, value: bool) -> void:
	if not is_instance_valid(building):
		return
	var indicator := building.get_node_or_null("SelectionIndicator") as MeshInstance3D
	if indicator != null:
		indicator.visible = value
