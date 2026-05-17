@tool
extends Panel
class_name RTSResourceBar

var resource_labels := {}

func _ready() -> void:
	_build_ui({})

func configure(resources: Dictionary) -> void:
	if resource_labels.is_empty():
		_build_ui(resources)
	else:
		update_resources(resources)

func update_resources(resources: Dictionary) -> void:
	for resource_type in resource_labels.keys():
		var label := resource_labels[resource_type] as Label
		if label != null:
			label.text = str(resources.get(resource_type, 0))

func _build_ui(resources: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	resource_labels.clear()

	add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.06, 0.04, 0.76), Color(0.14, 0.13, 0.09, 0.9)))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12.0
	row.offset_top = 4.0
	row.offset_right = -12.0
	row.offset_bottom = -4.0
	row.add_theme_constant_override("separation", 34)
	add_child(row)

	var readouts := [
		["Food", "food", Color(0.90, 0.24, 0.22)],
		["Wood", "wood", Color(0.72, 0.43, 0.18)],
		["Gold", "gold", Color(0.94, 0.73, 0.22)],
		["Stone", "0", Color(0.66, 0.70, 0.72)],
		["Tools", "0/0", Color(0.62, 0.63, 0.68)],
		["Population", "7/28", Color(0.82, 0.68, 0.48)]
	]

	for readout in readouts:
		row.add_child(_make_resource_readout(readout[0], readout[1], readout[2], resources))

func _make_resource_readout(label_text: String, amount: String, color: Color, resources: Dictionary) -> HBoxContainer:
	var readout := HBoxContainer.new()
	readout.add_theme_constant_override("separation", 6)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14.0, 14.0)
	swatch.color = color
	readout.add_child(swatch)

	var label := Label.new()
	label.text = str(resources.get(amount, amount))
	label.tooltip_text = label_text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.75))
	readout.add_child(label)

	if resources.has(amount):
		resource_labels[amount] = label

	return readout

func _make_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
