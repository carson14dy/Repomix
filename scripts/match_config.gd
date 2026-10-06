class_name MatchConfig
extends RefCounted
## Match settings chosen in the menus and read by the arena. Static so Title and
## CharacterSelect can write them before Main.tscn exists; reset() restores the defaults.

static var p1_character: String = "kage"
static var p2_character: String = "ignis"
static var p2_is_cpu: bool = false
static var difficulty: int = 1
static var stocks: int = 3


static func reset() -> void:
	p1_character = "kage"
	p2_character = "ignis"
	p2_is_cpu = false
	difficulty = 1
	stocks = 3
