class_name UnitPart
extends RefCounted
## One group of a unit's rules (work, riding, water, magic...), kept out of Unit itself.
##
## While `busy`, the unit calls `update` every frame before its own state machine; an
## update that returns true has steered the unit this frame and the state machine waits.
## Any new order calls `clear_orders`.

var unit: Unit
var busy := false


func _init(owner: Unit) -> void:
	unit = owner


func update(_delta: float) -> bool:
	return false


func clear_orders() -> void:
	pass


## Shorthands for the unit's player and its researched upgrades.
func player() -> Player:
	return Player.by_index.get(unit.team)


func idle_or_moving() -> bool:
	return unit.state == Unit.State.IDLE or unit.state == Unit.State.MOVING


## Walk towards `point`, finding the way again now and then; true once within `reach`.
func approach(point: Vector2, reach: float, repath_ms := Unit.REPATH_MS) -> bool:
	if unit.position.distance_to(point) <= reach:
		unit.path.clear()
		return true
	var now := Time.get_ticks_msec()
	if unit.path.is_empty() or now - unit._last_repath > repath_ms:
		unit._last_repath = now
		unit.path = unit.find_path(point)
	unit.state = Unit.State.MOVING if not unit.path.is_empty() else Unit.State.IDLE
	return false
