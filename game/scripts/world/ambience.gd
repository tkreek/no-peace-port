class_name Ambience
extends Node2D
## Life in the background: now and then a flock of gulls circles over water in view, and
## an eagle sails across the land, each with its shadow on the ground (effects/gulls,
## effects/eagle); and a river in view is heard flowing ("Sound Fluß").

const GULLS := "effects/gulls/gulls.anims.json"
const EAGLE := "effects/eagle/eagle.anims.json"
const GULL_PAUSE := Vector2(20.0, 45.0)  # seconds between flocks
const EAGLE_PAUSE := Vector2(50.0, 110.0)
const GULL_SECONDS := 30.0
const MAX_FLOCKS := 2
const EAGLE_SPEED := 110.0
const GULL_DRIFT := 12.0
const RIVER_CHECK := 2.0  # seconds between looks for the water nearest the middle of the view
const RIVER_VOLUME := 0.45
const RIVER_REACH := 1400.0

var camera: Camera2D
var _gull_wait := 8.0
var _eagle_wait := 30.0
var _river_wait := 1.0
var _river: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 80  # above units and buildings, under the fog of war
	_rng.randomize()


func _process(delta: float) -> void:
	if camera == null or NavGrid.current == null:
		return
	_gull_wait -= delta
	_eagle_wait -= delta
	_river_wait -= delta
	var view := _view()
	if _river_wait <= 0.0:
		_river_wait = RIVER_CHECK
		_place_river(view)
	if _gull_wait <= 0.0:
		_gull_wait = _rng.randf_range(GULL_PAUSE.x, GULL_PAUSE.y)
		var flocks := get_children().filter(func(n: Node) -> bool: return n is Flyer and n.set_path == GULLS)
		var water := _water_in(view)
		if flocks.size() < MAX_FLOCKS and water != Vector2.INF:
			var drift := Vector2.from_angle(_rng.randf() * TAU) * GULL_DRIFT
			_add(Flyer.new(GULLS, water, drift, 0, GULL_SECONDS))
	if _eagle_wait <= 0.0:
		_eagle_wait = _rng.randf_range(EAGLE_PAUSE.x, EAGLE_PAUSE.y)
		# In from one side of the view, out at the other.
		var heading := Vector2.from_angle(_rng.randf() * TAU)
		var start := view.get_center() - heading * (view.size.length() * 0.6) \
				+ heading.orthogonal() * _rng.randf_range(-0.3, 0.3) * view.size.y
		var direction := posmod(roundi((rad_to_deg(heading.angle()) - 45.0) / 45.0), 8)
		_add(Flyer.new(EAGLE, start, heading * EAGLE_SPEED, direction, view.size.length() * 1.2 / EAGLE_SPEED))


func _add(flyer: Flyer) -> void:
	if flyer.ready_to_fly():
		add_child(flyer)


func _view() -> Rect2:
	var size := get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - size / 2.0, size)


## The river's sound follows the water nearest the middle of the view, and falls silent
## when no water is in view.
func _place_river(view: Rect2) -> void:
	var water := _water_in(view, 32, view.get_center())
	if water == Vector2.INF:
		if _river:
			_river.stop()
		return
	if _river == null:
		_river = Sound.work_emitter("river")
		if _river == null:
			return
		_river.max_distance = RIVER_REACH
		_river.volume_db += linear_to_db(RIVER_VOLUME)
		_river.finished.connect(_river.play)
		_river.position = water
		add_child(_river)
	if _river.playing:
		_river.create_tween().tween_property(_river, "position", water, RIVER_CHECK)
	else:
		_river.position = water
		_river.play()


## A spot of open water in view (a few random tries), or INF.
## With `near`, the one closest to it of all the tries.
func _water_in(view: Rect2, tries := 24, near := Vector2.INF) -> Vector2:
	var nav := NavGrid.current
	if not nav.has_water:
		return Vector2.INF
	var best := Vector2.INF
	for i in tries:
		var p := view.position + Vector2(_rng.randf(), _rng.randf()) * view.size
		if nav.is_deep_water(nav.cell_of(p)):
			if near == Vector2.INF:
				return p
			if best == Vector2.INF or p.distance_squared_to(near) < best.distance_squared_to(near):
				best = p
	return best


## A bird (or flock) and its shadow, flying for a while and fading in and out.
class Flyer:
	extends Node2D

	const FADE := 2.0
	## Where the shadow falls from the bird, on the ground below (world px).
	const GROUND_OFFSET := Vector2(36.0, 130.0)
	static var _figures := {}  # sheet path -> per frame the centre of its opaque pixels

	var set_path := ""
	var _bob: BobFile
	var _velocity := Vector2.ZERO
	var _direction := 0
	var _life := 0.0
	var _age := 0.0
	var _step := 0
	var _time := 0.0
	var _body := Sprite2D.new()
	var _shadow := Sprite2D.new()

	func _init(path: String, at: Vector2, velocity: Vector2, direction: int, seconds: float) -> void:
		set_path = path
		position = at
		_velocity = velocity
		_direction = direction
		_life = seconds
		_bob = GameData.load_bob(path)

	func ready_to_fly() -> bool:
		return _bob != null and _bob.anims.size() >= 2

	func _ready() -> void:
		for sprite: Sprite2D in [_shadow, _body]:
			sprite.centered = false
			sprite.region_enabled = true
			add_child(sprite)
		SpriteMaterials.make_shadow(_shadow)
		modulate.a = 0.0
		_apply()

	func _process(delta: float) -> void:
		_age += delta
		position += _velocity * delta
		modulate.a = clampf(minf(_age, _life - _age) / FADE, 0.0, 1.0)
		if _age >= _life:
			queue_free()
			return
		var anim := _bob.anims[0]
		_time += delta * 1000.0
		while _time >= anim.durations_ms[_step]:
			_time -= anim.durations_ms[_step]
			_step = (_step + 1) % anim.frames.size()
		_apply()

	func _apply() -> void:
		var body_centre := _show(_body, 0)
		var shadow_centre := _show(_shadow, 1)
		# The original shadow frames aren't anchored like their birds: put the shadow's
		# figure straight under the bird's.
		_shadow.position = body_centre - shadow_centre + GROUND_OFFSET

	## Show the frame; returns the centre of its figure relative to the sprite's anchor.
	func _show(sprite: Sprite2D, anim_index: int) -> Vector2:
		var anim := _bob.anims[anim_index]
		var sheet := GameData.load_set_sheet(set_path, _bob, anim.sub_sprite)
		if sheet == null:
			return Vector2.ZERO
		var frame := (_direction % anim.directions) * anim.frames_per_direction + anim.frames[mini(_step, anim.frames.size() - 1)]
		if frame >= sheet.frame_count():
			return Vector2.ZERO
		if sprite.texture != sheet.texture:
			SpriteMaterials.prepare(sprite, sheet)
		sheet.apply(sprite, frame)
		return (_figure_centre(anim.sub_sprite, sheet, frame) - sheet.hotspots[frame]) / sheet.scale

	func _figure_centre(sheet_index: int, sheet: RdSprite, frame: int) -> Vector2:
		var key := set_path.get_base_dir().path_join(_bob.sub_sprites[sheet_index])
		if not _figures.has(key):
			var image := GameData.load_image(key + ".png")
			var centres := PackedVector2Array()
			for rect in sheet.rects:
				var used := image.get_region(rect).get_used_rect() if image else Rect2i(Vector2i.ZERO, rect.size)
				centres.append(Vector2(used.get_center()))
			_figures[key] = centres
		return _figures[key][frame]
