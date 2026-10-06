class_name FightCamera
extends Camera2D
## Two-target fight camera: frames the midpoint of both fighters, zooms out as they
## separate, and shakes on hits. Runs in _physics_process so tests can step it by frame.

@export var min_zoom: float = 0.72
@export var max_zoom: float = 1.15
@export var lerp_factor: float = 0.08
@export var y_offset: float = -40.0

var _a: Node2D
var _b: Node2D
var _shake_intensity: float = 0.0
var _shake_total: int = 0
var _shake_left: int = 0


func set_targets(a: Node2D, b: Node2D) -> void:
	_a = a
	_b = b


func shake(intensity: float, frames: int) -> void:
	_shake_intensity = intensity
	_shake_total = frames
	_shake_left = frames


## Position is NOT clamped here: Camera2D's own limit_* properties already keep the visible
## rect inside the limits (decision: a manual clamp of `position` fought the contract's
## "position.x > 700 with Player2 at x 1100" test, since the view at that zoom is 1609 px
## wide against a 1680 px limit span).
func _physics_process(_delta: float) -> void:
	if is_instance_valid(_a) and is_instance_valid(_b):
		var dist := _a.global_position.distance_to(_b.global_position)
		var target_zoom := clampf(700.0 / (dist + 300.0), min_zoom, max_zoom)
		zoom = zoom.lerp(Vector2.ONE * target_zoom, lerp_factor)
		var target_pos := (_a.global_position + _b.global_position) / 2.0 + Vector2(0, y_offset)
		position = position.lerp(target_pos, lerp_factor)
	if _shake_left > 0:
		var falloff := float(_shake_left) / float(_shake_total)
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_intensity * falloff
		_shake_left -= 1
	else:
		offset = Vector2.ZERO
