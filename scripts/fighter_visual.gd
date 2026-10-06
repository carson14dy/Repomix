extends Sprite2D
## Render-side body language for a Player, attached to its Sprite2D: reads the parent's public
## state every frame and bends the sprite (bob, lean, stretch, squash, tilt) plus a ground
## shadow and a player-colour chevron over the head. The Sprite2D sits at the feet (Player.tscn
## position (0, FEET_Y), Player.set_fighter_sprite lifts the art by offset), so every scale and
## rotation here pivots at the feet and never lifts them off, or sinks them into, the slab.
## Never touches gameplay state, modulate (player.gd owns the knockback tint), position or
## offset.

## Collider bottom in Player space (the 28x56 body is centred on the origin).
const FEET_Y := 28.0
const SHADOW_SIZE := Vector2(22, 5)
## Chevron tip this far above the texture top; the triangle is 12 px wide and 8 px tall.
const MARKER_GAP := 6.0
const SQUASH_FRAMES := 6
## Fraction of the way rotation and scale move towards their target each frame.
const EASE := 0.25

var _time: float = 0.0
var _squash_left: int = 0

@onready var _player: Player = get_parent()


func _ready() -> void:
	_player.landed.connect(func(_index: int) -> void: _squash_left = SQUASH_FRAMES)


func _process(delta: float) -> void:
	_time += delta
	var grounded := _player.is_on_floor()
	var speed_x := absf(_player.velocity.x)
	flip_h = _player.facing < 0
	# The idle bob is a 2% height pulse about the feet (about 1.3 px at the head).
	var idle := grounded and speed_x < 10.0

	# Godot's rotation is clockwise-positive, so +facing tips the head forward.
	var target_rotation := 0.0
	if _player.state == Player.State.KNOCKBACK:
		# Head trails the launch.
		target_rotation = -signf(_player.velocity.x) * 0.35
	elif grounded and speed_x > 100.0:
		target_rotation = _player.facing * 0.08
	var target_scale := Vector2.ONE
	if idle:
		target_scale.y = 1.0 + 0.02 * sin(_time * 4.0)
	if _squash_left > 0:
		_squash_left -= 1
		target_scale = Vector2(1.08, 0.92)
	elif not grounded and _player.velocity.y < -200.0:
		target_scale = Vector2(0.94, 1.08)
	rotation = lerpf(rotation, target_rotation, EASE)
	scale = scale.lerp(target_scale, EASE)
	queue_redraw()


## Both marks cancel this node's transform (draw in Player space). The chevron in the player
## colour tells the fighters apart even when both wear the same sprite; the shadow lies flat
## 2 px under the feet line (the texture is drawn before _draw).
func _draw() -> void:
	var unscaled := transform.affine_inverse()
	if texture != null:
		var tip := Vector2(0.0, FEET_Y - texture.get_height() - MARKER_GAP)
		draw_set_transform_matrix(unscaled)
		draw_colored_polygon(
			PackedVector2Array([tip + Vector2(-6, -8), tip + Vector2(6, -8), tip]),
			BrawlTheme.player_color(_player.player_index)
		)
	if not _player.is_on_floor():
		return
	var ellipse := Transform2D(0.0, SHADOW_SIZE / 2.0, 0.0, Vector2(0.0, FEET_Y + 2.0))
	draw_set_transform_matrix(unscaled * ellipse)
	draw_circle(Vector2.ZERO, 1.0, Color(BrawlTheme.OUTLINE, 0.35))
