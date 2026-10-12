class_name MissionDebug
extends Node
## The playtesting overlay of a campaign mission (F9): a translucent panel at the right
## with the mission's time, goal and countdown; its armed triggers with every condition in
## words, its value now and whether it holds (the false ones in red: what the mission waits
## on); the triggers that fired lately; timers, flags and variables; and per people its AI
## modules (by their source names), stockpile and numbers. F10 draws the mission's named
## areas on the map. Clicking a trigger selects it (its actions show, Ctrl+Shift+F fires it).
## Also the cheat keys (Cheats), which work wherever cheats are enabled. It only reads the
## game; the cheats go through Orders.
##
## --debug-overlay=1 opens it at the start, --debug-trigger=<n> selects trigger n (screenshots).

const WIDTH := 560.0
const REFRESH_SECONDS := 0.3
## Armed triggers shown with their conditions; the rest by name until "show all".
const EXPANDED := 12
const FIRED_SHOWN := 8
const GOAL_LINES := 3

const GOOD := "#9be07a"
const BAD := "#ff8070"
const DIM := "#b8a684"
const HEAD := "#ffd27a"
const PICKED := "#7fc8ff"

const KEYS := [
	["F9", "overlay"], ["F10", "areas"], ["Ctrl+Shift+R", "reveal map"], ["Ctrl+Shift+G", "+1000 each"],
	["Ctrl+Shift+K", "kill selected"], ["Ctrl+Shift+W", "win"], ["Ctrl+Shift+F", "fire selected trigger"],
	["Ctrl+Shift+T", "speed 1x/4x/8x"], ["Ctrl+Shift+C", "copy this report"],
]
const CATEGORIES := {0: "units", 1: "Native units", 2: "Mexican units", 3: "outlaw units", 4: "American units",
		5: "buildings", 6: "Native buildings", 7: "Mexican buildings", 8: "outlaw buildings", 9: "American buildings",
		16: "soldiers", 17: "Native soldiers", 18: "Mexican soldiers", 19: "outlaw soldiers", 20: "American soldiers"}
const ANIMAL_NAMES := {480: "horses", 481: "buffalo", 482: "cows", 483: "horses of nobody's"}

var main: Main
var hud: Hud
var mission: Mission
var panel := PanelContainer.new()
var areas := AreaLayer.new()
## The trigger clicked in the overlay (Ctrl+Shift+F fires it), or -1.
var picked := -1
var show_areas := true

var _scroll := ScrollContainer.new()
var _text := RichTextLabel.new()
var _footer := RichTextLabel.new()
var _refresh := 0.0
var _place := Rect2()
var _show_all := false
var _names := {}  # GUID -> name


func _init(game: Main, owner: Hud) -> void:
	main = game
	hud = owner
	mission = game.mission
	name = "MissionDebug"


func _ready() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.035, 0.02, 0.8)
	box.border_color = Color(0.55, 0.38, 0.2, 0.9)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	var column := VBoxContainer.new()
	panel.add_child(column)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	for label: RichTextLabel in [_text, _footer]:
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.meta_underlined = false
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("default_color", HudStyle.TEXT_COLOR)
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
		label.add_theme_constant_override("outline_size", 3)
	_text.meta_clicked.connect(_on_link)
	_scroll.add_child(_text)
	column.add_child(HSeparator.new())
	column.add_child(_footer)
	hud.root.add_child(panel)
	areas.debug = self
	areas.visible = false
	main.add_child(areas)
	get_viewport().size_changed.connect(layout)
	layout()
	if mission and GameData.cmdline_option("debug-overlay") != "":
		picked = GameData.cmdline_option("debug-trigger", "-1").to_int()
		toggle()


func layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var s := hud.ui_scale
	var top := 72.0 * s
	var bottom := view.y - 192.0 * s
	var width := minf(WIDTH * s, view.x * 0.45)
	_place = Rect2(view.x - width - 8.0 * s, top, width, maxf(120.0, bottom - top))
	panel.position = _place.position
	panel.size = _place.size
	var margin := 10.0 * s
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(margin)
	var font := maxi(12, roundi(15.0 * s))
	for label: RichTextLabel in [_text, _footer]:
		for kind in ["normal_font_size", "bold_font_size"]:
			label.add_theme_font_size_override(kind, font)
	_footer.add_theme_font_size_override("normal_font_size", maxi(11, roundi(13.0 * s)))
	# Non-breaking spaces within an entry: lines only break between keys.
	_footer.text = "   ".join(KEYS.map(func(k: Array) -> String:
		return ("[color=%s]%s[/color] %s" % [HEAD, k[0], k[1]]).replace(" ", "\u00a0")))
	_refresh = 0.0


func blocks_point(screen_point: Vector2) -> bool:
	return panel.visible and panel.get_global_rect().has_point(screen_point)


func toggle() -> void:
	if mission == null:
		return
	panel.visible = not panel.visible
	areas.visible = panel.visible and show_areas
	_refresh = 0.0


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_SECONDS
	var text := _report()
	if text != _text.text:
		_text.text = text
		panel.size = _place.size  # a container only ever grows to fit its content
	areas.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or get_tree().paused:
		return
	var key: int = event.keycode
	if not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and key in [KEY_F9, KEY_F10]:
		if key == KEY_F9:
			toggle()
		elif panel.visible:
			show_areas = not show_areas
			areas.visible = show_areas
		get_viewport().set_input_as_handled()
		return
	if not (event.ctrl_pressed and event.shift_pressed):
		return
	if key == KEY_C and mission:
		copy_report()
		get_viewport().set_input_as_handled()
		return
	if not Cheats.enabled:
		return
	match key:
		KEY_R:
			Orders.cheat("reveal")
			hud.notify("Cheat: fog %s" % ("on" if not main.fog.enabled else "off"), false)
		KEY_G:
			Orders.cheat("resources")
			hud.notify("Cheat: +%d food, wood, gold and guns" % Cheats.GIFT, false)
		KEY_K:
			var targets: Array = hud.selection.selection.duplicate()
			if is_instance_valid(hud.selection.selected_building):
				targets.append(hud.selection.selected_building)
			Orders.cheat("kill", [], targets)
			hud.notify("Cheat: killed %d" % targets.size(), false)
		KEY_W:
			if mission:
				Orders.cheat("win")
				hud.notify("Cheat: mission won", false)
		KEY_F:
			if mission and picked >= 0:
				Orders.cheat("fire", [picked])
				hud.notify("Cheat: trigger #%d fired" % picked, false)
			elif mission:
				hud.notify("Select a trigger in the overlay (F9) first", false)
		KEY_T:
			Orders.cheat("speed")
			hud.notify("Cheat: speed %dx" % Cheats.next_speed(), false)
		_:
			return
	get_viewport().set_input_as_handled()


## The overlay's text as it is now, without its colours.
func report_text() -> String:
	_text.text = _report()
	return _text.get_parsed_text()


## The overlay's text to the clipboard and the log (Ctrl+Shift+C), for a bug report.
func copy_report() -> void:
	var plain := report_text()
	DisplayServer.clipboard_set(plain)
	print("MISSION REPORT\n%s\nEND OF MISSION REPORT" % plain)
	hud.notify("Mission report copied to the clipboard", false)


func _on_link(meta: Variant) -> void:
	var link := str(meta)
	if link == "all":
		_show_all = not _show_all
	elif link.begins_with("t:"):
		var index := link.substr(2).to_int()
		picked = -1 if picked == index else index
	_refresh = 0.0


# ------------------------------------------------------------------ the report

func _report() -> String:
	var lines := PackedStringArray()
	var data := mission.data
	var seconds := int(Sim.time())
	lines.append("[b][color=%s]%s[/color][/b]  [color=%s]%s/%s[/color]" % [HEAD, _esc(Campaign.title(Match.campaign)), DIM,
			Match.campaign.get("set", ""), Match.campaign.get("code", "")])
	var state := "script over" if not mission.is_running() else "script running"
	if mission.outcome != 0:
		state = "WON" if mission.outcome > 0 else "LOST"
	lines.append("time %d:%02d · %s · speed %dx · fog %s%s" % [seconds / 60, seconds % 60, state,
			int(Cheats.SPEEDS[Cheats.speed_index]), "on" if main.fog.enabled else "off", " · input locked" if Orders.locked else ""])
	if mission.countdown_running or mission.clock_shown:
		lines.append("countdown %d:%02d%s%s" % [mission.countdown / 60, mission.countdown % 60,
				"" if mission.countdown_running else " (stopped)", "" if mission.clock_shown else " (hidden)"])
	var goal := mission.goal_text().strip_edges()
	if goal != "":
		var goal_lines := Array(goal.split("\n", false)).map(func(l: String) -> String: return l.strip_edges()) \
				.filter(func(l: String) -> bool: return l != "").slice(0, GOAL_LINES)
		lines.append("[color=%s]goal %d:[/color] [i]%s[/i]" % [DIM, mission.goal, _esc("  ".join(goal_lines))])
	_triggers(lines, data)
	_fired(lines, data)
	_state(lines)
	_ai(lines, data)
	return "\n".join(lines)


func _triggers(lines: PackedStringArray, data: MissionData) -> void:
	var armed: Array[int] = []
	for i in data.triggers.size():
		if mission.is_armed(i):
			armed.append(i)
	lines.append("")
	lines.append("[b][color=%s]TRIGGERS[/color][/b]  %d of %d armed · next checked #%d" % [HEAD, armed.size(),
			data.triggers.size(), mission.cursor()])
	var shown := 0
	var hidden := 0
	for i in armed:
		if shown < EXPANDED or _show_all or i == picked:
			_trigger(lines, data, i, true)
			shown += 1
		else:
			hidden += 1
	if hidden > 0:
		lines.append("  [url=all][color=%s]+ %d more armed (show all)[/color][/url]" % [PICKED, hidden])
	elif _show_all and armed.size() > EXPANDED:
		lines.append("  [url=all][color=%s]show fewer[/color][/url]" % PICKED)
	if picked >= 0 and picked < data.triggers.size() and not mission.is_armed(picked):
		_trigger(lines, data, picked, false)


func _trigger(lines: PackedStringArray, data: MissionData, index: int, armed: bool) -> void:
	var trigger: MissionData.Trigger = data.triggers[index]
	var descriptions := []
	var all := true
	var any := false
	var or_seen := false
	for c in trigger.conditions:
		var d := _condition(c)
		descriptions.append(d)
		if c[0] == 15:
			or_seen = true
		elif or_seen:
			any = any or d[1]
		else:
			all = all and d[1]
	var fires := all and (any or not or_seen)
	var colour := PICKED if index == picked else (GOOD if fires else HEAD)
	lines.append("[url=t:%d][color=%s]%s#%d %s[/color][/url]%s" % [index, colour, "▶ " if index == picked else "",
			index, _esc(trigger.name) if trigger.name != "" else _summary(trigger), "" if armed else " [color=%s](disarmed)[/color]" % DIM])
	for d in descriptions:
		var mark := "·" if d[1] == null else ("[color=%s]yes[/color]" % GOOD if d[1] else "[color=%s]NO[/color]" % BAD)
		var words: String = d[0] if d[1] != false else "[color=%s]%s[/color]" % [BAD, d[0]]
		lines.append("    %s  %s" % [mark, words])
	if index == picked:
		for a in trigger.actions:
			lines.append("    [color=%s]→ %s[/color]" % [PICKED, _action(a)])


## What an unnamed trigger does, in short (its first action that does something).
func _summary(trigger: MissionData.Trigger) -> String:
	for a in trigger.actions:
		if a[0] != 10:
			var words := _action(a)
			return "→ " + (words.substr(0, 48) + "…" if words.length() > 50 else words)
	return "(no name)"


func _fired(lines: PackedStringArray, data: MissionData) -> void:
	if mission.fired_log.is_empty():
		return
	lines.append("")
	lines.append("[b][color=%s]FIRED[/color][/b] (latest first)" % HEAD)
	var recent := mission.fired_log.slice(maxi(0, mission.fired_log.size() - FIRED_SHOWN))
	recent.reverse()
	for entry in recent:
		var at: int = entry[0] / 1000
		var trigger: MissionData.Trigger = data.triggers[entry[1]]
		lines.append("  [color=%s]%d:%02d[/color]  [url=t:%d]#%d %s[/url]%s" % [DIM, at / 60, at % 60, entry[1], entry[1],
				_esc(trigger.name) if trigger.name != "" else _summary(trigger), " [color=%s](cheat)[/color]" % BAD if entry[2] else ""])


func _state(lines: PackedStringArray) -> void:
	var timers := PackedStringArray()
	for i in Mission.TIMERS:
		var ms := mission.timer_ms(i)
		if ms > 0:
			timers.append("%d: %.1f s" % [i, ms / 1000.0])
		elif ms == 0:
			timers.append("%d: run out" % i)
	var flags := PackedStringArray()
	for i in Mission.FLAGS:
		if mission.flag(i):
			flags.append(str(i))
	var variables := PackedStringArray()
	for i in Mission.VARIABLES:
		if mission.variable(i) != -1:
			variables.append("v%d = %d" % [i, mission.variable(i)])
	lines.append("")
	lines.append("[color=%s]timers[/color] %s" % [HEAD, ", ".join(timers) if not timers.is_empty() else "-"])
	lines.append("[color=%s]flags set[/color] %s" % [HEAD, " ".join(flags) if not flags.is_empty() else "-"])
	lines.append("[color=%s]variables[/color] %s" % [HEAD, ", ".join(variables) if not variables.is_empty() else "-"])


func _ai(lines: PackedStringArray, data: MissionData) -> void:
	var units := {}
	var buildings := {}
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team > 0:
			units[unit.team] = units.get(unit.team, 0) + 1
	for object in MapObject.structures:
		if object.is_building() and object.is_alive() and object.owner_index > 0:
			buildings[object.owner_index] = buildings.get(object.owner_index, 0) + 1
	lines.append("")
	lines.append("[b][color=%s]PEOPLES AND AI[/color][/b]" % HEAD)
	for slot in data.players:
		if slot.control == MissionData.Seat.NONE:
			continue
		var seat: String = {MissionData.Seat.HUMAN: "human", MissionData.Seat.COMPUTER: "computer",
				MissionData.Seat.INDEPENDENT: "independent"}.get(slot.control, "?")
		lines.append("[color=%s]P%d %s[/color] [color=%s]%s, %s%s[/color]" % [HEAD, slot.index, _esc(_player_name(slot)), DIM,
				slot.faction, seat, " (you)" if slot.index == main.me else ""])
		var people: Player = Player.by_index.get(slot.index)
		if people:
			var stock := PackedStringArray()
			for key in Player.RESOURCES:
				stock.append("%s %d" % [key, int(people.resources.get(key, 0))])
			lines.append("    %s · %d units, %d buildings" % [" ".join(stock), units.get(slot.index, 0), buildings.get(slot.index, 0)])
		var ki: KiPlayer = main.ki.players.get(slot.index) if main.ki else null
		if ki and ki.running() > 0:
			var modules := {}
			for task: KiTask in ki.slots:
				if task:
					var module_name := _module_name(task.module)
					modules[module_name] = modules.get(module_name, 0) + 1
			var names := PackedStringArray()
			for module_name in modules:
				names.append(module_name if modules[module_name] == 1 else "%s ×%d" % [module_name, modules[module_name]])
			lines.append("    [color=%s]%d modules:[/color] %s" % [DIM, ki.running(), ", ".join(names)])


# ------------------------------------------------------------------ in words

## [words with the value now, whether it holds (null for the OR marker)].
func _condition(c: PackedInt32Array) -> Array:
	var p1 := _p(c, 1)
	var p2 := _p(c, 2)
	var p3 := _p(c, 3)
	match c[0]:
		1:
			return ["always", true]
		2, 12:
			var have := _stock(p1, p3)
			var holds := have >= p2 if c[0] == 2 else have < p2
			return ["stock(P%d, %s) %s %d: %d" % [p1, Mission.RESOURCES.get(p3, "?%d" % p3), ">=" if c[0] == 2 else "<", p2, have], holds]
		3, 11, 13, 14:
			var n := Mission.count(p1, p3, mission.area(_p(c, 4)))
			var compare: String = {3: "=", 11: "=", 13: ">", 14: "<"}[c[0]]
			var holds := n == p2 if compare == "=" else (n > p2 if compare == ">" else n < p2)
			return ["count(P%d, %s in %s) %s %d: %d" % [p1, _type(p3), _area(_p(c, 4)), compare, p2, n], holds]
		4:
			var now := "%d s" % mission.countdown if mission.countdown_running else "not running"
			return ["countdown < %d s: %s" % [p1, now], mission.holds(c)]
		5, 18:
			var is_set := p1 >= 0 and p1 < Mission.FLAGS and mission.flag(p1)
			return ["flag %d %s: %s" % [p1, "set" if c[0] == 5 else "clear", "set" if is_set else "clear"], mission.holds(c)]
		6:
			return ["P%d sees %s" % [p1, _area(p2)], mission.holds(c)]
		7, 9, 8, 10:
			var n := Mission.count(p1, p3)
			var less := c[0] in [7, 9]
			return ["count(P%d, %s) %s %d: %d" % [p1, _type(p3), "<" if less else ">", p2, n], n < p2 if less else n > p2]
		15:
			return ["[color=%s]OR: from here on any one is enough[/color]" % DIM, null]
		16:
			var ms := mission.timer_ms(p1) if p1 >= 0 and p1 < Mission.TIMERS else -1
			var now := "stopped" if ms < 0 else ("run out" if ms == 0 else "%.1f s left" % (ms / 1000.0))
			return ["timer %d run out: %s" % [p1, now], mission.holds(c)]
		17:
			var value := mission.variable(p1) if p1 >= 0 and p1 < Mission.VARIABLES else -1
			var now := "unset" if value == -1 else str(value)
			var note := " (disarms)" if value != -1 and value != p2 else ""
			return ["v%d = %d: %s%s" % [p1, p2, now, note], mission.holds(c)]
	return ["condition %d %s" % [c[0], Array(c.slice(1))], false]


func _action(a: PackedInt32Array) -> String:
	var p1 := _p(a, 1)
	var p2 := _p(a, 2)
	var p3 := _p(a, 3)
	var p4 := _p(a, 4)
	match a[0]:
		1:
			var module := KiModule.load(p2)
			return "start AI module %08d %s for P%d" % [p2, _module_name(module) if module else "(missing)", p1]
		2:
			return "P%d's view to %s" % [p1, _area(p2)]
		3:
			return "%d new %s for P%d at %s" % [p2, _type(p3), p1, _area(p4)]
		4, 13:
			return "P%d %s" % [p1, "loses" if a[0] == 4 else "wins"]
		5:
			return "message to P%d: %s" % [p2, _quote(p1)]
		6, 34:
			return "remove P%d's %s in %s" % [p1, _type(p2), _area(p3)]
		9:
			return "spoken message: %s" % _quote(p1)
		10:
			return "stay armed"
		11:
			return "countdown from %d s" % p1
		12, 23:
			return "%s flag %d" % ["set" if a[0] == 12 else "clear", p1]
		14:
			return "%s (nobody's) at %d,%d" % [_type(p1), p2, p3]
		15, 16:
			return "%s the countdown" % ("show" if a[0] == 15 else "hide")
		18, 19:
			return "%s the player's input" % ("lock" if a[0] == 18 else "unlock")
		20, 24:
			return "%s %s for P%d" % ["uncover" if a[0] == 20 else "cover", _area(p2), p1]
		21, 22:
			return "%s P%d %d %s" % ["give" if a[0] == 21 else "take from", p1, p2, Mission.RESOURCES.get(p3, "?")]
		25:
			return "timer %d = %d s" % [p1, p2]
		26:
			return "stop timer %d" % p1
		27:
			return "goal %d: %s" % [p1, _quote(p1)]
		28, 29:
			return "P%d and P%d %s sight" % [p1, p2, "share" if a[0] == 28 else "stop sharing"]
		30, 31, 32:
			return "P%d and P%d %s" % [p1, p2, ["allied", "at war", "neutral"][a[0] - 30]]
		33:
			return "v%d = random below %d" % [p1, p2]
		35:
			return "%s in %s goes over to P%d" % [_type(p1), _area(p2), p3]
		36:
			return "%s for P%d at %d,%d" % [_type(p1), p4, p2, p3]
		7, 8, 17:
			return "(nothing) %s" % [Array(a)]
	return "action %d %s" % [a[0], Array(a.slice(1))]


static func _p(item: PackedInt32Array, at: int) -> int:
	return item[at] if at < item.size() else 0


func _stock(player: int, which: int) -> int:
	var people: Player = Player.by_index.get(player)
	return int(people.resources.get(Mission.RESOURCES.get(which, ""), 0)) if people else 0


func _type(what: int) -> String:
	if what < 100:
		return CATEGORIES.get(what, "category %d" % what)
	if ANIMAL_NAMES.has(what):
		return ANIMAL_NAMES[what]
	if not _names.has(what):
		var called := String(GameData.stats(what).get("name", ""))
		if called == "" and Mission.EITHER.has(what):
			called = String(GameData.stats(Mission.EITHER[what][0]).get("name", "")) + " (on foot or mounted)"
		if called == "" or called.begins_with(" "):
			called = GameData.text(what, "GUID %d" % what)
		_names[what] = _esc(called)
	return _names[what]


func _area(id: int) -> String:
	if not mission.data.areas.has(id):
		return "the whole map"
	var called: String = mission.data.area_names.get(id, "")
	return "\"%s\"" % _esc(called) if called != "" else "area %d" % id


## A script text's first line, shortened.
func _quote(id: int) -> String:
	var text := " ".join(Array(mission.text(id).split("\n", false)).map(func(l: String) -> String: return l.strip_edges()))
	if text.length() > 70:
		text = text.substr(0, 67) + "…"
	return "[%d] \"%s\"" % [id, _esc(text)] if text != "" else "[%d]" % id


func _player_name(slot: MissionData.PlayerSlot) -> String:
	if slot.name.is_valid_int():
		var titles: Dictionary = Campaign.data().get(Match.campaign.get("set", "base"), {}).get("titles", {})
		return String(titles.get(slot.name, ""))
	return slot.name


static func _module_name(module: KiModule) -> String:
	return module.source if module.source != "" else "%08d" % module.number


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


## Where conditions and actions name an area: opcode -> the parameter.
const CONDITION_AREAS := {3: 4, 11: 4, 13: 4, 14: 4, 6: 2}
const ACTION_AREAS := {2: 2, 3: 4, 6: 3, 34: 3, 20: 2, 24: 2, 35: 2}


## The mission's named areas drawn on the map, the selected trigger's brighter.
class AreaLayer extends Node2D:
	var debug: MissionDebug

	func _init() -> void:
		z_index = 100  # above the fog
		z_as_relative = false

	func _draw() -> void:
		var data := debug.mission.data
		var used := {}
		if debug.picked >= 0 and debug.picked < data.triggers.size():
			var trigger: MissionData.Trigger = data.triggers[debug.picked]
			for c in trigger.conditions:
				if CONDITION_AREAS.has(c[0]):
					used[MissionDebug._p(c, CONDITION_AREAS[c[0]])] = true
			for a in trigger.actions:
				if ACTION_AREAS.has(a[0]):
					used[MissionDebug._p(a, ACTION_AREAS[a[0]])] = true
		var zoom := get_viewport().get_canvas_transform().get_scale().x
		var font := ThemeDB.fallback_font
		var size := roundi(15.0 / maxf(0.25, zoom))
		for id in data.areas:
			var rect: Rect2 = data.areas[id]
			var hue := fmod(float(id) * 0.137, 1.0)
			var lit := used.has(id)
			var colour := Color.from_hsv(hue, 0.65, 1.0, 0.95 if lit else 0.6)
			draw_rect(rect, Color(colour, 0.12 if lit else 0.05))
			draw_rect(rect, colour, false, (4.0 if lit else 2.0) / maxf(0.25, zoom))
			var label := "%d %s" % [id, data.area_names.get(id, "")]
			var at := rect.position + Vector2(6.0 / zoom, size + 4.0 / zoom)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, roundi(4.0 / maxf(0.25, zoom)), Color(0, 0, 0, 0.85))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour.lightened(0.3))
