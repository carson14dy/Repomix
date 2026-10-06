class_name MenuInput
extends RefCounted
## Menu-side input helpers: edge detection over InputMap actions (call just_pressed once per
## action per physics frame, like player.gd's held-flag pattern) and key names for hints.

## action -> whether it was down on the previous poll.
var _held: Dictionary = {}


## True on the frame an action goes down. The first poll of an action only records its state:
## a key still held from the previous scene (the attack that confirmed the title menu) must
## not count as a press in the one that replaces it.
func just_pressed(action: String) -> bool:
	var now := Input.is_action_pressed(action)
	var was: bool = _held.get(action, now)
	_held[action] = now
	return now and not was


## Name of the keyboard key bound to an action ("A", "Left", "L"), for on-screen hints.
static func key_label(action: String) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.physical_keycode)
	return action
