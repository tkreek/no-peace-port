@tool
extends Node
class_name EconomySystem

signal resources_changed(resources: Dictionary)

var resources := {
	"food": 250,
	"wood": 900,
	"gold": 500
}

func get_amount(resource_type: String) -> int:
	return int(resources.get(resource_type, 0))

func has_resource(resource_type: String) -> bool:
	return resources.has(resource_type)

func can_afford(cost: Dictionary) -> bool:
	for resource_type in cost.keys():
		if get_amount(str(resource_type)) < int(cost[resource_type]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for resource_type in cost.keys():
		var key := str(resource_type)
		resources[key] = get_amount(key) - int(cost[resource_type])
	_emit_changed()
	return true

func deposit(resource_type: String, amount: int) -> void:
	if not resources.has(resource_type):
		return
	resources[resource_type] = get_amount(resource_type) + amount
	_emit_changed()

func snapshot() -> Dictionary:
	return resources.duplicate()

func _emit_changed() -> void:
	emit_signal("resources_changed", snapshot())
