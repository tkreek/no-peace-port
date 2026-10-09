class_name UnitTepees
extends UnitPart
## Native Americans "can quickly pack up their tepees, load them onto travois and disappear
## into the landscape" (manual 5.1; Pack G, Unpack L): the travois takes the tepee down and
## carries it, and sets it up again wherever it is told, as worn as it was.

const TRAVOIS := 155
const TEPEES := [100, 101, 103, 107, 115]  # chief's, sleeping, training, elders', medicine man's
const PACK_SECONDS := 6.0

var packed := {}  ## {"guid", "health"} while a tepee rides on this travois
var _pack_target: MapObject
var _unpack_site: MapObject
var _timer := 0.0


func can_pack() -> bool:
	return unit.unit_type.guid() == TRAVOIS and unit.team > 0 and unit.is_alive()


func pack(tepee: MapObject) -> void:
	if not can_pack() or not packed.is_empty() or tepee == null or tepee.guid not in TEPEES \
			or tepee.owner_index != unit.team or not tepee.complete or not tepee.is_alive():
		return
	unit.clear_orders()
	_pack_target = tepee
	_timer = 0.0
	busy = true
	unit.state = Unit.State.MOVING
	unit.path = unit.find_path(tepee.work_rect().get_center())


## Head for the site placed for the carried tepee and set it up there.
func unpack(site: MapObject) -> void:
	if not can_pack() or packed.is_empty() or site == null:
		return
	unit.clear_orders()
	_unpack_site = site
	_timer = 0.0
	busy = true
	unit.state = Unit.State.MOVING
	unit.path = unit.find_path(site.work_rect().get_center())


func clear_orders() -> void:
	_pack_target = null
	if is_instance_valid(_unpack_site) and not _unpack_site.complete:
		_unpack_site.condition.vanish()  # the tepee stays on the travois
	_unpack_site = null
	busy = false


func update(delta: float) -> bool:
	if not idle_or_moving():
		return false
	var building := _pack_target if _pack_target != null else _unpack_site
	if not is_instance_valid(building) or (building == _pack_target and not building.is_alive()):
		_pack_target = null
		_unpack_site = null
		busy = false
		return false
	if not building.work_rect().grow(Unit.REACH * 2).has_point(unit.position):
		approach(building.work_rect().get_center(), 0.0, Unit.REPATH_MS * 3)
		return false
	unit.path.clear()
	unit.state = Unit.State.IDLE
	unit.face(building.work_rect().get_center() - unit.position)
	_timer += delta
	if _timer < PACK_SECONDS:
		return false
	busy = false
	if building == _pack_target:
		packed = {"guid": building.guid, "health": building.health / building.max_health}
		_pack_target = null
		building.condition.vanish()
	else:
		building.condition.finish_unpack(float(packed.health))
		packed = {}
		_unpack_site = null
	return false
