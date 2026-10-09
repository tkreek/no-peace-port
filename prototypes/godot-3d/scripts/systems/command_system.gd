@tool
extends Node
class_name CommandSystem

func has_worker(units: Array[Node]) -> bool:
	for unit in units:
		if str(unit.get("unit_role")) == "worker":
			return true
	return false

func issue_move(units: Array[Node], point: Vector3) -> void:
	if units.is_empty():
		return

	var spacing := 1.3
	var columns := int(ceilf(sqrt(float(units.size()))))
	for i in range(units.size()):
		var row := i / columns
		var column := i % columns
		var offset := Vector3((column - (columns - 1) * 0.5) * spacing, 0.0, row * spacing)
		if units[i].has_method("move_to"):
			units[i].move_to(point + offset)

func issue_gather(units: Array[Node], resource_node: Node3D, headquarters: Node3D) -> int:
	var gatherer_index := 0
	for unit in units:
		if unit.has_method("gather_from"):
			unit.gather_from(resource_node, headquarters, gatherer_index)
			gatherer_index += 1
	return gatherer_index

func issue_attack(units: Array[Node], enemy: Node3D) -> int:
	var attackers := 0
	for unit in units:
		if unit.has_method("attack"):
			unit.attack(enemy)
			var role := str(unit.get("unit_role"))
			if role not in ["worker", "support"]:
				attackers += 1
	return attackers

func set_behavior(units: Array[Node], mode: String) -> int:
	var changed := 0
	for unit in units:
		if unit.has_method("set_behavior_mode"):
			unit.set_behavior_mode(mode)
			changed += 1
	return changed
