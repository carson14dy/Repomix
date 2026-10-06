extends Node2D
## Test arena: wires each Player's damage_changed signal to its HUD label.

@onready var _labels: Dictionary = {
	1: $HUD/P1Label as Label,
	2: $HUD/P2Label as Label,
}


func _ready() -> void:
	for player: Node in [$Player1, $Player2]:
		player.connect("damage_changed", _on_damage_changed)


func _on_damage_changed(player_index: int, damage: float) -> void:
	var label: Label = _labels[player_index]
	label.text = "P%d  %d%%" % [player_index, roundi(damage)]
