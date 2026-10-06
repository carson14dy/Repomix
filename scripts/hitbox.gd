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
## Own copy of the attacker's hitstop: children process after their parent, so reading
## attacker.hitstop_left here would see it already counted down and resume a frame early.
var _hitstop_left: int = 0

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


func apply_hitstop(frames: int) -> void:
	_hitstop_left = maxi(_hitstop_left, frames)


## Overlaps reflect the previous physics step, so the shape must stay enabled for
## `frames` steps and the scan runs one callback after the last of them: scan first,
## then count down, and deactivate on the callback after the counter has reached 0.
func _physics_process(_delta: float) -> void:
	if _hitstop_left > 0:
		_hitstop_left -= 1
		return
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
		# Deferred (flushed at the end of this physics tick) so every hitbox scans before any
		# victim is stunned: a same-frame trade hits both fighters instead of whichever Player
		# comes first in the scene tree, and both stuns start on the next frame.
		_land.call_deferred(victim, dir)
	if _frames_left <= 0:
		deactivate()
	else:
		_frames_left -= 1


func _land(victim: Player, dir: Vector2) -> void:
	victim.take_damage(_base_knockback, dir, _damage)
	attacker.apply_hitstop(attacker.hitstop_frames)
	victim.apply_hitstop(attacker.hitstop_frames)
	attacker.hit_landed.emit(attacker.player_index, victim.player_index)
