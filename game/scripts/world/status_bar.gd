class_name StatusBar
extends RefCounted
## The original's little gauges over a selected unit or building: a row of short segments,
## each coloured by where it sits on the scale (red at the empty end, yellow, then green),
## lit up to the level; the morale row below is blue. Selections are marked in the player's
## colour: a ring at a unit's feet, a diamond on the ground round a building.

const SEGMENT := 2.0
const GAP := 1.0
const HEIGHT := 3.0
const BACK := Color(0.08, 0.08, 0.06, 0.85)
const MORALE := Color(0.35, 0.6, 1.0)
const BUILD := Color(0.95, 0.75, 0.2)


## A segmented row `width` wide with its top-left at `at`, lit to `ratio` (0..1). Without a
## `colour`, each segment takes its place on the red-yellow-green scale.
static func draw(canvas: CanvasItem, at: Vector2, width: float, ratio: float, colour := Color(0, 0, 0, 0)) -> void:
	var count := maxi(int((width + GAP) / (SEGMENT + GAP)), 4)
	var full := (SEGMENT + GAP) * count - GAP
	canvas.draw_rect(Rect2(at - Vector2.ONE, Vector2(full + 2.0, HEIGHT + 2.0)), BACK)
	var lit := ceili(clampf(ratio, 0.0, 1.0) * count - 0.001)
	for i in lit:
		var place := float(i) / maxf(count - 1, 1)
		var c := colour if colour.a > 0.0 else scale_colour(place)
		canvas.draw_rect(Rect2(at + Vector2(i * (SEGMENT + GAP), 0), Vector2(SEGMENT, HEIGHT)), c)


static func scale_colour(place: float) -> Color:
	var red := Color(0.9, 0.15, 0.05)
	var yellow := Color(0.95, 0.85, 0.1)
	var green := Color(0.25, 0.85, 0.15)
	return red.lerp(yellow, place * 2.0) if place < 0.5 else yellow.lerp(green, place * 2.0 - 1.0)


static func team_colour(team: int) -> Color:
	return Player.TEAM_COLORS[team] if team > 0 and team < Player.TEAM_COLORS.size() else Color(0.9, 0.9, 0.9)


## A thin ellipse at a unit's feet.
static func ring(canvas: CanvasItem, centre: Vector2, radius: float, colour: Color) -> void:
	canvas.draw_set_transform(centre, 0.0, Vector2(1.0, 0.5))
	canvas.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(colour, 0.95), 1.5, true)
	canvas.draw_set_transform(Vector2.ZERO)
