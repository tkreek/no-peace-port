class_name UnitStealth
extends UnitPart
## Camouflage (Native arrow shooters, flaming arrow shooters and riflemen after the upgrade)
## and the outlaw assassin digging in: hidden from enemies unless a detector (arrow shooter,
## militiaman, hunter, trapper) has them in sight. Any order breaks cover. Detectors are also
## the only ones who find traps.

const CAMOUFLAGE := {156: 915, 158: 915, 160: 915, 362: 0}  # unit GUID -> upgrade (0 = none)
const DETECTORS := [156, 157, 261, 358, 461]
const DETECTOR_REACH := 700.0  # beyond any detector's sight, upgrades included
const ASSASSIN := 362

var concealed := false


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
	if concealed:
		concealed = false
		busy = false
		unit.modulate.a = 1.0


func clear_orders() -> void:
	uncover()


## While hidden the unit only lies in wait; a dug-in assassin stabs whoever comes close.
func update(_delta: float) -> bool:
	if unit.state != Unit.State.IDLE:
		uncover()
		return false
	unit.play("hide")
	if unit.unit_type.guid() == ASSASSIN and not unit.unit_type.attack_anims.is_empty():
		for other: Unit in UnitGrid.near(unit.position, 40.0):
			if other.is_alive() and other.team > 0 and other.team != unit.team and other.position.distance_to(unit.position) < 40.0:
				uncover()
				unit.attack(other)
				return false
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
