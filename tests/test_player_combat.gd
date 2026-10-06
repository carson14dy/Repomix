extends RefCounted
## Attack hitbox timing, damage/knockback, one-hit-per-activation, and respawn.
## Expected values are hand-derived from the player.gd tunables.

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


func test_attack_hits_once_with_knockback(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var victim := fighters[1]
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	var landed: Array = []
	attacker.connect("hit_landed", func(a: int, v: int) -> void: landed.append([a, v]))
	ctx.check(hitbox_shape.disabled, "hitbox shape is disabled before attacking")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(8)
	ctx.check_near(
		victim.get("damage"), 8.0, 0.01, "attack_damage 8 lands within startup+active (9) frames"
	)
	ctx.check(victim.velocity.x > 0.0, "victim is knocked away from the attacker (right)")
	ctx.check(victim.velocity.y < 0.0, "knockback has an upward component")
	ctx.check(landed == [[1, 2]], "hit_landed emitted once with (attacker 1, victim 2)")
	ctx.check_near(attacker.get("damage"), 0.0, 0.01, "attacker never hits itself")
	await ctx.step(11)
	ctx.check(hitbox_shape.disabled, "hitbox shape is disabled again 20 frames after the attack")
	await ctx.step(19)
	ctx.check_near(victim.get("damage"), 8.0, 0.01, "one activation deals damage only once")


func test_take_hit_knockback_formula(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER)
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	await ctx.step(1)
	player.take_hit(700.0, 8.0, 260.0, 7.0)
	# speed = 260 + 7 * 8 = 316 along normalize(-1, -0.75) = (-0.8, -0.6)
	ctx.check_near(player.velocity.x, -252.8, 0.5, "knockback x = -0.8 * (260 + 7 * 8)")
	ctx.check_near(player.velocity.y, -189.6, 0.5, "knockback y = -0.6 * (260 + 7 * 8)")
	player.take_hit(500.0, 8.0, 260.0, 7.0)
	# damage is now 16: speed = 260 + 7 * 16 = 372, direction (+0.8, -0.6)
	ctx.check_near(player.velocity.x, 297.6, 0.5, "knockback scales with damage after the hit")
	ctx.check_near(player.get("damage"), 16.0, 0.01, "damage accumulates across hits")
	await ctx.step(1)


func test_damage_changed_signal(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	var received: Array = []
	player.connect(
		"damage_changed", func(index: int, dmg: float) -> void: received.append([index, dmg])
	)
	player.take_hit(0.0, 8.0, 260.0, 7.0)
	ctx.check(received == [[1, 8.0]], "damage_changed carries player_index and new damage")
	await ctx.step(1)


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


func test_player_without_floor_respawns(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, 100))
	player.take_hit(0.0, 8.0, 0.0, 0.0)
	var fell := false
	for _frame in range(MAX_FALL_FRAMES):
		await ctx.step(1)
		if player.global_position.y > 1100.0:
			fell = true
			break
	ctx.check(fell, "player falls past y = 1100 with no floor")
	await ctx.step(12)
	ctx.check(player.global_position.y < 200.0, "crossing respawn_below_y 1200 returns to spawn")
	ctx.check_near(player.get("damage"), 0.0, 0.01, "respawn resets damage to 0")
	ctx.check(player.velocity.y < 200.0, "respawn resets velocity (was falling at 900 px/s)")


func test_player_two_uses_second_sprite(ctx: TestContext) -> void:
	var player := ctx.spawn_player(2, Vector2(600, 100))
	await ctx.step(1)
	var sprite: Sprite2D = player.get_node("Sprite2D")
	ctx.check(
		sprite.texture.resource_path.ends_with("fighter_p2.png"),
		"player_index 2 swaps to the orange fighter sprite"
	)
