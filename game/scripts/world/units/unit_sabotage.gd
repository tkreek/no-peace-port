class_name UnitSabotage
extends UnitPart
## The outlaws' Chinese saboteur (expansion manual 4.3): sent into an enemy structure that
## shelters units (fort, watchtower, tepee of the ancestors...), he throws out up to three
## of the units inside; into an empty one, he captures it for his people. Each time he does
## either, he gives his life.
##
## Native traps: the saboteur and the scouts who can see them (UnitStealth.DETECTORS) are
## sent to one and work at it for four seconds, each with his own animation, as in
## AmericaAddOn.exe (0x41bd10 order, 0x41bd90 start, 0x41be20 done). The saboteur's trap
## (06_trap) then is his people's and he lives on; a scout's (the hunter's, trapper's and
## militiaman's 05_butcher, the arrow shooter's 11_debone) is destroyed.

const SABOTEUR := 369
const EXPELS := 3
const TRAP_SECONDS := 4.0
const TRAP_REACH := 128.0  # the original starts within 0x80 px of it

var target: MapObject
var _trap_work := 0.0  # seconds still to go at the trap; 0 while not at one


static func is_saboteur(who: Unit) -> bool:
	return who.unit_type.guid() == SABOTEUR


## Whether this unit can go into `building`, or disarm it (a trap).
func can_sabotage(building: MapObject) -> bool:
	if not unit.is_alive() or building == null or not building.is_building() or not building.complete \
			or building.health <= 0.0 or building.owner_index <= 0 or building.owner_index == unit.team:
		return false
	if building.is_trap():
		return _trap_action() != "" and unit.unit_type.anim_index(_trap_action()) >= 0
	return is_saboteur(unit) and building.defence.capacity() > 0


## The saboteur's own trap animation; the scouts' is the one they butcher game with.
func _trap_action() -> String:
	if is_saboteur(unit):
		return "trap"
	return "butcher" if unit.unit_type.guid() in UnitStealth.DETECTORS else ""


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
	_trap_work = 0.0


func update(_delta: float) -> bool:
	if target == null:
		busy = false
		return false
	if not is_instance_valid(target) or not can_sabotage(target):
		target = null
		busy = false
		_trap_work = 0.0
		if unit.path.is_empty():
			unit.state = Unit.State.IDLE
		return false
	if target.is_trap():
		return _work_at_trap(_delta)
	if target.near_walls(unit.position, Unit.REACH * 2.0):
		_strike(target)
		return true
	approach(target.wall_point(unit.position), Unit.REACH)
	return false


## At the trap: disarm it (the trap animation, looping); then it is the saboteur's people's,
## or gone.
func _work_at_trap(delta: float) -> bool:
	var pit := target.footprint_rect().get_center()
	if _trap_work <= 0.0:
		if unit.position.distance_to(pit) > TRAP_REACH:
			approach(pit, TRAP_REACH * 0.75)
			return false
		_trap_work = TRAP_SECONDS
		unit.path.clear()
		unit.state = Unit.State.IDLE
		unit.face(pit - unit.position)
		unit.play(_trap_action())
	_trap_work -= delta
	if _trap_work > 0.0:
		return true
	_trap_work = 0.0
	if is_saboteur(unit):
		target.capture(unit.team)
		target.flash(Color(1.0, 0.9, 0.4))
	else:
		target.take_damage(1000.0, unit)  # the original's 1000 points, past any trap's energy
	target = null
	busy = false
	unit.play("idle")
	return true


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
