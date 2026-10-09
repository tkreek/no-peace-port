class_name MenuStyle
extends RefCounted
## Shared look for menus and the HUD: a period serif (from the system, upgraded from the
## original 10 px bitmap fonts) in the parchment colour of the original menu font.

const TEXT := Color("#f0dfb4")
const TEXT_DIM := Color("#a8987a")
const TEXT_HOVER := Color("#ffe9a8")
const OUTLINE := Color(0.08, 0.05, 0.02)

static var _font: Font


static func font() -> Font:
	if _font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua",
				"DejaVu Serif", "Liberation Serif", "Noto Serif", "serif"])
		system.font_weight = 600
		_font = system
	return _font


static func label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	style(l, size, color)
	return l


static func style(control: Control, size: int, color := TEXT) -> void:
	control.add_theme_font_override("font", font())
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_outline_color", OUTLINE)
	control.add_theme_constant_override("outline_size", maxi(2, size / 6))


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	return t
