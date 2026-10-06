extends Control
## Coloured ring around a HUD portrait medallion. The HUD sets `ring_color` (or calls
## set_percentage) when a fighter's damage changes; the ring redraws itself.

const CENTRE := Vector2(56, 56)
const RADIUS := 50.0
const WIDTH := 6.0

var ring_color: Color = BrawlTheme.PERCENT_WHITE:
	set(value):
		ring_color = value
		queue_redraw()


func set_percentage(percentage: float) -> void:
	ring_color = BrawlTheme.percent_color(percentage)


func _draw() -> void:
	draw_arc(CENTRE, RADIUS, 0.0, TAU, 64, ring_color, WIDTH, true)
	draw_arc(CENTRE, RADIUS + WIDTH / 2.0 + 1.0, 0.0, TAU, 64, BrawlTheme.OUTLINE, 2.0, true)
