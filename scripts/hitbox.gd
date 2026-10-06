class_name Hitbox
extends Area2D
## Attack hitbox owned by a Player. Activated for a fixed number of physics frames;
## hits each other Player at most once per activation.

var attacker: Player
var active: bool = false

var _frames_left: int = 0
var _damage: float = 0.0
var _base_knockback: float = 0.0
var _already_hit: Array[Player] = []
var _base_x: float = 0.0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_base_x = position.x


func activate(frames: int, damage_amount: float, base_knockback: float) -> void:
	_frames_left = frames
	_damage = damage_amount
	_base_knockback = base_knockback
	_already_hit.clear()
	active = true
	_shape.disabled = false


func deactivate() -> void:
	active = false
	_frames_left = 0
	_shape.disabled = true


func set_facing(facing: int) -> void:
	position.x = absf(_base_x) * facing


func _physics_process(_delta: float) -> void:
	if not active:
		return
	for body in get_overlapping_bodies():
		var victim := body as Player
		if victim == null or victim == attacker or _already_hit.has(victim):
			continue
		_already_hit.append(victim)
		# Away from the attacker with a fixed upward lift: normalize(±1, -0.75) = (±0.8, -0.6).
		var dir := (
			Vector2(1.0 if victim.global_position.x >= attacker.global_position.x else -1.0, -0.75)
			. normalized()
		)
		victim.take_damage(_base_knockback, dir, _damage)
		attacker.hit_landed.emit(attacker.player_index, victim.player_index)
	_frames_left -= 1
	if _frames_left <= 0:
		deactivate()
