class_name HudStyle
extends RefCounted
## Shared pieces of the in-game interface: the parchment text colour, flat boxes, labels,
## sprite-sheet frames as textures, and the borderless icon buttons of the command bar.

const TEXT_COLOR := Color("#f3e3bd")
const PARCHMENT := Color(0.93, 0.84, 0.64, 0.92)
const INK := Color("#3a2410")
## The status bar's small icons: 0 rifle, 1 gold, 2 wood, 4 food, 5 face (population),
## 6 horseshoe, 8 heart (energy), 9 fist, 10 star (experience), 11 lightning (magic),
## 12 laurel (morale), 13 eye (sight).
const STATUS_ICONS := "interface/hud/resource_icons/resource_icons.anims.json"

static var _status_sheet: RdSprite
static var _status_material: Material


static func flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


static func label(size: int) -> Label:
	var l := Label.new()
	style_label(l, size)
	return l


static func style_label(l: Label, size: int) -> void:
	l.add_theme_color_override("font_color", TEXT_COLOR)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func atlas(sheet: RdSprite, frame: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = sheet.texture
	texture.region = Rect2(sheet.rects[frame])
	return texture


## A frame's size in original pixels (the upscaled sheets are larger).
static func frame_size(sheet: RdSprite, frame: int) -> Vector2:
	return Vector2(sheet.rects[frame].size) / sheet.scale


## One of the status bar's small icons (palette-drawn, like the original).
static func status_icon(frame: int, tip := "") -> TextureRect:
	if _status_sheet == null:
		var bob := GameData.load_bob(STATUS_ICONS)
		_status_sheet = GameData.load_set_sheet(STATUS_ICONS, bob, 0)
		_status_material = SpriteMaterials.body(_status_sheet, null)
	var icon := TextureRect.new()
	icon.texture = atlas(_status_sheet, frame)
	icon.material = _status_material
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.tooltip_text = tip
	icon.set_instance_shader_parameter("palette_row", 0)
	return icon


static func clear_styles(button: BaseButton) -> void:
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, none)


## A borderless button showing one icon from a sheet, brightened on hover; `active` rings it.
static func icon_button(sheet: RdSprite, frame: int, tip: String, active := false) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	clear_styles(button)
	if active:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = Color(1.0, 0.85, 0.3)
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", ring)
		button.add_theme_stylebox_override("hover", ring)
	button.tooltip_text = tip
	if sheet and frame < sheet.frame_count():
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = atlas(sheet, frame)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(icon)
		button.mouse_entered.connect(func() -> void: icon.modulate = Color(1.2, 1.15, 1.0))
		button.mouse_exited.connect(func() -> void: icon.modulate = Color.WHITE)
	return button


## A card for a parchment-coloured name when there is no picture (upgrades, trades).
static func name_card(text: String, size: int) -> Panel:
	var name := MenuStyle.label(text, size, INK)
	name.add_theme_constant_override("outline_size", 0)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := Panel.new()
	paper.add_theme_stylebox_override("panel", flat(Color(0.93, 0.84, 0.64, 0.95)))
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(name)
	name.set_anchors_preset(Control.PRESET_FULL_RECT)
	return paper


## A thin progress bar (training, research).
static func progress_bar(fill: Color, background := Color(0.12, 0.08, 0.05, 0.85)) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", flat(background))
	bar.add_theme_stylebox_override("fill", flat(fill))
	bar.max_value = 1.0
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar
