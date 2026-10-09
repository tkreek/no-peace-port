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

## Drop-off buildings by GUID (main buildings take everything).
const MAIN_BUILDINGS := [100, 200, 300, 400]
const DROP_OFFS := {
	"wood": [109, 209, 309, 409],          # wood processing, sawmills, carpentry shop
	"gold": [104, 206, 304, 419],          # gold warehouses
	"food": [108, 208, 408, 102, 202, 302, 402],  # granary, finca, farm; butchers / stockyard
}
const FOOD_STORES := [108, 208, 408]
const FIELD_GUID := 149
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


func take_damage(amount: float, _attacker: Node2D = null) -> void:
	if not is_building() or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_overlay.queue_redraw()
	if health <= 0.0:
		_destroy()


func _destroy() -> void:
	Sound.play_event(guid, Sound.Event.RUBBLE, position, 0)
	queue.clear()
	accepts = PackedStringArray()
	if NavGrid.current:
		NavGrid.current.unblock_footprint(object_type, position)
	selected = false
	destroyed.emit(self)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(0.3, 0.25, 0.2, 0.0), 2.5)
	tween.tween_callback(queue_free)


func is_building() -> bool:
	return object_type != null and object_type.kind == ObjectTypes.Kind.BUILDING and guid != FIELD_GUID


func is_field() -> bool:
	return guid == FIELD_GUID


func is_mine() -> bool:
	return object_type != null and object_type.name.begins_with("Mine")


## Workers inside a mine build up its timber entrance (original frames: bare, framing, timbered).
func add_mine_work(seconds: float) -> void:
	var before := _mine_stage()
	mine_work += seconds
	if _mine_stage() != before:
		_refresh_sprites()


## 0 untouched, 1 framing going up, 2 timbered entrance, 3 boarded up (exhausted).
func _mine_stage() -> int:
	if amount <= 0:
		return 3
	if mine_work <= 0.0:
		return 0
	return 1 if mine_work < MINE_FRAMED_AFTER else 2


## Add sowing work; returns true once the field is sown and starts growing.
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
	return GameData.type_name(object_type.id) if object_type else "?"


## Footprint rectangle in world space (for arrival checks and placement).
func footprint_rect() -> Rect2:
	return footprint_rect_for(object_type, position)


## The solid part of the footprint (trunk, walls, mine entrance): where workers stand at.
## The full footprint grid also covers the empty space around the sprite.
func work_rect() -> Rect2:
	if _work_rect.size == Vector2.ZERO:
		_work_rect = footprint_rect()
		if object_type and not object_type.footprint_cells.is_empty():
			var grid := object_type.footprint_grid
			var low := Vector2i(grid.x, grid.y)
			var high := Vector2i(-1, -1)
			for i in object_type.footprint_cells.size():
				if object_type.footprint_cells[i] & NavGrid.BLOCKED:
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
	elif type.kind == ObjectTypes.Kind.BUILDING:
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
	var team_row := owner if type.kind == ObjectTypes.Kind.BUILDING and owner > 0 else 0
	_body.set_instance_shader_parameter("palette_row", mini(team_row, _bob.palettes.size() - 1))
	return true


## Add construction work (worker-seconds); returns true when the building completes.
func add_build_work(seconds: float) -> bool:
	if complete:
		return true
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
		construction_finished.emit(self)
	return complete


## Units this building can train (GUIDs from the manual's "place of production").
func trainable_units() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not complete:
		return out
	for unit_guid in GameData.stats_guids():
		var stats := GameData.stats(unit_guid)
		if stats.get("kind") == "unit" and int(stats.get("produced_at", -1)) == guid:
			out.append(unit_guid)
	return out


func enqueue(unit_guid: int) -> bool:
	var player: Player = Player.by_index.get(owner_index)
	if queue.size() >= QUEUE_LIMIT or player == null:
		return false
	if unit_guid in Player.COMMANDERS and player.has_commander():
		return false
	var cost: Dictionary = GameData.stats(unit_guid).get("cost", {}).duplicate()
	cost.erase("population")
	cost.erase("horses")
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
			amount = FIELD_YIELD
		_refresh_sprites()
	if guid == DISTILLERY_GUID and complete:
		_distill(delta)
	if queue.is_empty() or not complete:
		return
	var unit_guid := queue[0]
	var seconds: float = TRAIN_SECONDS.default
	if GameData.stats(unit_guid).get("damage", 0) <= 4:
		seconds = TRAIN_SECONDS.worker
	seconds = float(GameData.stats(unit_guid).get("build_time", seconds))
	train_progress += delta / seconds
	if train_progress >= 1.0:
		train_progress = 0.0
		queue.remove_at(0)
		Sound.play_event(guid, Sound.Event.UNIT_READY, position, 0)
		unit_trained.emit(self, unit_guid)
	if selected:
		_overlay.queue_redraw()


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
		if not complete:
			body_anim = 0
			var stages := _bob.anims[0].frames.size()
			frame_hint = mini(stages - 1, int(build_progress * stages))
		else:
			body_anim = 2 if _bob.anims.size() > 3 else 0
		shadow_anim = _bob.shadow_for(body_anim)
	elif shadow_anim == body_anim:
		shadow_anim = _bob.shadow_for(body_anim)
	if not _show(_body, body_anim, frame_hint):
		return false
	_body.material = SpriteMaterials.body(_body.get_meta("sheet"), _palette, _ramps)
	_shadow.visible = shadow_anim >= 0 and shadow_anim < _bob.anims.size() and _show(_shadow, shadow_anim, frame_hint)
	return true


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
		var radius := maxf(work.size.x * 0.55, 20.0)
		canvas.draw_set_transform(work.get_center() + Vector2(0, work.size.y * 0.3), 0.0, Vector2(1.0, 0.55))
		canvas.draw_arc(Vector2.ZERO, radius * (1.25 - _flash_time * 0.25), 0.0, TAU, 48,
				Color(_flash_color, _flash_time), 2.5, true)
		canvas.draw_set_transform(Vector2.ZERO)
	if Unit.debug_paths and object_type:
		canvas.draw_rect(rect, Color(0, 1, 1, 0.8), false, 1.5)
		canvas.draw_circle(Vector2.ZERO, 3, Color.RED)
	if not is_building() or not (selected or not complete):
		return
	if selected:
		canvas.draw_set_transform(rect.get_center() + Vector2(0, rect.size.y * 0.15), 0.0, Vector2(1.0, 0.55))
		canvas.draw_arc(Vector2.ZERO, rect.size.x * 0.6, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 2.0, true)
		canvas.draw_set_transform(Vector2.ZERO)
	var bar := Rect2(rect.position.x + rect.size.x * 0.2, rect.position.y - 16, rect.size.x * 0.6, 4)
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
