class_name UnitSabotage
extends UnitPart
## The outlaws' Chinese saboteur (expansion manual 4.3): sent into an enemy structure that
## shelters units (fort, watchtower, tepee of the ancestors...), he throws out up to three
## of the units inside; into an empty one, he captures it for his people, and so the
## Natives' traps. Each time he does either, he gives his life.

const SABOTEUR := 369
const EXPELS := 3

var target: MapObject


static func is_saboteur(who: Unit) -> bool:
	return who.unit_type.guid() == SABOTEUR


## Whether this unit can go into `building`.
func can_sabotage(building: MapObject) -> bool:
	return is_saboteur(unit) and unit.is_alive() and building != null and building.is_building() \
			and building.complete and building.health > 0.0 and building.owner_index > 0 \
			and building.owner_index != unit.team and (building.defence.capacity() > 0 or building.is_trap())


func sabotage(building: MapObject) -> void:
	if not can_sabotage(building):
		return
	unit.clear_orders()
	target = building
	busy = true
	unit.state = Unit.State.MOVING
	unit.path = unit.find_path(building.wall_point(unit.position))


func clear_orders() -> void:
	target = null
	busy = false


func update(_delta: float) -> bool:
	if target == null:
		busy = false
		return false
	if not is_instance_valid(target) or not can_sabotage(target):
		target = null
		busy = false
		if unit.path.is_empty():
			unit.state = Unit.State.IDLE
		return false
	if target.near_walls(unit.position, Unit.REACH * 2.0):
		_strike(target)
		return true
	approach(target.wall_point(unit.position), Unit.REACH)
	return false


## In through the door: out with three of those inside, or the empty building is ours.
func _strike(building: MapObject) -> void:
	target = null
	busy = false
	var inside := building.defence.garrison
	if inside.is_empty():
		building.capture(unit.team)
	else:
		for i in mini(EXPELS, inside.size()):
			building.defence.release(inside[0])
	building.flash(Color(1.0, 0.9, 0.4))
	unit.health = 0.0
	unit.die()
