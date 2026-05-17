@tool
extends Node3D

@export_file("*.json") var manifest_path := "" :
	set(value):
		manifest_path = value
		if is_inside_tree():
			_load_manifest()

@export var animation_name := "idle" :
	set(value):
		animation_name = value
		animation_frame = 0
		elapsed = 0.0
		if is_inside_tree():
			_apply_current_frame()

var manifest: Dictionary = {}
var frames: Array = []
var animations: Dictionary = {}
var animation_frame := 0
var elapsed := 0.0
var sprite: Sprite3D

func _ready() -> void:
	_ensure_sprite()
	_load_manifest()

func _process(delta: float) -> void:
	if not animations.has(animation_name):
		return

	var animation: Dictionary = animations[animation_name]
	var sequence: Array = animation.get("frames", [])
	if sequence.is_empty():
		return

	elapsed += delta
	var frame_time := float(animation.get("frame_time", 0.2))
	if elapsed < frame_time:
		return

	elapsed = 0.0
	animation_frame += 1
	if animation_frame >= sequence.size():
		animation_frame = 0 if bool(animation.get("loop", true)) else sequence.size() - 1
	_apply_current_frame()

func _load_manifest() -> void:
	if manifest_path.is_empty():
		return

	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_warning("Could not open classic sprite manifest: %s" % manifest_path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Classic sprite manifest is not a JSON object: %s" % manifest_path)
		return

	manifest = parsed
	frames = manifest.get("frames", [])
	animations = manifest.get("animations", {})
	name = str(manifest.get("name", name))
	animation_frame = 0
	elapsed = 0.0

	_ensure_sprite()
	var texture_path := str(manifest.get("texture", ""))
	if not texture_path.is_empty():
		sprite.texture = _load_image_texture(texture_path)
	sprite.pixel_size = float(manifest.get("pixel_size", 0.025))
	sprite.region_enabled = true
	_apply_current_frame()

func _load_image_texture(texture_path: String) -> Texture2D:
	var image := Image.new()
	var error := image.load(texture_path)
	if error != OK:
		push_warning("Could not load classic sprite texture: %s" % texture_path)
		return null
	return ImageTexture.create_from_image(image)

func _ensure_sprite() -> void:
	if sprite != null and is_instance_valid(sprite):
		return

	sprite = get_node_or_null("Sprite") as Sprite3D
	if sprite == null:
		sprite = Sprite3D.new()
		sprite.name = "Sprite"
		add_child(sprite)
		if Engine.is_editor_hint():
			sprite.owner = get_tree().edited_scene_root

	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.centered = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

func _apply_current_frame() -> void:
	if sprite == null or frames.is_empty() or not animations.has(animation_name):
		return

	var animation: Dictionary = animations[animation_name]
	var sequence: Array = animation.get("frames", [])
	if sequence.is_empty():
		return

	var frame_index := int(sequence[clampi(animation_frame, 0, sequence.size() - 1)])
	if frame_index < 0 or frame_index >= frames.size():
		return

	var frame: Dictionary = frames[frame_index]
	sprite.region_rect = Rect2(
		float(frame.get("x", 0.0)),
		float(frame.get("y", 0.0)),
		float(frame.get("w", 0.0)),
		float(frame.get("h", 0.0))
	)
