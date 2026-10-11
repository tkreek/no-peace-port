class_name MissionPanel
extends VBoxContainer
## A mission's messages under the stockpiles: what the script tells the player (goals,
## people talking), each on a dark board for its seconds or as long as its speech lasts,
## the newest at the bottom; and the countdown clock when the script shows it.

const MAX_SHOWN := 4
const WIDTH := 640.0
## A spoken message stays this much longer than its recording.
const SPEECH_TAIL := 2.0
const DEFAULT_SECONDS := 10.0

var hud: Hud
var clock := Label.new()
var _speech := AudioStreamPlayer.new()


func _init(owner: Hud) -> void:
	hud = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE  # messages wait while the game is paused
	add_theme_constant_override("separation", 6)
	add_child(_speech)
	HudStyle.style_label(clock, 28)
	clock.visible = false
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Shows `text` for `seconds` (negative: as long as `speech` plays, which it starts).
func show_message(text: String, seconds: float, speech := "") -> void:
	if speech != "":
		var stream := Sound.speech_stream(speech)
		if stream:
			_speech.stream = stream
			_speech.volume_db = linear_to_db(maxf(0.001, Sound.sfx_volume))
			_speech.play()
			seconds = stream.get_length() + SPEECH_TAIL
	elif text != "":
		Sound.play_alert(Hud.MESSAGE_SOUND_GUID)
	if text == "":
		return
	if seconds <= 0.0:
		seconds = DEFAULT_SECONDS
	while get_child_count() > MAX_SHOWN:  # the speech player is a child too
		_drop(_boards()[0])
	var board := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.045, 0.025, 0.82)
	box.border_color = Color(0.55, 0.38, 0.2, 0.9)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10 * hud.ui_scale)
	board.add_theme_stylebox_override("panel", box)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := HudStyle.label(int(17 * hud.ui_scale))
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH * hud.ui_scale
	board.add_child(label)
	add_child(board)
	var tween := board.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(board, "modulate:a", 0.0, 1.0)
	tween.tween_callback(_drop.bind(board))


func _boards() -> Array:
	return get_children().filter(func(c: Node) -> bool: return c is PanelContainer)


func _drop(board: Control) -> void:
	if is_instance_valid(board) and board.get_parent() == self:
		remove_child(board)
		board.queue_free()


func update_clock(mission: Mission) -> void:
	clock.visible = mission.clock_shown
	if clock.visible:
		clock.text = "%d:%02d" % [mission.countdown / 60, mission.countdown % 60]
