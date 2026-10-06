class_name Player
extends CharacterBody2D
## One local fighter. All input goes through InputMap actions "p%d_<name>" so two players
## share one keyboard (or one joypad each) without any raw key reads.

signal damage_changed(player_index: int, damage: float)
signal hit_landed(attacker_index: int, victim_index: int)

@export_range(1, 2) var player_index: int = 1
@export_enum("Right:1", "Left:-1") var start_facing: int = 1

@export_group("Movement", "")
@export var run_speed: float = 340.0
@export var ground_acceleration: float = 2600.0
@export var ground_friction: float = 2400.0
@export var air_acceleration: float = 1300.0
## Slight horizontal resistance, applied only in the air with no horizontal input.
@export var air_friction: float = 320.0

@export_group("Falling", "")
@export var gravity: float = 1500.0
@export var max_fall_speed: float = 900.0
@export var fast_fall_gravity_multiplier: float = 2.5
@export var fast_fall_max_speed: float = 1500.0

@export_group("Jumping", "")
@export var jump_velocity: float = -620.0
@export var jump_buffer_frames: int = 6

@export_group("Attack", "")
@export var attack_startup_frames: int = 3
@export var attack_active_frames: int = 6
@export var attack_recovery_frames: int = 10
@export var attack_damage: float = 8.0
@export var attack_base_knockback: float = 260.0
## Knockback speed = base + scaling * victim damage (after this hit is added).
@export var attack_knockback_scaling: float = 7.0

@export_group("Stage", "")
@export var respawn_below_y: float = 1200.0

## Accumulated damage percent; read-only from outside, changed via take_hit()/respawn().
var damage: float = 0.0
## 1 = right, -1 = left.
var facing: int = 1

var _spawn_position: Vector2
var _jump_buffer: int = 0
## Previous-frame button states for edge detection (see _just_pressed).
var _jump_held: bool = false
var _attack_held: bool = false
## Frames left in the current attack (startup + active + recovery); 0 = not attacking.
var _attack_frames_left: int = 0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hitbox: Hitbox = $Hitbox


func _ready() -> void:
	_spawn_position = global_position
	facing = start_facing
	_hitbox.attacker = self
	if player_index == 2:
		_sprite.texture = load("res://assets/sprites/fighter_p2.png")
	_apply_facing()


func _physics_process(delta: float) -> void:
	var axis := Input.get_axis(_action("left"), _action("right"))
	var down_held := Input.is_action_pressed(_action("down"))
	var jump_pressed := _just_pressed("jump", _jump_held)
	_jump_held = Input.is_action_pressed(_action("jump"))
	var attack_pressed := _just_pressed("attack", _attack_held)
	_attack_held = Input.is_action_pressed(_action("attack"))
	# Reflects the previous frame's move_and_slide; read before moving.
	var on_floor := is_on_floor()

	_apply_horizontal(axis, on_floor, delta)
	if not on_floor:
		_apply_gravity(down_held, delta)
	_apply_jump(jump_pressed, on_floor)
	_apply_attack(attack_pressed)

	move_and_slide()

	if axis != 0.0:
		facing = signi(int(signf(axis)))
		_apply_facing()
	if global_position.y > respawn_below_y:
		respawn()


func take_hit(
	from_x: float, damage_amount: float, base_knockback: float, knockback_scaling: float
) -> void:
	damage += damage_amount
	var dir := 1.0 if global_position.x >= from_x else -1.0
	var speed := base_knockback + knockback_scaling * damage
	velocity = Vector2(dir, -0.75).normalized() * speed
	damage_changed.emit(player_index, damage)


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	damage = 0.0
	damage_changed.emit(player_index, damage)


func _apply_horizontal(axis: float, on_floor: bool, delta: float) -> void:
	if axis != 0.0:
		var accel := ground_acceleration if on_floor else air_acceleration
		velocity.x = move_toward(velocity.x, axis * run_speed, accel * delta)
	else:
		var friction := ground_friction if on_floor else air_friction
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _apply_gravity(down_held: bool, delta: float) -> void:
	# Fast-fall only once the fighter is no longer rising: a jump's upward arc is never cut
	# short by holding down. Engages at the apex (velocity.y == 0) or any time while falling.
	var fast_falling := down_held and velocity.y >= 0.0
	var g := gravity * (fast_fall_gravity_multiplier if fast_falling else 1.0)
	var cap := fast_fall_max_speed if fast_falling else max_fall_speed
	velocity.y = minf(velocity.y + g * delta, cap)


## A press is remembered for jump_buffer_frames frames so it still fires on landing.
func _apply_jump(jump_pressed: bool, on_floor: bool) -> void:
	if jump_pressed:
		_jump_buffer = jump_buffer_frames
	if on_floor and _jump_buffer > 0:
		velocity.y = jump_velocity
		_jump_buffer = 0
	elif _jump_buffer > 0:
		_jump_buffer -= 1


## Startup -> active -> recovery, counted in physics frames. Movement is not locked
## during an attack (decision: keeps the fighter responsive in a two-button game).
func _apply_attack(attack_pressed: bool) -> void:
	if attack_pressed and _attack_frames_left == 0:
		_attack_frames_left = attack_startup_frames + attack_active_frames + attack_recovery_frames
	if _attack_frames_left == 0:
		return
	_attack_frames_left -= 1
	if _attack_frames_left == attack_active_frames + attack_recovery_frames:
		_hitbox.activate(
			attack_active_frames, attack_damage, attack_base_knockback, attack_knockback_scaling
		)


func _apply_facing() -> void:
	_sprite.flip_h = facing < 0
	_hitbox.set_facing(facing)


## Press edge from is_action_pressed instead of Input.is_action_just_pressed: Godot 4.4
## reports an action pressed during a physics frame as "just pressed" only on the NEXT
## physics frame, which would delay every jump/attack by one frame.
func _just_pressed(name: String, was_held: bool) -> bool:
	return Input.is_action_pressed(_action(name)) and not was_held


func _action(name: String) -> String:
	return "p%d_%s" % [player_index, name]
