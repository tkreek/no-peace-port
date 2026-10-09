class_name MapObject
extends Node2D
## A placed object (building or scenery) drawn from its original sprite and shadow.
## Buildings can be under construction (the bob's construction-stage frames), have health,
## and train units from a queue.

signal construction_finished(building: MapObject)
signal unit_trained(building: MapObject, unit_guid: int)
signal destroyed(building: MapObject)

const TREE_WOOD := 150
const MINE_GOLD := 3000
## Worker-seconds of building work per point of structure energy.
const BUILD_WORK_PER_HEALTH := 0.05
const TRAIN_SECONDS := {"default": 14.0, "worker": 9.0}
const QUEUE_LIMIT := 5
const UPGRADE_SECONDS := 60.0

## Drop-off buildings by GUID (main buildings take everything).
const MAIN_BUILDINGS := [100, 200, 300, 400]
const DROP_OFFS := {
	"wood": [109, 209, 309, 409],          # wood processing, sawmills, carpentry shop
	"gold": [104, 206, 304, 419],          # gold warehouses
	"food": [108, 208, 408, 102, 202, 302, 402],  # granary, finca, farm; butchers / stockyard
}
const FOOD_STORES := [108, 208, 408]
const FIELD_GUID := 149
## Horses are raised at the corral (Native, outlaw), hacienda and ranch, which shelter five
## each ("zero of five possible horses"); mounted units cost one.
const HORSE_GUID := 9001
## Cattle (manual 2.5): raised at the hacienda and ranch, sold alive at animal processing.
const COW_GUID := 9002
const COW_BUILDINGS := [205, 405]
const ANIMAL_PROCESSING := [102, 202, 302, 402]
## The trading buildings (Native and Mexican trading post, outlaw drugstore, American
## general store) and their six trades.
const TRADE_BUILDINGS := [106, 210, 310, 410]
const TRADE_GUID := 9101
const TRADES := [
	{"good": "food", "buy": true, "icon": 50}, {"good": "food", "buy": false, "icon": 42},
	{"good": "wood", "buy": true, "icon": 46}, {"good": "wood", "buy": false, "icon": 38},
	{"good": "guns", "buy": true, "icon": 52}, {"good": "guns", "buy": false, "icon": 44},
]
const TRADE_QUEUE_LIMIT := 10
const HORSE_BUILDINGS := [105, 205, 305, 405]
const HORSES_PER_BUILDING := 5
const GOLD_MINE_GUID := 700  # selection sound "sound goldmine"
const FIELDS_PER_STORE := 5
const DISTILLERY_GUID := 308

## Trees: standing, felled (a trunk lying on the ground while its wood is cut up) and
## removed (a stump). The tree bobs hold these as frames 12 and 13 (anim pairs 24/25, 26/27).
enum TreeState { STANDING, FELLED, STUMP }
const TREE_FELLED_ANIM := 24
const TREE_STUMP_ANIM := 26

## Fields: fallow -> sown by a woman -> grow -> ripe, harvested down to fallow again.
enum Field { FALLOW, GROWING, RIPE }
const FIELD_SOW_WORK := 8.0     # woman-seconds
const FIELD_GROW_SECONDS := 45.0
const FIELD_YIELD := 300
const FIELD_STAGES := [3, 0, 1, 2]  # frames of anim 0: ploughed, sprouting, growing, ripe
## Distillery: turns wood into food (the outlaws' liquor) while wood lasts.
const DISTILL_SECONDS := 15.0
const DISTILL_WOOD := 20
const DISTILL_FOOD := 40

static var all_objects: Array[MapObject] = []

var object_type: ObjectTypes.ObjectType
var is_ghost := false  ## placement preview: not part of the world
var owner_index := 0
var guid := -1
var amount := 0
var resource := ""  ## "wood" or "gold" for harvestable scenery, "" otherwise
var accepts: PackedStringArray = []  ## resources a building takes as a drop-off
var selected := false:
	set(value):
		selected = value
		_overlay.queue_redraw()
var max_health := 0.0
var health := 0.0
var complete := true
var build_progress := 1.0  # 0..1 while under construction
var queue: PackedInt32Array = []  # unit GUIDs waiting to be trained
var train_progress := 0.0  # 0..1 for queue[0]
var tree_state := TreeState.STANDING
var field_state := Field.FALLOW
var field_progress := 0.0  # sowing work done, then growth (0..1)
var _distill_timer := 0.0
## Gold mines: worker-seconds spent inside; the entrance gets timbered as work goes on.
var mine_work := 0.0
const MINE_FRAMED_AFTER := 12.0  # worker-seconds until the timbered entrance is finished

var _bob: BobFile
var _body: Sprite2D
var _shadow: Sprite2D
var _palette: Texture2D
var _ramps: Texture2D
var _overlay := DrawOverlay.new()
var _work_rect := Rect2()


func _enter_tree() -> void:
	if not is_ghost:
		all_objects.append(self)


func _exit_tree() -> void:
	all_objects.erase(self)


var _flash_time := 0.0
var _flash_color := Color.WHITE


## Briefly pulse the object and ring it, to confirm it was picked as an order's target.
func flash(color := Color(1.0, 0.9, 0.4)) -> void:
	_flash_time = 1.0
	_flash_color = color
	set_process(true)


func is_alive() -> bool:
	return not is_building() or health > 0.0


func take_damage(amount: float, attacker: Node2D = null) -> void:
	if not is_building() or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_overlay.queue_redraw()
	if health <= 0.0:
		if attacker is Unit and is_instance_valid(attacker):
			var victor: Player = Player.by_index.get(attacker.team)
			if victor:
				victor.stats.razed += 1
		_destroy()
		return
	_update_fires()
	if health < max_health * BURNT_BELOW and _body_anim != BURNT_ANIM:
		_refresh_sprites()


func capacity() -> int:
	return int(GameData.stats(guid).get("capacity", 0)) if is_building() and complete and health > 0.0 else 0


func has_room_for(unit: Unit) -> bool:
	return unit.team == owner_index and garrison.size() < capacity()


func enter(unit: Unit) -> bool:
	if not has_room_for(unit):
		return false
	garrison.append(unit)
	unit.enter_quarters(self)
	set_process(true)
	_overlay.queue_redraw()
	return true


## Send quartered units back outside, below the building (all of them, or just `which`).
func release(which: Unit = null) -> void:
	for unit in garrison.duplicate():
		if which != null and unit != which:
			continue
		garrison.erase(unit)
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		var rect := footprint_rect()
		var spot := Vector2(rect.get_center().x + randf_range(-24, 24), rect.end.y + 8)
		if NavGrid.current:
			var cell := NavGrid.current.nearest_walkable(NavGrid.current.cell_of(spot))
			spot = (Vector2(cell) + Vector2(0.5, 0.5)) * NavGrid.CELL
		unit.leave_quarters(spot)


## Quartered riflemen and archers fire out at the nearest enemy each can reach.
func _update_garrison(delta: float) -> void:
	_garrison_scan -= delta
	for unit in garrison.duplicate():
		if not is_instance_valid(unit):
			garrison.erase(unit)
	if _garrison_scan > 0.0:
		return
	_garrison_scan = 0.25
	var centre := work_rect().get_center()
	for unit in garrison:
		if not unit.unit_type.ranged or unit.unit_type.attack_anims.is_empty() or not unit.ready_to_fire():
			continue
		var reach := unit.attack_range() + GARRISON_RANGE_BONUS
		var best: Node2D = null
		var best_distance := reach
		for other in Unit.all_units:
			if other.is_alive() and not other.inside and other.team > 0 and other.team != owner_index:
				var d := centre.distance_to(other.position)
				if d < best_distance:
					best = other
					best_distance = d
		if best:
			unit.fire_from_quarters(best, centre)


func is_gold_warehouse() -> bool:
	return guid in DROP_OFFS.gold and guid not in MAIN_BUILDINGS


func store_gold(amount_in: int) -> void:
	stored_gold += amount_in
	var player: Player = Player.by_index.get(owner_index)
	if player:
		player.resources_changed.emit()


func take_gold(wanted: int) -> int:
	var taken := mini(wanted, stored_gold)
	stored_gold -= taken
	if taken > 0:
		var player: Player = Player.by_index.get(owner_index)
		if player:
			player.resources_changed.emit()
	return taken


func needs_repair() -> bool:
	return is_building() and complete and health > 0.0 and health < max_health


## Repairing (manual 3.5): a builder restores energy at the construction pace, paying the
## share of the building's cost that the restored energy represents.
func add_repair_work(seconds: float) -> bool:
	var total := maxf(5.0, float(GameData.stats(guid).get("build_time", max_health * BUILD_WORK_PER_HEALTH)))
	var restore := minf(max_health - health, max_health * seconds / total)
	var cost: Dictionary = GameData.stats(guid).get("cost", {})
	var player: Player = Player.by_index.get(owner_index)
	_repair_debt += restore / max_health * 0.5  # half price, settled in whole units
	var bill := {}
	for key in cost:
		if Player.RESOURCES.has(key):
			var due := int(float(cost[key]) * _repair_debt)
			if due > 0:
				bill[key] = due
	if not bill.is_empty():
		if player == null or not player.spend(bill):
			return false
		_repair_debt = 0.0
	health += restore
	_overlay.queue_redraw()
	_update_fires()
	if health >= max_health * BURNT_BELOW and _body_anim == BURNT_ANIM:
		_refresh_sprites()
	return true


var _repair_debt := 0.0


## The Native pitfall (manual): crossed safely by its own people, deadly to enemies, hidden
## from them unless a detector sees it, spent after three kills.
const PITFALL_GUID := 114
const PITFALL_KILLS := 3
var trap_kills := 0
var _trap_scan := 0.0


func is_trap() -> bool:
	return guid == PITFALL_GUID


func _spring_trap(delta: float) -> void:
	_trap_scan -= delta
	if _trap_scan > 0.0:
		return
	_trap_scan = 0.2
	var pit := footprint_rect().get_center()
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team > 0 and unit.team != owner_index and not unit.inside \
				and not unit.unit_type.is_transport() and unit.position.distance_to(pit) < 30.0:
			unit.take_damage(unit.max_health * 10.0, self)
			trap_kills += 1
			if trap_kills >= PITFALL_KILLS:
				health = 0.0
				_destroy()
				return


## Abandoned warehouses (manual 4.3): neutral stores of guns or gold scattered over the
## map; transports empty them into their people's main building.
const ABANDONED_STORES := [26, 56, 299, 300]  # object types: USA_Lager, MEX_Magazin
var loot_kind := ""
var loot := 0


func is_abandoned_store() -> bool:
	return object_type != null and object_type.id in ABANDONED_STORES


func stock_abandoned_store(content: int, how_much: int) -> void:
	loot_kind = "gold" if content == 0x130 else "guns"
	loot = how_much


## What a transport can haul from here: a gold warehouse's gold or an abandoned store's goods.
func haul_kind() -> String:
	return loot_kind if is_abandoned_store() else "gold"


func haul_available() -> int:
	return loot if is_abandoned_store() else stored_gold


func take_haul(wanted: int) -> int:
	if is_abandoned_store():
		var taken := mini(wanted, loot)
		loot -= taken
		return taken
	return take_gold(wanted)


## Tear the building down (Del). Queued orders are refunded, and so is the part of the
## construction cost not yet built into an unfinished site.
func demolish() -> void:
	if not is_building() or health <= 0.0:
		return
	while not queue.is_empty():
		cancel_queued(queue.size() - 1)
	var player: Player = Player.by_index.get(owner_index)
	if player and not complete:
		var cost: Dictionary = GameData.stats(guid).get("cost", {})
		for key in cost:
			if Player.RESOURCES.has(key):
				player.add(key, int(int(cost[key]) * (1.0 - build_progress)))
	health = 0.0
	_destroy()


func _destroy() -> void:
	release()  # the quartered units escape the ruins
	Sound.play_event(guid, Sound.Event.RUBBLE, position, 0)
	queue.clear()
	accepts = PackedStringArray()
	if NavGrid.current:
		NavGrid.current.unblock_footprint(object_type, position)
	selected = false
	destroyed.emit(self)
	_update_fires()
	_refresh_sprites()  # the rubble, where the building has one
	var tween := create_tween()
	if _body_anim == RUBBLE_ANIM:
		tween.tween_interval(RUBBLE_SECONDS)
		tween.tween_property(self, "modulate", Color(1, 1, 1, 0.0), 3.0)
	else:
		tween.tween_property(self, "modulate", Color(0.3, 0.25, 0.2, 0.0), 2.5)
	tween.tween_callback(queue_free)


func is_building() -> bool:
	return object_type != null and (object_type.kind == ObjectTypes.Kind.BUILDING or guid == PITFALL_GUID) \
			and guid != FIELD_GUID


func is_field() -> bool:
	return guid == FIELD_GUID


func is_mine() -> bool:
	return object_type != null and object_type.name.begins_with("Mine")


## Workers inside a mine build up its timber entrance (original frames: bare, framing, timbered).
func add_mine_work(seconds: float) -> void:
	var before := _mine_stage()
	mine_work += seconds
	_keep_mine_sound()
	if _mine_stage() != before:
		_refresh_sprites()


var _mine_sound: AudioStreamPlayer2D
var _mine_heard := 0  # msec of the last work inside


## Picks and rubble from inside a worked mine ("sound goldmine"), heard from afar and
## through the fog; it keeps going while anyone works inside and stops soon after.
func _keep_mine_sound() -> void:
	_mine_heard = Time.get_ticks_msec()
	if _mine_sound == null:
		_mine_sound = Sound.work_emitter("sound goldmine")
		if _mine_sound == null:
			return
		_mine_sound.position = work_rect().get_center() - position
		add_child(_mine_sound)
		_mine_sound.finished.connect(func() -> void:
			if Time.get_ticks_msec() - _mine_heard < 1500 and amount > 0:
				_mine_sound.pitch_scale = randf_range(0.94, 1.06)
				_mine_sound.play())
	if not _mine_sound.playing:
		_mine_sound.play()


## 0 untouched, 1 framing going up, 2 timbered entrance, 3 boarded up (exhausted).
func _mine_stage() -> int:
	if amount <= 0:
		return 3
	if mine_work <= 0.0:
		return 0
	return 1 if mine_work < MINE_FRAMED_AFTER else 2


## Add sowing work; returns true once the field is sown and starts growing.
## Hail (medicine man): the crop is lost and the field must be sown again.
func ruin_crop() -> void:
	field_state = Field.FALLOW
	field_progress = 0.0
	amount = 0
	_refresh_sprites()


## Rain (medicine man): a ripe field holds half as much again; a growing one will.
var _rained := false


func rain() -> void:
	if field_state == Field.RIPE:
		amount = int(amount * 1.5)
	else:
		_rained = true


func sow(seconds: float) -> bool:
	if field_state != Field.FALLOW:
		return true
	field_progress += seconds / FIELD_SOW_WORK
	if field_progress >= 1.0:
		field_state = Field.GROWING
		field_progress = 0.0
	_refresh_sprites()
	return field_state != Field.FALLOW


func display_name() -> String:
	if is_tree():
		return "Tree"
	return GameData.type_name(object_type.id) if object_type else "?"


## Footprint rectangle in world space (for arrival checks and placement).
func footprint_rect() -> Rect2:
	return footprint_rect_for(object_type, position)


## Whether a click at `point` (world) lands on this object: on a solid pixel of its picture
## (walls, roof, canopy), or on its walls' ground area.
func hit(point: Vector2) -> bool:
	if work_rect().grow(4).has_point(point):
		return true
	if _body == null or _body.texture == null or not visual_rect().has_point(point):
		return false
	return _body.is_pixel_opaque(_body.to_local(point))


## Where the object's current picture is drawn, in world coordinates (canopy, roof...).
func visual_rect() -> Rect2:
	if _body == null or _body.texture == null:
		return footprint_rect()
	return _body.get_global_transform() * _body.get_rect()


## The solid part of the footprint (trunk, walls, mine entrance): where workers stand at.
## The full footprint grid also covers the empty space around the sprite.
func work_rect() -> Rect2:
	if is_field():
		# A field has no walls: its furrows fill the middle of the footprint.
		var rect := footprint_rect()
		return rect.grow_individual(-rect.size.x * 0.25, -rect.size.y * 0.25, -rect.size.x * 0.25, -rect.size.y * 0.25)
	if _work_rect.size == Vector2.ZERO:
		_work_rect = footprint_rect()
		if object_type and not object_type.footprint_cells.is_empty():
			var grid := object_type.footprint_grid
			var low := Vector2i(grid.x, grid.y)
			var high := Vector2i(-1, -1)
			for i in object_type.footprint_cells.size():
				if object_type.footprint_cells[i] & NavGrid.SOLID:
					var c := Vector2i(i % grid.x, i / grid.x)
					low = Vector2i(mini(low.x, c.x), mini(low.y, c.y))
					high = Vector2i(maxi(high.x, c.x), maxi(high.y, c.y))
			if high.x >= 0:
				var origin := footprint_rect().position
				_work_rect = Rect2(origin + Vector2(low * NavGrid.CELL), Vector2(high - low + Vector2i.ONE) * NavGrid.CELL)
	return _work_rect


static func footprint_rect_for(type: ObjectTypes.ObjectType, at: Vector2) -> Rect2:
	if type == null or type.footprint_size == Vector2i.ZERO:
		return Rect2(at - Vector2(16, 16), Vector2(32, 32))
	return Rect2(at - Vector2(type.footprint_anchor), Vector2(type.footprint_size))


## Take up to `wanted` units of this object's resource; removes depleted trees.
func harvest(wanted: int) -> int:
	if is_field() and field_state != Field.RIPE:
		return 0
	var taken := mini(wanted, amount)
	amount -= taken
	if is_mine() and amount <= 0:
		_refresh_sprites()
	if is_field():
		if amount <= 0:
			field_state = Field.FALLOW
			resource = "food"
		_refresh_sprites()
	if resource == "wood" and is_tree():
		if amount <= 0:
			# All wood taken: only the stump remains, and the ground is passable again.
			tree_state = TreeState.STUMP
			resource = ""
			if NavGrid.current:
				NavGrid.current.unblock_footprint(object_type, position)
		elif tree_state == TreeState.STANDING:
			tree_state = TreeState.FELLED  # the first cut brings the tree down
		_refresh_sprites()
	elif amount <= 0 and resource == "wood":
		if NavGrid.current:
			NavGrid.current.unblock_footprint(object_type, position)
		resource = ""
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 1.5)
		tween.tween_callback(queue_free)
	return taken


## Saved games: what is left of a tree or mine.
func restore_resource(left: int, state: int, work: float) -> void:
	amount = left
	mine_work = work
	if is_tree():
		tree_state = state as TreeState
		if tree_state == TreeState.STUMP:
			resource = ""
			if NavGrid.current:
				NavGrid.current.unblock_footprint(object_type, position)
	_refresh_sprites()


## Saved games: a building's or field's state.
func restore_state(entry: Dictionary) -> void:
	complete = bool(entry.complete)
	build_progress = float(entry.progress)
	health = float(entry.health)
	queue = PackedInt32Array(entry.queue.map(func(v) -> int: return int(v)))
	train_progress = float(entry.train)
	rally_point = Vector2(entry.rally[0], entry.rally[1]) if entry.rally != null else Vector2.INF
	stored_gold = int(entry.stored_gold)
	trap_kills = int(entry.trap_kills)
	loot_kind = entry.get("loot_kind", "")
	loot = int(entry.get("loot", 0))
	if is_field():
		field_state = int(entry.field_state) as Field
		field_progress = float(entry.field_progress)
		amount = int(entry.amount)
	if complete and is_building():
		accepts = _drop_off_for(guid)
	_refresh_sprites()
	_update_fires()
	_overlay.queue_redraw()


func is_tree() -> bool:
	return object_type != null and object_type.name.begins_with("Baum") and _bob != null \
			and _bob.anims.size() > TREE_STUMP_ANIM + 1


func setup(type: ObjectTypes.ObjectType, owner: int, placed_amount := 0, under_construction := false) -> bool:
	object_type = type
	owner_index = owner
	guid = GameData.guid_for_type(type.id)
	if guid == FIELD_GUID:
		resource = "food"
		amount = 0
	elif type.name.begins_with("Baum"):
		resource = "wood"
		amount = TREE_WOOD
	elif type.name.begins_with("Mine"):
		resource = "gold"
		amount = placed_amount if placed_amount > 0 else MINE_GOLD
	elif type.kind == ObjectTypes.Kind.BUILDING or guid == PITFALL_GUID:
		max_health = GameData.stats(guid).get("health", 1000)
		health = max_health
		if under_construction:
			complete = false
			build_progress = 0.0
			health = max_health * 0.1
		else:
			accepts = _drop_off_for(guid)
	_bob = GameData.load_bob(type.bob_path)
	if _bob == null or _bob.anims.is_empty():
		return false
	_palette = GameData.load_palette_texture(type.directory(), _bob.palettes)
	_ramps = GameData.load_ramps(type.bob_path)
	_shadow = Sprite2D.new()
	_body = Sprite2D.new()
	SpriteMaterials.make_shadow(_shadow)
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
	add_child(_shadow)
	add_child(_body)
	add_child(_overlay)
	if not _refresh_sprites():
		return false
	# Only buildings (training, distilling) and fields (growing) need a per-frame update.
	set_process(is_building() or is_field())
	_team_row = mini(owner if type.kind == ObjectTypes.Kind.BUILDING and owner > 0 else 0, _bob.palettes.size() - 1)
	_body.set_instance_shader_parameter("palette_row", _palette_row(_body_anim))
	return true


## Palette row for a sheet: the team's colours, or the sheet's own table (burnt walls,
## rubble, windmill) which the palette texture holds as a further row.
func _palette_row(anim_index: int) -> int:
	if anim_index < 0 or anim_index >= _bob.anims.size():
		return _team_row
	var own := _bob.palettes_for_sheet(_bob.anims[anim_index].sub_sprite)
	if own.size() == 1 and own[0] != _bob.palettes[0]:
		return maxi(0, Array(_bob.palettes).find(own[0]))
	return _team_row


var _build_sound_played := false
## Gold delivered to a gold warehouse: the people's, but only usable once hauled to the HQ.
var stored_gold := 0
var _team_row := 0
var _body_anim := -1
## Building anims shared by every building descriptor (body/shadow pairs).
const BURNT_ANIM := 7  # the burnt-out building, shown below a third of its energy
const RUBBLE_ANIM := 9
const AMBIENT_ANIM := 11  # a moving part (windmill sails...) and 12 its shadow
const BURNT_BELOW := 0.33
const FIRE_BELOW := 0.66
const RUBBLE_SECONDS := 25.0
const FIRE_BOB := "global/gfx/feuer/fire.bob"
## fire.bob: 0 large, 1 medium, 2 small flames; 3-5 clouds; 6 smoke column.
const FIRE_STAGES := [[], [2, 6], [2, 1, 0, 6]]
var _fires: Array[OrderMarker] = []
var _fire_stage := 0
var _ambient: Sprite2D
var _ambient_step := 0
var _ambient_time := 0.0
## Units quartered inside (forts, towers): safe from attack and shooting out at enemies.
var garrison: Array[Unit] = []
const GARRISON_RANGE_BONUS := 60.0  # firing from the walls / platform reaches further
var _garrison_scan := 0.0
## Where units trained here gather ("Specify assembly location"); INF = just outside.
var rally_point := Vector2.INF


## Add construction work (worker-seconds); returns true when the building completes.
func add_build_work(seconds: float) -> bool:
	if complete:
		return true
	if not _build_sound_played:
		_build_sound_played = true  # the construction sound plays once, when work begins
		Sound.play_event(guid, Sound.Event.BUILD, position, 0, get_instance_id(), Sound.WORK_RANGE)
	# Worker-seconds: the original production time (one worker), else scaled by energy.
	var total := float(GameData.stats(guid).get("build_time", max_health * BUILD_WORK_PER_HEALTH))
	total = maxf(5.0, total)
	build_progress = minf(1.0, build_progress + seconds / total)
	health = maxf(health, max_health * (0.1 + 0.9 * build_progress))
	_refresh_sprites()
	_overlay.queue_redraw()
	if build_progress >= 1.0:
		complete = true
		health = max_health
		accepts = _drop_off_for(guid)
		_refresh_sprites()
		Sound.play_event(guid, Sound.Event.FINISHED, position, 0)
		var builder_player: Player = Player.by_index.get(owner_index)
		if builder_player:
			builder_player.stats.built += 1
		construction_finished.emit(self)
	return complete


## Energy upgrades (e.g. "Thick boards", tower upgrades) for this building's type.
func refresh_upgrades() -> void:
	var player: Player = Player.by_index.get(owner_index)
	if player == null or not complete:
		return
	var base := float(GameData.stats(guid).get("health", max_health))
	var ratio := health / max_health if max_health > 0 else 1.0
	max_health = base * (1.0 + player.bonus(guid, "health_pct") / 100.0)
	health = max_health * ratio


## Upgrades researched here that the owner can start now.
func researchable_upgrades() -> PackedInt32Array:
	var out := PackedInt32Array()
	var player: Player = Player.by_index.get(owner_index)
	if not complete or player == null:
		return out
	var ids := GameData.stats_guids()
	ids.sort()
	for upgrade in ids:
		var stats := GameData.stats(upgrade)
		if stats.get("kind") == "upgrade" and int(stats.get("produced_at", -1)) == guid \
				and (player.can_research(upgrade) or upgrade in queue):
			out.append(upgrade)
	return out


## Units this building can train (GUIDs from the manual's "place of production").
func trainable_units() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not complete:
		return out
	if guid in HORSE_BUILDINGS:
		out.append(HORSE_GUID)
	if guid in COW_BUILDINGS:
		out.append(COW_GUID)
	if guid in TRADE_BUILDINGS:
		for i in TRADES.size():
			out.append(TRADE_GUID + i)
	for unit_guid in GameData.stats_guids():
		var stats := GameData.stats(unit_guid)
		if stats.get("kind") == "unit" and int(stats.get("produced_at", -1)) == guid:
			out.append(unit_guid)
	return out


static func is_trade(item: int) -> bool:
	return item >= TRADE_GUID and item < TRADE_GUID + TRADES.size()


var _trade_terms: Array[Dictionary] = []  # what each queued trade was paid with, in order


## Take entry `index` off the production queue and refund what it cost.
func cancel_queued(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var item := queue[index]
	if is_trade(item):
		var position_in_trades := 0
		for k in index:
			if is_trade(queue[k]):
				position_in_trades += 1
		var paid: Dictionary = _trade_terms[position_in_trades]
		_trade_terms.remove_at(position_in_trades)
		queue.remove_at(index)
		if index == 0:
			train_progress = 0.0
		var refund_to: Player = Player.by_index.get(owner_index)
		if refund_to:
			for key in paid:
				refund_to.add(key, int(paid[key]))
		return
	queue.remove_at(index)
	if index == 0:
		train_progress = 0.0
	var player: Player = Player.by_index.get(owner_index)
	if player:
		var cost: Dictionary = GameData.stats(item).get("cost", {})
		for key in cost:
			if Player.RESOURCES.has(key):
				player.add(key, int(cost[key]))


func enqueue(unit_guid: int) -> bool:
	var player: Player = Player.by_index.get(owner_index)
	if queue.size() >= QUEUE_LIMIT or player == null:
		return false
	var is_upgrade: bool = GameData.stats(unit_guid).get("kind") == "upgrade"
	if is_upgrade:
		var upgrade_cost: Dictionary = GameData.stats(unit_guid).get("cost", {})
		if not player.can_research(unit_guid) or not player.spend(upgrade_cost):
			return false
		queue.append(unit_guid)
		return true
	if is_trade(unit_guid):
		# Buying pays the gold now; selling hands over the goods now; the other side of the
		# deal arrives when the trade completes.
		if queue.size() >= TRADE_QUEUE_LIMIT:
			return false
		var trade: Dictionary = TRADES[unit_guid - TRADE_GUID]
		var paid := {"gold": player.buy_price(trade.good)} if trade.buy else {trade.good: Player.TRADE_PACKAGE[trade.good]}
		if not player.spend(paid):
			return false
		_trade_terms.append(paid)
		queue.append(unit_guid)
		return true
	if unit_guid == COW_GUID:
		if not player.spend(GameData.stats(COW_GUID).cost):
			return false
		queue.append(unit_guid)
		return true
	if unit_guid == HORSE_GUID:
		if int(player.resources.get("horses", 0)) + player.queued_horses() >= player.horse_capacity() \
				or not player.spend(GameData.stats(HORSE_GUID).cost):
			return false
		queue.append(unit_guid)
		return true
	if unit_guid in Player.COMMANDERS and player.has_commander():
		return false
	var cost: Dictionary = GameData.stats(unit_guid).get("cost", {}).duplicate()
	cost.erase("population")
	if player == null or not player.has_room() or not player.spend(cost):
		return false
	queue.append(unit_guid)
	return true


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		var pulse := 0.5 + 0.5 * sin(_flash_time * TAU * 3.0)
		_body.self_modulate = Color.WHITE.lerp(_flash_color * 1.6, pulse * _flash_time)
		_overlay.queue_redraw()
		if _flash_time <= 0.0:
			_body.self_modulate = Color.WHITE
			set_process(is_building() or is_field())
	if is_field() and field_state == Field.GROWING:
		field_progress += delta / FIELD_GROW_SECONDS
		if field_progress >= 1.0:
			field_state = Field.RIPE
			var owner_player: Player = Player.by_index.get(owner_index)
			amount = FIELD_YIELD + (int(owner_player.bonus(-1, "field_yield")) if owner_player else 0)
			if _rained:
				amount = int(amount * 1.5)
				_rained = false
		_refresh_sprites()
	if _ambient:
		_advance_ambient(delta)
	if not garrison.is_empty():
		_update_garrison(delta)
	if guid == DISTILLERY_GUID and complete:
		_distill(delta)
	if guid in INCOME_BUILDINGS and complete and health > 0.0:
		_earn(delta)
	if is_trap() and complete and health > 0.0:
		_spring_trap(delta)
	if guid in TRADE_BUILDINGS and complete:
		var market: Player = Player.by_index.get(owner_index)
		if market:
			market.settle_prices(delta)
	if queue.is_empty() or not complete:
		return
	var unit_guid := queue[0]
	var seconds: float = TRAIN_SECONDS.default
	if GameData.stats(unit_guid).get("damage", 0) <= 4:
		seconds = TRAIN_SECONDS.worker
	seconds = float(GameData.stats(unit_guid).get("build_time", seconds))
	if GameData.stats(unit_guid).get("kind") == "upgrade":
		# The editor data gives 60 s for level 1 and 90 s for level 2 of an upgrade.
		var name: String = GameData.stats(unit_guid).get("name", "")
		var level := name.get_slice(" ", name.get_slice_count(" ") - 1)
		seconds = 30.0 + 30.0 * level.to_int() if level.is_valid_int() else UPGRADE_SECONDS
	train_progress += delta / seconds
	if train_progress >= 1.0:
		train_progress = 0.0
		queue.remove_at(0)
		if GameData.stats(unit_guid).get("kind") == "upgrade":
			var player: Player = Player.by_index.get(owner_index)
			if player:
				player.complete_research(unit_guid)
			return
		if is_trade(unit_guid):
			var trader: Player = Player.by_index.get(owner_index)
			var trade: Dictionary = TRADES[unit_guid - TRADE_GUID]
			_trade_terms.pop_front()
			if trader:
				if trade.buy:
					trader.add(trade.good, Player.TRADE_PACKAGE[trade.good])
				else:
					trader.add("gold", trader.sell_price(trade.good))
				trader.move_price(trade.good, trade.buy)
			return
		if unit_guid == HORSE_GUID:
			var owner_player: Player = Player.by_index.get(owner_index)
			if owner_player:
				owner_player.add("horses", 1)
			Sound.play_event(guid, Sound.Event.UNIT_READY, position, 0)
			return
		Sound.play_event(guid, Sound.Event.UNIT_READY, position, 0)
		var trainer: Player = Player.by_index.get(owner_index)
		if trainer:
			trainer.stats.produced += 1
		unit_trained.emit(self, unit_guid)
	if selected:
		_overlay.queue_redraw()


## Banks (interest) and missions (donations) pay gold on their own; more of them pay more,
## up to five each (manual).
const INCOME_BUILDINGS := [416, 216]
const INCOME_GOLD := 15
const INCOME_SECONDS := 12.0
var _income_timer := 0.0


func _earn(delta: float) -> void:
	_income_timer += delta
	if _income_timer < INCOME_SECONDS:
		return
	_income_timer = 0.0
	var same := 0
	for object in all_objects:
		if object.guid == guid and object.owner_index == owner_index and object.complete and object.is_alive():
			same += 1
			if object == self and same > 5:
				return
	var player: Player = Player.by_index.get(owner_index)
	if player:
		player.add("gold", INCOME_GOLD)


func _distill(delta: float) -> void:
	var player: Player = Player.by_index.get(owner_index)
	if player == null or int(player.resources.get("wood", 0)) < DISTILL_WOOD:
		return
	_distill_timer += delta
	if _distill_timer >= DISTILL_SECONDS:
		_distill_timer = 0.0
		player.spend({"wood": DISTILL_WOOD})
		player.add("food", DISTILL_FOOD)


func _refresh_sprites() -> bool:
	var body_anim := object_type.anim
	var shadow_anim := object_type.shadow_anim
	var frame_hint := -1  # -1 = last frame of the animation
	if is_tree() and tree_state != TreeState.STANDING:
		body_anim = TREE_FELLED_ANIM if tree_state == TreeState.FELLED else TREE_STUMP_ANIM
		shadow_anim = body_anim + 1
	elif is_mine() and _bob.anims.size() >= 6:
		# Anim pairs (body, shadow): 0/1 untouched, 2/3 framing -> timbered, 4/5 exhausted.
		match _mine_stage():
			0:
				body_anim = 0
			1, 2:
				body_anim = 2
				frame_hint = _mine_stage() - 1
			3:
				body_anim = 4
		shadow_anim = body_anim + 1
	elif is_field():
		body_anim = 0
		var stage := 0
		match field_state:
			Field.GROWING:
				stage = 1 + mini(1, int(field_progress * 2.0))
			Field.RIPE:
				stage = 3 if amount > FIELD_YIELD / 3 else 2
		var frames := _bob.anims[0].frames
		frame_hint = frames.find(FIELD_STAGES[stage]) if frames.has(FIELD_STAGES[stage]) else 0
		shadow_anim = -1
	elif is_building():
		# Construction stages are the frames of anim 0 (shadow anim 1); 2/3 hold the finished frame.
		if not complete and health > 0.0:
			body_anim = 0
			var stages := _bob.anims[0].frames.size()
			frame_hint = mini(stages - 1, int(build_progress * stages))
		else:
			body_anim = 2 if _bob.anims.size() > 3 else 0
		if health <= 0.0 and _has_sheet(RUBBLE_ANIM):
			body_anim = RUBBLE_ANIM
		elif complete and health < max_health * BURNT_BELOW and _has_sheet(BURNT_ANIM):
			body_anim = BURNT_ANIM
		shadow_anim = _bob.shadow_for(body_anim)
	elif shadow_anim == body_anim:
		shadow_anim = _bob.shadow_for(body_anim)
	if not _show(_body, body_anim, frame_hint):
		return false
	_body.material = SpriteMaterials.body(_body.get_meta("sheet"), _palette, _ramps)
	if body_anim != _body_anim:
		_body_anim = body_anim
		_body.set_instance_shader_parameter("palette_row", _palette_row(body_anim))
	if is_building():
		_update_ambient()
	_shadow.visible = shadow_anim >= 0 and shadow_anim < _bob.anims.size() and _show(_shadow, shadow_anim, frame_hint)
	return true


func _has_sheet(anim_index: int) -> bool:
	return anim_index < _bob.anims.size() and not _bob.sub_sprite_is_shadow[_bob.anims[anim_index].sub_sprite]


## Flames and smoke grow as the building loses energy (none above two thirds).
func _update_fires() -> void:
	var ratio := health / max_health if max_health > 0.0 else 1.0
	var stage := 0
	if complete and health > 0.0:
		stage = 2 if ratio < BURNT_BELOW else (1 if ratio < FIRE_BELOW else 0)
	if stage == _fire_stage:
		return
	if stage > _fire_stage:
		Sound.play_event(guid, Sound.Event.BURNING, position, 0, get_instance_id(), Sound.WORK_RANGE)
	_fire_stage = stage
	for fire in _fires:
		if is_instance_valid(fire):
			fire.queue_free()
	_fires.clear()
	var walls := work_rect()
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var picture := visual_rect()
	for anim in FIRE_STAGES[stage]:
		# Somewhere on the building itself: a solid pixel in the upper part of its picture.
		var spot := walls.get_center()
		for attempt in 16:
			var candidate := Vector2(rng.randf_range(picture.position.x + picture.size.x * 0.2, picture.end.x - picture.size.x * 0.2),
					rng.randf_range(picture.position.y + picture.size.y * 0.25, picture.position.y + picture.size.y * 0.7))
			if _body.is_pixel_opaque(_body.to_local(candidate)):
				spot = candidate
				break
		_fires.append(OrderMarker.effect_loop(self, spot - position, FIRE_BOB, anim))


## Buildings with a moving part (the farm's windmill...) run it once they are finished.
func _update_ambient() -> void:
	var wanted := complete and health >= max_health * BURNT_BELOW and _has_sheet(AMBIENT_ANIM) \
			and _bob.anims[AMBIENT_ANIM].frames.size() > 1
	if not wanted:
		if _ambient:
			_ambient.queue_free()
			_ambient = null
		return
	if _ambient == null:
		_ambient = Sprite2D.new()
		_ambient.centered = false
		_ambient.region_enabled = true
		add_child(_ambient)
		move_child(_ambient, _body.get_index() + 1)
		_ambient_step = 0
		_show(_ambient, AMBIENT_ANIM, 0)
		_ambient.material = SpriteMaterials.body(_ambient.get_meta("sheet"), _palette, _ramps)
		_ambient.set_instance_shader_parameter("palette_row", _palette_row(AMBIENT_ANIM))


func _advance_ambient(delta: float) -> void:
	var anim := _bob.anims[AMBIENT_ANIM]
	_ambient_time += delta * 1000.0
	if _ambient_time >= anim.durations_ms[_ambient_step]:
		_ambient_time = 0.0
		_ambient_step = (_ambient_step + 1) % anim.frames.size()
		_show(_ambient, AMBIENT_ANIM, _ambient_step)


func _show(sprite: Sprite2D, anim_index: int, frame_hint: int) -> bool:
	var anim := _bob.anims[anim_index]
	var sheet := GameData.load_sprite(object_type.directory().path_join(_bob.sub_sprites[anim.sub_sprite]))
	if sheet == null or anim.frames.is_empty():
		return false
	var frame := anim.frames[frame_hint if frame_hint >= 0 else anim.frames.size() - 1]
	if frame >= sheet.frame_count():
		return false
	SpriteMaterials.prepare(sprite, sheet)
	sheet.apply(sprite, frame)
	sprite.set_meta("sheet", sheet)
	return true


func _draw_overlay(canvas: Node2D) -> void:
	var rect := footprint_rect()
	rect.position -= position
	if _flash_time > 0.0:
		var work := work_rect()
		work.position -= position
		# Trees get a tight ring round the trunk; buildings and mines one round their walls.
		var radius := 13.0 if is_tree() else maxf(work.size.x * 0.55, 20.0)
		canvas.draw_set_transform(work.get_center() + Vector2(0, work.size.y * 0.3), 0.0, Vector2(1.0, 0.55))
		canvas.draw_arc(Vector2.ZERO, radius * (1.25 - _flash_time * 0.25), 0.0, TAU, 48,
				Color(_flash_color, _flash_time), 2.5, true)
		canvas.draw_set_transform(Vector2.ZERO)
	if Unit.debug_paths and object_type:
		canvas.draw_rect(rect, Color(0, 1, 1, 0.8), false, 1.5)
		canvas.draw_circle(Vector2.ZERO, 3, Color.RED)
	var walls := work_rect()
	walls.position -= position
	if selected:
		# Ring the walls (the solid cells), not the whole footprint grid, which is lopsided
		# for buildings such as the finca; a tree is ringed round its trunk.
		var radius := 16.0 if is_tree() else walls.size.x * 0.68
		canvas.draw_set_transform(walls.get_center() + Vector2(0, walls.size.y * 0.1), 0.0, Vector2(1.0, 0.55))
		canvas.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 2.0, true)
		canvas.draw_set_transform(Vector2.ZERO)
	if not is_building() or not (selected or not complete):
		return
	var width := maxf(walls.size.x, 48.0)
	var bar := Rect2(walls.get_center().x - width * 0.4, rect.position.y - 16, width * 0.8, 4)
	canvas.draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
	if not complete:
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * build_progress, bar.size.y)), Color(0.95, 0.75, 0.2))
	else:
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / max_health, bar.size.y)), Color(0.3, 0.9, 0.2))
		if not queue.is_empty():
			var train := Rect2(bar.position + Vector2(0, 6), bar.size)
			canvas.draw_rect(train, Color(0.1, 0.1, 0.1, 0.8))
			canvas.draw_rect(Rect2(train.position, Vector2(train.size.x * train_progress, train.size.y)), Color(0.4, 0.7, 1.0))


## Which resources a building accepts.
static func _drop_off_for(building_guid: int) -> PackedStringArray:
	if building_guid in MAIN_BUILDINGS:
		return PackedStringArray(["wood", "gold", "food", "leather"])
	var out := PackedStringArray()
	for resource in DROP_OFFS:
		if building_guid in DROP_OFFS[resource]:
			out.append(resource)
	return out


## Fields a player may still plant: five per completed food store.
static func field_allowance(team: int) -> int:
	var stores := 0
	var fields := 0
	for object in all_objects:
		if object.owner_index != team:
			continue
		if object.guid in FOOD_STORES and object.complete and object.is_alive():
			stores += 1
		elif object.is_field():
			fields += 1
	return stores * FIELDS_PER_STORE - fields
