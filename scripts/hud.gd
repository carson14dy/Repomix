extends Control
## Fight HUD on HUD/Root in Main.tscn: each medallion's damage read-out and portrait ring
## follow that player's percentage and the Name label wears the player colour. Node names
## (P%dMedallion, P%dLabel, Ring, Name) and the player paths are the scene contract; a missing
## node is reported with push_error and skipped.

const PLAYER_PATHS := {1: ^"../../Player1", 2: ^"../../Player2"}

## player_index -> Label / ring Control (scripts/medallion_ring.gd); only present nodes.
var _labels: Dictionary = {}
var _rings: Dictionary = {}


func _ready() -> void:
	for index: int in [1, 2]:
		var medallion := get_node_or_null("P%dMedallion" % index)
		if medallion == null:
			push_error("HUD: missing node P%dMedallion under %s" % [index, get_path()])
			continue
		var name_label := medallion.get_node_or_null("Name") as Label
		if name_label != null:
			name_label.add_theme_color_override("font_color", BrawlTheme.player_color(index))
		var label := medallion.get_node_or_null("P%dLabel" % index) as Label
		if label == null:
			push_error("HUD: P%dMedallion has no P%dLabel" % [index, index])
		else:
			_labels[index] = label
		var ring := medallion.get_node_or_null("Ring")
		if ring == null or not ring.has_method("set_percentage"):
			push_error("HUD: P%dMedallion has no Ring with set_percentage()" % index)
		else:
			_rings[index] = ring
		var player := get_node_or_null(PLAYER_PATHS[index]) as Player
		if player == null:
			push_error("HUD: no Player at %s" % PLAYER_PATHS[index])
			continue
		player.percentage_changed.connect(_on_percentage_changed)
		_on_percentage_changed(index, player.percentage)


func _on_percentage_changed(player_index: int, percentage: float) -> void:
	var color := BrawlTheme.percent_color(percentage)
	if _labels.has(player_index):
		var label: Label = _labels[player_index]
		label.text = "%d%%" % roundi(percentage)
		label.add_theme_color_override("font_color", color)
	if _rings.has(player_index):
		_rings[player_index].set_percentage(percentage)
