class_name MapObject
extends Node2D
## A placed object, building or scenery (trees, mines, rocks, fields), drawn from its
## original sprite and shadow: where it stands, who owns it, how it looks, and whether a
## click lands on it.
##
## What it holds is its `stock` (wood, gold, crops, warehoused gold, an abandoned store's
## goods). Buildings also have a `condition` (construction, damage, fire, repair, their
## end), `production` (training, research, trades, income) and `defence` (garrison,
## pitfall); these are null for scenery and fields.

signal construction_finished(building: MapObject)
signal unit_trained(building: MapObject, unit_guid: int)
signal destroyed(building: MapObject)

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
## Fields lie flat on the ground: beneath the women working them, whose feet may be above
## the field's middle (where y-sorting would put them under it), and beneath corpses and
## shadows (z -1).
const FIELD_Z := -2
const GOLD_MINE_GUID := 700  # selection sound "gold_mine"
const PITFALL_GUID := BuildingDefence.PITFALL_GUID
## Wharves and the boathouse launch boats, so they go up at the water's edge.
const SHIPYARDS := [218, 418, 315]
const SHORE_REACH := 3  # cells of water at most this far from the footprint
## Building anims shared by every building descriptor (body/shadow pairs).
const BURNT_ANIM := 7  # the burnt-out building, shown below a third of its energy
const RUBBLE_ANIM := 9
const AMBIENT_ANIM := 11  # a moving part (windmill sails...) and 12 its shadow

static var all_objects: Array[MapObject] = []
## Buildings and fields: the few hundred objects worth scanning (all_objects also holds the
## thousands of trees, rocks and mines).
static var structures: Array[MapObject] = []
static var abandoned_stores: Array[MapObject] = []

var object_type: ObjectTypes.ObjectType
var is_ghost := false  ## placement preview: not part of the world
var owner_index := 0
var guid := -1
var accepts: PackedStringArray = []  ## resources a building takes as a drop-off
var selected := false:
	set(value):
		selected = value
		_overlay.queue_redraw()
var max_health := 0.0
var health := 0.0
var complete := true
var build_progress := 1.0  # 0..1 while under construction

var stock: ObjectStock
var condition: BuildingCondition
var production: BuildingProduction
var defence: BuildingDefence

var _bob: BobFile
var _body: Sprite2D
var _shadow: Sprite2D
var _ramps: Texture2D
var _overlay := DrawOverlay.new()
var _work_rect := Rect2()
var _walls: Array[Rect2] = []  # the solid footprint cells as row runs, relative to position
var _team_row := 0
var _body_anim := -1
var _ambient: Sprite2D
var _ambient_step := 0
var _ambient_time := 0.0
var _flash_time := 0.0
var _flash_color := Color.WHITE
var _is_building := false
var _is_tree := false


func setup(type: ObjectTypes.ObjectType, owner: int, placed_amount := 0, under_construction := false) -> bool:
	object_type = type
	owner_index = owner
	guid = GameData.guid_for_type(type.id)
	_is_building = (type.kind == ObjectTypes.Kind.BUILDING or guid == PITFALL_GUID) and guid != FIELD_GUID
	stock = ObjectStock.new(self, placed_amount)
	if _is_building:
		condition = BuildingCondition.new(self)
		production = BuildingProduction.new(self)
		defence = BuildingDefence.new(self)
		max_health = GameData.stats(guid).get("health", 1000)
		health = max_health
		if under_construction:
			complete = false
			build_progress = 0.0
			health = max_health * 0.1
		else:
			accepts = drop_off_for(guid)
	_bob = GameData.load_bob(type.anims)
	if _bob == null or _bob.anims.is_empty():
		return false
	_is_tree = type.name.begins_with("tree") and _bob.anims.size() > ObjectStock.TREE_STUMP_ANIM + 1
	if is_field():
		z_index = FIELD_Z
	_ramps = GameData.load_ramps(type.anims)
	_shadow = Sprite2D.new()
	_body = Sprite2D.new()
	SpriteMaterials.make_shadow(_shadow)
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
	add_child(_shadow)
	add_child(_body)
	add_child(_overlay)
	if not refresh_sprites():
		return false
	_team_row = mini(owner if type.kind == ObjectTypes.Kind.BUILDING and owner > 0 else 0, _bob.teams - 1)
	_body.set_instance_shader_parameter("palette_row", _palette_row(_body_anim))
	return true


func _enter_tree() -> void:
	if not is_ghost:
		all_objects.append(self)
		if is_building() or is_field():
			structures.append(self)
		if is_abandoned_store():
			abandoned_stores.append(self)


func _exit_tree() -> void:
	forget()


## Off the lists (the node may live on a moment longer, fading out or freed).
func forget() -> void:
	all_objects.erase(self)
	structures.erase(self)
	abandoned_stores.erase(self)


## Godot turns on per-frame processing for every node with a _process when it enters the
## tree; only buildings and fields need it (trees, mines and rocks are thousands strong).
func _ready() -> void:
	set_process(_flash_time > 0.0 or (not is_ghost and (is_building() or is_field())))


# ------------------------------------------------------------------ what it is

func is_building() -> bool:
	return _is_building


func is_field() -> bool:
	return guid == FIELD_GUID


func is_tree() -> bool:
	return _is_tree


func is_mine() -> bool:
	return object_type != null and object_type.name.begins_with("mine")


func is_trap() -> bool:
	return guid == PITFALL_GUID


func is_gold_warehouse() -> bool:
	return guid in DROP_OFFS.gold and guid not in MAIN_BUILDINGS


func is_abandoned_store() -> bool:
	return stock != null and stock.is_abandoned_store()


func is_alive() -> bool:
	return not _is_building or health > 0.0


func display_name() -> String:
	if is_tree():
		return "Tree"
	return GameData.type_name(object_type.id) if object_type else "?"


func take_damage(amount: float, attacker: Node2D = null, _splash := false) -> void:
	if _is_building:
		condition.take_damage(amount, attacker)


## Briefly pulse the object and ring it, to confirm it was picked as an order's target.
func flash(color := Color(1.0, 0.9, 0.4)) -> void:
	_flash_time = 1.0
	_flash_color = color
	set_process(true)


func redraw_overlay() -> void:
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		var pulse := 0.5 + 0.5 * sin(_flash_time * TAU * 3.0)
		_body.self_modulate = Color.WHITE.lerp(_flash_color * 1.6, pulse * _flash_time)
		_overlay.queue_redraw()
		if _flash_time <= 0.0:
			_body.self_modulate = Color.WHITE
			set_process(is_building() or is_field())
	if is_field():
		stock.grow(delta)
	if _ambient:
		_advance_ambient(delta)
	if not _is_building:
		return
	defence.update(delta)
	if condition.burning > 0.0:
		condition.burn(delta)
	if complete:
		production.update(delta)
		if guid in BuildingProduction.GUN_FACTORIES and (_ambient != null) != _ambient_wanted():
			_update_ambient()
		if selected and not production.queue.is_empty():
			_overlay.queue_redraw()


# ------------------------------------------------------------------ where it stands

## Footprint rectangle in world space (for arrival checks and placement).
func footprint_rect() -> Rect2:
	return footprint_rect_for(object_type, position)


static func footprint_rect_for(type: ObjectTypes.ObjectType, at: Vector2) -> Rect2:
	if type == null or type.footprint_size == Vector2i.ZERO:
		return Rect2(at - Vector2(16, 16), Vector2(32, 32))
	return Rect2(at - Vector2(type.footprint_anchor), Vector2(type.footprint_size))


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


## The solid footprint cells (walls, trunk, mine entrance) as one rectangle per row run,
## relative to the position. Empty for objects without solid cells.
func _wall_runs() -> Array[Rect2]:
	if _walls.is_empty() and object_type and not object_type.footprint_cells.is_empty():
		var grid := object_type.footprint_grid
		var origin := -Vector2(object_type.footprint_anchor)
		for y in grid.y:
			var x := 0
			while x < grid.x:
				if object_type.footprint_cells[y * grid.x + x] & NavGrid.SOLID:
					var start := x
					while x < grid.x and object_type.footprint_cells[y * grid.x + x] & NavGrid.SOLID:
						x += 1
					_walls.append(Rect2(origin + Vector2(start, y) * NavGrid.CELL, Vector2(x - start, 1) * NavGrid.CELL))
				x += 1
	return _walls


## The point of the walls nearest `from` (the solid cells, not their bounding rectangle,
## which for an L-shaped or diagonal building takes in a lot of open ground).
func wall_point(from: Vector2) -> Vector2:
	var runs := _wall_runs()
	if runs.is_empty() or is_field():
		var rect := work_rect()
		return from.clamp(rect.position, rect.end)
	var local := from - position
	var best := Vector2.INF
	for run in runs:
		var p := local.clamp(run.position, run.end)
		if p.distance_squared_to(local) < best.distance_squared_to(local):
			best = p
	return best + position


## Whether `point` is within `reach` of the walls (workers at a site, units at quarters...).
func near_walls(point: Vector2, reach: float) -> bool:
	return wall_point(point).distance_to(point) <= reach


## Where the object's current picture is drawn, in world coordinates (canopy, roof...).
func visual_rect() -> Rect2:
	if _body == null or _body.texture == null:
		return footprint_rect()
	return _body.get_global_transform() * _body.get_rect()


## Whether a click at `point` (world) lands on this object: on a solid pixel of its picture
## (walls, roof, canopy), or on its walls' ground area.
func hit(point: Vector2) -> bool:
	if near_walls(point, 4.0):
		return true
	if _body == null or _body.texture == null or not visual_rect().has_point(point):
		return false
	return _body.is_pixel_opaque(_body.to_local(point))


## Somewhere on the building itself: a solid pixel in the upper part of its picture.
func fire_spot(rng: RandomNumberGenerator) -> Vector2:
	var picture := visual_rect()
	for attempt in 16:
		var candidate := Vector2(rng.randf_range(picture.position.x + picture.size.x * 0.2, picture.end.x - picture.size.x * 0.2),
				rng.randf_range(picture.position.y + picture.size.y * 0.25, picture.position.y + picture.size.y * 0.7))
		if _body.is_pixel_opaque(_body.to_local(candidate)):
			return candidate
	return work_rect().get_center()


## Whether a footprint of `type` at `at` touches water (for shipyards).
static func by_water(type: ObjectTypes.ObjectType, at: Vector2) -> bool:
	var nav := NavGrid.current
	if nav == null or not nav.has_water:
		return false
	var rect := footprint_rect_for(type, at).grow(SHORE_REACH * NavGrid.CELL)
	var low := nav.cell_of(rect.position)
	var high := nav.cell_of(rect.end)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			if nav.is_deep_water(Vector2i(x, y)):
				return true
	return false


## Which resources a building accepts.
static func drop_off_for(building_guid: int) -> PackedStringArray:
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
	for object in structures:
		if object.owner_index != team:
			continue
		if object.guid in FOOD_STORES and object.complete and object.is_alive():
			stores += 1
		elif object.is_field():
			fields += 1
	return stores * FIELDS_PER_STORE - fields


## Saved games: a building's or field's state (`unit_ids` numbers the units, for the garrison).
func save_state(unit_ids: Dictionary) -> Dictionary:
	var entry := {"type": object_type.id, "x": position.x, "y": position.y, "owner": owner_index,
			"complete": complete, "progress": build_progress, "health": health,
			"amount": stock.amount, "field_state": stock.field_state, "field_progress": stock.field_progress,
			"stored_gold": stock.stored_gold, "loot_kind": stock.loot_kind, "loot": stock.loot}
	if _is_building:
		entry.merge({"queue": Array(production.queue), "train": production.progress, "distilling": production.distilling,
				"rally": [production.rally_point.x, production.rally_point.y] if production.rally_point != Vector2.INF else null,
				"trap_kills": defence.trap_kills, "burning": condition.burning,
				"garrison": defence.garrison.filter(func(u: Unit) -> bool: return unit_ids.has(u)).map(func(u: Unit) -> int: return unit_ids[u])})
	return entry


func restore_state(entry: Dictionary) -> void:
	complete = bool(entry.complete)
	build_progress = float(entry.progress)
	health = float(entry.health)
	stock.restore(entry)
	if _is_building:
		production.restore(entry)
		defence.trap_kills = int(entry.get("trap_kills", 0))
		if complete:
			accepts = drop_off_for(guid)
		if float(entry.get("burning", 0.0)) > 0.0:
			condition.ignite.call_deferred(float(entry.burning))
	refresh_sprites()
	if _is_building:
		condition.update_fires()
	_overlay.queue_redraw()


# ------------------------------------------------------------------ pictures

## Show the picture for the object's state; false when its sheet cannot be loaded.
func refresh_sprites() -> bool:
	var body_anim := object_type.anim
	var shadow_anim := object_type.shadow_anim
	var frame_hint := -1  # -1 = last frame of the animation
	if is_tree() and stock.tree_state != ObjectStock.TreeState.STANDING:
		body_anim = ObjectStock.TREE_FELLED_ANIM if stock.tree_state == ObjectStock.TreeState.FELLED else ObjectStock.TREE_STUMP_ANIM
		shadow_anim = body_anim + 1
	elif is_mine() and _bob.anims.size() >= 6:
		# Anim pairs (body, shadow): 0/1 untouched, 2/3 framing -> timbered, 4/5 exhausted.
		match stock.mine_stage():
			0:
				body_anim = 0
			1, 2:
				body_anim = 2
				frame_hint = stock.mine_stage() - 1
			3:
				body_anim = 4
		shadow_anim = body_anim + 1
	elif is_field():
		body_anim = 0
		var frames := _bob.anims[0].frames
		var wanted: int = ObjectStock.FIELD_STAGES[stock.field_stage()]
		frame_hint = frames.find(wanted) if frames.has(wanted) else 0
		shadow_anim = -1
	elif _is_building:
		# Construction stages are the frames of anim 0 (shadow anim 1); 2/3 hold the finished frame.
		if not complete and health > 0.0:
			body_anim = 0
			var stages := _construction_stages()
			frame_hint = mini(stages - 1, int(build_progress * stages))
		else:
			body_anim = 2 if _bob.anims.size() > 3 else 0
			frame_hint = 0 if body_anim == 2 else -1  # walls list several pictures; the first is the one built
		if health <= 0.0 and _has_sheet(RUBBLE_ANIM):
			body_anim = RUBBLE_ANIM
			frame_hint = 0
		elif condition.burnt() and _has_sheet(BURNT_ANIM):
			body_anim = BURNT_ANIM
			frame_hint = 0
		shadow_anim = _bob.shadow_for(body_anim)
	elif shadow_anim == body_anim:
		shadow_anim = _bob.shadow_for(body_anim)
	if not _show(_body, body_anim, frame_hint):
		return false
	_body.material = SpriteMaterials.body(_body.get_meta("sheet"), _ramps)
	if body_anim != _body_anim:
		_body_anim = body_anim
		_body.set_instance_shader_parameter("palette_row", _palette_row(body_anim))
	if _is_building:
		_update_ambient()
	_shadow.visible = shadow_anim >= 0 and shadow_anim < _bob.anims.size() and _show(_shadow, shadow_anim, frame_hint)
	return true


## How many of anim 0's frames are construction stages: up to the finished picture. Many
## lists run on past it (a stray repeat of the first stage, or a placement-preview frame),
## which would flash the bare foundation or a preview just before completion.
func _construction_stages() -> int:
	var frames := _bob.anims[0].frames
	if _bob.anims.size() > 2:
		var finished := _bob.anims[2].frames
		for i in frames.size():
			if finished.has(frames[i]):
				return i + 1
	return frames.size()


func shows_rubble() -> bool:
	return _body_anim == RUBBLE_ANIM


## Colour row for a sheet: the team's (sheets without team colours ignore it).
func _palette_row(_anim_index: int) -> int:
	return _team_row


func _has_sheet(anim_index: int) -> bool:
	return anim_index < _bob.anims.size() and not _bob.sub_sprite_is_shadow[_bob.anims[anim_index].sub_sprite]


## Buildings with a moving part (the farm's windmill...) run it once they are finished; the
## weapons factories' glowing furnace only while they are making something.
func _ambient_wanted() -> bool:
	if not complete or condition.burnt() or not _has_sheet(AMBIENT_ANIM) or _bob.anims[AMBIENT_ANIM].frames.size() <= 1:
		return false
	return guid not in BuildingProduction.GUN_FACTORIES or not production.queue.is_empty()


func _update_ambient() -> void:
	if not _ambient_wanted():
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
		_ambient.material = SpriteMaterials.body(_ambient.get_meta("sheet"), _ramps)
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
	var sheet := GameData.load_set_sheet(object_type.anims, _bob, anim.sub_sprite)
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
	if not _is_building or not (selected or not complete):
		return
	var width := maxf(walls.size.x, 48.0)
	var bar := Rect2(walls.get_center().x - width * 0.4, rect.position.y - 16, width * 0.8, 4)
	canvas.draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
	if not complete:
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * build_progress, bar.size.y)), Color(0.95, 0.75, 0.2))
	else:
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / max_health, bar.size.y)), Color(0.3, 0.9, 0.2))
		if not production.queue.is_empty():
			var train := Rect2(bar.position + Vector2(0, 6), bar.size)
			canvas.draw_rect(train, Color(0.1, 0.1, 0.1, 0.8))
			canvas.draw_rect(Rect2(train.position, Vector2(train.size.x * production.progress, train.size.y)), Color(0.4, 0.7, 1.0))
