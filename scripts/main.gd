extends Node2D
## Wyrm's Ossuary arena: applies the menus' MatchConfig (fighter sprites from the Roster, the
## stock count, a BotController on Player2 in CPU mode), points the fight camera at both
## fighters, scrolls the video backdrop with a little parallax, hands the fighters to the
## Match, and turns fighter and Match signals into Vfx, camera shake, sound and the win screen,
## where Down goes back to the character select.
## The HUD (HUD/Root, scripts/hud.gd) reads MatchConfig and binds to the players'
## percentage_changed itself; its stock pips are fed from the Match here.

signal navigate(scene_path: String)

const CHARACTER_SELECT_PATH := "res://scenes/CharacterSelect.tscn"
const BOT_SCENE: PackedScene = preload("res://prefabs/BotController.tscn")
const SCREEN_CENTRE := Vector2(640, 360)
const PARALLAX := 0.06
## Hits at or past this percentage get the strong spark and the big shake.
const STRONG_HIT_PERCENT := 90.0

## Tests set this false: Down on the win screen then only emits navigate.
@export var change_scenes: bool = true

var _menu_input := MenuInput.new()

@onready var _players: Dictionary = {1: $Player1 as Player, 2: $Player2 as Player}
@onready var _camera: FightCamera = $Camera2D
@onready var _vfx: Vfx = $Vfx
@onready var _backdrop: CanvasLayer = $VideoBackdrop
@onready var _match: Match = $Match
@onready var _sfx: Sfx = $Sfx
@onready var _hud: Control = $HUD/Root
@onready var _controls_hint: Label = $HUD/Root/Controls
@onready var _win_layer: CanvasLayer = $WinLayer
@onready var _winner_label: Label = $WinLayer/Winner


func _ready() -> void:
	_camera.set_targets(_players[1], _players[2])
	for index: int in _players:
		var player: Player = _players[index]
		player.set_fighter_sprite(load(_fighter_def(index)["sprite"]))
		player.attack_started.connect(_on_attack_started)
		player.hit_landed.connect(_on_hit_landed)
		player.landed.connect(_on_landed)
		player.jumped.connect(_on_jumped)
	_match.stocks_per_player = MatchConfig.stocks
	_match.stocks_changed.connect(_hud.set_stocks)
	_match.fighter_koed.connect(_on_fighter_koed)
	_match.match_ended.connect(_on_match_ended)
	_match.match_restarted.connect(_on_match_restarted)
	if MatchConfig.p2_is_cpu:
		_add_bot()
	_match.set_players(_players)


## Parallax from the clamped view centre (not `global_position`, which Camera2D's limits do
## not clamp), so the backdrop stands still whenever the stage does.
func _process(_delta: float) -> void:
	_backdrop.offset = -(_camera.get_screen_center_position() - SCREEN_CENTRE) * PARALLAX


## Either player's Down press (edge) on the win screen returns to the character select. Polled
## every frame so a Down held through the final KO is never read as a press.
func _physics_process(_delta: float) -> void:
	var down := false
	for index: int in _players:
		down = _menu_input.just_pressed("p%d_down" % index) or down
	if down and _match.winner_index != 0:
		navigate.emit(CHARACTER_SELECT_PATH)
		if change_scenes:
			get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)


## The CPU drives Player2 through the p2_* actions. It sleeps while the win screen is up so it
## cannot press the attack that starts the rematch.
func _add_bot() -> void:
	var bot: BotController = BOT_SCENE.instantiate()
	bot.controlled_index = 2
	bot.difficulty = MatchConfig.difficulty as BotController.Difficulty
	add_child(bot)
	bot.set_fighters(_players[2], _players[1])
	bot.enabled = true
	_match.match_ended.connect(func(_winner_index: int) -> void: bot.enabled = false)
	_match.match_restarted.connect(func() -> void: bot.enabled = true)


func _fighter_def(index: int) -> Dictionary:
	return Roster.get_def(MatchConfig.character(index))


## Ignored on the win screen: the winner's rematch press would otherwise flash a slash arc.
func _on_attack_started(player_index: int, facing: int) -> void:
	if _match.winner_index != 0:
		return
	var player: Player = _players[player_index]
	_vfx.slash_arc(player.global_position, facing, BrawlTheme.player_color(player_index))
	_sfx.play_swing()


func _on_hit_landed(attacker_index: int, victim_index: int) -> void:
	var victim: Player = _players[victim_index]
	var strong := victim.percentage >= STRONG_HIT_PERCENT
	_vfx.hit_spark(
		victim.global_position + Vector2(0, -10), BrawlTheme.player_color(attacker_index), strong
	)
	_camera.shake(9.0 if strong else 4.0, 8)
	_sfx.play_hit(strong)


func _on_landed(player_index: int) -> void:
	var player: Player = _players[player_index]
	_vfx.dust(player.global_position + Vector2(0, 28))
	_sfx.play_land()


func _on_jumped(player_index: int, air: bool) -> void:
	if air:
		var player: Player = _players[player_index]
		_vfx.dust(player.global_position + Vector2(0, 28))
	_sfx.play_jump()


func _on_fighter_koed(_player_index: int) -> void:
	_camera.shake(14.0, 12)
	_sfx.play_ko()


func _on_match_ended(winner_index: int) -> void:
	_winner_label.text = "%s wins" % _fighter_def(winner_index)["name"]
	_winner_label.add_theme_color_override("font_color", BrawlTheme.player_color(winner_index))
	_controls_hint.hide()
	_win_layer.show()


func _on_match_restarted() -> void:
	_win_layer.hide()
	_controls_hint.show()
