class_name BuildingCondition
extends RefCounted
## A building's life: construction (the bob's construction-stage frames), energy and
## damage, flames and smoke as it weakens and the burnt-out picture below a third, fire
## from flaming arrows that eats it and spreads, repair, and its end: destroyed into
## rubble, demolished, or packed onto a travois (tepees).

## Worker-seconds of building work per point of structure energy, when the data gives none.
const BUILD_WORK_PER_HEALTH := 0.05
const BURNT_BELOW := 0.33
const FIRE_BELOW := 0.66
const RUBBLE_SECONDS := 25.0
const FIRE_BOB := "effects/fire/fire.anims.json"
## Ruins smoulder while they lie (two or three plumes, by the building's size).
const SMOKE_BOB := "effects/smoke/smoke.anims.json"
## fire.bob: 0 large, 1 medium, 2 small flames; 3-5 clouds; 6 smoke column.
const FIRE_STAGES := [[], [2, 6], [2, 1, 0, 6]]
## Flaming arrows "set fortifications and houses on fire" (manual 5.1): a hit sets the
## building alight for a while; the fire eats its energy and can leap to the buildings next
## to it. A builder at work on it puts the fire out.
const FIRE_STARTERS := [154, 158, 159, 276, 277]  # canoe, flaming arrow shooters, Gall
const BURN_SECONDS := 20.0
const BURN_DAMAGE := 3.0  # energy per second
const SPREAD_REACH := 48.0  # between the walls of neighbouring buildings (their margins keep 32 apart)
const SPREAD_CHANCE := 0.06  # per second, for each neighbour

var building: MapObject
var burning := 0.0  ## seconds the fire still burns
var _fires: Array[OrderMarker] = []
var _fire_stage := 0
var _flame: OrderMarker
var _burn_tick := 0.0
var _build_sound_played := false
var _repair_debt := 0.0


func _init(owner: MapObject) -> void:
	building = owner


func burnt() -> bool:
	return building.complete and building.health < building.max_health * BURNT_BELOW


func needs_repair() -> bool:
	return building.complete and building.health > 0.0 and (building.health < building.max_health or burning > 0.0)


func _total_work() -> float:
	return maxf(5.0, float(GameData.stats(building.guid).get("build_time", building.max_health * BUILD_WORK_PER_HEALTH)))


## Add construction work (worker-seconds); returns true when the building completes.
func add_build_work(seconds: float) -> bool:
	if building.complete:
		return true
	if not _build_sound_played:
		_build_sound_played = true  # the construction sound plays once, when work begins
		Sound.play_event(building.guid, Sound.Event.BUILD, building.position, 0, building.get_instance_id(), Sound.WORK_RANGE)
	# Worker-seconds: the original production time (one worker), else scaled by energy.
	building.build_progress = minf(1.0, building.build_progress + seconds / _total_work())
	building.health = maxf(building.health, building.max_health * (0.1 + 0.9 * building.build_progress))
	building.refresh_sprites()
	building.redraw_overlay()
	if building.build_progress >= 1.0:
		_finish()
		var builder: Player = Player.by_index.get(building.owner_index)
		if builder:
			builder.stats.built += 1
	return building.complete


func _finish() -> void:
	building.complete = true
	building.build_progress = 1.0
	building.accepts = MapObject.drop_off_for(building.guid)
	building.refresh_sprites()
	Sound.play_event(building.guid, Sound.Event.FINISHED, building.position, 0)
	building.construction_finished.emit(building)


## A travois has set the tepee up again: it stands at once, as worn as when it was packed.
func finish_unpack(health_ratio: float) -> void:
	building.health = building.max_health * clampf(health_ratio, 0.05, 1.0)
	refresh_upgrades()
	_finish()
	update_fires()
	building.redraw_overlay()


## Repairing (manual 3.5): a builder restores energy at the construction pace, paying the
## share of the building's cost that the restored energy represents (at half price).
func add_repair_work(seconds: float) -> bool:
	extinguish()
	var max_health := building.max_health
	var restore := minf(max_health - building.health, max_health * seconds / _total_work())
	var cost: Dictionary = GameData.stats(building.guid).get("cost", {})
	_repair_debt += restore / max_health * 0.5  # settled in whole units
	var bill := {}
	for key in cost:
		if Player.RESOURCES.has(key):
			var due := int(float(cost[key]) * _repair_debt)
			if due > 0:
				bill[key] = due
	if not bill.is_empty():
		var player: Player = Player.by_index.get(building.owner_index)
		if player == null or not player.spend(bill):
			return false
		_repair_debt = 0.0
	var was_burnt := burnt()
	building.health += restore
	building.redraw_overlay()
	update_fires()
	if was_burnt != burnt():
		building.refresh_sprites()
	return true


## Energy upgrades (e.g. "Thick boards", tower upgrades) for this building's type.
func refresh_upgrades() -> void:
	var player: Player = Player.by_index.get(building.owner_index)
	if player == null or not building.complete:
		return
	var base := float(GameData.stats(building.guid).get("health", building.max_health))
	var ratio := building.health / building.max_health if building.max_health > 0 else 1.0
	building.max_health = base * (1.0 + player.bonus(building.guid, "health_pct") / 100.0)
	building.health = building.max_health * ratio


func take_damage(amount: float, attacker: Node2D) -> void:
	if building.health <= 0.0:
		return
	var was_burnt := burnt()
	building.health = maxf(0.0, building.health - amount)
	building.redraw_overlay()
	var people: Player = Player.by_index.get(building.owner_index)
	if people:
		people.alert_attacked(building, attacker)
	if building.health <= 0.0:
		if attacker is Unit and is_instance_valid(attacker):
			var victor: Player = Player.by_index.get(attacker.team)
			if victor:
				victor.stats.razed += 1
		destroy()
		return
	update_fires()
	if was_burnt != burnt():
		building.refresh_sprites()


# ------------------------------------------------------------------ fire

## Flames and smoke grow as the building loses energy (none above two thirds).
func update_fires() -> void:
	var ratio := building.health / building.max_health if building.max_health > 0.0 else 1.0
	var stage := 0
	if building.complete and building.health > 0.0:
		stage = 2 if ratio < BURNT_BELOW else (1 if ratio < FIRE_BELOW else 0)
	if stage == _fire_stage:
		return
	if stage > _fire_stage:
		Sound.play_event(building.guid, Sound.Event.BURNING, building.position, 0, building.get_instance_id(), Sound.WORK_RANGE)
	_fire_stage = stage
	for fire in _fires:
		if is_instance_valid(fire):
			fire.queue_free()
	_fires.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = building.get_instance_id()
	for anim in FIRE_STAGES[stage]:
		_fires.append(OrderMarker.effect_loop(building, building.fire_spot(rng) - building.position, FIRE_BOB, anim))


func ignite(seconds := BURN_SECONDS) -> void:
	if building.is_trap() or building.health <= 0.0:
		return
	burning = maxf(burning, seconds)
	building.set_process(true)
	if not is_instance_valid(_flame):
		var rng := RandomNumberGenerator.new()
		rng.seed = building.get_instance_id() + 7
		_flame = OrderMarker.effect_loop(building, building.fire_spot(rng) - building.position, FIRE_BOB, 1)
		Sound.play_event(building.guid, Sound.Event.BURNING, building.position, 0, building.get_instance_id(), Sound.WORK_RANGE)


func extinguish() -> void:
	burning = 0.0
	if is_instance_valid(_flame):
		_flame.queue_free()
	_flame = null


func burn(delta: float) -> void:
	burning -= delta
	_burn_tick += delta
	if _burn_tick >= 1.0:
		_burn_tick -= 1.0
		take_damage(BURN_DAMAGE, null)
		var walls := building.work_rect().grow(SPREAD_REACH)
		for other in MapObject.structures:
			if other != building and other.is_building() and other.condition.burning <= 0.0 and other.is_alive() \
					and walls.intersects(other.work_rect()) and randf() < SPREAD_CHANCE:
				other.condition.ignite()
	if burning <= 0.0 or building.health <= 0.0:
		extinguish()


# ------------------------------------------------------------------ the end

## Tear the building down (Del). Queued orders are refunded, and so is the part of the
## construction cost not yet built into an unfinished site.
func demolish() -> void:
	if building.health <= 0.0:
		return
	building.production.cancel_all()
	var player: Player = Player.by_index.get(building.owner_index)
	if player and not building.complete:
		var cost: Dictionary = GameData.stats(building.guid).get("cost", {})
		for key in cost:
			if Player.RESOURCES.has(key):
				player.add(key, int(int(cost[key]) * (1.0 - building.build_progress)))
	building.health = 0.0
	destroy()


## Destroyed: the quartered units escape, the rubble lies for a while and fades.
func destroy() -> void:
	building.defence.release()
	extinguish()
	Sound.play_event(building.guid, Sound.Event.RUBBLE, building.position, 0)
	building.production.queue.clear()
	building.accepts = PackedStringArray()
	if NavGrid.current:
		NavGrid.current.unblock_footprint(building.object_type, building.position)
	building.selected = false
	building.destroyed.emit(building)
	update_fires()
	var rubble := building.refresh_sprites() and building.shows_rubble()
	var tween := building.create_tween()
	if rubble:
		_smoulder()
		tween.tween_interval(RUBBLE_SECONDS)
		tween.tween_property(building, "modulate", Color(1, 1, 1, 0.0), 3.0)
	else:
		tween.tween_property(building, "modulate", Color(0.3, 0.25, 0.2, 0.0), 2.5)
	tween.tween_callback(building.queue_free)


func _smoulder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = building.get_instance_id() + 3
	var plumes := 3 if building.footprint_rect().size.x > 128.0 else 2
	for i in plumes:
		OrderMarker.effect_loop(building, building.fire_spot(rng) - building.position, SMOKE_BOB, 0)


## Packing (a Native tepee onto a travois) or a cancelled set-up: the building leaves
## without rubble. Quartered units step out and queued orders are refunded.
func vanish() -> void:
	building.defence.release()
	extinguish()
	building.production.cancel_all()
	if NavGrid.current:
		NavGrid.current.unblock_footprint(building.object_type, building.position)
	building.selected = false
	building.health = 0.0
	building.accepts = PackedStringArray()
	building.forget()
	building.queue_free()
