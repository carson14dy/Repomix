class_name Roster
extends RefCounted
## The fighter roster the menus read. Stats are 1-10. A fighter without portrait art has an
## empty "portrait" (the select screen draws a placeholder disc); Zephyr also has no sprite yet
## and borrows Kage's, and takes MIST as the only BrawlTheme teal.

const DATA := {
	"kage":
	{
		"name": "Kage",
		"title": "The Shadow Weaver",
		"colour": BrawlTheme.P1_COLOR,
		"portrait": "res://assets/sprites/kage_portrait.png",
		"sprite": "res://assets/sprites/kage.png",
		"speed": 9,
		"power": 6,
		"defense": 5,
		"recovery": 9,
		"description":
		(
			"An agile hooded assassin with piercing blue eyes. "
			+ "Swift multi-hit combos, aerial speed and phantom teleportation."
		),
	},
	"ignis":
	{
		"name": "Ignis",
		"title": "The Spectral Dreadnought",
		"colour": BrawlTheme.P2_COLOR,
		"portrait": "res://assets/sprites/ignis_portrait.png",
		"sprite": "res://assets/sprites/ignis.png",
		"speed": 5,
		"power": 9,
		"defense": 9,
		"recovery": 5,
		"description":
		(
			"A colossal sentinel in blackened plate glowing with crimson spectral fury. "
			+ "A greatsword with devastating knockback."
		),
	},
	"zephyr":
	{
		"name": "Zephyr",
		"title": "The Tempest Valkyrie",
		"colour": BrawlTheme.MIST,
		"portrait": "",
		"sprite": "res://assets/sprites/kage.png",
		"speed": 7,
		"power": 7,
		"defense": 6,
		"recovery": 10,
		"description":
		(
			"A winged aerial duelist wielding a gale lance. "
			+ "Triple jumps, floating descent and long-range whirlwind thrusts."
		),
	},
}


## Roster order as shown left to right in the character select.
static func ids() -> Array[String]:
	return ["kage", "ignis", "zephyr"]


static func get_def(id: String) -> Dictionary:
	return DATA[id]
