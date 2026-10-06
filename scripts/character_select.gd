extends Control
## Character select. Each player browses the roster with left/right in their own column and
## locks in with attack; down unlocks, and Player 1's down with nothing locked returns to the
## title. Against the CPU the P2 column is picked automatically (the fighter after Player 1's
## in roster order) and Player 1's lock-in starts the match. Once everyone is locked in,
## MatchConfig is written, start_requested fires, "FIGHT" flashes for FLASH_FRAMES physics
## frames, then Main.tscn loads.

signal start_requested
signal navigate(scene_path: String)

const TITLE_PATH := "res://scenes/Title.tscn"
const MAIN_PATH := "res://scenes/Main.tscn"
const FLASH_FRAMES := 30
## Stat rows: label, Roster key.
const STATS := [
	["Speed", "speed"],
	["Power", "power"],
	["Defense", "defense"],
	["Recovery", "recovery"],
]
const STAT_MAX := 10.0
const STAT_ROW_HEIGHT := 34.0
const STAT_TRACK := Rect2(120.0, 7.0, 220.0, 10.0)

## Tests set this false: starting a match then only writes MatchConfig and emits the signals.
@export var change_scenes: bool = true

var _ids: Array[String] = Roster.ids()
## player_index -> index into _ids.
var _selection: Dictionary = {1: 0, 2: 0}
var _confirmed: Dictionary = {1: false, 2: false}
## player_index -> Array of the four stat fill ColorRects / value Labels, in STATS order.
var _fills: Dictionary = {}
var _values: Dictionary = {}
## -1 while choosing; counts down from FLASH_FRAMES after the match is requested.
var _flash_left: int = -1
var _menu_input := MenuInput.new()


func _ready() -> void:
	_selection[1] = maxi(_ids.find(MatchConfig.p1_character), 0)
	_selection[2] = maxi(_ids.find(MatchConfig.p2_character), 0)
	$Subheading.text = (
		"Left and right browse the roster, attack locks in. Player 1's %s returns to the title."
		% MenuInput.key_label("p1_down")
	)
	for player_index in [1, 2]:
		var colour := BrawlTheme.player_color(player_index)
		var column := _column(player_index)
		(column.get_node("Rule") as ColorRect).color = colour
		(column.get_node("Frame") as ColorRect).color = colour
		(column.get_node("Header") as Label).add_theme_color_override("font_color", colour)
		_build_stats(player_index, column.get_node("Stats") as Control, colour)
	_refresh()


func _physics_process(_delta: float) -> void:
	if _flash_left >= 0:
		_tick_flash()
		return
	for player_index in [1, 2]:
		var left := _menu_input.just_pressed("p%d_left" % player_index)
		var right := _menu_input.just_pressed("p%d_right" % player_index)
		var confirm := _menu_input.just_pressed("p%d_attack" % player_index)
		var back := _menu_input.just_pressed("p%d_down" % player_index)
		if player_index == 2 and MatchConfig.p2_is_cpu:
			continue
		if _confirmed[player_index]:
			if back:
				_confirmed[player_index] = false
				_refresh()
			continue
		if left:
			_cycle(player_index, -1)
		if right:
			_cycle(player_index, 1)
		if confirm:
			_confirmed[player_index] = true
			_refresh()
		elif back and player_index == 1 and not _confirmed[2]:
			set_physics_process(false)
			navigate.emit(TITLE_PATH)
			if change_scenes:
				get_tree().change_scene_to_file(TITLE_PATH)
			return
	if _confirmed[1] and (_confirmed[2] or MatchConfig.p2_is_cpu):
		_start_match()


## Roster id currently shown in a player's column.
func selected_id(player_index: int) -> String:
	return _ids[_selection[player_index]]


func is_confirmed(player_index: int) -> bool:
	return _confirmed[player_index]


func _column(player_index: int) -> Control:
	return get_node("P%dColumn" % player_index) as Control


func _cycle(player_index: int, direction: int) -> void:
	_selection[player_index] = posmod(_selection[player_index] + direction, _ids.size())
	_refresh()


func _start_match() -> void:
	MatchConfig.p1_character = selected_id(1)
	MatchConfig.p2_character = selected_id(2)
	start_requested.emit()
	$FlashBacking.visible = true
	$FightFlash.visible = true
	_flash_left = FLASH_FRAMES


func _tick_flash() -> void:
	if _flash_left == 0:
		return
	_flash_left -= 1
	if _flash_left == 0 and change_scenes:
		get_tree().change_scene_to_file(MAIN_PATH)


func _refresh() -> void:
	if MatchConfig.p2_is_cpu:
		_selection[2] = (_selection[1] + 1) % _ids.size()
	for player_index in [1, 2]:
		var def := Roster.get_def(selected_id(player_index))
		var column := _column(player_index)
		var portrait := column.get_node("Portrait") as TextureRect
		var placeholder := column.get_node("PortraitPlaceholder")
		var has_portrait: bool = def["portrait"] != ""
		portrait.visible = has_portrait
		portrait.texture = load(def["portrait"]) if has_portrait else null
		placeholder.visible = not has_portrait
		placeholder.set("initial", String(def["name"]).left(1))
		(column.get_node("Name") as Label).text = def["name"]
		(column.get_node("Title") as Label).text = def["title"]
		(column.get_node("Description") as Label).text = def["description"]
		for i in STATS.size():
			var stat: int = def[STATS[i][1]]
			(_fills[player_index][i] as ColorRect).size.x = STAT_TRACK.size.x * stat / STAT_MAX
			(_values[player_index][i] as Label).text = str(stat)
		_refresh_status(player_index, column)


func _refresh_status(player_index: int, column: Control) -> void:
	var header := column.get_node("Header") as Label
	var status := column.get_node("Status") as Label
	var cpu := player_index == 2 and MatchConfig.p2_is_cpu
	header.text = "CPU opponent" if cpu else "Player %d" % player_index
	column.get_node("Frame").visible = _confirmed[player_index] or cpu
	if cpu:
		status.text = "Picked for you"
		status.add_theme_color_override("font_color", BrawlTheme.BONE_SHADOW)
	elif _confirmed[player_index]:
		status.text = "Ready"
		status.add_theme_color_override("font_color", BrawlTheme.player_color(player_index))
	else:
		status.text = (
			"%s / %s browse   %s lock in"
			% [
				MenuInput.key_label("p%d_left" % player_index),
				MenuInput.key_label("p%d_right" % player_index),
				MenuInput.key_label("p%d_attack" % player_index),
			]
		)
		status.add_theme_color_override("font_color", BrawlTheme.BONE_SHADOW)


## Four rows of label, bone track, player-coloured fill (sized in _refresh) and value.
func _build_stats(player_index: int, parent: Control, colour: Color) -> void:
	var fills: Array[ColorRect] = []
	var values: Array[Label] = []
	for i in STATS.size():
		var y := i * STAT_ROW_HEIGHT
		parent.add_child(
			_make_label(STATS[i][0], Vector2(0, y), Vector2(110, 24), BrawlTheme.BONE_SHADOW)
		)
		var track := ColorRect.new()
		track.position = STAT_TRACK.position + Vector2(0, y)
		track.size = STAT_TRACK.size
		track.color = Color(BrawlTheme.BONE_DARK, 0.35)
		parent.add_child(track)
		var fill := ColorRect.new()
		fill.position = track.position
		fill.size = Vector2(0, STAT_TRACK.size.y)
		fill.color = colour
		parent.add_child(fill)
		fills.append(fill)
		var value := _make_label("", Vector2(352, y), Vector2(28, 24), BrawlTheme.BONE)
		parent.add_child(value)
		values.append(value)
	_fills[player_index] = fills
	_values[player_index] = values


func _make_label(text: String, pos: Vector2, label_size: Vector2, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = label_size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
