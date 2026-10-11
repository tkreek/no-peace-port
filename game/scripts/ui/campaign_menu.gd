class_name CampaignMenu
extends RefCounted
## The campaign screens of the main menu, on the original's pictures: choose a people
## (selectkampagne: four figures in wooden rings), then one of its missions (selectmission:
## the mission's map on the big board, the list beside it), then the briefing (the people's
## storyteller with the map on the parchment and the tale, read out, beside them).
## Missions open one at a time (Campaign.unlocked); the expansion's campaigns and the
## tutorials have their own entries.

## Where each people's figure stands (centre of its ring) on the 800x600 picture, and its
## frames in the button sheet (normal, hover, pressed).
const RINGS := {"ind": Vector2(397, 262), "mex": Vector2(215, 340), "usa": Vector2(579, 340), "des": Vector2(397, 470)}
const FIGURES := {"des": 0, "ind": 3, "mex": 6, "usa": 9}
const RING_AT := 0.62  ## how far down its frame a figure's ring is centred
const TITLE_SLOT := Rect2(277, 103, 247, 30)
const PICTURE_SLOT := Rect2(278, 154, 376, 216)
const LIST_SLOT := Rect2(56, 152, 204, 214)
const LEFT_BARS := [Rect2(56, 380, 204, 26), Rect2(56, 417, 204, 26), Rect2(56, 455, 204, 26), Rect2(56, 494, 204, 26)]
const RIGHT_BARS := [Rect2(278, 380, 376, 26), Rect2(278, 417, 376, 26), Rect2(278, 455, 376, 26)]
## The briefing: the map on the storyteller's parchment, the tale on the dark side.
const BRIEF_MAP := Rect2(0, 330, 424, 270)  ## the picture is that corner of the backdrop with the map on it
const BRIEF_TEXT := Rect2(446, 40, 336, 470)

var menu: Control  ## the main menu (MainMenu): screens, backdrops, loading
var campaign_screen := Control.new()
var missions_screen := Control.new()
var briefing_screen := Control.new()
var set_name := "base"
var people := "ind"
var selected := {}  ## the mission entry picked

var _sheet: RdSprite
var _set_button: Button
var _title := Label.new()
var _list := VBoxContainer.new()
var _picture := TextureRect.new()
var _mission_title := Label.new()
var _mission_state := Label.new()
var _brief_title := Label.new()
var _brief_text := RichTextLabel.new()
var _brief_map := TextureRect.new()
var _narration := AudioStreamPlayer.new()


func _init(main_menu: Control) -> void:
	menu = main_menu
	_sheet = GameData.load_sprite(Campaign.art("select_campaign_buttons"))
	set_name = "base" if Campaign.has_set("base") else "expansion"
	for screen in [campaign_screen, missions_screen, briefing_screen]:
		screen.size = Vector2(800, 600)
	_build_campaign()
	_build_missions()
	_build_briefing()
	briefing_screen.add_child(_narration)
	_fill_missions()


## The screen to open after a mission (Match.campaign): its campaign's list, the next
## mission picked.
func resume(entry: Dictionary) -> void:
	set_name = entry.get("set", set_name)
	people = entry.get("people", people)
	_fill_missions()


# ------------------------------------------------------------------ choose a people

func _build_campaign() -> void:
	var title := _slot_label(TITLE_SLOT, "Campaign", 18)
	campaign_screen.add_child(title)
	for p in RINGS:
		campaign_screen.add_child(_figure(p))
	var bottom := VBoxContainer.new()
	bottom.position = Vector2(40, 456)
	bottom.add_theme_constant_override("separation", 8)
	campaign_screen.add_child(bottom)
	bottom.add_child(menu._small_button(GameData.menu_text(16, "Back"), func() -> void: menu._show("main")))
	if not Campaign.missions("base", Campaign.TUTORIAL).is_empty():
		bottom.add_child(menu._small_button("Tutorials", func() -> void:
			set_name = "base"
			_open(Campaign.TUTORIAL)))
	if Campaign.has_set("base") and Campaign.has_set("expansion"):
		_set_button = menu._small_button("", func() -> void:
			set_name = "expansion" if set_name == "base" else "base"
			_refresh_set())
		_set_button.custom_minimum_size.x = 180
		bottom.add_child(_set_button)
	_refresh_set()


func _refresh_set() -> void:
	if _set_button:
		_set_button.text = "Expansion campaigns" if set_name == "base" else "Original campaigns"
	for child in campaign_screen.get_children():
		if child.has_meta("people"):
			(child.get_meta("caption") as Label).text = Campaign.people_name(set_name, child.get_meta("people"))


## A people's figure in its ring, lighting up under the pointer, with its name below.
func _figure(p: String) -> Control:
	var frame: int = FIGURES[p]
	var button := TextureButton.new()
	button.set_meta("people", p)
	button.texture_normal = _frame(frame)
	button.texture_hover = _frame(frame + 1)
	button.texture_pressed = _frame(frame + 2)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var size := Vector2(_sheet.rects[frame].size) / _sheet.scale if _sheet else Vector2(160, 196)
	button.size = size
	button.position = RINGS[p] - Vector2(size.x / 2.0, size.y * RING_AT)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_open.bind(p))
	var caption := MenuStyle.label("", 15)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size = Vector2(size.x + 60, 20)
	caption.position = Vector2(-30, size.y * RING_AT + 64)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	button.set_meta("caption", caption)
	return button


func _frame(index: int) -> Texture2D:
	if _sheet == null or index >= _sheet.frame_count():
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = _sheet.texture
	atlas.region = Rect2(_sheet.rects[index])
	return atlas


func _open(which: String) -> void:
	people = which
	if Campaign.missions(set_name, people).is_empty():
		return
	_fill_missions()
	menu._show("missions")


# ------------------------------------------------------------------ choose a mission

func _build_missions() -> void:
	_title = _slot_label(TITLE_SLOT, "", 18)
	missions_screen.add_child(_title)
	_picture.position = PICTURE_SLOT.position
	_picture.size = PICTURE_SLOT.size
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	missions_screen.add_child(_picture)
	var scroll := ScrollContainer.new()
	scroll.position = LIST_SLOT.position
	scroll.size = LIST_SLOT.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.custom_minimum_size.x = LIST_SLOT.size.x - 6
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	missions_screen.add_child(scroll)
	_mission_title = _slot_label(RIGHT_BARS[0], "", 16)
	_mission_state = _slot_label(RIGHT_BARS[1], "", 14, MenuStyle.TEXT_DIM)
	missions_screen.add_child(_mission_title)
	missions_screen.add_child(_mission_state)
	missions_screen.add_child(_bar_button(LEFT_BARS[0], "Briefing", _brief))
	missions_screen.add_child(_bar_button(LEFT_BARS[1], "Start mission", _start))
	missions_screen.add_child(_bar_button(LEFT_BARS[3], GameData.menu_text(16, "Back"), func() -> void: menu._show("campaign")))


func _fill_missions() -> void:
	for child in _list.get_children():
		child.queue_free()
	var title := Campaign.people_name(set_name, people)
	_title.text = title if people == Campaign.TUTORIAL or set_name == "base" else "%s (expansion)" % title
	var list := Campaign.missions(set_name, people)
	var open := Campaign.unlocked(set_name, people)
	for i in list.size():
		var entry := Campaign.mission_entry("%s/%s" % [set_name, list[i].code])
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, Campaign.title(entry)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.disabled = i >= open
		MenuStyle.style(button, 13, MenuStyle.TEXT if i < open else MenuStyle.TEXT_DIM)
		button.add_theme_color_override("font_disabled_color", Color(0.45, 0.4, 0.33))
		button.add_theme_color_override("font_hover_color", MenuStyle.TEXT_HOVER)
		button.add_theme_color_override("font_pressed_color", MenuStyle.TEXT_HOVER)
		for state in ["normal", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(0.45, 0.25, 0.08, 0.6)
		lit.set_corner_radius_all(3)
		button.add_theme_stylebox_override("hover", lit)
		button.add_theme_stylebox_override("pressed", lit)
		button.pressed.connect(_pick.bind(entry, button))
		_list.add_child(button)
	var first := mini(open, list.size()) - 1
	if first >= 0:
		_pick(Campaign.mission_entry("%s/%s" % [set_name, list[first].code]), _list.get_child(first))


func _pick(entry: Dictionary, button: Button) -> void:
	selected = entry
	for child in _list.get_children():
		(child as Button).set_pressed_no_signal(child == button)
	_picture.texture = _texture(entry.get("picture", ""))
	_mission_title.text = Campaign.title(entry)
	var count := Campaign.missions(entry.set, entry.people).size()
	_mission_state.text = "Mission %d of %d%s" % [int(entry.number), count,
			" — won" if Campaign.won(entry.set, entry.code) else ""]


# ------------------------------------------------------------------ briefing

func _build_briefing() -> void:
	_brief_map.position = BRIEF_MAP.position
	_brief_map.size = BRIEF_MAP.size
	_brief_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_brief_map.stretch_mode = TextureRect.STRETCH_SCALE
	_brief_map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	briefing_screen.add_child(_brief_map)
	var board := Panel.new()
	board.position = BRIEF_TEXT.position - Vector2(12, 12)
	board.size = BRIEF_TEXT.size + Vector2(24, 70)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.025, 0.015, 0.72)
	box.set_corner_radius_all(6)
	board.add_theme_stylebox_override("panel", box)
	briefing_screen.add_child(board)
	_brief_title = MenuStyle.label("", 20)
	_brief_title.position = BRIEF_TEXT.position
	_brief_title.size = Vector2(BRIEF_TEXT.size.x, 28)
	_brief_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing_screen.add_child(_brief_title)
	_brief_text.position = BRIEF_TEXT.position + Vector2(0, 36)
	_brief_text.size = BRIEF_TEXT.size - Vector2(0, 36)
	_brief_text.add_theme_font_override("normal_font", MenuStyle.font())
	_brief_text.add_theme_font_size_override("normal_font_size", 13)
	_brief_text.add_theme_color_override("default_color", MenuStyle.TEXT)
	_brief_text.scroll_active = true
	briefing_screen.add_child(_brief_text)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(BRIEF_TEXT.position.x, BRIEF_TEXT.end.y + 18)
	buttons.add_theme_constant_override("separation", 20)
	briefing_screen.add_child(buttons)
	buttons.add_child(menu._small_button(GameData.menu_text(16, "Back"), func() -> void:
		_narration.stop()
		Sound.play_music("title")
		menu._show("missions")))
	buttons.add_child(menu._small_button("Start mission", _start))


func _brief() -> void:
	if selected.is_empty():
		return
	_brief_title.text = Campaign.title(selected)
	var story := Campaign.story(selected)
	_brief_text.text = story if story != "" else _first_goal(selected)
	_brief_text.scroll_to_line(0)
	_brief_map.texture = _texture(selected.get("picture", ""))
	menu.set_screen_backdrop("briefing", Campaign.art(selected.people) if Campaign.art(selected.people) != "" \
			else Campaign.art("select_mission"))
	menu._show("briefing")
	Sound.play_music("briefing")
	_narration.stop()
	if selected.get("narration", "") != "":
		_narration.stream = Sound.speech_stream(selected.narration)
		_narration.volume_db = linear_to_db(maxf(0.001, Sound.sfx_volume))
		_narration.play()


## A tutorial has no story: its first goal stands in.
func _first_goal(entry: Dictionary) -> String:
	var map := AlfMap.load_from_file(GameData.path(entry.map))
	if map == null:
		return ""
	for trigger in MissionData.from_map(map).triggers:
		for action in trigger.actions:
			if action[0] == 27 and action.size() > 1:
				return String(Campaign.texts(entry.set).get(str(action[1]), "")).replace("@", "\n")
	return ""


func _start() -> void:
	if selected.is_empty():
		return
	_narration.stop()
	Match.setup(selected.map, [])
	Match.campaign = selected
	Match.population_limit = Match.POPULATION_LIMITS[-1]
	Match.speed = 1.0
	Match.difficulty = 2
	Match.game_type = Match.GameType.EVERYBODY
	menu._show_loading()
	await menu.get_tree().process_frame
	await menu.get_tree().process_frame
	menu.get_tree().change_scene_to_file("res://scenes/main.tscn")


# ------------------------------------------------------------------ pieces

func _slot_label(rect: Rect2, text: String, size: int, color := MenuStyle.TEXT) -> Label:
	var label := MenuStyle.label(text, size, color)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A text button filling one of the board's dark bars.
func _bar_button(rect: Rect2, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	MenuStyle.style(button, 15)
	button.add_theme_color_override("font_hover_color", MenuStyle.TEXT_HOVER)
	for state in ["normal", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(0.45, 0.25, 0.08, 0.45)
	lit.set_corner_radius_all(12)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("pressed", lit)
	button.pressed.connect(action)
	return button


func _texture(asset: String) -> Texture2D:
	if asset == "":
		return null
	var image := GameData.load_image(asset)
	return ImageTexture.create_from_image(image) if image else null
