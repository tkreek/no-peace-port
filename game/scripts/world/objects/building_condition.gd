class_name BuildingCondition
extends RefCounted
## A building's life: construction (the bob's construction-stage frames), energy and
## damage, flames as it weakens and the burnt-out picture below 40%, repair, and its end:
## destroyed into rubble, demolished, or packed onto a travois (tepees).
##
## AmericaAddOn.exe keeps energy in 1/256ths (the building at +4, its maximum at +0x578);
## the remake keeps whole points as floats.

## AmericaAddOn.exe (0x40c4b0) does a building's production time `t` (property 6, at least
## 1: 0x40ccd7) in steps of 51 of a worker's 20 ms ticks (the building's counter +0x594
## goes up by 20 for each worker each tick, a step when it passes 1000), each step adding
## max / t energy, so one worker takes t x 1.02 s and n workers 1/n of that.
const BUILD_STEP_SECONDS := 1.02
## A site starts at 1 point of energy (0x40c3f0: +4 = 0x100).
const SITE_ENERGY := 1.0
## A site nobody has worked on is lost after 10 minutes (0x40c3f0 sets +0x98 = 600000 ms;
## the building tick 0x40c0f0 deals 1 point when it runs out, which the site's 1 point does
## not survive; any builder's step, 0x40c4d8, stops the clock for good).
const SITE_ABANDON_SECONDS := 600.0
## Repairing (0x40c6bc) steps every 50 of a worker's ticks (1.00 s, the counter reaching
## 1000), each step restoring max / t and costing each resource's cost / t (whole units,
## 0x40c300: +0x15c..), the full price over a full repair; short of any, the worker stops
## and the owner hears 800-804 (0x40c71a..0x40c80d).
const REPAIR_STEP_SECONDS := 1.0
## Flames show once a blow takes the building below 90% (0x40c99c: flag 4 at +0x5a4 when
## energy < +0x580 = max * 90 / 100, 0x40c372), growing in four stages, a quarter of that
## each (+0xe4 = (0.9 max - energy) / (0.9 max / 4)); building or repairing past 90% puts
## them out (0x40c55e, 0x40c888). The burnt-out picture (anim 7, shadow 8) from a blow below
## 40% (flag 0x10, +0x584 = max * 40 / 100) until a repair takes it back to 40% (0x40c845).
## The fire is only a picture: it does no damage and does not spread (the tick 0x40c070
## only draws and sounds it), and no attack sets one (projectiles hit at 0x405510).
const FIRE_BELOW := 0.9
const BURNT_BELOW := 0.4
## Rubble lies 10 s (0x40cb66: +0x174 = 10000 ms, 0x40cc10), the footprint blocked until it
## goes (0x40cc38); fields go at once (+0x174 = 0).
const RUBBLE_SECONDS := 10.0
## The Del order (0x10000005, 0x456605) deals 5000 points: no refund of the cost or the queue.
const DEMOLISH_DAMAGE := 5000.0
const FIRE_BOB := "effects/fire/fire.anims.json"
## Ruins smoulder while they lie (two or three plumes, by the building's size), the smoke
## thinning away over the last two seconds (the remake's; the original draws none).
const SMOULDER_SECONDS := 10.0
const SMOKE_BOB := "effects/smoke/smoke.anims.json"
## fire.bob: 0 large, 1 medium, 2 small flames; 3-5 their clouds (large to small), drawn
## half blended over them; 6 a smoke column. Fire object 0x462140: size s (0 small .. 2
## large) is flame 2 - s with cloud 5 - s. At stage e (+0xe4) the building burns at e + 1
## spots (0x40d440): the first at size min(e, 2), the k-th after it at size k - 1.
const FIRE_STAGES := [[0], [1, 0], [2, 0, 1], [2, 0, 1, 2]]
const BURN_SOUND_SECONDS := 4.1  # 151 again every 4100 ms while it burns (0x40c920)

var building: MapObject
var site_timer := 0.0  ## seconds an untouched site has left (0: none, or work has begun)
var _aflame := false  # flag 4
var _burnt := false  # flag 0x10
var _fires: Array[OrderMarker] = []
var _fire_stage := -1
var _burn_sound := 0.0  ## until the fire is heard again (s)
var _build_time := 0.0  # worker-seconds towards the next construction step
var _repair_time := 0.0  # worker-seconds towards the next repair step


func _init(owner: MapObject) -> void:
	building = owner


func burnt() -> bool:
	return _burnt and building.health > 0.0


## Flames show (the building lost more than a tenth of its energy to blows).
func on_fire() -> bool:
	return _aflame and building.health > 0.0


func needs_repair() -> bool:
	return building.complete and building.health > 0.0 and building.health < building.max_health


func _production_time() -> float:
	return maxf(1.0, float(MapRules.stats(building.owner_index, building.guid).get("build_time", 0)))


## A new site: 1 point of energy, lost if nobody starts work on it within 10 minutes.
func start_site() -> void:
	building.health = SITE_ENERGY
	site_timer = SITE_ABANDON_SECONDS if not building.is_trap() else 0.0  # the pitfall's own start (0x41ecd0) sets no clock


## One step of the game for a site nobody has touched.
func tick_site(delta: float) -> void:
	site_timer -= delta
	if site_timer <= 0.0:
		site_timer = 0.0
		_hurt(1.0)


## Add construction work (worker-seconds); returns true when the building completes.
func add_build_work(seconds: float) -> bool:
	if building.complete:
		return true
	site_timer = 0.0
	_build_time += seconds
	var time := _production_time()
	while _build_time >= BUILD_STEP_SECONDS and not building.complete:
		_build_time -= BUILD_STEP_SECONDS
		building.build_progress = minf(1.0, building.build_progress + 1.0 / time)
		building.health = minf(building.max_health, building.health + building.max_health / time)
		if _aflame and building.health >= building.max_health * FIRE_BELOW:
			_aflame = false
		if building.build_progress >= 1.0 or building.health >= building.max_health:
			_finish()
			var builder: Player = Player.by_index.get(building.owner_index)
			if builder:
				builder.stats.built += 1
	building.refresh_sprites()
	building.redraw_overlay()
	update_fires()
	return building.complete


func _finish() -> void:
	building.complete = true
	building.build_progress = 1.0
	site_timer = 0.0
	_burnt = false  # the finished picture (0x40c649; flags back to 2)
	building.accepts = MapObject.drop_off_for(building.guid)
	building.refresh_sprites()
	if building.owner_index == Orders.local_player:  # only our own, as in the original
		Sound.play_event(building.guid, Sound.Event.FINISHED, building.position, 0)
	building.construction_finished.emit(building)


## A travois has set the tepee up again: it stands at once, as worn as when it was packed.
func finish_unpack(health_ratio: float) -> void:
	building.health = building.max_health * clampf(health_ratio, 0.05, 1.0)
	refresh_upgrades()
	_finish()
	_aflame = building.health < building.max_health * FIRE_BELOW
	_burnt = building.health < building.max_health * BURNT_BELOW
	building.refresh_sprites()
	update_fires()
	building.redraw_overlay()


## Repairing (worker-seconds): false when the owner cannot pay the next step.
func add_repair_work(seconds: float) -> bool:
	if not needs_repair():
		return true
	_repair_time += seconds
	while _repair_time >= REPAIR_STEP_SECONDS and needs_repair():
		var time := _production_time()
		var bill := {}
		var cost: Dictionary = MapRules.stats(building.owner_index, building.guid).get("cost", {})
		for key in ["food", "wood", "horses", "gold", "guns"]:  # the order the alerts are checked in
			var due := int(int(cost.get(key, 0)) / time)
			if due > 0:
				bill[key] = due
		var player: Player = Player.by_index.get(building.owner_index)
		if not bill.is_empty():
			if player == null or not player.can_afford(bill):
				if player and building.owner_index == Orders.local_player:
					player.alert_shortage(bill)
				return false
			player.spend(bill)
		_repair_time -= REPAIR_STEP_SECONDS
		var was_burnt := burnt()
		building.health = minf(building.max_health, building.health + building.max_health / time)
		if _burnt and building.health >= building.max_health * BURNT_BELOW:
			_burnt = false
		if _aflame and building.health >= building.max_health * FIRE_BELOW:
			_aflame = false
		if was_burnt != burnt():
			building.refresh_sprites()
	building.redraw_overlay()
	update_fires()
	return true


## Energy upgrades for this building's type (none of the original's upgrades is one: Thick
## boards is the wagons', 0x40db80 gives the towers only sight).
func refresh_upgrades() -> void:
	var player: Player = Player.by_index.get(building.owner_index)
	if player == null or not building.complete:
		return
	var base := float(MapRules.stats(building.owner_index, building.guid).get("health", building.max_health))
	var ratio := building.health / building.max_health if building.max_health > 0 else 1.0
	building.max_health = base * (1.0 + player.bonus(building.guid, "health_pct") / 100.0)
	building.health = building.max_health * ratio


func take_damage(amount: float, attacker: Node2D) -> void:
	if building.health <= 0.0:
		return
	var people: Player = Player.by_index.get(building.owner_index)
	if people:
		people.alert_attacked(building, attacker)
	if _hurt(amount) and attacker is Unit and is_instance_valid(attacker):
		var victor: Player = Player.by_index.get(attacker.team)
		if victor:
			victor.stats.razed += 1


## The original's take-damage (0x40c970): energy down, the fire and burnt-out flags, the end
## at none left. True when this destroyed the building.
func _hurt(amount: float) -> bool:
	if building.health <= 0.0:
		return false
	if building.health <= amount:
		building.health = 0.0
		building.redraw_overlay()
		destroy()
		return true
	var was_burnt := burnt()
	building.health -= amount
	if building.health < building.max_health * FIRE_BELOW:
		_aflame = true
	if building.health < building.max_health * BURNT_BELOW:
		_burnt = true
	building.redraw_overlay()
	update_fires()
	if was_burnt != burnt():
		building.refresh_sprites()
	return false


# ------------------------------------------------------------------ fire

## The fire's stage (0x40c9bd: a quarter of 90% of the energy each), -1 for none.
func fire_stage() -> int:
	if not on_fire():
		return -1
	var line := building.max_health * FIRE_BELOW
	return clampi(int((line - building.health) / (line / 4.0)), 0, FIRE_STAGES.size() - 1)


## Flames (and their clouds) for the fire's stage.
func update_fires() -> void:
	var stage := fire_stage()
	if stage == _fire_stage:
		return
	_fire_stage = stage
	for fire in _fires:
		if is_instance_valid(fire):
			fire.queue_free()
	_fires.clear()
	if stage < 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = building.get_instance_id()
	for size: int in FIRE_STAGES[stage]:
		var spot := building.fire_spot(rng) - building.position
		_fires.append(OrderMarker.effect_loop(building, spot, FIRE_BOB, 2 - size))
		var cloud := OrderMarker.effect_loop(building, spot, FIRE_BOB, 5 - size)
		cloud.modulate.a = 0.5  # drawn half blended (0x4622f0 -> 0x4637d0)
		_fires.append(cloud)


## One step of the game while it burns: heard every 4.1 s, the first time at once.
func burn(delta: float) -> void:
	_burn_sound -= delta
	if _burn_sound <= 0.0:
		_burn_sound = BURN_SOUND_SECONDS
		Sound.play_event(building.guid, Sound.Event.BURNING, building.position, 0, building.get_instance_id(), Sound.WORK_RANGE)


## The original has no fires that attacks set: a flaming arrow is a blow like any other.
## (Kept, with the list of the flaming arrow shooters, so that callers may still ask; it
## does nothing.)
const FIRE_STARTERS := [154, 158, 159, 276, 277]  # canoe, flaming arrow shooters, Gall
func ignite(_seconds := 0.0) -> void:
	pass


## Saved games: the fire and burnt-out flags (they depend on the blows, not only the energy).
func save_flags() -> Array:
	return [_aflame, _burnt, site_timer]


func restore_flags(flags) -> void:
	if flags is Array and flags.size() >= 3:
		_aflame = bool(flags[0])
		_burnt = bool(flags[1])
		site_timer = float(flags[2])
	else:
		_aflame = building.health < building.max_health * FIRE_BELOW
		_burnt = building.complete and building.health < building.max_health * BURNT_BELOW
		if building.complete:
			site_timer = 0.0


# ------------------------------------------------------------------ the end

## Tear the building down (Del): 5000 points of damage, as the original's order deals
## (0x456605); nothing is refunded, neither the cost nor the queue (as when it is destroyed).
func demolish() -> void:
	if building.health <= 0.0:
		return
	_hurt(DEMOLISH_DAMAGE)


## Destroyed: the quartered units step out unhurt (0x40cadc -> 0x40d7b0), the queue is lost
## (0x40cbac), the rubble lies 10 s and then goes, freeing the ground.
func destroy() -> void:
	building.health = 0.0
	building.defence.release()
	_aflame = false
	_burnt = false
	Sound.play_event(building.guid, Sound.Event.RUBBLE, building.position, 0)
	building.production.queue.clear()
	building.accepts = PackedStringArray()
	building.selected = false
	building.destroyed.emit(building)
	update_fires()
	var rubble := building.refresh_sprites() and building.shows_rubble()
	var tween := building.create_tween()
	if rubble:
		_smoulder()
		tween.tween_interval(RUBBLE_SECONDS - 1.0)
		tween.tween_property(building, "modulate", Color(1, 1, 1, 0.0), 1.0)
	else:
		tween.tween_property(building, "modulate", Color(0.3, 0.25, 0.2, 0.0), 2.5)
	var gone := building
	Sim.after(RUBBLE_SECONDS, func() -> void:  # on the same step everywhere
		if is_instance_valid(gone):
			if NavGrid.current:
				NavGrid.current.unblock_footprint(gone.object_type, gone.position)
			gone.queue_free())


func _smoulder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = building.get_instance_id() + 3
	var plumes := 3 if building.footprint_rect().size.x > 128.0 else 2
	for i in plumes:
		var plume := OrderMarker.effect_loop(building, building.fire_spot(rng) - building.position, SMOKE_BOB, 0)
		var tween := plume.create_tween()
		tween.tween_interval(SMOULDER_SECONDS - 2.0)
		tween.tween_property(plume, "modulate:a", 0.0, 2.0)
		tween.tween_callback(plume.queue_free)


## Packing (a Native tepee onto a travois) or a cancelled set-up: the building leaves
## without rubble. Quartered units step out and queued orders are refunded.
func vanish() -> void:
	building.defence.release()
	_aflame = false
	update_fires()
	building.production.cancel_all()
	if NavGrid.current:
		NavGrid.current.unblock_footprint(building.object_type, building.position)
	building.selected = false
	building.health = 0.0
	building.accepts = PackedStringArray()
	building.forget()
	building.queue_free()
