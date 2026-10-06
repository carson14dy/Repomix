class_name Vfx
extends Node2D
## Short-lived hit feedback drawn in world space: hit sparks, slash arcs and landing dust.
## Effects age in _physics_process so their lifetimes are deterministic frame counts; _draw
## reads age / life as 0..1 and never mutates anything.

const SPARK_LIFE := 9
const SPARK_LIFE_STRONG := 14
const SLASH_LIFE := 9
const DUST_LIFE := 12
const SPIKES := 8
const PUFFS := 4
## Outward drift of each dust puff, in the order drawn.
const PUFF_DIRS: Array[Vector2] = [
	Vector2(-1.0, -0.3), Vector2(-0.4, -0.7), Vector2(0.4, -0.7), Vector2(1.0, -0.3)
]

var _effects: Array[Dictionary] = []


## Starburst at `pos`: 8 spikes of `color` (outer radius 40, 64 when strong), an expanding
## white ring and a white centre flash. Lives 9 frames, 14 when strong.
func hit_spark(pos: Vector2, color: Color, strong: bool) -> void:
	var spark := {"kind": "spark", "pos": pos, "color": color, "age": 0}
	spark["radius"] = 64.0 if strong else 40.0
	spark["life"] = SPARK_LIFE_STRONG if strong else SPARK_LIFE
	_effects.append(spark)


## Crescent in front of a fighter at `pos` swinging towards `facing` (1 right, -1 left).
func slash_arc(pos: Vector2, facing: int, color: Color) -> void:
	var centre := pos + Vector2(22.0 * facing, -34.0)
	var slash := {"kind": "slash", "pos": centre, "facing": facing, "color": color, "age": 0}
	slash["life"] = SLASH_LIFE
	_effects.append(slash)


## Four grey puffs drifting out from the feet position `pos`.
func dust(pos: Vector2) -> void:
	_effects.append({"kind": "dust", "pos": pos, "life": DUST_LIFE, "age": 0})


func active_effect_count() -> int:
	return _effects.size()


func _physics_process(_delta: float) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		var effect := _effects[i]
		effect["age"] += 1
		if effect["age"] >= effect["life"]:
			_effects.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for effect in _effects:
		var t: float = float(effect["age"]) / float(effect["life"])
		match effect["kind"]:
			"spark":
				_draw_spark(effect, t)
			"slash":
				_draw_slash(effect, t)
			"dust":
				_draw_dust(effect, t)


func _draw_spark(effect: Dictionary, t: float) -> void:
	var pos: Vector2 = effect["pos"]
	var color: Color = effect["color"]
	var outer: float = effect["radius"]
	var fade := 1.0 - t
	# Spikes shoot out over the first third of the life, then fade in place.
	var reach := outer * minf(1.0, t * 3.0 + 0.25)
	var spike_color := Color(color, fade)
	for i in range(SPIKES):
		var angle := TAU * i / SPIKES + 0.2
		var dir := Vector2.from_angle(angle)
		var side := dir.orthogonal() * 4.0 * fade
		draw_colored_polygon(
			PackedVector2Array([pos + dir * 6.0 + side, pos + dir * reach, pos + dir * 6.0 - side]),
			spike_color
		)
	draw_arc(pos, outer * (0.3 + 0.9 * t), 0.0, TAU, 32, Color(1.0, 1.0, 1.0, fade), 4.0, true)
	draw_circle(pos, 14.0 * fade, Color(1.0, 1.0, 1.0, fade))


func _draw_slash(effect: Dictionary, t: float) -> void:
	var pos: Vector2 = effect["pos"]
	var color: Color = effect["color"]
	var facing: int = effect["facing"]
	var fade := 1.0 - t
	# Sweep the crescent in over the first third of the life, mirrored across x for facing -1.
	var sweep := minf(1.0, t * 3.0 + 0.35)
	var start := deg_to_rad(-80.0)
	var end := start + deg_to_rad(140.0) * sweep
	if facing < 0:
		start = PI - start
		end = PI - end
	draw_arc(pos, 48.0, start, end, 24, Color(color, fade), 12.0, true)
	draw_arc(pos, 52.0, start, end, 24, Color(1.0, 1.0, 1.0, fade), 3.0, true)


func _draw_dust(effect: Dictionary, t: float) -> void:
	var pos: Vector2 = effect["pos"]
	var color := Color(BrawlTheme.BONE_SHADOW, 0.5 * (1.0 - t))
	var radius := lerpf(5.0, 14.0, t)
	for dir in PUFF_DIRS:
		draw_circle(pos + dir * 18.0 * t, radius, color)
