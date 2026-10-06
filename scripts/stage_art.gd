extends Node2D
## Procedural art for Wyrm's Ossuary: the main platform is a dragon's spine lying over the
## Floor collider (x 190..1090, y 596..644) with a ribcage hanging from its underside, and
## the two one-way platforms (centres (380, 470) and (900, 470), 240x20) are floating bone
## shards. Static: drawn once in world space, no per-frame redraw (about 120 draw calls).

const RIM := Color("#f5f8fa")
const CRACK := Color(BrawlTheme.BONE_DARK, 0.55)

const SLAB := Rect2(190, 596, 900, 48)
const SLAB_RADIUS := 14.0
const SHADOW_BAND_TOP := 620.0
const RIB_TOP := 640.0
const RIB_BOTTOM := 800.0
const RIB_COUNT := 9
const RIB_FIRST_X := 250.0
const RIB_SPACING := 97.5
const INNER_RIB_COUNT := 4
const VERTEBRA_COUNT := 11
const VERTEBRA_FIRST_X := 230.0
const VERTEBRA_SPACING := 80.0
const SHARD_CENTRES := [Vector2(380, 470), Vector2(900, 470)]
const SHARD := Rect2(-120, -10, 240, 20)
## Teeth under each shard: [x offset from centre, length]
const TEETH := [[-72.0, 18.0], [-4.0, 22.0], [68.0, 14.0]]
## Hairline cracks across the slab, in world space.
const CRACKS := [
	[Vector2(372, 602), Vector2(380, 611), Vector2(392, 616), Vector2(398, 626)],
	[Vector2(640, 600), Vector2(632, 609), Vector2(636, 618)],
	[Vector2(905, 603), Vector2(914, 612), Vector2(910, 621), Vector2(922, 630)],
	[Vector2(1040, 602), Vector2(1033, 612), Vector2(1038, 619)],
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_inner_ribs()
	_draw_ribs()
	_draw_slab()
	_draw_vertebrae()
	for centre: Vector2 in SHARD_CENTRES:
		_draw_shard(centre)


## Rib spine curve: hangs from the slab underside, fans outward with its distance from the
## stage centre (`lean`), bulges mid-way and curls back under at the tip like a real rib.
func _rib_points(x: float, lean: float, bottom: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(9):
		var t := i / 8.0
		var dx := lean * t * 60.0 + sin(t * PI) * 26.0 * signf(lean) - lean * t * t * t * 30.0
		points.append(Vector2(x + dx, lerpf(RIB_TOP, bottom, t)))
	return points


## Tapered band around a curve: `grow` pads both edges (used for the outline pass).
func _taper(
	points: PackedVector2Array, top_w: float, tip_w: float, grow: float
) -> PackedVector2Array:
	var n := points.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(n):
		var dir := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var half := lerpf(top_w, tip_w, i / float(n - 1)) / 2.0 + grow
		left.append(points[i] + normal * half)
		right.append(points[i] - normal * half)
	right.reverse()
	left.append_array(right)
	return left


func _draw_ribs() -> void:
	for i in range(RIB_COUNT):
		var x := RIB_FIRST_X + RIB_SPACING * i
		var lean := (x - SLAB.get_center().x) / (SLAB.size.x / 2.0)
		var bottom := RIB_BOTTOM - absf(lean) * 36.0 + (6.0 if i % 2 == 0 else -6.0)
		var points := _rib_points(x, lean, bottom)
		draw_colored_polygon(_taper(points, 26.0, 9.0, 2.0), BrawlTheme.OUTLINE)
		draw_colored_polygon(_taper(points, 26.0, 9.0, 0.0), BrawlTheme.BONE_SHADOW)
		# Lit edge on the side facing the sky light (towards the stage centre).
		var lit := PackedVector2Array()
		for p in points.slice(1, 7):
			lit.append(p + Vector2(-signf(lean) * 6.0, 0))
		draw_polyline(lit, BrawlTheme.BONE, 4.0, true)


## Fainter ribs further back, between the front ones, read as the far side of the ribcage.
func _draw_inner_ribs() -> void:
	var color := Color(BrawlTheme.BONE_DARK, 0.7)
	for i in range(INNER_RIB_COUNT):
		var x := 350.0 + 195.0 * i
		var lean := (x - SLAB.get_center().x) / (SLAB.size.x / 2.0) * 0.6
		draw_colored_polygon(_taper(_rib_points(x, lean, RIB_BOTTOM - 60.0), 16.0, 6.0, 0.0), color)


func _draw_slab() -> void:
	var outer := _rounded_rect(SLAB, SLAB_RADIUS, SLAB_RADIUS)
	draw_colored_polygon(outer, BrawlTheme.BONE)
	var band := Rect2(SLAB.position.x, SHADOW_BAND_TOP, SLAB.size.x, SLAB.end.y - SHADOW_BAND_TOP)
	draw_colored_polygon(_rounded_rect(band, 0.0, SLAB_RADIUS), BrawlTheme.BONE_SHADOW)
	# Darker seam where the shadow band meets the underside.
	draw_line(
		Vector2(SLAB.position.x + 6, SLAB.end.y - 5),
		Vector2(SLAB.end.x - 6, SLAB.end.y - 5),
		BrawlTheme.BONE_DARK,
		3.0
	)
	# Bright top rim, inset so the outline stays crisp.
	draw_rect(
		Rect2(
			SLAB.position.x + SLAB_RADIUS, SLAB.position.y + 1.5, SLAB.size.x - 2 * SLAB_RADIUS, 4.0
		),
		RIM
	)
	# Vertebra joints: a faint seam down the slab under every other knob.
	for i in range(0, VERTEBRA_COUNT, 2):
		var jx := VERTEBRA_FIRST_X + VERTEBRA_SPACING * i + VERTEBRA_SPACING / 2.0
		draw_line(Vector2(jx, 601), Vector2(jx + 2, SHADOW_BAND_TOP), CRACK, 2.0)
	for crack: Array in CRACKS:
		draw_polyline(PackedVector2Array(crack), CRACK, 1.5, true)
	_draw_chipped_end(Vector2(SLAB.position.x, 610.0), -1.0, 22.0)
	_draw_chipped_end(Vector2(SLAB.end.x, 622.0), 1.0, 22.0)
	outer.append(outer[0])
	draw_polyline(outer, BrawlTheme.OUTLINE, 3.0, true)


func _draw_vertebrae() -> void:
	for i in range(VERTEBRA_COUNT):
		var centre := Vector2(VERTEBRA_FIRST_X + VERTEBRA_SPACING * i, SLAB.position.y)
		draw_circle(centre, 11.0, BrawlTheme.OUTLINE)
		draw_circle(centre, 9.0, BrawlTheme.BONE)
		draw_circle(centre + Vector2(1, 3), 5.5, BrawlTheme.BONE_SHADOW)
		draw_circle(centre + Vector2(-2.5, -3), 3.0, RIM)
		if i < VERTEBRA_COUNT - 1:
			draw_circle(centre + Vector2(VERTEBRA_SPACING / 2.0, 4.0), 3.0, BrawlTheme.BONE_DARK)


## A short jagged triangle poking out of a slab end; `side` is -1 (left) or +1 (right).
func _draw_chipped_end(base: Vector2, side: float, length: float) -> void:
	var tip := base + Vector2(side * length, 6.0)
	var chip := PackedVector2Array([base + Vector2(0, -10), tip, base + Vector2(0, 12)])
	draw_colored_polygon(chip, BrawlTheme.BONE_SHADOW)
	draw_polyline(PackedVector2Array([chip[0], chip[1], chip[2]]), BrawlTheme.OUTLINE, 3.0, true)


func _draw_shard(centre: Vector2) -> void:
	var rect := Rect2(centre + SHARD.position, SHARD.size)
	for tooth: Array in TEETH:
		var top := Vector2(centre.x + tooth[0], rect.end.y - 3.0)
		var tip := top + Vector2(1.5, tooth[1] + 3.0)
		var fang := PackedVector2Array([top + Vector2(-3, 0), tip, top + Vector2(3, 0)])
		draw_polyline(fang, BrawlTheme.OUTLINE, 4.0, true)
		draw_colored_polygon(fang, BrawlTheme.BONE_SHADOW)
	var outer := _rounded_rect(rect, 8.0, 8.0)
	draw_colored_polygon(outer, BrawlTheme.BONE)
	var band := Rect2(rect.position.x, centre.y, rect.size.x, rect.end.y - centre.y)
	draw_colored_polygon(_rounded_rect(band, 0.0, 8.0), BrawlTheme.BONE_SHADOW)
	draw_rect(Rect2(rect.position.x + 8.0, rect.position.y + 1.5, rect.size.x - 16.0, 3.0), RIM)
	draw_line(centre + Vector2(-30, -7), centre + Vector2(-22, 1), CRACK, 1.5)
	_draw_chipped_end(Vector2(rect.position.x, centre.y - 2.0), -1.0, 14.0)
	_draw_chipped_end(Vector2(rect.end.x, centre.y + 2.0), 1.0, 14.0)
	outer.append(outer[0])
	draw_polyline(outer, BrawlTheme.OUTLINE, 3.0, true)


## Rounded-rectangle outline, 6 segments per rounded corner (radius 0 = sharp).
func _rounded_rect(rect: Rect2, top_radius: float, bottom_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(top_radius, top_radius), PI, top_radius],
		[Vector2(rect.end.x - top_radius, rect.position.y + top_radius), -PI / 2.0, top_radius],
		[rect.end - Vector2(bottom_radius, bottom_radius), 0.0, bottom_radius],
		[
			Vector2(rect.position.x + bottom_radius, rect.end.y - bottom_radius),
			PI / 2.0,
			bottom_radius
		],
	]
	for corner: Array in corners:
		var centre: Vector2 = corner[0]
		var start: float = corner[1]
		var radius: float = corner[2]
		if radius <= 0.0:
			points.append(centre)
			continue
		for i in range(7):
			var angle := start + (PI / 2.0) * i / 6.0
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
