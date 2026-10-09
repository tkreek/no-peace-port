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

var _bob: BobFile
var _body: Sprite2D
var _shadow: Sprite2D
var _palette: Texture2D
var _ramps: Texture2D
var _overlay := DrawOverlay.new()


func _enter_tree() -> void:
	if not is_ghost:
		all_objects.append(self)


func _exit_tree() -> void:
	all_objects.erase(self)


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
	return object_type != null and object_type.kind == ObjectTypes.Kind.BUILDING


func display_name() -> String:
	return GameData.type_name(object_type.id) if object_type else "?"


## Footprint rectangle in world space (for arrival checks and placement).
func footprint_rect() -> Rect2:
	return footprint_rect_for(object_type, position)


static func footprint_rect_for(type: ObjectTypes.ObjectType, at: Vector2) -> Rect2:
	if type == null or type.footprint_size == Vector2i.ZERO:
		return Rect2(at - Vector2(16, 16), Vector2(32, 32))
	return Rect2(at - Vector2(type.footprint_anchor), Vector2(type.footprint_size))


## Take up to `wanted` units of this object's resource; removes depleted trees.
func harvest(wanted: int) -> int:
	var taken := mini(wanted, amount)
	amount -= taken
	if amount <= 0 and resource == "wood":
		if NavGrid.current:
			NavGrid.current.unblock_footprint(object_type, position)
		resource = ""
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 1.5)
		tween.tween_callback(queue_free)
	return taken


func setup(type: ObjectTypes.ObjectType, owner: int, placed_amount := 0, under_construction := false) -> bool:
	object_type = type
	owner_index = owner
	guid = GameData.guid_for_type(type.id)
	if type.name.begins_with("Baum"):
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
			accepts = _drop_off_for(type.name)
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
	var team_row := owner if type.kind == ObjectTypes.Kind.BUILDING and owner > 0 else 0
	_body.set_instance_shader_parameter("palette_row", mini(team_row, _bob.palettes.size() - 1))
	return true


## Add construction work (worker-seconds); returns true when the building completes.
func add_build_work(seconds: float) -> bool:
	if complete:
		return true
	var total := maxf(10.0, max_health * BUILD_WORK_PER_HEALTH)
	build_progress = minf(1.0, build_progress + seconds / total)
	health = maxf(health, max_health * (0.1 + 0.9 * build_progress))
	_refresh_sprites()
	_overlay.queue_redraw()
	if build_progress >= 1.0:
		complete = true
		health = max_health
		accepts = _drop_off_for(object_type.name)
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
	if queue.size() >= QUEUE_LIMIT:
		return false
	var player: Player = Player.by_index.get(owner_index)
	var cost: Dictionary = GameData.stats(unit_guid).get("cost", {}).duplicate()
	cost.erase("population")
	cost.erase("horses")
	if player == null or not player.has_room() or not player.spend(cost):
		return false
	queue.append(unit_guid)
	return true


func _process(delta: float) -> void:
	if queue.is_empty() or not complete:
		return
	var unit_guid := queue[0]
	var seconds: float = TRAIN_SECONDS.default
	if GameData.stats(unit_guid).get("damage", 0) <= 4:
		seconds = TRAIN_SECONDS.worker
	train_progress += delta / seconds
	if train_progress >= 1.0:
		train_progress = 0.0
		queue.remove_at(0)
		Sound.play_event(guid, Sound.Event.UNIT_READY, position, 0)
		unit_trained.emit(self, unit_guid)
	if selected:
		_overlay.queue_redraw()


func _refresh_sprites() -> bool:
	var body_anim := object_type.anim
	var shadow_anim := object_type.shadow_anim
	var frame_hint := -1  # -1 = last frame of the animation
	if is_building():
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


## Which resources a building accepts, from its original object name.
static func _drop_off_for(name: String) -> PackedStringArray:
	if name.contains("_HQ") or name.contains("Hauptzelt") or name.contains("Basis"):
		return PackedStringArray(["wood", "gold", "food", "leather"])
	if name.contains("Saege") or name.contains("Holz") or name.contains("Tischlerei"):
		return PackedStringArray(["wood"])
	if name.contains("Gold"):
		return PackedStringArray(["gold"])
	return PackedStringArray()
