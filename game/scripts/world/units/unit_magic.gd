class_name UnitMagic
extends UnitPart
## Magic (manual 3.8): the medicine man's dances and the priest's conversion, each paid
## from a pool of magic energy that refills over time; the protective shield on whoever
## carries it; and the healers (nurses, nuns) walking up to the wounded and tending them,
## each point of life restored paid from the same kind of pool.
##
## As in AmericaAddOn.exe: the energy is unit+0x394, 0..10000 (ours is a hundredth of it),
## the maximum +0x380 10000 (0x416c0f), 15000 with Magic energy or Healing energy
## (0x41b045, 0x41b184, 0x41b1c7, 0x41b393). Every 20 ms tick it grows by 1, by 2 with
## Regeneration (0x4175dd..0x417627). Costs are taken from the medicine man's +0x6a4..+0x6b4
## (set at 0x433b8d) and the priest's +0x6a4 (0x459301); the tooltips say the same (50 or
## 75, 0x46e832).

## `cost` in our energy (a hundredth), `seconds` of dancing or praying before it works,
## `range` how near the caster must be (INF: the medicine man casts from where he stands,
## 0x433c00..0x433dd0 check no distance). Hail and rain fall on one field (the object
## clicked, 0x47ca80 / 0x47cac0).
const SPELLS := {
	918: {"name": "Eagle eye", "cost": 50, "target": "point", "range": INF, "seconds": 0.0,
			"text": "An eagle circles the spot for a while, lifting the fog of war"},
	919: {"name": "Lightning dance", "cost": 75, "target": "point", "range": INF, "seconds": 6.0,
			"text": "A thunderstorm that strikes everyone beneath it"},
	920: {"name": "Hail dance", "cost": 50, "target": "field", "range": INF, "seconds": 6.0,
			"text": "Hail destroys a field"},
	921: {"name": "Rain dance", "cost": 50, "target": "field", "range": INF, "seconds": 6.0,
			"text": "Rain makes a field yield more"},
	922: {"name": "Protective dance", "cost": 75, "target": "unit", "range": INF, "seconds": 6.0,
			"text": "A protective shield takes four fifths of the harm done to a unit"},
	948: {"name": "Conversion", "cost": 50, "target": "enemy", "range": 500.0, "seconds": 3.0,
			"text": "Wins an enemy unit over to your side"},
}
const CASTERS := {164: [918, 919, 920, 921, 922], 257: [948]}
## The nun and the nurse (their classes 0x4a8198 / 0x4a45d4 heal; the medicine man's
## 0x4a8708 does not).
const HEALERS := [256, 457]
## The upgrade that makes each one's pool half as big again (Defaults.bin's lists).
const POOL_UPGRADES := {164: 917, 257: 947, 256: 945, 457: 983}
const REGENERATION := 946  # the nun's: her energy refills twice as fast
const CONVERSION := 948
const POWER := 949  # the priest converts in 1500 ms instead of 3000 (0x459380)
const MAGIC_POOL := 100.0
const MAGIC_REGEN := 0.5  # per second: 1 of 10000 every 20 ms
## Energy a new unit has: 500 (0x418deb); the medicine man 1000 (0x433bb7), the healers
## 5000 (0x43f662), the priest 3000 once Conversion is researched (0x45939f).
const BASE_ENERGY := 5.0
const START_ENERGY := {164: 10.0, 257: 30.0, 256: 50.0, 457: 50.0}
const SHIELD_SECONDS := 60.0  # 0x434046
const SHIELD_FACTOR := 0.2  # damage taken under the shield (0x418fe9)
## Healing (0x43f5b0): every 500 ms one point of life for 100 energy, from within 32 px
## (64 px while at it, 0x43f613); without the energy the healer waits by the patient.
const HEAL_INTERVAL := 0.5
const HEAL_COST := 1.0
const HEAL_REACH := 32.0
const HEAL_KEEP_REACH := 64.0
## An idle healer looks for a hurt unit of her people (herself too) within 256 px once a
## second (0x43f6c0, 0x45dc40).
const HEAL_SEARCH := 256.0
const HEAL_SEARCH_SECONDS := 1.0
const MEDICINE_MAN := 164
const PRIEST := 257
## The sound table's "special action" events: the medicine man's four chants and his dance
## (SPELL_CHANTS), the nurse's and nun's healing, the priest's conversion; and the
## spells' weather on the cloud (GUID 490: rain, thunder, hail) and the eagle's cry
## (483, its "order").
const CLOUD := 490
const SPELL_SOUNDS := {919: Sound.Event.SPECIAL_2, 920: Sound.Event.SPECIAL_3, 921: Sound.Event.SPECIAL_1}
## The medicine man's chant for each spell as he starts it (AmericaAddOn.exe 0x433c00-0x433e14).
const SPELL_CHANTS := {918: Sound.Event.SPECIAL_3, 919: Sound.Event.SPECIAL_4, 920: Sound.Event.SPECIAL_2,
		921: Sound.Event.SPECIAL_1, 922: Sound.Event.SPECIAL_5}
const EAGLE := 483
const EAGLE_EYE := 918
## The eagle (0x462af0) flies 22500 ms in a circle of 300 px about the spot, seeing as far
## as the shortest sight (256 px, 0x421039).
const EAGLE_EYE_SECONDS := 22.5
const EAGLE_EYE_REACH := 300.0 + 256.0
## The weather cloud (0x47c6e0): it gathers for 1200 ms, storms 5000 ms and dissolves in
## 1200 ms. Lightning strikes every 500 ms of the storm, 10 points to every unit, whoever's,
## from 50 px left of the spot to 130 px right and 90 px above to 90 px below (0x47ca10);
## hail and rain work as it dissolves.
const CLOUD_GATHER_SECONDS := 1.2
const STORM_SECONDS := 5.0
const LIGHTNING_EVERY := 0.5
const LIGHTNING_DAMAGE := 10.0
const LIGHTNING_AREA := Rect2(-50, -90, 180, 180)
## Rain (0x47ca80) fills the field with 350 food, as against a woman's 150 (Shovel: 175,
## 200) when she sows it.
const RAIN_FOOD := 350.0
const SOWN_FOOD := 150.0
const FIELD_PICK := 48.0  # how far from a field a click still means it

var magic_energy := 0.0
var shield_time := 0.0
var heal_target: Unit  ## a wounded friend this healer is tending
var spell := -1  ## the spell being cast, -1 for none
var _spell_point := Vector2.ZERO
var _spell_unit: Unit
var _spell_field: MapObject
var _cast_timer := 0.0
var _caster := false
var _healer := false
var _research_seen := -1  ## the priest: how many upgrades his people had at his last recharge
var _heal_timer := 0.0
var _search_timer := 0.0
var _heal_sounded_for: Unit  ## the patient whose care the healer's sound announced


func _init(owner: Unit) -> void:
	super(owner)
	var guid := unit.unit_type.guid()
	_caster = CASTERS.has(guid)
	_healer = guid in HEALERS
	magic_energy = START_ENERGY.get(guid, BASE_ENERGY)
	if guid == PRIEST:
		magic_energy = BASE_ENERGY
		_recharge_priest()
	busy = _caster or _healer


func is_healer() -> bool:
	return _healer


func clear_orders() -> void:
	spell = -1
	heal_target = null
	busy = _caster or _healer or shield_time > 0.0


func update(delta: float) -> bool:
	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			busy = _caster or _healer
	if (_caster or _healer) and _regenerates():
		var owner := player()
		var regen := 2.0 if owner and owner.researched.has(REGENERATION) and _upgraded(REGENERATION) else 1.0
		magic_energy = minf(magic_pool(), magic_energy + MAGIC_REGEN * regen * delta)
	if spell >= 0 and idle_or_moving():
		_update_spell(delta)
	if _healer:
		_search_timer -= delta
	if heal_target != null and idle_or_moving():
		_update_heal(delta)
		return true
	return false


## The priest's energy does not refill before Conversion. With it, his people's upgrade
## refresh (made, and again whenever one of their upgrades is finished: 0x41763c,
## 0x459340) sets it to 3000.
func _regenerates() -> bool:
	if unit.unit_type.guid() != PRIEST:
		return true
	_recharge_priest()
	return _research_seen >= 0


func _recharge_priest() -> void:
	var owner := player()
	if owner == null or not owner.researched.has(CONVERSION):
		return
	if owner.researched.size() != _research_seen:
		_research_seen = owner.researched.size()
		magic_energy = START_ENERGY[PRIEST]


func _upgraded(upgrade: int) -> bool:
	return unit.unit_type.guid() in GameData.UPGRADE_TARGETS.get(upgrade, [])


func shield() -> void:
	shield_time = SHIELD_SECONDS
	busy = true
	Weather.spawn(unit, Vector2(0, -20), Weather.SHIELD_BOB, SHIELD_SECONDS)


# ------------------------------------------------------------------ spells

func known_spells() -> Array:
	var owner := player()
	if owner == null:
		return []
	return CASTERS.get(unit.unit_type.guid(), []).filter(func(s: int) -> bool: return owner.researched.has(s))


func magic_pool() -> float:
	var owner := player()
	var upgrade: int = POOL_UPGRADES.get(unit.unit_type.guid(), -1)
	return MAGIC_POOL * (1.5 if owner != null and owner.researched.has(upgrade) else 1.0)


## Healers and spell casters carry magic (or healing) energy.
func has_energy() -> bool:
	return _caster or _healer


## Cast `which` at `point` (or on `on_unit`): walk within range of it first (the priest),
## dance or pray, then it works. Hail and rain take the field at `point`.
func cast(which: int, point: Vector2, on_unit: Unit = null) -> void:
	if not unit.is_alive() or which not in known_spells() or magic_energy < SPELLS[which].cost:
		return
	var kind: String = SPELLS[which].target
	if kind == "unit" and (on_unit == null or on_unit.team != unit.team):
		return
	if kind == "enemy" and (on_unit == null or not convertible(on_unit)):
		return
	var field: MapObject = field_at(point) if kind == "field" else null
	if kind == "field" and field == null:
		return
	unit.clear_orders()
	if which == EAGLE_EYE:
		# The eagle rises at once, paid for there and then (0x433c36).
		unit.stop()
		magic_energy -= SPELLS[which].cost
		Sound.play_event(unit.unit_type.guid(), SPELL_CHANTS[which], unit.position, 0)
		_apply_spell(which, point)
		return
	spell = which
	_spell_point = point
	_spell_unit = on_unit
	_spell_field = field
	_cast_timer = 0.0
	busy = true
	unit.state = Unit.State.MOVING
	unit.path.clear()


## The field whose plot `point` is in, or the nearest within a few steps.
static func field_at(point: Vector2) -> MapObject:
	var best: MapObject = null
	var best_distance := FIELD_PICK
	for field in MapObject.structures:
		if not is_instance_valid(field) or not field.is_field():
			continue
		var rect := field.footprint_rect()
		if rect.has_point(point):
			return field
		var distance := rect.get_center().distance_to(point)
		if distance < best_distance:
			best = field
			best_distance = distance
	return best


## Who a priest may convert: what the cursor offers (0x4779a6), an enemy unit that is not
## a leader, transport, woodcutter, woman, wagon or builder (class 0x89848000).
func convertible(other: Unit) -> bool:
	return Diplomacy.hostile(unit.team, other.team) and other.is_alive() and not other.inside \
			and other.unit_type.guid() not in Player.COMMANDERS and not other.unit_type.can_gather("wood") \
			and not other.unit_type.can_gather("gold") and not other.unit_type.is_farmer() \
			and not other.unit_type.is_transport() and other.unit_type.anim_index("build") < 0


func _update_spell(delta: float) -> void:
	var info: Dictionary = SPELLS[spell]
	var at := _spell_point
	if info.target == "unit" or info.target == "enemy":
		if not is_instance_valid(_spell_unit) or not _spell_unit.is_alive():
			spell = -1
			unit.state = Unit.State.IDLE
			return
		at = _spell_unit.position
	elif info.target == "field":
		if not is_instance_valid(_spell_field):
			spell = -1
			unit.state = Unit.State.IDLE
			return
		at = _spell_field.footprint_rect().get_center()
	if not approach(at, info.range):
		return
	unit.state = Unit.State.IDLE
	unit.face(at - unit.position)
	unit.play_repeating("heal")  # the medicine man dances, the priest prays
	if _cast_timer == 0.0:
		var guid := unit.unit_type.guid()
		Sound.play_event(guid, SPELL_CHANTS.get(spell, Sound.Event.SPECIAL_1) if guid == MEDICINE_MAN else Sound.Event.SPECIAL_1, unit.position, 0)
	_cast_timer += delta
	var cast_time: float = info.seconds
	if spell == CONVERSION and player() and player().researched.has(POWER):
		cast_time /= 2.0
	if _cast_timer < cast_time:
		return
	if magic_energy >= info.cost:
		magic_energy -= info.cost
		_apply_spell(spell, at)
	spell = -1


func _apply_spell(which: int, at: Vector2) -> void:
	var parent := unit.get_parent()
	var team := unit.team
	if SPELL_SOUNDS.has(which):
		Sound.play_event(CLOUD, SPELL_SOUNDS[which], at, 0)
	elif which == EAGLE_EYE:
		Sound.play_event(EAGLE, Sound.Event.ORDER, at, 0)
	var storm := CLOUD_GATHER_SECONDS + STORM_SECONDS
	match which:
		918:
			var mine := FogOfWar.current == null or FogOfWar.current.player_team == team
			if FogOfWar.current and mine:
				FogOfWar.current.reveal_for(at, EAGLE_EYE_REACH, EAGLE_EYE_SECONDS)
			if mine and Ambience.current:
				Ambience.current.eagle_over(at, EAGLE_EYE_SECONDS)
		919:
			Weather.spawn(parent, at, Weather.LIGHTNING_BOB, storm, func(where: Vector2) -> void:
				var area := Rect2(where + LIGHTNING_AREA.position, LIGHTNING_AREA.size)
				for other: Unit in UnitGrid.near(area.get_center(), area.size.length() / 2.0):
					if other.is_alive() and not other.inside and area.has_point(other.position):
						other.take_damage(LIGHTNING_DAMAGE),
				LIGHTNING_EVERY, CLOUD_GATHER_SECONDS, roundi(STORM_SECONDS / LIGHTNING_EVERY))
		920:
			var field := _spell_field
			Weather.spawn(parent, at, Weather.HAIL_BOB, storm, func(_where: Vector2) -> void:
				if is_instance_valid(field):
					field.stock.ruin_crop(),
				storm, storm, 1)
		921:
			var field := _spell_field
			Weather.spawn(parent, at, Weather.RAIN_BOB, storm, func(_where: Vector2) -> void:
				if is_instance_valid(field):
					field.stock.rain(),
				storm, storm, 1)
		922:
			if is_instance_valid(_spell_unit):
				_spell_unit.magic.shield()
		948:
			if is_instance_valid(_spell_unit) and convertible(_spell_unit):
				_spell_unit.change_team(team)


# ------------------------------------------------------------------ healing

## An idle healer looks for someone to tend (called from the unit's idle scan).
func look_for_wounded() -> void:
	if _search_timer > 0.0:
		return
	_search_timer = HEAL_SEARCH_SECONDS
	heal_target = _nearest_wounded()
	_heal_timer = 0.0


func _nearest_wounded() -> Unit:
	var best: Unit = null
	var best_distance := HEAL_SEARCH
	for other: Unit in UnitGrid.near(unit.position, best_distance):
		if other.team == unit.team and other.is_alive() and not other.inside \
				and other.health < other.max_health and other.health >= 1.0:
			var distance := unit.position.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


## Walk up to the wounded unit and tend it until it is whole again.
func _update_heal(delta: float) -> void:
	if not is_instance_valid(heal_target) or not heal_target.is_alive() or heal_target.inside \
			or heal_target.health >= heal_target.max_health:
		heal_target = null
		unit.state = Unit.State.IDLE
		return
	var reach := HEAL_KEEP_REACH if unit.state == Unit.State.IDLE and _heal_sounded_for == heal_target else HEAL_REACH
	if not approach(heal_target.position, reach):
		unit.follow_path(delta)
		unit.play("walk")
		unit.state = Unit.State.MOVING
		_heal_sounded_for = null
		return
	unit.state = Unit.State.IDLE
	if heal_target != unit:
		unit.face(heal_target.position - unit.position)
	unit.play_repeating("heal")
	if _heal_sounded_for != heal_target:
		# Like the original (0x43f55f): the healer is heard as she starts on a patient.
		_heal_sounded_for = heal_target
		_heal_timer = HEAL_INTERVAL
		Sound.play_event(unit.unit_type.guid(), Sound.Event.SPECIAL_1, unit.position, 0)
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	_heal_timer += HEAL_INTERVAL
	if magic_energy < HEAL_COST:
		return  # spent: she waits by the patient until the energy comes back
	magic_energy -= HEAL_COST
	heal_target.heal(1.0)
