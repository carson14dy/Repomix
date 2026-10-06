extends Node2D
## Three soft mist blobs drifting slowly across the bone stage, world space, behind the
## fighters. Concentric alpha steps fake a radial gradient without a texture.

const STEPS := 6
## [centre x, centre y, radius, drift amplitude, drift speed (rad/s), phase, peak alpha]
const BLOBS := [
	[330.0, 610.0, 210.0, 90.0, 0.21, 0.0, 0.16],
	[700.0, 690.0, 270.0, 120.0, 0.15, 2.1, 0.18],
	[1010.0, 600.0, 190.0, 80.0, 0.26, 4.0, 0.13],
]

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for blob: Array in BLOBS:
		var centre := Vector2(blob[0] + sin(_time * blob[4] + blob[5]) * blob[3], blob[1])
		var radius: float = blob[2]
		var step_alpha: float = blob[6] / STEPS
		for i in range(STEPS):
			var r := radius * (1.0 - float(i) / STEPS)
			draw_circle(centre, r, Color(BrawlTheme.MIST, step_alpha))
