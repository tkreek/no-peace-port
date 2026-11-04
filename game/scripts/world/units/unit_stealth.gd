class_name UnitStealth
extends UnitPart
## Camouflage (Native arrow shooters, flaming arrow shooters, riflemen and tomahawk
## throwers after the upgrade, the outlaw saboteur after his) and the outlaw assassin
## digging in: hidden from enemies unless a detector has them in sight. Detectors are also
## the only ones who find traps.
##
## As in AmericaAddOn.exe: camouflage (unit+0x401) is switched on and off by the unit's
## button (order 0x20000009, sub-codes 3 and 4: 0x41a550, 0x41a5b0); orders to move or fight
## leave it on. Going into cover takes the 4000 ms hide animation (0x41a594). It costs
## energy (+0x394, the magic energy of casters): 2 a 20 ms tick while it lasts, against the 1
## every such unit regains (0x4175b3..0x417627), and it ends when the energy runs out. Every
## unit starts with 500 of 10000 (0x418deb). An upgrade finished by its people also ends it
## (the refresh 0x41a4d0 clears +0x401).
##
## Enemies see a hidden unit only where a detector's sight covers it: the units with +0x399
## set (0x41bf2d) and the watchtowers (0x4598c0) mark a second sight map (0x7d2ad0 layer
## +0x19c) that the targeting (0x45d8fe) and drawing (0x41bc80) of hidden units consult.

const CAMOUFLAGE_UPGRADES := [915, 966]  # Native camouflage, the saboteur's (Defaults.bin lists)
const ASSASSIN := 362
## Units that mark the hidden: arrow shooters on foot and mounted (0x432e44), militiamen
## (0x45905b), hunters (0x41339b), the saboteur (0x41463f), trappers and the two campaign
## heroes of their class (0x467b75).
const DETECTORS := [156, 157, 261, 294, 295, 358, 369, 461]
const WATCHTOWERS := [213, 313, 413]
const DETECTOR_REACH := 1400.0  # beyond any detector's sight, upgrades and towers included
const HIDE_SECONDS := 4.0
const START_ENERGY := 5.0  # of 100: 500 of 10000
const ENERGY_POOL := 100.0  # 10000 (0x416c0f)
const ENERGY_REGEN := 0.5  # per second: 1 a tick
const ENERGY_DRAIN := 1.0  # per second while hidden: 2 a tick
## The assassin under his mound (0x413bc0, 0x413c80): every 100 ms he looks for an enemy
## within 32 px; then he bursts out (06_dig_fight's second animation), 300 ms into it his
## knife does 1000 points, and 2000 ms after he began he lies under the mound again.
const AMBUSH_REACH := 32.0
const AMBUSH_SCAN := 0.1
const AMBUSH_STRIKE := 0.3
const AMBUSH_SECONDS := 2.0
const AMBUSH_DAMAGE := 1000.0

var concealed := false
var energy := START_ENERGY
var _hiding := 0.0  # seconds of the hide animation still to go before the unit is in cover
var _buried := false  # the assassin has dug in and lies under his mound of earth
var _ambushed: Unit = null  # whom he is bursting out of it at
var _ambush_time := 0.0
var _struck := false
var _scan := 0.0
var _research_seen := -1


func _init(owner: Unit) -> void:
	super(owner)
	var me := unit.unit_type.guid()
	# Those who may camouflage keep their energy up (once the upgrade is in).
	busy = CAMOUFLAGE_UPGRADES.any(func(u: int) -> bool: return me in GameData.UPGRADE_TARGETS.get(u, []))


func can_hide() -> bool:
	var me := unit.unit_type.guid()
	if unit.unit_type.anim_index("hide") < 0:
		return false
	if me == ASSASSIN:
		return true
	return _camouflage_researched()


func _camouflage_researched() -> bool:
	var owner := player()
	if owner == null:
		return false
	var me := unit.unit_type.guid()
	for upgrade: int in CAMOUFLAGE_UPGRADES:
		if owner.researched.has(upgrade) and me in GameData.UPGRADE_TARGETS.get(upgrade, []):
			return true
	return false


func is_assassin() -> bool:
	return unit.unit_type.guid() == ASSASSIN


## The camouflage button: into cover, or (already in it) out again. The assassin digs in.
func conceal() -> void:
	if not can_hide() or not unit.is_alive():
		return
	if concealed and not is_assassin():
		uncover()
		return
	unit.stop()
	busy = true
	unit.play("hide")
	if is_assassin():
		_enter_cover()
	else:
		_hiding = HIDE_SECONDS


func _enter_cover() -> void:
	_hiding = 0.0
	concealed = true
	unit.modulate.a = 0.55  # see-through for its owner; enemies don't see it at all


func uncover() -> void:
	_buried = false
	_ambushed = null
	_hiding = 0.0
	if concealed:
		concealed = false
		unit.modulate.a = 1.0
	busy = not is_assassin() and CAMOUFLAGE_UPGRADES.any(func(u: int) -> bool:
			return unit.unit_type.guid() in GameData.UPGRADE_TARGETS.get(u, []))


## Orders end the assassin's ambush and the hide animation, not camouflage.
func clear_orders() -> void:
	if is_assassin() or not concealed:
		uncover()


func _regenerates() -> bool:
	return not is_assassin() and _camouflage_researched()


func update(delta: float) -> bool:
	if not is_assassin():
		return _update_camouflage(delta)
	return _update_assassin(delta)


func _update_camouflage(delta: float) -> bool:
	var owner := player()
	if owner and owner.researched.size() != _research_seen:
		if _research_seen >= 0 and concealed:
			uncover()  # an upgrade finished: the refresh clears camouflage
		_research_seen = owner.researched.size()
	if _regenerates():
		energy = minf(ENERGY_POOL, energy + ENERGY_REGEN * delta)
	if concealed:
		energy -= ENERGY_DRAIN * delta
		if energy <= 0.0:
			energy = 0.0
			uncover()
			return false
	if _hiding > 0.0:
		if unit.state != Unit.State.IDLE:
			_hiding = 0.0
			return false
		unit.play("hide")
		_hiding -= delta
		if _hiding <= 0.0:
			_enter_cover()
		return true
	if concealed and unit.state == Unit.State.IDLE:
		unit.play("hide")  # lies in wait
		return true
	return false


## The assassin digs himself in (05_dig_in, once through), then lies under a mound of earth
## (06_dig_fight's first animation); whoever comes close, he bursts out of it (its second)
## and stabs, and goes back under.
func _update_assassin(delta: float) -> bool:
	if not concealed and _ambushed == null:
		busy = false
		return false
	var mound := unit.unit_type.anims_named("dig_fight")
	if _ambushed != null:
		_ambush_time += delta
		if not _struck and _ambush_time >= AMBUSH_STRIKE:
			_struck = true
			if is_instance_valid(_ambushed) and _ambushed.is_alive():
				_ambushed.take_damage(AMBUSH_DAMAGE, unit)
		if _ambush_time < AMBUSH_SECONDS:
			return true
		_ambushed = null
		concealed = true
		unit.modulate.a = 0.55
		if not mound.is_empty():
			unit.play_index(mound[0])
		return true
	if unit.state != Unit.State.IDLE:
		uncover()
		return false
	if not _buried:
		unit.play("hide")
		if unit.anim_done() and not mound.is_empty():
			_buried = true
			unit.play_index(mound[0])
		return true
	_scan -= delta
	if _scan > 0.0:
		return true
	_scan = AMBUSH_SCAN
	for other: Unit in UnitGrid.near(unit.position, AMBUSH_REACH):
		if other.is_alive() and not other.inside and Diplomacy.hostile(unit.team, other.team) \
				and other.position.distance_to(unit.position) < AMBUSH_REACH:
			_ambushed = other
			_ambush_time = 0.0
			_struck = false
			concealed = false  # out in the open as he bursts out
			unit.modulate.a = 1.0
			unit.face(other.position - unit.position)
			if mound.size() >= 2:
				unit.play_index(mound[1])
			return true
	return true


## Whether `by_team` has a detector (or a watchtower) with `point` in sight.
static func detected(point: Vector2, by_team: int) -> bool:
	for other: Unit in UnitGrid.near(point, DETECTOR_REACH):
		if other.team == by_team and other.is_alive() and not other.inside and other.unit_type.guid() in DETECTORS \
				and other.position.distance_to(point) <= other.sight():
			return true
	for tower in MapObject.structures:
		if is_instance_valid(tower) and tower.owner_index == by_team and tower.guid in WATCHTOWERS \
				and tower.complete and tower.is_alive():
			var owner: Player = Player.by_index.get(by_team)
			var sharper := owner.bonus(tower.guid, "sight_pct") if owner else 0.0
			if tower.footprint_rect().get_center().distance_to(point) <= FogOfWar.building_sight(tower) * (1.0 + sharper / 100.0):
				return true
	return false


func detected_by(by_team: int) -> bool:
	return detected(unit.position, by_team)
