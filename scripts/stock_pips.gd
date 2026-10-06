extends Control
## Stock counter under a HUD medallion: `max_stocks` diamonds, the first `stocks` of them filled
## in `color` with an OUTLINE stroke, the rest (lost stocks) hollow slate with a BONE_SHADOW
## stroke so an empty slot still reads against the dark backdrop. `align_right` mirrors the
## row for the right-hand medallion.

const PITCH := 22.0
const HALF := 7.0

@export var color: Color = BrawlTheme.PERCENT_WHITE
@export var align_right: bool = false
@export var max_stocks: int = 3

var stocks: int = 3:
	set(value):
		stocks = value
		queue_redraw()


func set_stocks(value: int) -> void:
	stocks = value


func _draw() -> void:
	for i in range(max_stocks):
		var x := HALF + 2.0 + PITCH * i
		if align_right:
			x = size.x - x
		var centre := Vector2(x, size.y / 2.0)
		var diamond := PackedVector2Array(
			[
				centre + Vector2(0, -HALF),
				centre + Vector2(HALF, 0),
				centre + Vector2(0, HALF),
				centre + Vector2(-HALF, 0),
			]
		)
		var filled := i < stocks
		draw_colored_polygon(diamond, color if filled else Color(BrawlTheme.SLATE, 0.75))
		var outline := diamond.duplicate()
		outline.append(diamond[0])
		draw_polyline(outline, BrawlTheme.OUTLINE if filled else BrawlTheme.BONE_SHADOW, 2.0, true)
