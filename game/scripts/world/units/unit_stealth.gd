class_name UnitStealth
extends UnitPart
## Camouflage (Native arrow shooters, flaming arrow shooters and riflemen after the upgrade)
## and the outlaw assassin digging in: hidden from enemies unless a detector (arrow shooter,
## militiaman, hunter, trapper) has them in sight. Any order breaks cover. Detectors are also
## the only ones who find traps.

const CAMOUFLAGE := {156: 915, 158: 915, 160: 915, 362: 0, 369: 966}  # unit GUID -> upgrade (0 = none)
const DETECTORS := [156, 157, 261, 358, 461]
const DETECTOR_REACH := 700.0  # beyond any detector's sight, upgrades included
const ASSASSIN := 362

var concealed := false
var _buried := false  # the assassin has dug in and lies under his mound of earth
var _ambushed: Unit = null  # whom he is bursting out of it at


func can_hide() -> bool:
	var me := unit.unit_type.guid()
	if not CAMOUFLAGE.has(me) or unit.unit_type.anim_index("hide") < 0:
		return false
	var owner := player()
	return CAMOUFLAGE[me] == 0 or (owner != null and owner.researched.has(CAMOUFLAGE[me]))


func conceal() -> void:
	if not can_hide() or not unit.is_alive():
		return
	unit.stop()
	concealed = true
	busy = true
	unit.modulate.a = 0.55  # see-through for its owner; enemies don't see it at all
	unit.play("hide")


func uncover() -> void:
	_buried = false
	_ambushed = null
	if concealed:
		concealed = false
		busy = false
		unit.modulate.a = 1.0


func clear_orders() -> void:
	uncover()


## While hidden the unit only lies in wait. The assassin digs himself in (05_dig_in, once
## through), then lies under a mound of earth (06_dig_fight's first animation); whoever
## comes close, he bursts out of it (its second) and stabs.
func update(_delta: float) -> bool:
	if _ambushed != null:
		if not unit.anim_done():
			return true
		var victim := _ambushed
		uncover()
		if is_instance_valid(victim) and victim.is_alive():
			unit.attack(victim)
		return false
	if unit.state != Unit.State.IDLE:
		uncover()
		return false
	if unit.unit_type.guid() != ASSASSIN:
		unit.play("hide")
		return true
	var mound := unit.unit_type.anims_named("dig_fight")
	if not _buried:
		unit.play("hide")
		if unit.anim_done() and not mound.is_empty():
			_buried = true
			unit.play_index(mound[0])
	if unit.unit_type.attack_anims.is_empty():
		return true
	for other: Unit in UnitGrid.near(unit.position, 40.0):
		if other.is_alive() and other.team > 0 and other.team != unit.team and other.position.distance_to(unit.position) < 40.0:
			if not _buried or mound.size() < 2:
				uncover()
				unit.attack(other)
				return false
			_ambushed = other
			concealed = false  # out in the open as he bursts out
			unit.modulate.a = 1.0
			unit.face(other.position - unit.position)
			unit.play_index(mound[1])
			return true
	return true


## Whether `by_team` has a detector with `point` in sight.
static func detected(point: Vector2, by_team: int) -> bool:
	for other: Unit in UnitGrid.near(point, DETECTOR_REACH):
		if other.team == by_team and other.is_alive() and other.unit_type.guid() in DETECTORS \
				and other.position.distance_to(point) <= other.sight():
			return true
	return false


func detected_by(by_team: int) -> bool:
	return detected(unit.position, by_team)
