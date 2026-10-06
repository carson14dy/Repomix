extends Control
## Stand-in portrait for a fighter without portrait art: the same slate disc and bone ring as
## the processed medallions (radius 46 of 96), with the fighter's initial.

var initial: String = "?":
	set(value):
		initial = value
		queue_redraw()


func _draw() -> void:
	var centre := size / 2.0
	var radius := minf(size.x, size.y) * 46.0 / 96.0
	draw_circle(centre, radius, BrawlTheme.SLATE)
	draw_arc(centre, radius, 0.0, TAU, 64, BrawlTheme.BONE_DARK, 4.0, true)
	var font := ThemeDB.fallback_font
	var font_size := int(radius)
	var width := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(
		font,
		Vector2(centre.x - width / 2.0, baseline),
		initial,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		BrawlTheme.BONE_SHADOW
	)
