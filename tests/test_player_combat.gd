extends RefCounted
## take_damage() formula, knockback state, hitbox integration, signals and respawn.
## Expected values are hand-derived from the player.gd tunables (dt = 1/60).

const FLOOR_CENTER := Vector2(600, 600)
## Default make_floor size is 1200x40, so its top is 580; players are 56 px tall.
const STAND_Y := 552.0
const MAX_FALL_FRAMES := 200


## P1 at x = 500 facing right, P2 at x = 540 inside P1's hitbox reach; both grounded.
func _face_off(ctx: TestContext) -> Array[CharacterBody2D]:
	ctx.make_floor(FLOOR_CENTER)
	var attacker := ctx.spawn_player(1, Vector2(500, STAND_Y))
	var victim := ctx.spawn_player(2, Vector2(540, STAND_Y))
	await ctx.step(3)
	ctx.check(attacker.is_on_floor() and victim.is_on_floor(), "both fighters start grounded")
	return [attacker, victim]


func _check_velocity(
	ctx: TestContext, player: CharacterBody2D, want: Vector2, tol: float, label: String
) -> void:
	ctx.check_near(player.velocity.x, want.x, tol, label + " (x)")
	ctx.check_near(player.velocity.y, want.y, tol, label + " (y)")


# a. actual_knockback = base_knockback * (percentage / 10), percentage after the hit.
func test_take_damage_formula(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER)
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	await ctx.step(1)
	player.take_damage(300.0, Vector2(1, 0), 20.0)
	ctx.check_near(player.get("percentage"), 20.0, 0.01, "first hit adds 20 percent")
	_check_velocity(ctx, player, Vector2(600, 0), 0.01, "knockback = 300 * (20 / 10) along +x")
	player.take_damage(300.0, Vector2(0, -1), 10.0)
	ctx.check_near(player.get("percentage"), 30.0, 0.01, "percentage accumulates to 30")
	_check_velocity(ctx, player, Vector2(0, -900), 0.01, "knockback = 300 * (30 / 10) along -y")
	await ctx.step(1)


# b. direction is normalized; a zero direction launches straight up.
func test_take_damage_normalizes_direction(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	player.take_damage(100.0, Vector2(3, -4), 10.0)
	_check_velocity(ctx, player, Vector2(60, -80), 0.01, "(3, -4) normalizes to (0.6, -0.8)")
	var other := ctx.spawn_player(2, Vector2(700, STAND_Y))
	other.take_damage(100.0, Vector2.ZERO, 10.0)
	_check_velocity(ctx, other, Vector2(0, -100), 0.01, "zero direction falls back to Vector2.UP")
	await ctx.step(1)


# c. The user's two-argument call shape adds the default 10 percent.
func test_take_damage_default_damage_is_ten(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	player.take_damage(100.0, Vector2(1, 0))
	ctx.check_near(player.get("percentage"), 10.0, 0.01, "take_damage(base, dir) adds 10 percent")
	_check_velocity(ctx, player, Vector2(100, 0), 0.01, "knockback = 100 * (10 / 10)")
	await ctx.step(1)


# d. Knockback state: input ignored, no air friction, gravity only, lasts knockback_stun_frames.
func test_knockback_state_blocks_control(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER)
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	var hitbox_shape: CollisionShape2D = player.get_node("Hitbox/CollisionShape2D")
	await ctx.step(3)
	ctx.check(player.is_on_floor(), "player starts grounded")
	player.take_damage(400.0, Vector2(1, -1).normalized(), 10.0)
	_check_velocity(ctx, player, Vector2(282.84, -282.84), 0.05, "400 * (10 / 10) along (1, -1)")
	ctx.check(player.get("state") == Player.State.KNOCKBACK, "take_damage enters KNOCKBACK")
	ctx.press("p1_left")
	ctx.press("p1_jump")
	ctx.press("p1_attack")
	await ctx.step(2)
	ctx.release("p1_jump")
	ctx.release("p1_attack")
	await ctx.step(8)
	ctx.check_near(
		player.velocity.x, 282.84, 0.5, "held left is ignored and no air friction during stun"
	)
	# 10 frames of gravity: 10 * 1500 / 60 = 250; a jump would have set -620.
	ctx.check_near(player.velocity.y, -32.84, 1.0, "gravity only during stun (jump ignored)")
	ctx.check(hitbox_shape.disabled, "attack pressed during stun does not activate the hitbox")
	await ctx.step(9)
	ctx.check(player.get("state") == Player.State.KNOCKBACK, "still KNOCKBACK after 19 frames")
	await ctx.step(1)
	ctx.check(player.get("state") == Player.State.NORMAL, "NORMAL after knockback_stun_frames 20")
	await ctx.step(10)
	ctx.check(
		player.velocity.x < 182.0,
		"held left slows the fighter once control returns (actual %.2f)" % player.velocity.x
	)


# e. Being hit cancels an attack in progress on the same call.
func test_take_damage_cancels_attack(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var hitbox: Area2D = attacker.get_node("Hitbox")
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	ctx.press("p1_attack")
	await ctx.step(4)
	ctx.release("p1_attack")
	ctx.check(hitbox.get("active") and not hitbox_shape.disabled, "hitbox is active 4 frames in")
	attacker.take_damage(100.0, Vector2(-1, 0), 10.0)
	ctx.check(hitbox.get("active") == false, "hit cancels the attack: hitbox inactive")
	ctx.check(hitbox_shape.disabled, "hit cancels the attack: hitbox shape disabled")
	await ctx.step(1)


# f. Hitbox integration: attack_damage 8, knockback 260 * 0.8 along normalize(1, -0.75).
func test_attack_hits_once_with_knockback(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var victim := fighters[1]
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	var landed: Array = []
	var launch: Array[Vector2] = []
	attacker.connect(
		"hit_landed",
		func(a: int, v: int) -> void:
			landed.append([a, v])
			launch.append(victim.velocity)
	)
	ctx.check(hitbox_shape.disabled, "hitbox shape is disabled before attacking")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(8)
	ctx.check_near(
		victim.get("percentage"), 8.0, 0.01, "attack_damage 8 lands within startup+active frames"
	)
	ctx.check(victim.get("state") == Player.State.KNOCKBACK, "victim is in KNOCKBACK")
	# 260 * (8 / 10) = 208 along normalize(1, -0.75) = (0.8, -0.6), read when hit_landed fired.
	var hit_velocity := launch[0] if launch.size() == 1 else Vector2.ZERO
	ctx.check_near(hit_velocity.x, 166.4, 0.01, "launch x = 0.8 * 260 * 0.8 away from the attacker")
	ctx.check_near(hit_velocity.y, -124.8, 0.01, "launch y = -0.6 * 260 * 0.8 (upward)")
	ctx.check_near(
		victim.velocity.x, 166.4, 0.5, "x is still 166.4 after 9 frames: stun has no air friction"
	)
	ctx.check(
		victim.global_position.y < STAND_Y - 1.0, "victim has been lifted off the floor by the hit"
	)
	ctx.check(landed == [[1, 2]], "hit_landed emitted once with (attacker 1, victim 2)")
	ctx.check_near(attacker.get("percentage"), 0.0, 0.01, "attacker never hits itself")
	await ctx.step(11)
	ctx.check(hitbox_shape.disabled, "hitbox shape is disabled again 20 frames after the attack")
	await ctx.step(30)
	ctx.check_near(victim.get("percentage"), 8.0, 0.01, "one activation deals damage only once")


# g. percentage_changed(player_index, percentage).
func test_percentage_changed_signal(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	var received: Array = []
	player.connect(
		"percentage_changed", func(index: int, pct: float) -> void: received.append([index, pct])
	)
	player.take_damage(100.0, Vector2(1, 0), 8.0)
	ctx.check(received == [[1, 8.0]], "percentage_changed carries player_index and percentage")
	await ctx.step(1)


# h. Respawn resets position, percentage and state.
func test_player_without_floor_respawns(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, 100))
	player.take_damage(0.0, Vector2(1, 0), 8.0)
	var fell := false
	for _frame in range(MAX_FALL_FRAMES):
		await ctx.step(1)
		if player.global_position.y > 1100.0:
			fell = true
			break
	ctx.check(fell, "player falls past y = 1100 with no floor")
	await ctx.step(12)
	ctx.check(player.global_position.y < 200.0, "crossing respawn_below_y 1200 returns to spawn")
	ctx.check_near(player.get("percentage"), 0.0, 0.01, "respawn resets percentage to 0")
	ctx.check(player.get("state") == Player.State.NORMAL, "respawn resets state to NORMAL")
	ctx.check(player.velocity.y < 200.0, "respawn resets velocity (was falling at 900 px/s)")


# i. Kept from the movement slice.
func test_attack_cannot_restart_during_recovery(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(9)
	ctx.check(hitbox_shape.disabled, "hitbox is off during recovery")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(3)
	ctx.check(hitbox_shape.disabled, "pressing attack during recovery does not start a new attack")


func test_player_two_uses_second_sprite(ctx: TestContext) -> void:
	var player := ctx.spawn_player(2, Vector2(600, 100))
	await ctx.step(1)
	var sprite: Sprite2D = player.get_node("Sprite2D")
	ctx.check(
		sprite.texture.resource_path.ends_with("fighter_p2.png"),
		"player_index 2 swaps to the orange fighter sprite"
	)
