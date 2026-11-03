class_name Projectile
extends Node2D
## Something thrown or fired across the field with the shooter's own sprite sheet: arrows,
## flaming arrows, knives, tomahawks, cannonballs and dynamite. As AmericaAddOn.exe flies
## them (the projectile base, 0x405240 / 0x405350 / 0x405450): from the shooter's feet to
## where the target stood when it was fired (0x41bcf0, no leading, no homing), in a time
## fixed by kind whatever the distance, starting at a height and falling to the ground with
## a little gravity. When it lands (0x405510) it hits its target if that is still within
## 64 px of the landing point (a building: 96 px), else the first enemy or neutral unit or
## building within 32 px (0x45d560), else nothing. Cannonballs and dynamite then burst
## into the explosion animation (in water, a splash), but hurt only the one they hit.

## The exe's projectile objects, set up by the attack (0x436cc0) per class flag: arrows
## (+0x6d3; 0x4610d0, object 723: archers, flaming archers, Gall, the canoe), knives and
## tomahawks (+0x6d4; 0x457780, 722), cannonballs (+0x6d1; 0x437dc0, 720) and dynamite
## (+0x6d2; 0x4167b0, 721). Flight time in ms (+0xe0) and starting height (+0xb8, drawn
## 0.03 px a unit, 0x461280; the shadow keeps to the ground).
const FLIGHT_MS := {"arrow": 500.0, "knife": 800.0, "tomahawk": 800.0, "ball": 250.0, "dynamite": 500.0}
const HEIGHT := {"arrow": 1500.0, "knife": 1100.0, "tomahawk": 1100.0, "ball": 1.0, "dynamite": 1500.0}
const PX_PER_HEIGHT := 0.03
## Gravity per 20 ms step (0x4a1580); the climb is set so the flight ends on the ground.
const GRAVITY := 0.981
const STEP_MS := 20.0
## Landing (0x405510): the target counts as hit this close to where the shot comes down.
const HIT_UNIT := 64.0
const HIT_BUILDING := 96.0
const STRAY_RADIUS := 32.0
const EXPLOSION_BOB := "effects/explosion/explosion.anims.json"
## Impact sounds from the sound table (GUID 720 cannonball, 721 dynamite; event "shoot").
const IMPACT_SOUND := {"ball": 720, "dynamite": 721}

var _type: UnitType
var _anim := -1
var _kind := ""
var _attacker: Unit
var _team := 0  ## the shooter's people when it fired
var _target: Node2D
var _damage := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _flight_ms := 500.0
var _elapsed_ms := 0.0
var _z0 := 0.0
var _climb := 0.0  ## height gained per step at the start
var _body := Sprite2D.new()
var _step_time := 0.0
var _step := 0


static func launch(shooter: Unit, target: Node2D, damage: float) -> void:
	var p := Projectile.new()
	p._type = shooter.unit_type
	p._anim = shooter.unit_type.projectile_anim
	var file := p._type.bob.sub_sprites[p._type.bob.anims[p._anim].sub_sprite].get_file()
	p._kind = "arrow"
	for kind in UnitType.PROJECTILE_STEMS:
		if file.contains(kind):
			p._kind = kind
	p._attacker = shooter
	p._team = shooter.team
	p._target = target
	p._damage = damage
	p._from = shooter.position
	p._to = shooter.aim_point(target)
	p._flight_ms = FLIGHT_MS.get(p._kind, 500.0)
	p._z0 = HEIGHT.get(p._kind, 1500.0)
	var steps: float = p._flight_ms / STEP_MS
	p._climb = GRAVITY / 2.0 * steps - p._z0 / steps  # 0x405350: 0.4905 T - z0 / T
	p.position = p._from - Vector2(0, p._z0 * PX_PER_HEIGHT)
	p.z_index = 4
	shooter.get_parent().add_child(p)
	p._setup(shooter.team)


func _setup(team: int) -> void:
	_body.centered = false
	_body.region_enabled = true
	add_child(_body)
	var sheet := _type.sprite_for(_anim)
	if sheet == null:
		return
	SpriteMaterials.prepare(_body, sheet)
	_body.material = SpriteMaterials.body(sheet, _type.ramps)
	_body.set_instance_shader_parameter("palette_row", clampi(team, 0, _type.bob.teams - 1))
	_apply(_to - _from)


var _sim_on := false
var _sim_listed := false


func _enter_tree() -> void:
	Sim.activate(self)


## Height above the ground, in the exe's units, after `n` steps of 20 ms (0x405450: the
## height grows by the climb, the climb shrinks by the gravity, each step).
func _height(n: float) -> float:
	return _z0 + _climb * n - GRAVITY * n * (n - 1.0) / 2.0


## One step of the game (Sim).
func sim_tick(delta: float) -> void:
	_elapsed_ms = minf(_flight_ms, _elapsed_ms + delta * 1000.0)
	var f := _elapsed_ms / _flight_ms
	var ground := _from.lerp(_to, f)
	var lift := maxf(0.0, _height(_elapsed_ms / STEP_MS)) * PX_PER_HEIGHT
	var previous := position
	position = ground - Vector2(0, lift)
	_step_time += delta * 1000.0
	var anim := _type.bob.anims[_anim]
	if _step_time >= anim.durations_ms[_step % anim.durations_ms.size()]:
		_step_time = 0.0
		_step = (_step + 1) % anim.frames.size()
	_apply(position - previous)
	if _elapsed_ms >= _flight_ms:
		_land()


func _apply(heading: Vector2) -> void:
	var sheet := _type.sprite_for(_anim)
	if sheet == null:
		return
	var anim := _type.bob.anims[_anim]
	var direction := 0
	if heading.length_squared() > 0.01:
		direction = posmod(roundi((rad_to_deg(heading.angle()) - 45.0) / 45.0), 8)
	var frame := (direction % anim.directions) * anim.frames_per_direction + anim.frames[mini(_step, anim.frames.size() - 1)]
	if frame < sheet.frame_count():
		sheet.apply(_body, frame)


## What the shot hits where it comes down (0x405510): its target if still close enough,
## else the first enemy or neutral unit or building within 32 px, else nothing.
func _victim(side: int) -> Node2D:
	if is_instance_valid(_target) and _target.is_alive() and not Unit.at_peace(side, _target):
		if _target is MapObject:
			if _target.wall_point(_to).distance_to(_to) < HIT_BUILDING:
				return _target
		elif _target.position.distance_to(_to) < HIT_UNIT:
			return _target
	var best: Node2D = null
	var best_distance := STRAY_RADIUS
	for unit: Unit in UnitGrid.near(_to, STRAY_RADIUS):
		var distance := unit.position.distance_to(_to)
		if distance < best_distance and unit.is_alive() and not unit.inside and _strikes(side, unit.team):
			best = unit
			best_distance = distance
	if best:
		return best
	for object in MapObject.structures:
		if object.is_alive() and object.is_building() and _strikes(side, object.owner_index) \
				and object.wall_point(_to).distance_to(_to) < best_distance:
			best = object
			best_distance = object.wall_point(_to).distance_to(_to)
	return best


## The stray shot's test (0x42c040 at 0x45d5d8): the shooter's enemies, or no one's.
static func _strikes(side: int, other: int) -> bool:
	return other <= 0 or Diplomacy.hostile(side, other)


func _land() -> void:
	var explodes := _kind == "ball" or _kind == "dynamite"
	var side := _attacker.team if is_instance_valid(_attacker) else _team
	var victim := _victim(side)
	if victim:
		if is_instance_valid(_attacker):
			_attacker.deal_damage(victim, _damage, explodes)  # flaming arrows too: a plain blow
		else:
			victim.take_damage(_damage, null, explodes)
	if explodes:
		var nav := NavGrid.current
		if victim == null and nav and nav.has_water and nav.is_deep_water(nav.cell_of(_to)):
			Sound.play_named("water_splash", _to, true)  # into the river (0x4069b0, 0x438023)
		else:
			Sound.play_event(IMPACT_SOUND[_kind], Sound.Event.SHOOT, _to, 0)
		# One object takes the blast, as with any shot (0x405510): no splash round it.
		OrderMarker.effect(get_parent(), _to, EXPLOSION_BOB, 0)
	queue_free()
