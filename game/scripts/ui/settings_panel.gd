class_name SettingsPanel
extends VBoxContainer
## The rows of the settings screen (main menu and the in-game options): sliders, switches
## and the window size, each saved as soon as it changes.

const SLIDERS := [["Music volume", "music_volume", 0.0, 1.0, 0.05], ["Sound volume", "sound_volume", 0.0, 1.0, 0.05],
		["Scroll speed", "scroll_speed", 0.4, 2.5, 0.05], ["Interface size", "ui_scale", 0.7, 1.5, 0.05]]
const SWITCHES := [["Scroll at screen edges", "edge_scroll", ""], ["Full screen", "fullscreen", ""],
		["Vertical sync", "vsync", ""],
		["Classic graphics", "classic_graphics", "The original pixels instead of the upscaled set (from the next game)"]]

var text_size := 16
var label_width := 190.0


static func create(size: int, width: float) -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel.text_size = size
	panel.label_width = width
	panel._build()
	return panel


func _build() -> void:
	add_theme_constant_override("separation", int(text_size * 0.5))
	process_mode = Node.PROCESS_MODE_ALWAYS  # works in the paused in-game menu
	for row in SLIDERS:
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.value = Settings.value(row[1])
		slider.custom_minimum_size = Vector2(label_width, text_size * 1.5)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var key: String = row[1]
		var shown := MenuStyle.label(_percent(slider.value), int(text_size * 0.85), MenuStyle.TEXT_DIM)
		shown.custom_minimum_size.x = text_size * 3.5
		# The interface size is applied on release, so the slider doesn't move under the mouse.
		slider.value_changed.connect(func(v: float) -> void:
			shown.text = _percent(v)
			if key != "ui_scale":
				Settings.set_value(key, v))
		slider.drag_ended.connect(func(_changed: bool) -> void:
			if key == "ui_scale":
				Settings.set_value(key, slider.value))
		_add_row(row[0], [slider, shown])
	for row in SWITCHES:
		var box := CheckBox.new()
		box.button_pressed = Settings.enabled(row[1])
		box.focus_mode = Control.FOCUS_NONE
		var key: String = row[1]
		box.toggled.connect(func(on: bool) -> void:
			Settings.set_value(key, 1.0 if on else 0.0)
			_window_size.disabled = Settings.enabled("fullscreen"))
		if row[2] != "":
			box.tooltip_text = row[2]
		_add_row(row[0], [box])
	_window_size = OptionButton.new()
	for size: Vector2i in Settings.WINDOW_SIZES:
		_window_size.add_item("As it is" if size == Vector2i.ZERO else "%d × %d" % [size.x, size.y])
	_window_size.select(clampi(int(Settings.value("window_size")), 0, Settings.WINDOW_SIZES.size() - 1))
	_window_size.disabled = Settings.enabled("fullscreen")
	_window_size.focus_mode = Control.FOCUS_NONE
	_window_size.item_selected.connect(func(index: int) -> void: Settings.set_value("window_size", index))
	MenuStyle.style(_window_size, int(text_size * 0.9))
	_add_row("Window size", [_window_size])


var _window_size: OptionButton


func _add_row(caption: String, controls: Array) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(text_size * 0.6))
	var label := MenuStyle.label(caption, text_size)
	label.custom_minimum_size.x = label_width
	line.add_child(label)
	for control: Control in controls:
		line.add_child(control)
	add_child(line)


static func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100)
