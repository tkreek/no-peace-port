class_name CommandPanel
extends RefCounted
## The command buttons on the middle plank and their keyboard shortcuts: build menus,
## fields, stances, patrol and follow, formations, spells, dismounting, camouflage, boats,
## tepees and quarters for units; training, research, trades and the assembly location for
## buildings. Mixed groups get only the commands every member can carry out (manual 3.2).
## Buttons are rebuilt only when what they depend on changes; in between, their
## affordability and research progress are updated.

const COMMAND_ICONS := "interface/icons/misc/misc_icons"
const EXTRA_ICONS := "interface/icons/misc/icons_first_row"
const SMALL_ICONS := "interface/icons/misc/small_icons"
const FIELD_ICONS := "interface/icons/units/americans/american_units"
## SonstigeIcons frames (colour; +1 is the greyed version).
const ICON_STOP := 14
const ICON_BUILD := 18  # small hammer: structures for the economic and military cycle
const ICON_BUILD_EXPANDED := 16  # large hammer: structures with enhanced functions
const ICON_FOLLOW := 2  # two men walking one behind the other
const ICON_PATROL := 4  # two men with an arrow
const ICON_DISMOUNT := 54  # horse with an arrow
const ICON_REPAIR := 20  # carpenter's tools
## Iconserstereihe frames.
const ICON_RALLY := 12  # signpost
const ICON_HIDE := 14  # hooded figure
const ICON_ENTER := 2  # arrow into a doorway
const ICON_LEAVE := 0  # arrow out of a doorway
const ICON_DEMOLISH := 8  # gravestone
const ICON_FIELD := 32  # the green crop field among the American unit icons
const STANCE_ICONS := {Unit.Stance.AGGRESSIVE: 0, Unit.Stance.DEFENSIVE: 6, Unit.Stance.HOLD: 12,
		Unit.Stance.PASSIVE: 8}
## The original used A/D/S for aggressive, defensive and stop; those keys scroll the map
## (WASD), so aggressive and defensive sit on Q/E and stop on X.
const STANCE_KEYS := {KEY_Q: Unit.Stance.AGGRESSIVE, KEY_E: Unit.Stance.DEFENSIVE, KEY_H: Unit.Stance.HOLD,
		KEY_Y: Unit.Stance.PASSIVE}
const FORMATION_ICONS := {Unit.Formation.COLUMN: 11, Unit.Formation.DOUBLE_COLUMN: 9, Unit.Formation.WEDGE: 6,
		Unit.Formation.DOUBLE_LINE: 4, Unit.Formation.SQUARE: 2, Unit.Formation.RELAXED: 0}
const FORMATION_NAMES := {Unit.Formation.COLUMN: "Column", Unit.Formation.DOUBLE_COLUMN: "Double column",
		Unit.Formation.WEDGE: "Wedge", Unit.Formation.DOUBLE_LINE: "Double line", Unit.Formation.SQUARE: "Square",
		Unit.Formation.RELAXED: "Relaxed"}
## "Build expanded structure" (V) per the manual's keyboard table; every other structure is
## a basic one (B).
const EXPANDED_STRUCTURES := [110, 111, 112, 114, 115,  # campfire, totem, camouflage school, pitfall, medicine man
		210, 211, 212, 213, 215, 216, 217, 218,  # Mexican trading post, weapons, wall, tower, church, mission, fort, wharf
		307, 310, 311, 312, 313, 314, 315,  # hotel, drugstore, cellar, barricade, lookout, explosives, boathouse
		407, 411, 412, 413, 415, 416, 417, 418]  # sheriff, weapons, stockade, tower, church, bank, fort, wharf
const CANNOT := 80  # the original "not possible" sound

var hud: Hud
var grid := GridContainer.new()
var signature := ""  ## what the buttons were built for; "" forces a rebuild
var build_menu := ""  ## "", "basic" or "expanded"
var command_icons: RdSprite
var extra_icons: RdSprite
var small_icons: RdSprite


func _init(owner: Hud, parent: Control) -> void:
	hud = owner
	command_icons = GameData.load_sprite(COMMAND_ICONS)
	extra_icons = GameData.load_sprite(EXTRA_ICONS)
	small_icons = GameData.load_sprite(SMALL_ICONS)
	parent.add_child(grid)


## The buttons fill the plank `area` between the selection panel and the minimap.
## Fill the board with the buttons: as large as the original's while they fit in its rows,
## smaller for long lists (the build menus).
func layout(area: Rect2) -> void:
	var scale := hud.ui_scale
	var spacing := 4.0 * scale
	var inner := Rect2(area.position + Vector2(10, 14) * scale, area.size - Vector2(18, 24) * scale)
	var buttons := grid.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	var button_size := 0.0
	var columns := 1
	for candidate in [50.0, 44.0, 38.0, 32.0]:
		button_size = candidate * scale
		columns = maxi(1, int((inner.size.x + spacing) / (button_size + spacing)))
		var rows := maxi(1, int((inner.size.y + spacing) / (button_size + spacing)))
		if columns * rows >= buttons.size():
			break
	grid.position = inner.position
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", int(spacing))
	grid.add_theme_constant_override("v_separation", int(spacing))
	for button: Control in buttons:
		button.custom_minimum_size = Vector2(button_size, button_size)


func _units() -> Array:
	return hud.selection.selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())


## The selected building, if a building (not a tree, mine or field) is selected.
func selected_building() -> MapObject:
	var building := hud.selection.selected_building
	return building if is_instance_valid(building) and building.is_building() else null


# ------------------------------------------------------------------ the buttons

func refresh() -> void:
	var units := _units()
	var building := selected_building()
	var builders := units.filter(func(u: Unit) -> bool: return u.unit_type.can_build())
	if builders.size() < units.size():
		builders = []
	var farmers := units.filter(func(u: Unit) -> bool: return u.unit_type.is_farmer())
	if farmers.size() < units.size():
		farmers = []
	var fighters := units.filter(func(u: Unit) -> bool: return not u.unit_type.attack_anims.is_empty() \
			and not u.unit_type.can_build() and u.team == hud.player.index)
	if fighters.size() < units.size():
		fighters = []
	var stances := {}
	var formations := {}
	for u: Unit in fighters:
		stances[u.stance] = true
		formations[u.formation] = true
	if builders.is_empty():
		build_menu = ""
	var wanted := "%d/%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [hud.player.researched.size(),
			building.production.queue if building else [], builders.size() > 0,
			farmers.size() > 0, building.get_instance_id() if building else 0,
			building.complete if building else false, build_menu, fighters.size() > 0, stances.keys(),
			units.size() > 0, formations.keys(), hud.selection.pending,
			building.defence.garrison.size() if building else 0,
			units.map(func(u: Unit) -> String: return "%s%d" % [u.tepees.packed.is_empty(), u.water.passengers.size()])]
	if wanted == signature:
		_update_affordability()
		return
	signature = wanted
	for child in grid.get_children():
		child.queue_free()
	if not build_menu.is_empty():
		_add_build_menu()
	elif not units.is_empty():
		_add_unit_commands(units, builders, farmers, fighters, stances, formations)
	elif building and building.complete and building.owner_index == hud.player.index:
		_add_building_commands(building)
	if building and building.owner_index == hud.player.index:
		if not building.defence.garrison.is_empty():
			_add_icon(extra_icons, ICON_LEAVE, "Move units from quarters (L)", func() -> void: building.defence.release())
		_add_icon(extra_icons, ICON_DEMOLISH, "Demolish (Del)" if building.complete \
				else "Demolish (Del) — refunds the unbuilt part", func() -> void: building.condition.demolish())
	layout(hud.command_area())


## One of the two building menus: its structures, then a way back.
func _add_build_menu() -> void:
	for guid in _faction_guids("structure"):
		if guid == MapObject.FIELD_GUID or (guid in EXPANDED_STRUCTURES) != (build_menu == "expanded"):
			continue
		var type_id := GameData.type_for_guid(guid, hud.biome)
		if type_id >= 0:
			_add_card(type_id, guid, func() -> void: hud.build_controller.start(type_id))
	_add_icon(extra_icons, ICON_LEAVE, "Back", func() -> void: open_build_menu(""))


func _add_unit_commands(units: Array, builders: Array, farmers: Array, fighters: Array,
		stances: Dictionary, formations: Dictionary) -> void:
	var selection := hud.selection
	if not builders.is_empty():
		_add_icon(command_icons, ICON_BUILD, "Build structure (B)", func() -> void: open_build_menu("basic"))
		_add_icon(command_icons, ICON_BUILD_EXPANDED, "Build expanded structure (V)", func() -> void: open_build_menu("expanded"))
		_add_icon(command_icons, ICON_REPAIR, "Repair (R): click a damaged building",
				func() -> void: selection.begin_targeting("repair"), selection.pending == "repair")
	if not farmers.is_empty():
		var field_type := GameData.type_for_guid(MapObject.FIELD_GUID, hud.biome)
		if field_type >= 0:
			var button := _add_card(field_type, MapObject.FIELD_GUID, func() -> void: hud.build_controller.start(field_type))
			button.set_meta("tooltip", "Field (F)\n" + button.get_meta("tooltip"))
	if not fighters.is_empty():
		for stance in STANCE_ICONS:
			var key: int = STANCE_KEYS.find_key(stance)
			_add_icon(command_icons, STANCE_ICONS[stance], "%s (%s)" % [SelectionPanel.STANCE_NAMES[stance],
					OS.get_keycode_string(key)], func() -> void: set_stance(stance), stances.size() == 1 and stances.has(stance))
		_add_icon(command_icons, ICON_PATROL, "Patrol (Z): click the far end of the route",
				func() -> void: selection.begin_targeting("patrol"), selection.pending == "patrol")
		_add_icon(command_icons, ICON_FOLLOW, "Follow (C): click the unit to follow",
				func() -> void: selection.begin_targeting("follow"), selection.pending == "follow")
		if fighters.size() > 1:
			for formation in FORMATION_ICONS:
				_add_icon(small_icons, FORMATION_ICONS[formation], FORMATION_NAMES[formation],
						func() -> void: set_formation(formation), formations.size() == 1 and formations.has(formation))
	for spell in (units[0] as Unit).magic.known_spells():
		if units.all(func(u: Unit) -> bool: return spell in u.magic.known_spells()):
			var info: Dictionary = UnitMagic.SPELLS[spell]
			_add_spell(spell, "%s (%d magic)\n%s\nThen click the %s" % [info.name, info.cost, info.text,
					{"point": "spot", "unit": "unit to protect", "enemy": "enemy to convert"}[info.target]])
	if units.all(func(u: Unit) -> bool: return u.riding.can_dismount()):
		_add_icon(command_icons, ICON_DISMOUNT, "Dismount: the horse can be led into a corral, hacienda or ranch",
				func() -> void: for_each_selected(func(u: Unit) -> void: u.dismount()))
	if units.all(func(u: Unit) -> bool: return u.stealth.can_hide()):
		var assassin := units.any(func(u: Unit) -> bool: return u.unit_type.guid() == UnitStealth.ASSASSIN)
		_add_icon(extra_icons, ICON_HIDE, "Dig in: wait hidden and stab passers-by" if assassin \
				else "Camouflage: blend into the landscape until given another order",
				func() -> void: for_each_selected(func(u: Unit) -> void: u.conceal()))
	if units.all(func(u: Unit) -> bool: return u.water.is_carrier()) \
			and units.any(func(u: Unit) -> bool: return not u.water.passengers.is_empty()):
		_add_icon(extra_icons, ICON_LEAVE, "Remove units (U): the guards climb out" if units.all(func(u: Unit) -> bool: return not u.water.is_boat())
				else "Unload (U): put the passengers ashore at the nearest bank\n(or right-click the land where they should go)",
				unload_boats)
	if units.all(func(u: Unit) -> bool: return u.tepees.can_pack()):
		_add_icon(extra_icons, ICON_ENTER, "Pack tepee (G): click one of your tepees",
				func() -> void: selection.begin_targeting("pack"), selection.pending == "pack")
		var loaded := units.filter(func(u: Unit) -> bool: return not u.tepees.packed.is_empty())
		if not loaded.is_empty():
			_add_icon(extra_icons, ICON_LEAVE, "Set up tepee (L): %s" % GameData.stats(int(loaded[0].tepees.packed.guid)).get("name", "tepee"),
					unpack_tepee)
	if units.all(selection._can_quarter):
		_add_icon(extra_icons, ICON_ENTER, "Move into quarters (G): click a fort or tower",
				func() -> void: selection.begin_targeting("quarters"), selection.pending == "quarters")
	_add_icon(command_icons, ICON_STOP, "Stop (X)", stop_selection)


func _add_building_commands(building: MapObject) -> void:
	var production := building.production
	var enqueue := func(item: int) -> void:
		if production.enqueue(item):
			return
		if GameData.stats(item).get("kind") == "unit" and not hud.player.has_room():
			hud.warn_population_limit()
		else:
			Sound.play_sound(CANNOT)
	for guid in production.trainable_units():
		if BuildingProduction.is_trade(guid):
			var trade: Dictionary = BuildingProduction.TRADES[guid - BuildingProduction.TRADE_GUID]
			var button := _add_icon(command_icons, trade.icon, "", enqueue.bind(guid))
			button.set_meta("guid", guid)
			button.set_meta("trade", trade)
		elif guid == BuildingProduction.GUN_GUID:
			var button := _add_icon(command_icons, int(GameData.stats(guid).icon_frame), "Make a rifle\n%s" % _cost_text(guid),
					enqueue.bind(guid))
			button.set_meta("guid", guid)
		elif guid == BuildingProduction.HORSE_GUID or guid == BuildingProduction.COW_GUID:
			_add_card(-1, guid, enqueue.bind(guid))
		else:
			var type_id := GameData.type_for_guid(guid, hud.biome)
			if type_id >= 0:
				_add_card(type_id, guid, enqueue.bind(guid))
	if building.guid == BuildingProduction.SALOON and hud.player.researched.has(BuildingProduction.LIFT_FOG_UPGRADE):
		var ready := Time.get_ticks_msec() >= production.look_ready_at
		_add_spell(BuildingProduction.LIFT_FOG_UPGRADE, "Look over the land: click a spot to lift the fog there for a while" +
				("" if ready else "\n(recovering)"), "look")
	var spirit := production.spirit_level()
	if building.guid == BuildingProduction.SPIRIT_TEPEE and spirit > 0:
		_add_spell(BuildingProduction.SPIRIT_UPGRADES[spirit - 1],
				"Invoke warrior spirit: every fighting unit gains %d%% morale for %d s\nCosts %d magic energy (see the tepee's energy)" % [
				roundi(BuildingProduction.SPIRIT_BOOST[spirit - 1] * 100), BuildingProduction.SPIRIT_SECONDS,
				BuildingProduction.SPIRIT_COST], "", func() -> void:
					if not production.invoke_spirit():
						Sound.play_sound(CANNOT))
	if building.guid == BuildingProduction.DISTILLERY_GUID:
		_add_icon(command_icons, ICON_STOP, "Stop distilling (keeps the wood)" if production.distilling \
				else "Start distilling again (%d wood into %d food every %d s)" % [BuildingProduction.DISTILL_WOOD,
				BuildingProduction.DISTILL_FOOD, BuildingProduction.DISTILL_SECONDS], func() -> void:
					production.distilling = not production.distilling
					signature = "", not production.distilling)
	if not production.trainable_units().is_empty():
		_add_icon(extra_icons, ICON_RALLY, "Specify assembly location (I)",
				func() -> void: hud.selection.begin_targeting("rally"), hud.selection.pending == "rally")
	for upgrade in production.researchable_upgrades():
		_add_card(-1, upgrade, enqueue.bind(upgrade))


func _add_icon(sheet: RdSprite, frame: int, tip: String, action: Callable, active := false) -> Button:
	var button := HudStyle.icon_button(sheet, frame, tip, active)
	button.set_meta("tooltip", tip)
	button.set_meta("guid", -1)
	button.pressed.connect(action)
	grid.add_child(button)
	return button


## A spell or skill button with the upgrade's picture: it starts targeting `command`
## (default "spell:<id>"), or runs `action` at once when given.
func _add_spell(spell: int, tip: String, command := "", action := Callable()) -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	HudStyle.clear_styles(button)
	button.tooltip_text = tip
	button.set_meta("tooltip", tip)
	button.set_meta("guid", -1)
	var thumb := Thumbnail.portrait(spell)  # the upgrade's own picture
	if thumb:
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(thumb)
	var order := command if command != "" else "spell:%d" % spell
	if action.is_valid():
		button.pressed.connect(action)
	else:
		button.pressed.connect(func() -> void: hud.selection.begin_targeting(order))
	grid.add_child(button)


## A parchment button with a structure's, unit's or upgrade's picture and its cost.
func _add_card(type_id: int, guid: int, action: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", HudStyle.flat(HudStyle.PARCHMENT))
	button.add_theme_stylebox_override("hover", HudStyle.flat(Color(1.0, 0.94, 0.78, 0.98)))
	button.add_theme_stylebox_override("pressed", HudStyle.flat(Color(0.8, 0.7, 0.5, 0.98)))
	button.add_theme_stylebox_override("disabled", HudStyle.flat(Color(0.45, 0.4, 0.35, 0.8)))
	var stats := GameData.stats(guid)
	button.tooltip_text = "%s\n%s" % [stats.get("name", "?"), _cost_text(guid)]
	if stats.get("kind") == "upgrade":
		button.tooltip_text = "Research: %s\n%s\n%s\nApplies to: %s" % [stats.get("name", "?"),
				stats.get("function", ""), _cost_text(guid), stats.get("applies_to", "")]
	button.set_meta("tooltip", button.tooltip_text)
	button.set_meta("guid", guid)
	button.pressed.connect(action)
	var thumb: Thumbnail = null
	var inset := 0
	if guid == MapObject.FIELD_GUID:
		var sheet := GameData.load_sprite(FIELD_ICONS)
		if sheet and ICON_FIELD < sheet.frame_count():
			thumb = Thumbnail.new()
			thumb.set_meta("portrait", true)
			thumb.texture = HudStyle.atlas(sheet, ICON_FIELD)
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		thumb = Thumbnail.portrait(guid)
		if thumb == null and type_id >= 0:
			thumb = Thumbnail.for_type(type_id, hud.player.index)
			inset = 3
	if thumb == null and type_id < 0:
		# Upgrades without a picture: a parchment card with the upgrade's name.
		var card := HudStyle.name_card(stats.get("name", "?"), int(10 * hud.ui_scale))
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(card)
	if thumb and thumb.has_meta("portrait"):
		# The parchment portrait is the button; just brighten it on hover.
		HudStyle.clear_styles(button)
		button.mouse_entered.connect(func() -> void: thumb.self_modulate = Color(1.15, 1.1, 1.0))
		button.mouse_exited.connect(func() -> void: thumb.self_modulate = Color.WHITE)
	if thumb:
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = inset
		thumb.offset_top = inset
		thumb.offset_right = -inset
		thumb.offset_bottom = -inset
		button.add_child(thumb)
	grid.add_child(button)
	return button


func _faction_guids(kind: String) -> Array:
	var out := []
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") == hud.player.faction and stats.get("kind") == kind:
			out.append(guid)
	out.sort()
	return out


func _cost_text(guid: int) -> String:
	var parts := PackedStringArray()
	var cost: Dictionary = GameData.stats(guid).get("cost", {})
	for key in cost:
		if key != "population":
			parts.append("%d %s" % [cost[key], key])
	return ", ".join(parts)


# ------------------------------------------------------------------ availability

func _update_affordability() -> void:
	var building := selected_building()
	for button: Button in grid.get_children():
		if button.has_meta("trade"):
			_update_trade_button(button)
			continue
		var guid: int = button.get_meta("guid", -1)
		if guid < 0:
			continue
		var cost: Dictionary = GameData.stats(guid).get("cost", {}).duplicate()
		cost.erase("population")
		cost.erase("horses")
		var reason := unavailable_reason(guid, cost)
		button.disabled = not reason.is_empty()
		button.tooltip_text = button.get_meta("tooltip") + ("\n" + reason if reason else "")
		button.modulate = Color(1, 1, 1, 0.55) if button.disabled else Color.WHITE
		# An upgrade being researched here shows its progress across the button.
		var researching: bool = GameData.stats(guid).get("kind") == "upgrade" and building != null \
				and guid in building.production.queue
		var bar := button.get_node_or_null("Research") as ProgressBar
		if researching:
			if bar == null:
				bar = HudStyle.progress_bar(Color(0.4, 0.7, 1.0, 0.9), Color(0.1, 0.07, 0.04, 0.75))
				bar.name = "Research"
				bar.show_percentage = true
				bar.add_theme_font_size_override("font_size", int(11 * hud.ui_scale))
				bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
				bar.offset_top = -14 * hud.ui_scale
				button.add_child(bar)
			bar.value = building.production.progress if building.production.queue[0] == guid else 0.0
			button.modulate = Color.WHITE
			button.tooltip_text = "%s\nResearching: %d%%" % [button.get_meta("tooltip"), int(bar.value * 100)]
		elif bar:
			bar.queue_free()


## Trade buttons show the current price and whether it can be paid.
func _update_trade_button(button: Button) -> void:
	var player := hud.player
	var trade: Dictionary = button.get_meta("trade")
	var amount: int = Player.TRADE_PACKAGE[trade.good]
	var text := ""
	var can := false
	if trade.buy:
		text = "Buy %d %s for %d gold" % [amount, trade.good, player.buy_price(trade.good)]
		can = int(player.resources.get("gold", 0)) >= player.buy_price(trade.good)
	else:
		text = "Sell %d %s for %d gold" % [amount, trade.good, player.sell_price(trade.good)]
		can = int(player.resources.get(trade.good, 0)) >= amount
	button.tooltip_text = text + ("" if can else "\nNot enough " + ("gold" if trade.buy else trade.good))
	button.disabled = not can
	button.modulate = Color.WHITE if can else Color(1, 1, 1, 0.55)


## Why a build/train button is unavailable, or "" when it can be used.
func unavailable_reason(guid: int, cost: Dictionary) -> String:
	var player := hud.player
	if guid == MapObject.FIELD_GUID and MapObject.field_allowance(player.index) <= 0:
		var store := ""
		for food_store in MapObject.FOOD_STORES:
			if GameData.stats(food_store).get("faction") == player.faction:
				store = GameData.stats(food_store).get("name", "food store")
		return "Build a %s first (each allows %d fields)" % [store, MapObject.FIELDS_PER_STORE] if store \
				else "Needs a food store"
	var stats := GameData.stats(guid)
	if guid in MapObject.SHIPYARDS and not NavGrid.current.has_water:
		return "Needs water (this map has none)"
	if guid == BuildingProduction.HORSE_GUID and int(player.resources.get("horses", 0)) + player.queued_horses() >= player.horse_capacity():
		return "No room for more horses (%d per corral, hacienda or ranch)" % BuildingProduction.HORSES_PER_BUILDING
	if stats.get("kind") == "upgrade" and not player.can_research(guid):
		return "Already researched or in progress" if player.researched.has(guid) or player.is_researching(guid) \
				else "Research the previous level first"
	if stats.get("kind") == "unit":
		if guid in Player.COMMANDERS and player.has_commander():
			return "You can only have one %s" % stats.get("name", "commander").to_lower()
		if not player.has_room():
			var house := ""
			for other in GameData.stats_guids():
				var s2 := GameData.stats(other)
				if s2.get("faction") == player.faction and s2.get("kind") == "structure" \
						and int(s2.get("housing", 0)) > 0 and int(s2.get("housing", 0)) < 12:
					house = s2.get("name", "")
			return "Not enough housing (%d/%d)%s" % [player.population() + player.queued_units(),
					player.population_cap(), " — build a %s" % house if house else ""]
		var selected := selected_building()
		if selected and selected.production.queue.size() >= BuildingProduction.QUEUE_LIMIT:
			return "Queue full"
	var missing := PackedStringArray()
	# Fields are shared by every people; their requirement is the grain store checked above.
	for required in ([] if guid == MapObject.FIELD_GUID else GameData.prerequisites(guid)):
		if not player.has_building(required):
			missing.append(GameData.stats(required).get("name", "?"))
	if not missing.is_empty():
		return "Requires: " + ", ".join(missing)
	var short := PackedStringArray()
	for key in cost:
		if int(player.resources.get(key, 0)) < int(cost[key]):
			short.append(GameData.text(Player.RESOURCES[key].text, key) if Player.RESOURCES.has(key) else key)
	if not short.is_empty():
		return "Not enough " + ", ".join(short).to_lower()
	return ""


# ------------------------------------------------------------------ orders

func open_build_menu(menu: String) -> void:
	build_menu = menu
	signature = ""


func for_each_selected(order: Callable) -> void:
	for u in _units():
		order.call(u)


func set_stance(stance: Unit.Stance) -> void:
	for_each_selected(func(u: Unit) -> void:
		if not u.unit_type.attack_anims.is_empty():
			u.set_stance(stance))
	signature = ""


func set_formation(formation: Unit.Formation) -> void:
	for_each_selected(func(u: Unit) -> void: u.formation = formation)
	hud.selection.reform()
	signature = ""


func stop_selection() -> void:
	for_each_selected(func(u: Unit) -> void: u.stop())


## Place the tepee the first loaded travois in the selection carries.
func unpack_tepee() -> void:
	for u: Unit in _units():
		if u.tepees.can_pack() and not u.tepees.packed.is_empty():
			var type_id := GameData.type_for_guid(int(u.tepees.packed.guid), hud.biome)
			if type_id >= 0:
				hud.build_controller.start(type_id, u)
			return


func unload_boats() -> void:
	for_each_selected(func(u: Unit) -> void:
		if u.water.is_carrier():
			u.unload_at(u.position))


func _all_travois() -> bool:
	var units := _units()
	return not units.is_empty() and units.all(func(u: Unit) -> bool: return u.tepees.can_pack())


## The original keyboard shortcuts for the commands; true when `key` was one.
func handle_key(key: int) -> bool:
	var selection := hud.selection
	var units := _units()
	var building := selected_building()
	var ours := building != null and building.owner_index == hud.player.index
	match key:
		KEY_X:
			stop_selection()
		KEY_Z, KEY_C:
			if not units.is_empty():
				selection.begin_targeting("patrol" if key == KEY_Z else "follow")
		KEY_DELETE:
			if ours:
				building.condition.demolish()
		KEY_U:
			if not units.any(func(u: Unit) -> bool: return u.water.is_carrier()):
				return false
			unload_boats()
		KEY_G:
			if _all_travois():
				selection.begin_targeting("pack")
			elif not units.is_empty():
				selection.begin_targeting("quarters")
		KEY_L:
			if _all_travois():
				unpack_tepee()
			elif ours:
				building.defence.release()
		KEY_I:
			if ours:
				selection.begin_targeting("rally")
		KEY_R:
			if units.is_empty() or not units.all(func(u: Unit) -> bool: return u.unit_type.can_build()):
				return false
			selection.begin_targeting("repair")
		KEY_B, KEY_V:
			if not units.is_empty() and units.all(func(u: Unit) -> bool: return u.unit_type.can_build()):
				open_build_menu("basic" if key == KEY_B else "expanded")
		KEY_F:
			var field_type := GameData.type_for_guid(MapObject.FIELD_GUID, hud.biome)
			if field_type >= 0 and not units.is_empty() and units.all(func(u: Unit) -> bool: return u.unit_type.is_farmer()):
				hud.build_controller.start(field_type)
		_:
			if not STANCE_KEYS.has(key):
				return false
			set_stance(STANCE_KEYS[key])
	return true
