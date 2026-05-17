@tool
extends Node
class_name BuildSystem

var terrain_service: Node

func can_place(position: Vector3, size: Vector3, groups: Array, tree: SceneTree) -> bool:
	if absf(position.x) + size.x * 0.5 > 47.0 or absf(position.z) + size.z * 0.5 > 47.0:
		return false
	if terrain_service != null and terrain_service.has_method("blocks_building") and terrain_service.blocks_building(position):
		return false

	var min_distance := maxf(size.x, size.z) * 0.5 + 2.2
	for group_name in groups:
		for node in tree.get_nodes_in_group(group_name):
			var other := node as Node3D
			if other == null:
				continue
			var offset := other.global_position - position
			offset.y = 0.0
			if offset.length() < min_distance:
				return false
	return true

func assign_workers(workers: Array[Node], site: Node3D) -> int:
	var builder_index := 0
	for unit in workers:
		if str(unit.get("unit_role")) == "worker" and unit.has_method("build"):
			unit.build(site, builder_index)
			builder_index += 1
	return builder_index
