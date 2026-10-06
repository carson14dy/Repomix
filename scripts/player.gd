class_name Player
extends CharacterBody2D
## One local fighter. All input goes through InputMap actions "p%d_<name>" so two players
## share one keyboard (or one joypad each) without any raw key reads.

signal percentage_changed(player_index: int, percentage: float)
signal hit_landed(attacker_index: int, victim_index: int)
signal attack_started(player_index: int, facing: int)
signal landed(player_index: int)
## `air` is true for an air jump, false for a grounded (or buffered) one.
signal jumped(player_index: int, air: bool)

enum State { NORMAL, KNOCKBACK }

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
## Jumps available in the air before landing again (a fresh press each, never buffered).
@export var air_jumps: int = 1
@export var air_jump_velocity: float = -560.0

@export_group("Attack", "")
@export var attack_startup_frames: int = 3
@export var attack_active_frames: int = 6
@export var attack_recovery_frames: int = 10
@export var attack_damage: float = 8.0
@export var attack_base_knockback: float = 260.0

@export_group("Knockback", "")
## Physics frames a hit fighter has no control over movement, jumping or attacking.
@export var knockback_stun_frames: int = 20

@export_group("Combat feel", "")
## Physics frames both fighters freeze for when a hit lands.
@export var hitstop_frames: int = 5

## Accumulated damage percent; read-only from outside, changed via take_damage()/respawn().
var percentage: float = 0.0
## Read-only from outside; KNOCKBACK is entered by take_damage() and times out on its own.
var state: State = State.NORMAL
## 1 = right, -1 = left.
var facing: int = 1
## Frames of hit-freeze left; read-only from outside, set via apply_hitstop().
var hitstop_left: int = 0
## False between ko() and respawn(): hidden, not simulated, not hittable.
var active: bool = true

var _spawn_position: Vector2
var _jump_buffer: int = 0
## Previous-frame button states for edge detection (see _just_pressed).
var _jump_held: bool = false
var _attack_held: bool = false
## Frames left in the current attack (startup + active + recovery); 0 = not attacking.
var _attack_frames_left: int = 0
var _stun_frames_left: int = 0
var _air_jumps_left: int = 0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hitbox: Hitbox = $Hitbox


func _ready() -> void:
	_spawn_position = global_position
	facing = start_facing
	_air_jumps_left = air_jumps
	_hitbox.attacker = self
	if player_index == 2:
		_sprite.texture = load("res://assets/sprites/ignis.png")
	_apply_facing()


func _physics_process(delta: float) -> void:
	if hitstop_left > 0:
		hitstop_left -= 1
		# Keep the press-edge detectors current so a button held through the freeze is not
		# read as a fresh press once it ends. Velocity, stun and attack frames all pause.
		_jump_held = Input.is_action_pressed(_action("jump"))
		_attack_held = Input.is_action_pressed(_action("attack"))
		return
	var axis := Input.get_axis(_action("left"), _action("right"))
	var down_held := Input.is_action_pressed(_action("down"))
	var jump_pressed := _just_pressed("jump", _jump_held)
	_jump_held = Input.is_action_pressed(_action("jump"))
	var attack_pressed := _just_pressed("attack", _attack_held)
	_attack_held = Input.is_action_pressed(_action("attack"))
	# Reflects the previous frame's move_and_slide; read before moving.
	var on_floor := is_on_floor()
	if on_floor:
		_air_jumps_left = air_jumps

	match state:
		State.NORMAL:
			_apply_horizontal(axis, on_floor, delta)
			if not on_floor:
				_apply_gravity(down_held, delta)
			_apply_jump(jump_pressed, on_floor)
			_apply_attack(attack_pressed)
		State.KNOCKBACK:
			_apply_knockback(on_floor, delta)

	move_and_slide()

	if is_on_floor() and not on_floor:
		landed.emit(player_index)
	if state == State.NORMAL and axis != 0.0:
		facing = signi(int(signf(axis)))
		_apply_facing()


## Knockback speed = base_knockback * (percentage / 10), with this hit's damage already added.
## The hit launches the fighter along `direction` and starts the knockback stun.
func take_damage(base_knockback: float, direction: Vector2, damage_amount: float = 10.0) -> void:
	percentage += damage_amount
	var actual_knockback := base_knockback * (percentage / 10.0)
	var dir := direction.normalized() if direction.length_squared() > 0.0 else Vector2.UP
	velocity = dir * actual_knockback
	_enter_knockback()
	percentage_changed.emit(player_index, percentage)


## Freeze both this fighter and its hitbox for `frames` physics frames (longest wins).
func apply_hitstop(frames: int) -> void:
	hitstop_left = maxi(hitstop_left, frames)
	_hitbox.apply_hitstop(frames)


## Knocked out: parked hidden at the spawn point, not simulated and not hittable until
## respawn(). The Match calls this when a fighter leaves the blast zone.
func ko() -> void:
	active = false
	_reset_at_spawn()
	hide()
	set_physics_process(false)


## Back on stage at 0%. Also cancels a swing started before the KO, so nothing lands at the
## spawn point.
func respawn() -> void:
	active = true
	_reset_at_spawn()
	show()
	set_physics_process(true)


func _reset_at_spawn() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	percentage = 0.0
	state = State.NORMAL
	_stun_frames_left = 0
	_jump_buffer = 0
	_air_jumps_left = air_jumps
	_attack_frames_left = 0
	_hitbox.deactivate()
	_sprite.modulate = Color.WHITE
	percentage_changed.emit(player_index, percentage)


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


## A press is remembered for jump_buffer_frames frames so it still fires on landing. In the
## air a fresh press spends an air jump at once; only a press with none left is buffered.
func _apply_jump(jump_pressed: bool, on_floor: bool) -> void:
	if jump_pressed:
		_jump_buffer = jump_buffer_frames
	if on_floor and _jump_buffer > 0:
		velocity.y = jump_velocity
		_jump_buffer = 0
		jumped.emit(player_index, false)
	elif jump_pressed and _air_jumps_left > 0:
		velocity.y = air_jump_velocity
		_air_jumps_left -= 1
		_jump_buffer = 0
		jumped.emit(player_index, true)
	elif _jump_buffer > 0:
		_jump_buffer -= 1


## Startup -> active -> recovery, counted in physics frames. Movement is not locked
## during an attack (decision: keeps the fighter responsive in a two-button game).
func _apply_attack(attack_pressed: bool) -> void:
	if attack_pressed and _attack_frames_left == 0:
		_attack_frames_left = attack_startup_frames + attack_active_frames + attack_recovery_frames
		attack_started.emit(player_index, facing)
	if _attack_frames_left == 0:
		return
	_attack_frames_left -= 1
	if _attack_frames_left == attack_active_frames + attack_recovery_frames:
		_hitbox.activate(attack_active_frames, attack_damage, attack_base_knockback)


func _enter_knockback() -> void:
	state = State.KNOCKBACK
	_stun_frames_left = knockback_stun_frames
	_jump_buffer = 0
	_attack_frames_left = 0
	_hitbox.deactivate()
	_sprite.modulate = Color(1.0, 0.6, 0.6)


## No input while stunned. is_on_floor() still reports last frame's contact, so a fighter
## launched upward counts as airborne right away (decision: gravity, no friction, so the
## launch is never damped); grounded knockback slides out under ground_friction.
func _apply_knockback(on_floor: bool, delta: float) -> void:
	if on_floor and velocity.y >= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	else:
		_apply_gravity(false, delta)
	_stun_frames_left -= 1
	if _stun_frames_left <= 0:
		state = State.NORMAL
		_sprite.modulate = Color.WHITE


## The sprite flip is applied by fighter_visual.gd from `facing`.
func _apply_facing() -> void:
	_hitbox.set_facing(facing)


## Press edge from is_action_pressed instead of Input.is_action_just_pressed: Godot 4.4
## reports an action pressed during a physics frame as "just pressed" only on the NEXT
## physics frame, which would delay every jump/attack by one frame.
func _just_pressed(name: String, was_held: bool) -> bool:
	return Input.is_action_pressed(_action(name)) and not was_held


func _action(name: String) -> String:
	return "p%d_%s" % [player_index, name]
