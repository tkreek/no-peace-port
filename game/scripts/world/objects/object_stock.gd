class_name ObjectStock
extends RefCounted
## What an object holds for the taking: the wood of a tree (standing, felled, then a
## stump), the gold of a mine (whose entrance the miners timber as they work), the crop of
## a field (sown, growing, ripe), the gold a gold warehouse keeps until a wagon hauls it,
## and the goods in an abandoned warehouse (manual 4.3).

const TREE_WOOD := 150
const MINE_GOLD := 3000
## Trees: the bobs hold felled and stump pictures as anim pairs 24/25 and 26/27.
enum TreeState { STANDING, FELLED, STUMP }
const TREE_FELLED_ANIM := 24
const TREE_STUMP_ANIM := 26
## Mines: worker-seconds to timber the entrance before the gold can be dug (a few seconds
## for a handful of miners).
const MINE_FRAMED_AFTER := 12.0
## Fields: fallow -> sown by a woman -> grow -> ripe, harvested down to fallow again.
enum Field { FALLOW, GROWING, RIPE }
const FIELD_SOW_WORK := 8.0  # woman-seconds
const FIELD_GROW_SECONDS := 45.0
const FIELD_YIELD := 300
const FIELD_STAGES := [3, 0, 1, 2]  # frames of anim 0: ploughed, sprouting, growing, ripe
## Abandoned warehouses: object types USA_Lager, MEX_Magazin (both biomes).
const ABANDONED_STORES := [26, 56, 299, 300]

var object: MapObject
var resource := ""  ## "wood", "gold" or "food" while there is something to harvest
var amount := 0
var tree_state := TreeState.STANDING
var field_state := Field.FALLOW
var field_progress := 0.0  # sowing work done, then growth (0..1)
var mine_work := 0.0  ## worker-seconds spent inside a mine
var stored_gold := 0  ## a gold warehouse's: the people's, but only usable once hauled to the HQ
var loot_kind := ""  ## an abandoned warehouse's goods
var loot := 0
var _rained := false
var _mine_sound: AudioStreamPlayer2D
var _mine_heard := 0  # msec of the last work inside


func _init(owner: MapObject, placed_amount: int) -> void:
	object = owner
	var name := object.object_type.name
	if object.guid == MapObject.FIELD_GUID:
		resource = "food"
	elif name.begins_with("tree"):
		resource = "wood"
		amount = TREE_WOOD
	elif name.begins_with("mine"):
		resource = "gold"
		amount = placed_amount if placed_amount > 0 else MINE_GOLD


func is_abandoned_store() -> bool:
	return object.object_type.id in ABANDONED_STORES


## Whether there is anything left to take (fields always, they grow again).
func has_resource() -> bool:
	return resource != "" and (object.is_field() or amount > 0)


# ------------------------------------------------------------------ harvesting

## Take up to `wanted` of the resource; trees fall and leave a stump, mines are boarded up.
func harvest(wanted: int) -> int:
	if object.is_field() and field_state != Field.RIPE:
		return 0
	var taken := mini(wanted, amount)
	amount -= taken
	if object.is_mine() and amount <= 0:
		object.refresh_sprites()
	if object.is_field():
		if amount <= 0:
			field_state = Field.FALLOW
			var farmer: Player = Player.by_index.get(object.owner_index)
			if farmer:
				farmer.alert(Player.FIELD_HARVESTED_ALERT, object.position, 5000)
		object.refresh_sprites()
	if resource == "wood" and object.is_tree():
		if amount <= 0:
			# All wood taken: only the stump remains, and the ground is passable again.
			tree_state = TreeState.STUMP
			resource = ""
			_clear_ground()
		elif tree_state == TreeState.STANDING:
			tree_state = TreeState.FELLED  # the first cut brings the tree down
		object.refresh_sprites()
	elif amount <= 0 and resource == "wood":
		_clear_ground()
		resource = ""
		var tween := object.create_tween()
		tween.tween_property(object, "modulate:a", 0.0, 1.5)
		tween.tween_callback(object.queue_free)
	return taken


func _clear_ground() -> void:
	if NavGrid.current:
		NavGrid.current.unblock_footprint(object.object_type, object.position)


## Whether the entrance is timbered: until then the miners build it, and no gold comes out.
func mine_framed() -> bool:
	return mine_work >= MINE_FRAMED_AFTER


## Workers at a new mine build its timber entrance (original frames: bare, framing, timbered).
func add_mine_work(seconds: float) -> void:
	var before := mine_stage()
	mine_work += seconds
	_keep_mine_sound()
	if mine_stage() != before:
		object.refresh_sprites()


## 0 untouched, 1 framing going up, 2 timbered entrance, 3 boarded up (exhausted).
func mine_stage() -> int:
	if amount <= 0:
		return 3
	if mine_work <= 0.0:
		return 0
	return 1 if mine_work < MINE_FRAMED_AFTER else 2


## Picks and rubble from inside a worked mine ("gold_mine"), heard from afar and
## through the fog; it keeps going while anyone works inside and stops soon after.
func _keep_mine_sound() -> void:
	_mine_heard = Time.get_ticks_msec()
	if _mine_sound == null:
		_mine_sound = Sound.work_emitter("gold_mine")
		if _mine_sound == null:
			return
		_mine_sound.position = object.work_rect().get_center() - object.position
		object.add_child(_mine_sound)
		_mine_sound.finished.connect(func() -> void:
			if Time.get_ticks_msec() - _mine_heard < 1500 and amount > 0:
				_mine_sound.pitch_scale = randf_range(0.94, 1.06)
				_mine_sound.play())
	if not _mine_sound.playing:
		_mine_sound.play()


func is_mine_sounding() -> bool:
	return _mine_sound != null and _mine_sound.playing


# ------------------------------------------------------------------ fields

## Add sowing work; returns true once the field is sown and growing.
func sow(seconds: float) -> bool:
	if field_state != Field.FALLOW:
		return true
	field_progress += seconds / FIELD_SOW_WORK
	if field_progress >= 1.0:
		field_state = Field.GROWING
		field_progress = 0.0
	object.refresh_sprites()
	return field_state != Field.FALLOW


func grow(delta: float) -> void:
	if field_state != Field.GROWING:
		return
	field_progress += delta / FIELD_GROW_SECONDS
	if field_progress >= 1.0:
		field_state = Field.RIPE
		var owner: Player = Player.by_index.get(object.owner_index)
		amount = FIELD_YIELD + (int(owner.bonus(-1, "field_yield")) if owner else 0)
		if _rained:
			amount = int(amount * 1.5)
			_rained = false
	object.refresh_sprites()


## Hail (medicine man): the crop is lost and the field must be sown again.
func ruin_crop() -> void:
	field_state = Field.FALLOW
	field_progress = 0.0
	amount = 0
	object.refresh_sprites()


## Rain (medicine man): a ripe field holds half as much again; a growing one will.
func rain() -> void:
	if field_state == Field.RIPE:
		amount = int(amount * 1.5)
	else:
		_rained = true


func is_rained() -> bool:
	return _rained


## The field picture for its state: ploughed, sprouting, growing, ripe.
func field_stage() -> int:
	match field_state:
		Field.GROWING:
			return 1 + mini(1, int(field_progress * 2.0))
		Field.RIPE:
			return 3 if amount > FIELD_YIELD / 3 else 2
	return 0


# ------------------------------------------------------------------ stores and hauling

func store_gold(amount_in: int) -> void:
	stored_gold += amount_in
	_notify_owner()


func take_gold(wanted: int) -> int:
	var taken := mini(wanted, stored_gold)
	stored_gold -= taken
	if taken > 0:
		_notify_owner()
	return taken


func _notify_owner() -> void:
	var owner: Player = Player.by_index.get(object.owner_index)
	if owner:
		owner.resources_changed.emit()


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


# ------------------------------------------------------------------ saved games

func restore_resource(left: int, state: int, work: float) -> void:
	amount = left
	mine_work = work
	if object.is_tree():
		tree_state = state as TreeState
		if tree_state == TreeState.STUMP:
			resource = ""
			_clear_ground()
	object.refresh_sprites()


func restore(entry: Dictionary) -> void:
	stored_gold = int(entry.get("stored_gold", 0))
	loot_kind = entry.get("loot_kind", "")
	loot = int(entry.get("loot", 0))
	if object.is_field():
		field_state = int(entry.field_state) as Field
		field_progress = float(entry.field_progress)
		amount = int(entry.amount)
