class_name UnitRiding
extends UnitPart
## Riding (manual 2.6, 3.10): units that can ride mount a loose horse by walking up to it
## and dismount leaving it behind. Soldiers shoot the rider, not the horse, so a rider who
## falls leaves a riderless horse to his people, as one who dismounts does; told to (Ctrl +
## right click), they shoot the horse instead, and the rider fights on on foot.

const HORSE_HEALTH := 80.0
const MAX_OWN_LOOSE_HORSES := 5
const MAX_WILD_HORSES := 30

var aim_at_horse := false  ## this unit was told to shoot the mount
var horse_health := HORSE_HEALTH
var _mount_target: Unit


func can_mount() -> bool:
	return unit.team > 0 and GameData.mounted_of(unit.unit_type.guid()) >= 0


func can_dismount() -> bool:
	return GameData.foot_of(unit.unit_type.guid()) >= 0


func clear_orders() -> void:
	_mount_target = null
	busy = false


func mount(horse: Unit) -> void:
	if not can_mount() or horse == null or not horse.is_alive() or not horse.animal.is_horse():
		return
	unit.clear_orders()
	_mount_target = horse
	busy = true
	unit.state = Unit.State.MOVING
	unit.path = unit.find_path(horse.position)


func update(_delta: float) -> bool:
	if not idle_or_moving():
		return false
	var horse := _mount_target
	if not is_instance_valid(horse) or not horse.is_alive() or (horse.team > 0 and horse.team != unit.team):
		clear_orders()
		return false
	if not approach(horse.position, 36.0):
		return false
	clear_orders()
	var rider := become(GameData.mounted_of(unit.unit_type.guid()))
	if rider:
		# The mounted unit's "order" line is the rider's call as he swings up.
		Sound.play_event(rider.unit_type.guid(), Sound.Event.ORDER, rider.position, 0)
		Unit.all_units.erase(horse)
		Unit.roster_version += 1
		horse.queue_free()
	return false


func dismount() -> void:
	var foot := GameData.foot_of(unit.unit_type.guid())
	if foot < 0 or not unit.is_alive():
		return
	var at := unit.position
	var owner := unit.team
	var parent := unit.get_parent()
	if become(foot):
		UnitAnimal.loose_horse(parent, at + Vector2(24, 8), owner).animal.wild_timer = UnitAnimal.OWNED_HORSE_SECONDS


## The rider falls and his horse stays with his people, as when he dismounts; but with more
## than 5 loose horses of theirs about, or more than 30 wild ones, it falls too
## (AmericaAddOn.exe 0x41933c..0x4193cd). False when this unit is not on horseback.
func shot_from_saddle() -> bool:
	var foot := GameData.foot_of(unit.unit_type.guid())
	if not unit.unit_type.mounted or foot < 0 or unit.team <= 0:
		return false
	var at := unit.position
	var owner := unit.team
	var parent := unit.get_parent()
	var rider := become(foot)
	if rider == null:
		return false
	rider.health = 0.0
	rider.die()
	var horse := UnitAnimal.loose_horse(parent, at + Vector2(22, 6), owner)
	horse.animal.wild_timer = UnitAnimal.OWNED_HORSE_SECONDS
	if _loose_horses(owner) > MAX_OWN_LOOSE_HORSES or _loose_horses(0) > MAX_WILD_HORSES:
		horse.health = 0.0
		horse.die()
	return true


static func _loose_horses(team: int) -> int:
	return Unit.all_units.filter(func(u: Unit) -> bool: return u.team == team and u.is_alive() and u.animal.is_horse()).size()


## A shot at the mount; when the horse falls it leaves a carcass and the rider walks on.
func hit_horse(amount: float, attacker: Node2D) -> void:
	if not unit.is_alive():
		return
	if unit.magic.shield_time > 0.0:
		amount *= UnitMagic.SHIELD_FACTOR
	horse_health -= amount
	if horse_health > 0.0:
		return
	var at := unit.position
	var parent := unit.get_parent()
	if become(GameData.foot_of(unit.unit_type.guid())) == null:
		unit.take_damage(amount, attacker, true)
		return
	var horse := UnitAnimal.loose_horse(parent, at + Vector2(22, 6), 0)
	horse.health = 0.0
	horse.die()  # meat for the hunters


## Replace the unit by another kind (mounting, dismounting), keeping its condition.
func become(guid: int) -> Unit:
	var new_type := UnitType.for_guid(guid)
	if new_type == null:
		return null
	var other := Unit.new()
	other.position = unit.position
	unit.get_parent().add_child(other)
	other.setup(new_type, unit.team)
	other.health = other.max_health * (unit.health / unit.max_health if unit.max_health > 0 else 1.0)
	other.experience = unit.experience
	other.stance = unit.stance
	other.direction = unit.direction
	Unit.all_units.erase(unit)
	Unit.roster_version += 1
	unit.state = Unit.State.DEAD  # gone: shots already in flight find nothing here
	unit.visible = false
	unit.queue_free()
	return other
