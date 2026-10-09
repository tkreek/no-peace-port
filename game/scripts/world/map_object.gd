class_name MapObject
extends Node2D
## A static placed object (building or scenery) drawn from its original sprite and shadow.


const TREE_WOOD := 150
const MINE_GOLD := 3000

static var all_objects: Array[MapObject] = []

var object_type: ObjectTypes.ObjectType
var owner_index := 0
var amount := 0
var resource := ""  ## "wood" or "gold" for harvestable scenery, "" otherwise
var accepts: PackedStringArray = []  ## resources a building takes as a drop-off


func _enter_tree() -> void:
	all_objects.append(self)


func _exit_tree() -> void:
	all_objects.erase(self)


## Footprint rectangle in world space (for arrival checks and placement).
func footprint_rect() -> Rect2:
	if object_type == null or object_type.footprint_size == Vector2i.ZERO:
		return Rect2(position - Vector2(16, 16), Vector2(32, 32))
	return Rect2(position - Vector2(object_type.footprint_anchor), Vector2(object_type.footprint_size))


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


func setup(type: ObjectTypes.ObjectType, owner: int, placed_amount := 0) -> bool:
	object_type = type
	owner_index = owner
	if type.name.begins_with("Baum"):
		resource = "wood"
		amount = TREE_WOOD
	elif type.name.begins_with("Mine"):
		resource = "gold"
		amount = placed_amount if placed_amount > 0 else MINE_GOLD
	elif type.kind == ObjectTypes.Kind.BUILDING:
		accepts = _drop_off_for(type.name)
	var bob := GameData.load_bob(type.bob_path)
	if bob == null or bob.anims.is_empty():
		return false
	var body_anim := type.anim
	var shadow_anim := type.shadow_anim
	if type.kind == ObjectTypes.Kind.BUILDING:
		# Buildings: anim 0/1 are construction stages; 2/3 hold the finished frame.
		body_anim = 2 if bob.anims.size() > 3 else 0
		shadow_anim = bob.shadow_for(body_anim)
	elif shadow_anim == body_anim:
		shadow_anim = bob.shadow_for(body_anim)
	var palette := GameData.load_palette_texture(type.directory(), bob.palettes)
	var ramps := GameData.load_ramps(type.bob_path)
	var team_row := owner if type.kind == ObjectTypes.Kind.BUILDING and owner > 0 else 0
	if shadow_anim >= 0 and shadow_anim < bob.anims.size():
		var shadow := _sprite(bob, shadow_anim)
		if shadow:
			SpriteMaterials.make_shadow(shadow)
			add_child(shadow)
	var body := _sprite(bob, body_anim)
	if body == null:
		return false
	body.material = SpriteMaterials.body(body.get_meta("sheet"), palette, ramps)
	add_child(body)
	body.set_instance_shader_parameter("palette_row", mini(team_row, bob.palettes.size() - 1))
	return true


func _sprite(bob: BobFile, anim_index: int) -> Sprite2D:
	var anim := bob.anims[anim_index]
	var sheet := GameData.load_sprite(object_type.directory().path_join(bob.sub_sprites[anim.sub_sprite]))
	if sheet == null or anim.frames.is_empty():
		return null
	var frame := anim.frames[anim.frames.size() - 1]
	if frame >= sheet.frame_count():
		return null
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.region_enabled = true
	SpriteMaterials.prepare(sprite, sheet)
	sheet.apply(sprite, frame)
	sprite.set_meta("sheet", sheet)
	return sprite


## Which resources a building accepts, from its original object name.
static func _drop_off_for(name: String) -> PackedStringArray:
	if name.contains("_HQ") or name.contains("Hauptzelt") or name.contains("Basis"):
		return PackedStringArray(["wood", "gold", "food", "leather"])
	if name.contains("Saege") or name.contains("Holz") or name.contains("Tischlerei"):
		return PackedStringArray(["wood"])
	if name.contains("Gold"):
		return PackedStringArray(["gold"])
	return PackedStringArray()
