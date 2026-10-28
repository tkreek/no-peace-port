class_name SaveBrowser
extends VBoxContainer
## The saved games, for choosing one to load or for saving under a name (in the game menu
## and on the main menu's Load game screen): one row per save, newest first, with its picture,
## its name, where it was played, when it was saved and how long the game had run. Saving: a
## name to type (a fresh one offered), or a row picked to save over, after asking. Either way
## a save can be deleted, after asking.

const ROW_COLOR := Color(0.16, 0.09, 0.04, 0.75)
const ROW_HOVER := Color(0.3, 0.17, 0.07, 0.9)
const ROW_LIT := Color(0.4, 0.23, 0.08, 0.95)
const LIT_BORDER := Color(1.0, 0.85, 0.3)

var saving := false
var _scale := 1.0
var _on_save: Callable  # (name) -> void, when saving
var _on_load: Callable  # (path) -> void, when loading
var _saves: Array[Dictionary] = []
var _selected := -1
var _name_edit := LineEdit.new()
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _status: Label
var _buttons := HBoxContainer.new()
var _confirm := HBoxContainer.new()
var _go: Button
var _delete: Button
var _asking := Callable()  # what Yes does while a question is up


## `saving`: the save page (on_done(name)), else the load page (on_done(path)); `on_back`
## for the Back button. Sizes are multiplied by `scale`.
func _init(save_page: bool, scale: float, on_done: Callable, on_back: Callable, offered_name := "") -> void:
	saving = save_page
	_scale = scale
	if saving:
		_on_save = on_done
	else:
		_on_load = on_done
	add_theme_constant_override("separation", int(10 * scale))
	if saving:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", int(8 * scale))
		line.add_child(MenuStyle.label("Name", int(17 * scale)))
		_name_edit.text = offered_name
		_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_edit.max_length = 60
		_name_edit.select_all_on_focus = true
		MenuStyle.style(_name_edit, int(17 * scale))
		_name_edit.add_theme_color_override("caret_color", MenuStyle.TEXT_HOVER)
		_name_edit.add_theme_color_override("selection_color", Color(0.55, 0.3, 0.12, 0.8))
		var box := _box(Color(0.1, 0.05, 0.02, 0.95), Color(0.5, 0.34, 0.16))
		box.set_content_margin_all(5 * scale)
		_name_edit.add_theme_stylebox_override("normal", box)
		var focused := box.duplicate()
		focused.border_color = Color(0.8, 0.6, 0.3)
		_name_edit.add_theme_stylebox_override("focus", focused)
		_name_edit.text_submitted.connect(func(_text: String) -> void: _press_go())
		_name_edit.text_changed.connect(func(_text: String) -> void: _sync_selection())
		line.add_child(_name_edit)
		add_child(line)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(560, 330) * scale
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", int(4 * scale))
	_scroll.add_child(_rows)
	add_child(_scroll)
	_status = MenuStyle.label("", int(15 * scale), MenuStyle.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 560 * scale
	add_child(_status)
	for row: HBoxContainer in [_buttons, _confirm]:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", int(12 * scale))
		add_child(row)
	_go = _button("Save" if saving else "Load", _press_go)
	_delete = _button("Delete", _press_delete)
	_buttons.add_child(_go)
	_buttons.add_child(_delete)
	_buttons.add_child(_button("Back", on_back))
	_confirm.add_child(_button("Yes", func() -> void:
		var action := _asking
		_ask("", Callable())
		action.call()))
	_confirm.add_child(_button("No", func() -> void: _ask("", Callable())))
	_confirm.visible = false
	refresh()


func _ready() -> void:
	if saving:
		_name_edit.grab_focus.call_deferred()


## Read the list of saves again and show it.
func refresh() -> void:
	_saves = SaveGame.list()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in _saves.size():
		_rows.add_child(_row(i))
	if _saves.is_empty():
		var none := MenuStyle.label("No saved games yet.", int(16 * _scale), MenuStyle.TEXT_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(none)
	_ask("", Callable())
	if saving:
		_sync_selection()
	else:
		select(0 if not _saves.is_empty() else -1)


func saves() -> Array[Dictionary]:
	return _saves


func selected() -> int:
	return _selected


func set_save_name(text: String) -> void:
	_name_edit.text = text
	_sync_selection()


func save_name() -> String:
	return _name_edit.text.strip_edges()


## Whether a question (save over, delete) waits for Yes or No.
func asking() -> bool:
	return _confirm.visible


## Pick a row (-1: none); when saving its name goes into the name field.
func select(index: int) -> void:
	_selected = index if index >= 0 and index < _saves.size() else -1
	for row: Button in _rows.get_children().filter(func(c: Node) -> bool: return c is Button):
		_light(row, row.get_index() == _selected)
	if saving and _selected >= 0 and _name_edit.text.strip_edges() != _saves[_selected].name:
		_name_edit.text = _saves[_selected].name
	_update_buttons()


## Saving: the row whose file the typed name would write to is the one lit.
func _sync_selection() -> void:
	var path := SaveGame.path_for(_name_edit.text)
	var index := -1
	for i in _saves.size():
		if _saves[i].path == path:
			index = i
	_selected = index
	for row: Button in _rows.get_children().filter(func(c: Node) -> bool: return c is Button):
		_light(row, row.get_index() == _selected)
	_update_buttons()


func _update_buttons() -> void:
	_go.disabled = save_name() == "" if saving else _selected < 0
	_delete.disabled = _selected < 0


## Save (asking first when that overwrites a save), or load the picked save.
func _press_go() -> void:
	if asking() or _go.disabled:
		return
	if not saving:
		_on_load.call(_saves[_selected].path)
		return
	var save_name := save_name()
	if FileAccess.file_exists(SaveGame.path_for(save_name)):
		var old := _selected
		_ask("Save over “%s”?" % (_saves[old].name if old >= 0 else save_name), func() -> void: _on_save.call(save_name))
	else:
		_on_save.call(save_name)


func _press_delete() -> void:
	if asking() or _selected < 0:
		return
	var entry := _saves[_selected]
	_ask("Delete “%s”?" % entry.name, func() -> void:
		SaveGame.delete(entry.path)
		refresh())


## A line under the list (a save that could not be read or written).
func tell(text: String) -> void:
	_ask("", Callable())
	_status.text = text
	_status.visible = text != ""


## Put a question with Yes and No in place of the buttons (empty: take it away).
func _ask(question: String, action: Callable) -> void:
	_asking = action
	_confirm.visible = question != ""
	_buttons.visible = question == ""
	_status.text = question
	_status.add_theme_color_override("font_color", MenuStyle.TEXT if question != "" else MenuStyle.TEXT_DIM)
	_status.visible = question != ""


func _row(index: int) -> Button:
	var entry := _saves[index]
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 66) * _scale
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.tooltip_text = entry.path.get_file()
	_light(row, false)
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 6 * _scale
	line.offset_right = -8 * _scale
	line.add_theme_constant_override("separation", int(10 * _scale))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(96, 54) * _scale
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if entry.thumbnail:
		picture.texture = ImageTexture.create_from_image(entry.thumbnail)
	else:
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel", _box(Color(0.08, 0.04, 0.02, 0.9), Color(0.35, 0.24, 0.12)))
		blank.set_anchors_preset(Control.PRESET_FULL_RECT)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(blank)
	line.add_child(picture)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", int(2 * _scale))
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := MenuStyle.label(entry.name, int(18 * _scale))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title)
	var details := PackedStringArray()
	if entry.place != "":
		details.append(entry.place)
	details.append("played %s" % _duration(entry.game_time))
	var about := MenuStyle.label(" · ".join(details), int(14 * _scale), MenuStyle.TEXT_DIM)
	about.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	about.clip_text = true
	about.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(about)
	line.add_child(text)
	var when := MenuStyle.label(_date(int(entry.saved)), int(14 * _scale), MenuStyle.TEXT_DIM)
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	when.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(when)
	row.add_child(line)
	row.pressed.connect(func() -> void: select(index))
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			select(index)
			_press_go())
	return row


## A row's look: lit when it is the save picked.
func _light(row: Button, on: bool) -> void:
	var normal := _box(ROW_LIT if on else ROW_COLOR, LIT_BORDER if on else Color(0.35, 0.24, 0.12))
	normal.set_border_width_all(2 if on else 1)
	var hover := normal.duplicate()
	hover.bg_color = ROW_LIT if on else ROW_HOVER
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", hover)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(130, 34) * _scale
	MenuStyle.style(button, int(17 * _scale))
	button.add_theme_color_override("font_disabled_color", MenuStyle.TEXT_DIM.darkened(0.3))
	var normal := _box(Color(0.3, 0.17, 0.08), Color(0.6, 0.42, 0.2))
	var hover := normal.duplicate()
	hover.bg_color = Color(0.48, 0.27, 0.1)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.2, 0.12, 0.06, 0.8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.pressed.connect(action)
	return button


func _box(colour: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	return box


## When a save was made, in the computer's local time.
static func _date(unix: int) -> String:
	if unix <= 0:
		return ""
	var at := Time.get_datetime_dict_from_unix_time(unix + Time.get_time_zone_from_system().bias * 60)
	return "%04d-%02d-%02d\n%02d:%02d" % [at.year, at.month, at.day, at.hour, at.minute]


## A game's running time as h:mm:ss (m:ss under an hour).
static func _duration(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]
