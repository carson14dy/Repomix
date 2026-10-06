extends RefCounted
## The two-player action set in project.godot is the contract every script reads input through.

const EXPECTED_KEYS := {
	"p1_left": KEY_A,
	"p1_right": KEY_D,
	"p1_jump": KEY_W,
	"p1_down": KEY_S,
	"p1_attack": KEY_G,
	"p2_left": KEY_LEFT,
	"p2_right": KEY_RIGHT,
	"p2_jump": KEY_UP,
	"p2_down": KEY_DOWN,
	"p2_attack": KEY_L,
}


func test_keyboard_bindings(ctx: TestContext) -> void:
	for action: String in EXPECTED_KEYS:
		ctx.check(InputMap.has_action(action), "action %s exists" % action)
		var key_events := InputMap.action_get_events(action).filter(
			func(e: InputEvent) -> bool: return e is InputEventKey
		)
		var expected_key: int = EXPECTED_KEYS[action]
		var key_ok: bool = (
			key_events.size() == 1
			and (key_events[0] as InputEventKey).physical_keycode == expected_key
		)
		ctx.check(key_ok, "%s bound to physical key %d" % [action, expected_key])


func test_joypad_bindings_are_per_device(ctx: TestContext) -> void:
	for action: String in EXPECTED_KEYS:
		var expected_device := 0 if action.begins_with("p1_") else 1
		var pad_events := InputMap.action_get_events(action).filter(
			func(e: InputEvent) -> bool:
				return e is InputEventJoypadButton or e is InputEventJoypadMotion
		)
		ctx.check(pad_events.size() >= 1, "%s has a joypad binding" % action)
		var all_on_device: bool = pad_events.all(
			func(e: InputEvent) -> bool: return e.device == expected_device
		)
		ctx.check(all_on_device, "%s joypad bindings use device %d" % [action, expected_device])
	await ctx.step(1)
