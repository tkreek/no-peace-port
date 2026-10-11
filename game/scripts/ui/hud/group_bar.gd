class_name GroupBar
extends RefCounted
## The control groups (Ctrl+0-9) as a row of buttons along the bottom of the screen, in the
## open stretch between the status bar and the minimap: each shows its number, the portrait
## of what it holds (its building, or the group's most common unit) and how many. A click
## selects the group and brings the view to it; the selected group's frame lights up.

const CARD := 50.0
const GAP := 5.0
const ORDER := [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]  # as on the keyboard
const FRAME_COLOR := Color(0.36, 0.24, 0.12)
const ACTIVE_COLOR := Color(1.0, 0.85, 0.3)

var hud: Hud
var root := Control.new()
var _signature := ""
var _active := -2


func _init(owner: Hud, parent: Control) -> void:
	hud = owner
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)


## The bar sits on the bottom edge of `area`, from its left end.
func layout(area: Rect2) -> void:
	root.position = area.position
	root.size = area.size
	_signature = ""


func refresh() -> void:
	var selection := hud.selection
	var shown: Array[Dictionary] = []
	var parts := PackedStringArray()
	for digit: int in ORDER:
		if not selection.groups.has(digit):
			continue
		var members := selection.group_members(digit)
		if members.is_empty():
			continue
		var group := _describe(digit, members)
		shown.append(group)
		parts.append("%d:%d:%d" % [digit, group.guid, members.size()])
	var signature := ",".join(parts)
	if signature != _signature:
		_signature = signature
		_rebuild(shown)
		_active = -2
	var active := selection.selected_group()
	if active != _active:
		_active = active
		for frame: Panel in root.get_children():
			frame.add_theme_stylebox_override("panel", _frame_style(int(frame.get_meta("digit")) == active))


func blocks_point(screen_point: Vector2) -> bool:
	for frame: Control in root.get_children():
		if frame.get_global_rect().has_point(screen_point):
			return true
	return false


## What a group's button shows: a building's own portrait, or the most common unit's.
func _describe(digit: int, members: Array) -> Dictionary:
	if members[0] is MapObject:
		var building: MapObject = members[0]
		return {"digit": digit, "guid": building.guid, "type": -1, "count": 1,
				"tip": "Group %d: %s" % [digit, building.display_name()]}
	var counts := {}
	var lead: Unit = members[0]
	for unit: Unit in members:
		var guid := unit.unit_type.guid()
		counts[guid] = int(counts.get(guid, 0)) + 1
		if counts[guid] > counts[lead.unit_type.guid()]:
			lead = unit
	var names := PackedStringArray()
	for unit: Unit in members:
		if names.size() < 4 and unit.display_name() not in names:
			names.append(unit.display_name())
	return {"digit": digit, "guid": lead.unit_type.guid(), "type": lead.unit_type.type_id, "count": members.size(),
			"tip": "Group %d: %d %s (%s%s)" % [digit, members.size(), "unit" if members.size() == 1 else "units",
					", ".join(names), "…" if counts.size() > names.size() else ""]}


func _rebuild(groups: Array[Dictionary]) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	var scale := hud.ui_scale
	var size := CARD * scale
	var inset := 3.0 * scale
	for i in groups.size():
		var group: Dictionary = groups[i]
		var digit: int = group.digit
		var frame := Panel.new()
		frame.set_meta("digit", digit)
		frame.size = Vector2(size, size)
		frame.position = Vector2(i * (CARD + GAP) * scale, root.size.y - size)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(frame)
		var card := hud.selected.portrait_card(group.guid, size - inset * 2, group.type)
		card.position = Vector2(inset, inset)
		card.tooltip_text = "%s\n%d to select (twice to go there), Ctrl+%d to keep the selection here" % [group.tip, digit, digit]
		card.pressed.connect(func() -> void: hud.selection.recall_group(digit, true))
		frame.add_child(card)
		var number := HudStyle.label(int(17 * scale))
		number.text = str(digit)
		number.position = Vector2(4, -2) * scale
		number.add_theme_constant_override("outline_size", int(5 * scale))
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(number)
		if group.count > 1:
			var count := HudStyle.label(int(12 * scale))
			count.text = str(group.count)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			count.size = Vector2(size - 5 * scale, size - 2 * scale)
			count.add_theme_constant_override("outline_size", int(4 * scale))
			count.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(count)


func _frame_style(active: bool) -> StyleBoxFlat:
	var box := HudStyle.flat(Color(0.08, 0.05, 0.03, 0.8))
	box.border_color = ACTIVE_COLOR if active else FRAME_COLOR
	box.set_border_width_all(maxi(1, int((2.0 if active else 1.5) * hud.ui_scale)))
	box.set_corner_radius_all(int(3 * hud.ui_scale))
	return box
