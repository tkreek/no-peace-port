class_name SelectionPanel
extends RefCounted
## The left of the status bar: the portrait, name, energy and details of what is selected;
## a building's production queue (click a card to cancel it) and quartered units (click to
## send one out); for a group, every member's portrait with its energy (click one to select
## only it, shift-click to drop it).

const TREE_PORTRAIT := "portraits/other/z_04_tree.png"
const MINE_PORTRAIT := "portraits/other/z_05_gold_mine.png"
const PORTRAIT_SIZE := 56.0
const CARD_SIZE := 44.0
const CARD_STEP := 15.0  # queued units overlap like a hand of cards
const GROUP_ICON := 30.0
const STANCE_NAMES := {Unit.Stance.AGGRESSIVE: "Act aggressively", Unit.Stance.DEFENSIVE: "Act defensively",
		Unit.Stance.HOLD: "Hold ground", Unit.Stance.PASSIVE: "Passive"}
## Status icons (HudStyle.STATUS_ICONS) for the stats, as in the original status menu.
const ICON_ENERGY := 8
const ICON_RIFLE := 0
const ICON_FIST := 9
const ICON_MORALE := 12
const ICON_EXPERIENCE := 10
const ICON_MAGIC := 11
const ICON_SIGHT := 13
const ICON_PEOPLE := 5

var hud: Hud
var _panel: Control  # the left plank everything sits on
var _title := HudStyle.label(22)
var _info := VBoxContainer.new()  # the stat icons, then any further detail as text
var _stats := GridContainer.new()  # two stats a row, as in the original
var _stats_signature := ""
var _detail := HudStyle.label(16)
var _health_bar := HudStyle.progress_bar(Color(0.35, 0.75, 0.2))
var _portrait := TextureRect.new()
var _portrait_key := ""
var _queue_box := Control.new()
var _queue_signature := ""
var _group_box := Control.new()
var _group_signature := ""


func _init(owner: Hud, panel: Control) -> void:
	hud = owner
	_panel = panel
	_health_bar.max_value = 100.0
	for item: Control in [_title, _info, _health_bar]:
		panel.add_child(item)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.columns = 2
	_info.add_child(_stats)
	_info.add_child(_detail)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_portrait)
	for box: Control in [_queue_box, _group_box]:
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(box)


## Everything stays on the bar's nailed board (Hud.selection_area): the name and energy at
## the top, the portrait in the top right corner, the stat icons below; a building's queue
## and a group's portraits in the lower part.
func layout() -> void:
	var scale := hud.ui_scale
	var area := hud.selection_area()
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE) * scale
	_portrait.position = area.position + Vector2(area.size.x - (PORTRAIT_SIZE + 10) * scale, 14 * scale)
	_layout_text(_portrait.texture != null)
	_title.add_theme_font_size_override("font_size", int(17 * scale))
	_detail.add_theme_font_size_override("font_size", int(12 * scale))
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_constant_override("separation", int(2 * scale))
	_stats.add_theme_constant_override("h_separation", int(8 * scale))
	_stats.add_theme_constant_override("v_separation", int(0 * scale))
	_stats_signature = ""
	_group_box.position = area.position + Vector2(10, 14) * scale
	_queue_signature = ""
	_group_signature = ""


## Name, energy bar and stats fill the board left of the portrait.
func _layout_text(with_portrait: bool) -> void:
	var scale := hud.ui_scale
	var area := hud.selection_area()
	var pad := Vector2(10, 12) * scale
	var width := area.size.x - pad.x * 2 - ((PORTRAIT_SIZE + 6) * scale if with_portrait else 0.0)
	_portrait.visible = with_portrait
	_title.position = area.position + pad
	_title.size.x = width
	_title.clip_text = true
	_health_bar.position = area.position + pad + Vector2(0, 23 * scale)
	_health_bar.size = Vector2(width, 5 * scale)
	_info.position = area.position + pad + Vector2(0, 32 * scale)
	_info.size = Vector2(width, 0)
	_stats.custom_minimum_size.x = width
	_queue_box.position = area.position + Vector2(10, 98) * scale


func refresh() -> void:
	var selection := hud.selection
	var units := selection.selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	var object := selection.selected_building if is_instance_valid(selection.selected_building) else null
	if units.is_empty() and object:
		_set_portrait(object.guid, object)
		_title.visible = true
		_info.visible = true
		_title.text = object.display_name()
		_health_bar.visible = object.is_building()
		_health_bar.max_value = object.max_health
		_health_bar.value = object.health
		_show_stats(_object_stats(object))
		_detail.text = _object_detail(object)
		_detail.visible = not _detail.text.is_empty()
		_refresh_queue(object if object.is_building() else null)
		_refresh_group([])
		return
	_refresh_queue(null)
	_refresh_group(units if units.size() > 1 else [])
	_health_bar.visible = units.size() == 1
	_title.visible = units.size() <= 1
	_info.visible = units.size() == 1
	if units.size() != 1:
		_set_portrait(-1, null)
		_title.text = ""
		_detail.text = ""
		return
	var unit: Unit = units[0]
	_set_portrait(unit.unit_type.guid(), unit)
	_title.text = unit.display_name()
	_health_bar.max_value = unit.max_health
	_health_bar.value = unit.health
	_show_stats(_unit_stats(unit))
	_detail.text = _unit_detail(unit)
	_detail.visible = not _detail.text.is_empty()


## A unit's status as icon and value pairs: energy, attack force (with the upgrades' bonus),
## morale and experience as in the original status menu; then magic, sight, the load in
## hand and the passengers aboard.
func _unit_stats(unit: Unit) -> Array:
	var stats := [[ICON_ENERGY, "%d/%d" % [unit.health, unit.max_health], "Energy"]]
	if not unit.unit_type.attack_anims.is_empty():
		var bonus := int(unit.bonus("attack"))
		var attack := "%d" % unit.unit_type.damage + (" +%d" % bonus if bonus > 0 else "")
		var weapon := "Range %d" % unit.attack_range() if unit.unit_type.ranged else "Melee"
		var tip := "Attack force%s\nDamage per blow now %d (morale and experience included)\n%s · reload %.1f s · speed %d" % [
				" (+%d from upgrades)" % bonus if bonus > 0 else "", unit.attack_damage(), weapon,
				unit.unit_type.reload_ms / 1000.0, unit.move_speed()]
		stats.append([ICON_RIFLE if unit.unit_type.ranged else ICON_FIST, attack, tip])
	if unit.team > 0:
		stats.append([ICON_MORALE, "%d%%" % roundi(unit.morale() * 100), "Morale"])
		stats.append([ICON_EXPERIENCE, "%d%%" % roundi(unit.experience * 100), "Experience"])
	if UnitMagic.CASTERS.has(unit.unit_type.guid()):
		stats.append([ICON_MAGIC, "%d/%d" % [unit.magic.magic_energy, unit.magic.magic_pool()], "Magic energy"])
	stats.append([ICON_SIGHT, "%d" % unit.sight(), "Sight"])
	if unit.work.carried > 0 and Player.RESOURCES.has(unit.work.carrying):
		stats.append([Player.RESOURCES[unit.work.carrying].icon, "%d" % unit.work.carried, "Carrying %s" % unit.work.carrying])
	if unit.water.is_carrier():
		stats.append([ICON_PEOPLE, "%d/%d" % [unit.water.passengers.size(), unit.water.capacity()], "Passengers"])
	if unit.animal.has_meat():
		var meat := unit.animal.meat_left if unit.animal.meat_left >= 0 else unit.animal.meat_value()
		stats.append([Player.RESOURCES.food.icon, "%d" % meat, "Food when hunted"])
	return stats


## What the icons don't say: special states (the weapon's reach and pace are in the attack
## icon's tooltip, the stance on the command buttons).
func _unit_detail(unit: Unit) -> String:
	var lines := PackedStringArray()
	if unit.work.carried > 0 and not Player.RESOURCES.has(unit.work.carrying):
		lines.append("Carrying %d %s" % [unit.work.carried, unit.work.carrying])
	if not unit.tepees.packed.is_empty():
		lines.append("Carrying a packed %s" % String(GameData.stats(int(unit.tepees.packed.guid)).get("name", "tepee")).to_lower())
	if unit.animal.is_cow():
		lines.append("Worth %d gold (up to %d)" % [unit.animal.cattle_value, UnitAnimal.COW_MAX_VALUE])
	if unit.magic.shield_time > 0.0:
		lines.append("Shielded %d s" % ceili(unit.magic.shield_time))
	return "\n".join(lines)


## A building's energy and housing as icons (trees, mines and fields have only text).
func _object_stats(object: MapObject) -> Array:
	if not object.is_building():
		return []
	var stats := [[ICON_ENERGY, "%d/%d" % [object.health, object.max_health], "Energy"]]
	var housing := int(GameData.stats(object.guid).get("housing", 0))
	if housing > 0 and object.complete:
		stats.append([ICON_PEOPLE, "%d" % housing, "Houses %d" % housing])
	return stats


## Show `stats` ([icon frame, value, tooltip] each) as rows of icons with their values. The
## icons are rebuilt only when which ones are shown changes; the values every frame.
func _show_stats(stats: Array) -> void:
	_stats.visible = not stats.is_empty()
	var signature := ",".join(stats.map(func(entry: Array) -> String: return str(entry[0])))
	var scale := hud.ui_scale
	if signature != _stats_signature:
		_stats_signature = signature
		for child in _stats.get_children():
			_stats.remove_child(child)
			child.queue_free()
		for entry: Array in stats:
			var pair := HBoxContainer.new()
			pair.add_theme_constant_override("separation", int(3 * scale))
			var icon := HudStyle.status_icon(entry[0])
			icon.custom_minimum_size = Vector2(15, 15) * scale
			pair.add_child(icon)
			var value := HudStyle.label(int(13 * scale))
			value.name = "Value"
			pair.add_child(value)
			_stats.add_child(pair)
	var pairs := _stats.get_children()
	for i in mini(pairs.size(), stats.size()):
		(pairs[i].get_node("Value") as Label).text = stats[i][1]
		pairs[i].tooltip_text = stats[i][2]
		(pairs[i].get_child(0) as Control).tooltip_text = stats[i][2]


func _object_detail(object: MapObject) -> String:
	var stock := object.stock
	if object.is_tree():
		return "Wood left: %d" % stock.amount
	if object.is_mine():
		return "Gold left: %d" % stock.amount if stock.amount > 0 else "Exhausted"
	if object.is_field():
		match stock.field_state:
			ObjectStock.Field.FALLOW:
				return "Fallow — needs sowing"
			ObjectStock.Field.GROWING:
				return "Growing %d%%" % int(stock.field_progress * 100)
		return "Ripe: %d food" % stock.amount
	if not object.is_building():
		return ""
	var owner_note := ""
	if object.owner_index != hud.player.index and Player.by_index.has(object.owner_index):
		owner_note = "\n" + Match.faction_name(Player.by_index[object.owner_index].faction)
	if not object.complete:
		return "Under construction %d%%%s" % [int(object.build_progress * 100), owner_note]
	var production := object.production
	if not production.queue.is_empty():
		var current := GameData.stats(production.queue[0])
		var doing: String = {"upgrade": "Researching", "trade": "Trading", "horse": "Raising", "gun": "Making"}.get(current.get("kind"), "Training")
		return "%s %s — %d%%" % [doing, current.get("name", "?"), int(production.progress * 100)]
	if object.guid == BuildingProduction.DISTILLERY_GUID:
		owner_note += "\n" + ("Distilling %d wood into %d food every %d s" % [BuildingProduction.DISTILL_WOOD,
				BuildingProduction.DISTILL_FOOD, BuildingProduction.DISTILL_SECONDS] if production.distilling else "Resting")
	if object.guid == BuildingProduction.SPIRIT_TEPEE and object.owner_index == hud.player.index:
		owner_note += "\nMagic energy %d / %d" % [production.spirit_energy, BuildingProduction.SPIRIT_MAX]
	var defence := object.defence
	var quartered := "\nQuartered %d / %d" % [defence.garrison.size(), defence.capacity()] if defence.capacity() > 0 else ""
	if object.is_abandoned_store():
		return "Abandoned warehouse: %d %s\nSend a wagon to haul it home" % [stock.loot, stock.loot_kind] if stock.loot > 0 \
				else "Abandoned warehouse (empty)"
	if object.is_gold_warehouse():
		quartered += "\nGold stored: %d (send a wagon to haul it)" % stock.stored_gold
	return (quartered + owner_note).strip_edges()


## The portrait of the selected unit or object at the left of the panel.
func _set_portrait(guid: int, thing: Object) -> void:
	var key := "%d:%s" % [guid, thing.get_instance_id() if thing else 0]
	if key == _portrait_key:
		return
	_portrait_key = key
	_portrait.texture = null
	if thing == null:
		_layout_text(false)
		return
	var thumb: Thumbnail = null
	if thing is MapObject and thing.is_tree():
		thumb = Thumbnail.from_image(TREE_PORTRAIT)
	elif thing is MapObject and thing.is_mine():
		thumb = Thumbnail.from_image(MINE_PORTRAIT)
	elif guid >= 0:
		thumb = Thumbnail.portrait(guid)
	if thumb == null and thing is MapObject and thing.object_type:
		thumb = Thumbnail.for_type(thing.object_type.id, thing.owner_index)
	elif thumb == null and thing is Unit:
		thumb = Thumbnail.for_type(thing.unit_type.type_id, thing.team)
	if thumb:
		_portrait.texture = thumb.texture
		_portrait.material = thumb.material
		thumb.free()
	_layout_text(_portrait.texture != null)


## The production queue as a hand of overlapping cards; the first one shows its progress.
func _refresh_queue(building: MapObject) -> void:
	var scale := hud.ui_scale
	var queue: Array = Array(building.production.queue) if building and building.complete else []
	var quartered: Array = building.defence.garrison.duplicate() if building and queue.is_empty() else []
	var signature := "%s|%s|%s" % [building.get_instance_id() if building else 0, queue,
			quartered.map(func(u: Unit) -> int: return u.get_instance_id())]
	if signature != _queue_signature:
		_queue_signature = signature
		for child in _queue_box.get_children():
			child.queue_free()
		for i in queue.size():
			var card := _card(queue[i], CARD_SIZE * scale)
			card.position = Vector2(i * CARD_STEP * scale + (8 * scale if i > 0 else 0.0), 0)
			card.tooltip_text = "%s\nClick to cancel" % GameData.stats(queue[i]).get("name", "?")
			var index := i
			card.pressed.connect(func() -> void: Orders.building(building, "cancel", [index]))
			_queue_box.add_child(card)
			_queue_box.move_child(card, 0)  # later orders tuck in behind the first
		for i in quartered.size():
			var unit: Unit = quartered[i]
			var card := _card(unit.unit_type.guid(), CARD_SIZE * 0.8 * scale, unit.unit_type.type_id)
			card.position = Vector2(i * (CARD_SIZE * 0.8 + 3) * scale, 0)
			card.tooltip_text = "%s\nClick to leave quarters" % unit.display_name()
			card.pressed.connect(func() -> void: Orders.building(building, "release", [unit]))
			_queue_box.add_child(card)
		if not queue.is_empty():
			var bar := HudStyle.progress_bar(Color(0.4, 0.7, 1.0))
			bar.position = Vector2(0, CARD_SIZE * scale + 2)
			bar.size = Vector2(CARD_SIZE * scale, 5 * scale)
			bar.name = "Progress"
			_queue_box.add_child(bar)
	var progress := _queue_box.get_node_or_null("Progress") as ProgressBar
	if progress and building:
		progress.value = building.production.progress


func _refresh_group(units: Array) -> void:
	var scale := hud.ui_scale
	var signature := ",".join(units.map(func(u: Unit) -> String: return str(u.get_instance_id())))
	if signature != _group_signature:
		_group_signature = signature
		for child in _group_box.get_children():
			child.queue_free()
		var size := GROUP_ICON * scale
		var columns := maxi(1, int((hud.selection_area().size.x - 20 * scale) / (size + 2)))
		for i in units.size():
			var unit: Unit = units[i]
			var card := _card(unit.unit_type.guid(), size, unit.unit_type.type_id)
			card.position = Vector2((i % columns) * (size + 2), (i / columns) * (size + 7 * scale))
			card.tooltip_text = unit.display_name()
			card.set_meta("unit", unit)
			card.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					if event.shift_pressed:
						hud.selection.deselect(unit)
					else:
						hud.selection.select_units([unit])
					card.accept_event())
			var health := ColorRect.new()
			health.name = "Health"
			health.mouse_filter = Control.MOUSE_FILTER_IGNORE
			health.position = Vector2(0, size + 1)
			health.size = Vector2(size, 3 * scale)
			card.add_child(health)
			_group_box.add_child(card)
	for card in _group_box.get_children():
		var unit = card.get_meta("unit") if card.has_meta("unit") else null  # may have been freed
		var health := card.get_node_or_null("Health") as ColorRect
		if is_instance_valid(unit) and health:
			var ratio: float = unit.health / unit.max_health if unit.max_health > 0 else 0.0
			health.size.x = GROUP_ICON * scale * ratio
			health.color = Color(0.9, 0.2, 0.1).lerp(Color(0.3, 0.85, 0.2), ratio)


## A small portrait button for a unit, building or upgrade.
func _card(guid: int, size: float, type_id := -1) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.size = Vector2(size, size)
	HudStyle.clear_styles(card)
	var thumb: Control = Thumbnail.portrait(guid)
	if thumb == null and type_id < 0:
		type_id = GameData.type_for_guid(guid, hud.biome)
	if thumb == null and type_id >= 0:
		thumb = Thumbnail.for_type(type_id, hud.player.index)
	if thumb == null:
		thumb = HudStyle.name_card(GameData.stats(guid).get("name", "?"), int(9 * hud.ui_scale))
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(thumb)
	card.mouse_entered.connect(func() -> void: thumb.modulate = Color(1.2, 1.15, 1.0))
	card.mouse_exited.connect(func() -> void: thumb.modulate = Color.WHITE)
	return card
