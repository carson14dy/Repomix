class_name Hitbox
extends Area2D
## Attack hitbox owned by a Player. Activated for a fixed number of physics frames;
## hits each other Player at most once per activation.

var attacker: Player
var active: bool = false

var _frames_left: int = 0
var _damage: float = 0.0
var _base_knockback: float = 0.0
var _knockback_scaling: float = 0.0
var _already_hit: Array[Player] = []
var _base_x: float = 0.0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_base_x = position.x


func activate(
	frames: int, damage_amount: float, base_knockback: float, knockback_scaling: float
) -> void:
	_frames_left = frames
	_damage = damage_amount
	_base_knockback = base_knockback
	_knockback_scaling = knockback_scaling
	_already_hit.clear()
	active = true
	_shape.disabled = false


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
		victim.take_hit(attacker.global_position.x, _damage, _base_knockback, _knockback_scaling)
		attacker.hit_landed.emit(attacker.player_index, victim.player_index)
	_frames_left -= 1
	if _frames_left <= 0:
		active = false
		_shape.disabled = true
