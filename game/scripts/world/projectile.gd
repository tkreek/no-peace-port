class_name Projectile
extends Node2D
## Something thrown or fired across the field with the shooter's own sprite sheet: arrows,
## flaming arrows, knives, tomahawks, cannonballs and dynamite. It homes on its target and
## deals the damage when it lands; cannonballs and dynamite burst into the original
## explosion animation and hurt everyone close by.

const SPEED := {"ball": 1800.0, "dynamite": 480.0, "tomahawk": 620.0, "knife": 720.0}
const DEFAULT_SPEED := 900.0  # arrows
const ARC := {"ball": 0.03, "dynamite": 0.3, "tomahawk": 0.12, "knife": 0.06}
## Kinds that fly straight at where the target stood when fired instead of following it.
const STRAIGHT := ["ball"]
## Cannonballs leave from the muzzle: this far out along the barrel, and this high.
const MUZZLE := Vector2(30.0, -14.0)
const EXPLOSION_BOB := "effects/explosion/explosion.anims.json"
const SPLASH_RADIUS := 40.0
## Impact sounds from the sound table (GUID 720 cannonball, 721 dynamite; event "shoot").
const IMPACT_SOUND := {"ball": 720, "dynamite": 721}

var _type: UnitType
var _anim := -1
var _kind := ""
var _attacker: Unit
var _target: Node2D
var _hit := true
var _damage := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _flight := 0.0
var _duration := 0.3
var _body := Sprite2D.new()
var _step_time := 0.0
var _step := 0


static func launch(shooter: Unit, target: Node2D, damage: float, hit: bool) -> void:
	var p := Projectile.new()
	p._type = shooter.unit_type
	p._anim = shooter.unit_type.projectile_anim
	var file := p._type.bob.sub_sprites[p._type.bob.anims[p._anim].sub_sprite].get_file()
	for kind in UnitType.PROJECTILE_STEMS:
		if file.contains(kind):
			p._kind = kind
	p._attacker = shooter
	p._target = target
	p._damage = damage
	p._hit = hit
	p._from = shooter.position + Vector2(0, -22)
	if p._kind == "ball":
		var barrel := Vector2.from_angle(deg_to_rad(shooter.direction * 45.0 + 45.0))
		p._from = shooter.position + barrel * MUZZLE.x + Vector2(0, MUZZLE.y)
	p._to = shooter.aim_point(target)
	if not hit:
		p._to += Vector2(Sim.randf_range(-30, 30), Sim.randf_range(-20, 20))
	p._duration = maxf(0.12, p._from.distance_to(p._to) / SPEED.get(p._kind, DEFAULT_SPEED))
	p.position = p._from
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


## One step of the game (Sim).
func sim_tick(delta: float) -> void:
	# Follow a moving target so a hit lands where the target now stands.
	if _hit and _kind not in STRAIGHT and is_instance_valid(_target) and _target.is_alive() and _attacker and is_instance_valid(_attacker):
		_to = _attacker.aim_point(_target) if _target is MapObject else _target.position + Vector2(0, -16)
	_flight = minf(1.0, _flight + delta / _duration)
	var ground := _from.lerp(_to, _flight)
	var lift := sin(_flight * PI) * _from.distance_to(_to) * float(ARC.get(_kind, 0.0))
	var previous := position
	position = ground - Vector2(0, lift)
	_step_time += delta * 1000.0
	var anim := _type.bob.anims[_anim]
	if _step_time >= anim.durations_ms[_step % anim.durations_ms.size()]:
		_step_time = 0.0
		_step = (_step + 1) % anim.frames.size()
	_apply(position - previous)
	if _flight >= 1.0:
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


func _land() -> void:
	var explodes := _kind == "ball" or _kind == "dynamite"
	if _hit and is_instance_valid(_target) and _target.is_alive():
		if is_instance_valid(_attacker):
			_attacker.deal_damage(_target, _damage, explodes)
			if _target is MapObject and _attacker.unit_type.guid() in BuildingCondition.FIRE_STARTERS:
				_target.condition.ignite()
		else:
			_target.take_damage(_damage, null, explodes)
	if explodes:
		var nav := NavGrid.current
		if not _hit and nav and nav.has_water and nav.is_deep_water(nav.cell_of(_to)):
			Sound.play_named("water_splash", _to, true)  # a miss goes into the river
		else:
			Sound.play_event(IMPACT_SOUND[_kind], Sound.Event.SHOOT, _to, 0)
		OrderMarker.effect(get_parent(), _to, EXPLOSION_BOB, 0)
		var team := _attacker.team if is_instance_valid(_attacker) else -1
		for unit: Unit in UnitGrid.near(_to, SPLASH_RADIUS):
			if unit != _target and unit.is_alive() and unit.team > 0 and unit.team != team \
					and unit.position.distance_to(_to) < SPLASH_RADIUS:
				unit.take_damage(_damage * 0.5, _attacker if is_instance_valid(_attacker) else null, true)
	queue_free()
