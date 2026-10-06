class_name BotController
extends Node
## CPU opponent. Drives ONE Player by pressing that player's InputMap actions
## (Input.action_press / action_release), exactly like a keyboard or the test suite does, so
## player.gd needs no bot-specific code. Ported from the prototype's engine/ai.ts: a reaction
## interval and hit/jump chances per difficulty tier, recovery first, then approach and swing.
##
## Everything random comes from one RandomNumberGenerator seeded by `seed`, so the same seed
## against the same fight replays the same decisions.

enum Difficulty { EASY, NORMAL, BRUTAL }

## Attack range: the hitbox reaches 6..46 px in front of the fighter (see Player.tscn).
const RANGE_X := 48.0
const RANGE_Y := 40.0
## Opponent standing this much higher (platform) tempts a jump.
const JUMP_UP_DY := 60.0
## Falling while this far above the floor top: hold down to fast-fall back into the fight.
const FAST_FALL_HEIGHT := 160.0

## Per-tier tuning: physics frames between decisions, then the chance (0..1) of each action
## when its rule applies. BRUTAL never idles.
const TUNING := {
	Difficulty.EASY: {"interval": 12, "recover": 0.5, "attack": 0.35, "jump": 0.3, "idle": 0.25},
	Difficulty.NORMAL: {"interval": 6, "recover": 0.8, "attack": 0.7, "jump": 0.6, "idle": 0.1},
	Difficulty.BRUTAL: {"interval": 2, "recover": 1.0, "attack": 1.0, "jump": 0.9, "idle": 0.0},
}
const ACTIONS: Array[String] = ["left", "right", "jump", "down", "attack"]

## Which player's actions ("p%d_*") this bot presses.
@export_range(1, 2) var controlled_index: int = 2
@export var difficulty: Difficulty = Difficulty.NORMAL
@export var seed: int = 11

@export_group("Stage", "stage_")
## Horizontal extent of the main floor; outside it the bot is "off stage" and recovers.
@export var stage_left_x: float = 190.0
@export var stage_right_x: float = 1090.0
## Top surface of the main floor.
@export var stage_top_y: float = 580.0

## A disabled bot presses nothing; disabling releases whatever it was holding.
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			_release_all()

var _me: Player
var _opponent: Node2D
var _rng := RandomNumberGenerator.new()
var _frame: int = 0
## Actions currently held by this bot (name without the "p%d_" prefix).
var _held: Array[String] = []
## Actions pressed this frame to be released on the next one (buttons, not directions).
var _taps: Array[String] = []


func _ready() -> void:
	_rng.seed = seed


func _exit_tree() -> void:
	_release_all()


## `me` must be a Player (the fighter this bot controls); `opponent` only needs a position.
func set_fighters(me: Node2D, opponent: Node2D) -> void:
	_me = me as Player
	_opponent = opponent
	if _me == null:
		push_error("BotController.set_fighters: `me` must be a Player, got %s" % me)


func _physics_process(_delta: float) -> void:
	for action in _taps:
		_set_held(action, false)
	_taps.clear()
	if not enabled or not is_instance_valid(_me) or not is_instance_valid(_opponent):
		_release_all()
		return
	# Being hit is a reflex, not a decision: let go the very next frame so a held direction
	# never steers the fighter the moment control returns (decision: checked every frame).
	if _me.state == Player.State.KNOCKBACK:
		_release_all()
		return
	_frame += 1
	if _frame % int(_tune("interval")) != 0:
		return
	_decide()


func _decide() -> void:
	var pos := _me.global_position
	if pos.x < stage_left_x or pos.x > stage_right_x:
		_recover(pos)
		return
	if _rng.randf() < _tune("idle"):
		_release_all()
		return
	var to_opponent := _opponent.global_position - pos
	var toward := signi(int(signf(to_opponent.x)))
	var in_range := absf(to_opponent.x) < RANGE_X and absf(to_opponent.y) < RANGE_Y
	if in_range:
		_set_move(0)
		# The hitbox only reaches forward: an opponent behind us gets a one-frame direction
		# tap, which turns the fighter (Player reads facing from the axis) without a run-up.
		if toward != 0 and _me.facing != toward:
			_tap("left" if toward < 0 else "right")
	else:
		_set_move(toward)
	_set_held("down", pos.y < stage_top_y - FAST_FALL_HEIGHT and _me.velocity.y > 0.0)
	if in_range and _rng.randf() < _tune("attack"):
		_tap("attack")
	if to_opponent.y < -JUMP_UP_DY and _rng.randf() < _tune("jump"):
		_tap("jump")


## Off stage: steer toward the stage centre and (sometimes) jump while falling. The jump is
## buffered by the Player, so it also fires the moment the fighter touches down.
func _recover(pos: Vector2) -> void:
	var centre_x := (stage_left_x + stage_right_x) * 0.5
	_set_move(1 if pos.x < centre_x else -1)
	_set_held("down", false)
	if _me.velocity.y > 0.0 and _rng.randf() < _tune("recover"):
		_tap("jump")


func _tune(key: String) -> float:
	var tier: Dictionary = TUNING[difficulty]
	return float(tier[key])


## -1 holds left, 1 holds right, 0 releases both.
func _set_move(direction: int) -> void:
	_set_held("left", direction < 0)
	_set_held("right", direction > 0)


## Press now, release on the next physics frame so the Player sees a fresh press edge.
func _tap(action: String) -> void:
	_set_held(action, true)
	if not _taps.has(action):
		_taps.append(action)


func _set_held(action: String, held: bool) -> void:
	if held == _held.has(action):
		return
	if held:
		Input.action_press(_action(action))
		_held.append(action)
	else:
		Input.action_release(_action(action))
		_held.erase(action)


func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(_action(action))
	_held.clear()
	_taps.clear()


func _action(name: String) -> String:
	return "p%d_%s" % [controlled_index, name]
