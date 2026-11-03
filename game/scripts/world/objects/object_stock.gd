class_name ObjectStock
extends RefCounted
## What an object holds for the taking: the wood of a tree (standing, felled, then a
## stump), the gold of a mine (whose entrance the miners timber as they work), the crop of
## a field (sown, growing, ripe), the gold a gold warehouse keeps until a wagon hauls it,
## and the goods in an abandoned warehouse (manual 4.3).

## Wood in a tree (AmericaAddOn.exe): Defaults.bin property 302 of its type, read when the
## tree is made (0x428822), by kind within each run of twelve GUIDs (500-511, the "b" set
## 512-523, the "c" set 524-535): deciduous large 01-03, small 01-03, conifer large 01-03,
## small 01-03. A type without it would get 1000 (0x405fe0).
const TREE_WOOD_BY_KIND := [250, 250, 150, 200, 200, 150, 250, 250, 250, 200, 200, 200]
const TREE_WOOD_DEFAULT := 1000
## A mine holds what the map gives it (0x4239fb; 0 there is an exhausted mine); ours
## falls back to this for editor maps that leave it out.
const MINE_GOLD := 3000
## Trees: the bobs hold felled and stump pictures as anim pairs 24/25 and 26/27.
enum TreeState { STANDING, FELLED, STUMP }
const TREE_FELLED_ANIM := 24
const TREE_STUMP_ANIM := 26
## Mines: worker-seconds to timber the entrance before the gold can be dug: each worker at
## it adds 20 ms a tick until 11000 (AmericaAddOn.exe 0x423a39, 0x423d70).
const MINE_FRAMED_AFTER := 11.0
## Fields: fallow -> tended by a woman until ripe -> harvested down to fallow again. A field
## does not grow by itself: a woman works it, every 1.02 s taking 3000 / 25 off its pool of
## 3000 (property 6 of the field, 149; 0x41f7a0, 0x40cc50 -> 0x40c300), 25.5 s in all.
## GROWING is a field she has started on.
enum Field { FALLOW, GROWING, RIPE }
const FIELD_SOW_WORK := 25.5  # woman-seconds
## Ripe, it holds the value the woman brought it (0x402c3e, 0x41f88e): 150, with the
## Shovel upgrades 175 and 200 (0x403240).
const FIELD_YIELD := 150
## Rain sets a ripe field's crop to this (0x47ca80); an unripe field's is overwritten when
## it ripens (0x41f88e), so rain on it is lost.
const RAIN_CROP := 350
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
## Picked clean: the next woman to start on it pays the field's cost again (0x402e17 ->
## 0x403180, the field's energy reset to 0x100 by 0x41f740).
var needs_paying := false
var _mine_sound: AudioStreamPlayer2D
var _mine_heard := 0  # msec of the last work inside


func _init(owner: MapObject, placed_amount: int) -> void:
	object = owner
	var name := object.object_type.name
	if object.guid == MapObject.FIELD_GUID:
		resource = "food"
	elif name.begins_with("tree"):
		resource = "wood"
		amount = tree_wood(object.guid)
	elif name.begins_with("mine"):
		resource = "gold"
		amount = placed_amount if placed_amount > 0 else MINE_GOLD


static func tree_wood(guid: int) -> int:
	if guid >= 500 and guid <= 535:
		return TREE_WOOD_BY_KIND[(guid - 500) % 12]
	return TREE_WOOD_DEFAULT


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
			field_progress = 0.0
			needs_paying = true
			var farmer: Player = Player.by_index.get(object.owner_index)
			if farmer:
				farmer.alert(Player.FIELD_HARVESTED_ALERT, object.position, 5000)
		object.refresh_sprites()
	if resource == "wood" and object.is_tree():
		# The first load fells the tree and frees its cells (0x406299); the last leaves the
		# stump (0x406223).
		if tree_state == TreeState.STANDING:
			_clear_ground()
		if amount <= 0:
			tree_state = TreeState.STUMP
			resource = ""
		elif tree_state == TreeState.STANDING:
			tree_state = TreeState.FELLED
		object.refresh_sprites()
	elif amount <= 0 and resource == "wood":
		_clear_ground()
		resource = ""
		var tween := object.create_tween()
		tween.tween_property(object, "modulate:a", 0.0, 1.5)
		Sim.after(1.5, object.queue_free)
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

## A woman's work on an unripe field; returns true once it is ripe.
func sow(seconds: float) -> bool:
	if field_state == Field.RIPE:
		return true
	field_state = Field.GROWING
	field_progress += seconds / FIELD_SOW_WORK
	if field_progress >= 1.0:
		field_state = Field.RIPE
		field_progress = 0.0
		var owner: Player = Player.by_index.get(object.owner_index)
		amount = FIELD_YIELD + roundi(owner.bonus(-1, "field_yield") if owner else 0.0)
	object.refresh_sprites()
	return field_state == Field.RIPE


## Fields grow only by a woman's work (sow).
func grow(_delta: float) -> void:
	pass


## Hail (medicine man): the field is destroyed outright (0x47cac0: its state set to
## ruined, removed the next tick by 0x40c070 -> 0x40cc10).
func ruin_crop() -> void:
	field_state = Field.FALLOW
	amount = 0
	object.forget()
	object.queue_free()


## Rain (medicine man): a ripe field's crop becomes RAIN_CROP (0x47ca80); nothing else.
func rain() -> void:
	if field_state == Field.RIPE:
		amount = RAIN_CROP


func is_rained() -> bool:
	return false


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


## The map's content code 301-305 is the kind (0x43fe50): food, wood, nothing, gold, guns.
const STORE_KINDS := {0x12d: "food", 0x12e: "wood", 0x130: "gold", 0x131: "guns"}


func stock_abandoned_store(content: int, how_much: int) -> void:
	loot_kind = STORE_KINDS.get(content, "")
	loot = how_much if loot_kind != "" else 0


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
		needs_paying = bool(entry.get("needs_paying", false))
