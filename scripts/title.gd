extends Control
## Title screen. Either player drives the menu through the fight actions: jump moves up, down
## moves down, attack confirms (the mouse works too). Versus and Versus CPU record the mode in
## MatchConfig.p2_is_cpu, emit navigate and load the character select; Controls toggles a
## panel listing both keyboard layouts read from the InputMap.

signal navigate(scene_path: String)

const CHARACTER_SELECT_PATH := "res://scenes/CharacterSelect.tscn"
## Menu/<name> in top-to-bottom order; the index into this list is the selection.
const ITEMS: Array[String] = ["Versus", "VersusCpu", "Controls"]
const ITEM_SPACING := 52.0
## Rows of the controls panel: label, then the action suffixes shown for it.
const CONTROL_ROWS := [
	["Move", ["left", "right"]],
	["Jump", ["jump"]],
	["Fast-fall", ["down"]],
	["Attack", ["attack"]],
]
const ENTRANCE_SECONDS := 0.45

## Tests set this false: selecting a mode then only writes MatchConfig and emits navigate.
@export var change_scenes: bool = true

var _selected: int = 0
var _menu_input := MenuInput.new()

@onready var _menu: Control = $Menu
@onready var _marker: ColorRect = $Marker
@onready var _controls_panel: Control = $ControlsPanel


func _ready() -> void:
	for index in ITEMS.size():
		var item := _item(index)
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.mouse_entered.connect(_select.bind(index))
		item.gui_input.connect(_on_item_gui_input.bind(index))
	_fill_controls_panel()
	$Footer.text = (
		"Player 1  %s / %s move   %s confirm      Player 2  %s / %s move   %s confirm"
		% [
			MenuInput.key_label("p1_jump"),
			MenuInput.key_label("p1_down"),
			MenuInput.key_label("p1_attack"),
			MenuInput.key_label("p2_jump"),
			MenuInput.key_label("p2_down"),
			MenuInput.key_label("p2_attack"),
		]
	)
	$Version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	_refresh()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, ENTRANCE_SECONDS)


func _physics_process(_delta: float) -> void:
	for player_index: int in [1, 2]:
		var up := _menu_input.just_pressed("p%d_jump" % player_index)
		var down := _menu_input.just_pressed("p%d_down" % player_index)
		var confirm := _menu_input.just_pressed("p%d_attack" % player_index)
		if _controls_panel.visible:
			if confirm:
				_controls_panel.visible = false
			continue
		if up:
			_select(posmod(_selected - 1, ITEMS.size()))
		if down:
			_select(posmod(_selected + 1, ITEMS.size()))
		if confirm:
			_activate()
			if not is_physics_processing():
				return  # handed off to the character select; ignore the other player's confirm


func _item(index: int) -> Label:
	return _menu.get_node(ITEMS[index]) as Label


func _select(index: int) -> void:
	_selected = index
	_refresh()


func _refresh() -> void:
	for index in ITEMS.size():
		var colour := BrawlTheme.BONE if index == _selected else BrawlTheme.BONE_SHADOW
		_item(index).add_theme_color_override("font_color", colour)
	_marker.position.y = _menu.position.y + _selected * ITEM_SPACING + 8.0


func _activate() -> void:
	match ITEMS[_selected]:
		"Versus":
			_start(false)
		"VersusCpu":
			_start(true)
		"Controls":
			_controls_panel.visible = not _controls_panel.visible


func _start(p2_is_cpu: bool) -> void:
	# Hand off once: the other player's confirm on the same frame must not navigate again.
	set_physics_process(false)
	MatchConfig.p2_is_cpu = p2_is_cpu
	navigate.emit(CHARACTER_SELECT_PATH)
	if change_scenes:
		get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)


func _on_item_gui_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_select(index)
		_activate()


func _fill_controls_panel() -> void:
	for player_index: int in [1, 2]:
		var actions: Array[String] = []
		var keys: Array[String] = []
		for row: Array in CONTROL_ROWS:
			actions.append(row[0])
			var names: Array[String] = []
			for suffix: String in row[1]:
				names.append(MenuInput.key_label("p%d_%s" % [player_index, suffix]))
			keys.append(" / ".join(names))
		var header := _controls_panel.get_node("P%dHeader" % player_index) as Label
		header.add_theme_color_override("font_color", BrawlTheme.player_color(player_index))
		(_controls_panel.get_node("P%dActions" % player_index) as Label).text = "\n".join(actions)
		(_controls_panel.get_node("P%dKeys" % player_index) as Label).text = "\n".join(keys)
	($ControlsPanel/Close as Label).text = (
		"%s or %s closes this panel"
		% [MenuInput.key_label("p1_attack"), MenuInput.key_label("p2_attack")]
	)
