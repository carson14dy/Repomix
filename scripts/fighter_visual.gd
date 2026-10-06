extends Sprite2D
## Render-side body language for a Player, attached to its Sprite2D: reads the parent's public
## state every frame and bends the sprite (bob, lean, stretch, squash, tilt) plus a ground
## shadow. Never touches gameplay state or modulate (player.gd owns the knockback tint).

## Collider bottom in Player space (the 28x56 body is centred on the origin).
const FEET_Y := 28.0
const SHADOW_SIZE := Vector2(22, 5)
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
	# Feet on the collider bottom whatever the texture height (Kage 64 -> -4, Ignis 72 -> -8).
	var rest_y := FEET_Y - texture.get_height() / 2.0
	var idle := grounded and speed_x < 10.0
	offset.y = rest_y + (sin(_time * 4.0) * 1.5 if idle else 0.0)

	# Godot's rotation is clockwise-positive, so +facing tips the head forward.
	var target_rotation := 0.0
	if _player.state == Player.State.KNOCKBACK:
		# Head trails the launch.
		target_rotation = -signf(_player.velocity.x) * 0.35
	elif grounded and speed_x > 100.0:
		target_rotation = _player.facing * 0.08
	var target_scale := Vector2.ONE
	if _squash_left > 0:
		_squash_left -= 1
		target_scale = Vector2(1.08, 0.92)
	elif not grounded and _player.velocity.y < -200.0:
		target_scale = Vector2(0.94, 1.08)
	rotation = lerpf(rotation, target_rotation, EASE)
	scale = scale.lerp(target_scale, EASE)
	queue_redraw()


func _draw() -> void:
	if not _player.is_on_floor():
		return
	# Cancel this node's rotation and scale so the shadow lies flat just under the feet; the
	# texture is drawn before _draw, so the ellipse sits 2 px below the feet line, not on it.
	var ellipse := Transform2D(0.0, SHADOW_SIZE / 2.0, 0.0, Vector2(0.0, FEET_Y + 2.0))
	draw_set_transform_matrix(transform.affine_inverse() * ellipse)
	draw_circle(Vector2.ZERO, 1.0, Color(BrawlTheme.OUTLINE, 0.35))
