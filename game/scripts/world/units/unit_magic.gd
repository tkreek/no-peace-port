class_name UnitMagic
extends UnitPart
## Magic (manual 3.8): the medicine man's dances and the priest's conversion, each paid
## from a pool of magic energy that refills over time (+50% with the Magic energy upgrade);
## the protective shield on whoever carries it; and healers (nurses, nuns, medicine men)
## walking up to the wounded and tending them.

const SPELLS := {
	918: {"name": "Eagle eye", "cost": 30, "target": "point", "range": 900.0,
			"text": "Lifts the fog of war around a spot for a while"},
	919: {"name": "Lightning dance", "cost": 60, "target": "point", "range": 450.0,
			"text": "A thunderstorm that saps the life of enemies beneath it"},
	920: {"name": "Hail dance", "cost": 40, "target": "point", "range": 450.0,
			"text": "Hail ruins the crops on enemy fields"},
	921: {"name": "Rain dance", "cost": 40, "target": "point", "range": 450.0,
			"text": "Rain makes a field yield half as much again"},
	922: {"name": "Protective dance", "cost": 50, "target": "unit", "range": 450.0,
			"text": "A protective shield halves the harm done to a unit"},
	948: {"name": "Conversion", "cost": 60, "target": "enemy", "range": 220.0,
			"text": "Wins an enemy soldier over to your side"},
}
const CASTERS := {164: [918, 919, 920, 921, 922], 257: [948]}
const MAGIC_UPGRADES := [917, 947]
const MAGIC_POOL := 100.0
const MAGIC_REGEN := 1.5  # per second
const CAST_SECONDS := 2.0
const SHIELD_SECONDS := 30.0
const HEAL_PER_SECOND := 4.0
const HEAL_REACH := 40.0
const MEDICINE_MAN := 164
## The sound table's "special action" events: the medicine man's four chants (event 3 is
## his dance), the nurse's, nun's and barber's healing, the priest's conversion; and the
## spells' weather on the cloud (GUID 490: rain, thunder, hail) and the eagle's cry
## (483, its "order").
const CHANTS := [Sound.Event.SPECIAL_1, Sound.Event.SPECIAL_2, Sound.Event.SPECIAL_4, Sound.Event.SPECIAL_5]
const DANCE := Sound.Event.SPECIAL_3
const CLOUD := 490
const SPELL_SOUNDS := {919: Sound.Event.SPECIAL_2, 920: Sound.Event.SPECIAL_3, 921: Sound.Event.SPECIAL_1}
const EAGLE := 483
const EAGLE_EYE := 918

var magic_energy := MAGIC_POOL
var shield_time := 0.0
var heal_target: Unit  ## a wounded friend this healer is tending
var spell := -1  ## the spell being cast, -1 for none
var _spell_point := Vector2.ZERO
var _spell_unit: Unit
var _cast_timer := 0.0
var _caster := false
var _healer := false
var _heal_sound_wait := 0.0  ## until the healer's next sound (s)


func _init(owner: Unit) -> void:
	super(owner)
	_caster = CASTERS.has(unit.unit_type.guid())
	_healer = unit.unit_type.attack_anims.is_empty() and unit.unit_type.anim_index("heal") >= 0
	busy = _caster


func is_healer() -> bool:
	return _healer


func clear_orders() -> void:
	spell = -1
	heal_target = null
	busy = _caster or shield_time > 0.0


func update(delta: float) -> bool:
	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			busy = _caster or heal_target != null
	if _caster:
		magic_energy = minf(magic_pool(), magic_energy + MAGIC_REGEN * delta)
	if spell >= 0 and idle_or_moving():
		_update_spell(delta)
	if heal_target != null and idle_or_moving():
		_update_heal(delta)
		return true
	return false


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
	var boosted := owner != null and MAGIC_UPGRADES.any(func(u: int) -> bool: return owner.researched.has(u))
	return MAGIC_POOL * (1.5 if boosted else 1.0)


## Walk within range of the target and cast `which` there (or on `on_unit`).
func cast(which: int, point: Vector2, on_unit: Unit = null) -> void:
	if not unit.is_alive() or which not in known_spells() or magic_energy < SPELLS[which].cost:
		return
	var kind: String = SPELLS[which].target
	if kind == "unit" and (on_unit == null or on_unit.team != unit.team):
		return
	if kind == "enemy" and (on_unit == null or not convertible(on_unit)):
		return
	unit.clear_orders()
	spell = which
	_spell_point = point
	_spell_unit = on_unit
	_cast_timer = 0.0
	busy = true
	unit.state = Unit.State.MOVING
	unit.path.clear()


## Leaders, builders, gatherers, transports and boats cannot be converted (manual).
func convertible(other: Unit) -> bool:
	return other.team > 0 and other.team != unit.team and other.is_alive() and not other.inside \
			and other.unit_type.guid() not in Player.COMMANDERS and not other.unit_type.can_gather("wood") \
			and not other.unit_type.can_gather("gold") and not other.unit_type.is_farmer() \
			and not other.unit_type.is_transport() and other.unit_type.anim_index("build") < 0


func _update_spell(delta: float) -> void:
	var info: Dictionary = SPELLS[spell]
	var at := _spell_unit.position if is_instance_valid(_spell_unit) else _spell_point
	if info.target != "point" and (not is_instance_valid(_spell_unit) or not _spell_unit.is_alive()):
		spell = -1
		unit.state = Unit.State.IDLE
		return
	if not approach(at, info.range):
		return
	unit.state = Unit.State.IDLE
	unit.face(at - unit.position)
	unit.play_repeating("heal")  # the medicine man dances, the priest prays
	if _cast_timer == 0.0:
		var guid := unit.unit_type.guid()
		Sound.play_event(guid, DANCE if guid == MEDICINE_MAN else Sound.Event.SPECIAL_1, unit.position, 0)
	_cast_timer += delta
	var cast_time := CAST_SECONDS / (1.0 + unit.bonus("convert_pct") / 100.0)  # Power: faster conversion
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
	match which:
		918:
			if FogOfWar.current and FogOfWar.current.player_team == team:
				FogOfWar.current.reveal_for(at, 450.0, 20.0)
		919:
			Weather.spawn(parent, at, Weather.LIGHTNING_BOB, 6.0, func(where: Vector2) -> void:
				for other: Unit in UnitGrid.near(where, 140.0):
					if other.is_alive() and other.team > 0 and other.team != team and other.position.distance_to(where) < 140.0:
						other.take_damage(8.0))
		920:
			Weather.spawn(parent, at, Weather.HAIL_BOB, 4.0)
			for field in MapObject.structures:
				if field.is_field() and field.owner_index != team and field.position.distance_to(at) < 200.0:
					field.stock.ruin_crop()
		921:
			Weather.spawn(parent, at, Weather.RAIN_BOB, 4.0)
			for field in MapObject.structures:
				if field.is_field() and field.owner_index == team and field.position.distance_to(at) < 200.0:
					field.stock.rain()
		922:
			if is_instance_valid(_spell_unit):
				_spell_unit.magic.shield()
		948:
			if is_instance_valid(_spell_unit) and convertible(_spell_unit):
				_spell_unit.change_team(team)


# ------------------------------------------------------------------ healing

## An idle healer looks for someone to tend (called from the unit's idle scan).
func look_for_wounded() -> void:
	heal_target = _nearest_wounded()
	if heal_target:
		busy = true


func _nearest_wounded() -> Unit:
	var best: Unit = null
	var best_distance := unit.sight()
	for other: Unit in UnitGrid.near(unit.position, best_distance):
		if other != unit and other.team == unit.team and other.is_alive() and not other.inside \
				and other.health < other.max_health:
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
		busy = _caster or shield_time > 0.0
		unit.state = Unit.State.IDLE
		return
	if not approach(heal_target.position, HEAL_REACH):
		unit.follow_path(delta)
		unit.play("walk")
		unit.state = Unit.State.MOVING
		return
	unit.state = Unit.State.IDLE
	unit.face(heal_target.position - unit.position)
	unit.play_repeating("heal")
	_heal_sound_wait -= delta
	if _heal_sound_wait <= 0.0:
		# A pause after each sound; the medicine man sings one of his chants.
		var guid := unit.unit_type.guid()
		var event: int = CHANTS.pick_random() if guid == MEDICINE_MAN else Sound.Event.SPECIAL_1
		_heal_sound_wait = Sound.play_event(guid, event, unit.position, 0) + 1.5
	# Healing energy and Regeneration upgrades: half as much healing again each.
	var better := 1.0 + (unit.bonus("heal_pct") + unit.bonus("heal_regen_pct")) / 100.0
	heal_target.heal(HEAL_PER_SECOND * better * delta)
