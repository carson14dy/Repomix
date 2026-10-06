extends Node2D
## Wyrm's Ossuary arena: points the fight camera at both fighters, scrolls the video backdrop
## with a little parallax, hands the fighters to the Match, and turns fighter and Match signals
## into Vfx, camera shake, sound and the win screen.
## The HUD (HUD/Root, scripts/hud.gd) binds to the players' percentage_changed itself; its
## stock pips are fed from the Match here.

const SCREEN_CENTRE := Vector2(640, 360)
const PARALLAX := 0.06
## Hits at or past this percentage get the strong spark and the big shake.
const STRONG_HIT_PERCENT := 90.0

@onready var _players: Dictionary = {1: $Player1 as Player, 2: $Player2 as Player}
@onready var _camera: FightCamera = $Camera2D
@onready var _vfx: Vfx = $Vfx
@onready var _backdrop: CanvasLayer = $VideoBackdrop
@onready var _match: Match = $Match
@onready var _sfx: Sfx = $Sfx
@onready var _hud: Control = $HUD/Root
@onready var _win_layer: CanvasLayer = $WinLayer
@onready var _winner_label: Label = $WinLayer/Winner


func _ready() -> void:
	_camera.set_targets(_players[1], _players[2])
	for player: Player in _players.values():
		player.attack_started.connect(_on_attack_started)
		player.hit_landed.connect(_on_hit_landed)
		player.landed.connect(_on_landed)
		player.jumped.connect(_on_jumped)
	_match.stocks_changed.connect(_hud.set_stocks)
	_match.fighter_koed.connect(_on_fighter_koed)
	_match.match_ended.connect(_on_match_ended)
	_match.match_restarted.connect(_on_match_restarted)
	_match.set_players(_players)


func _process(_delta: float) -> void:
	_backdrop.offset = -(_camera.global_position - SCREEN_CENTRE) * PARALLAX


func _on_attack_started(player_index: int, facing: int) -> void:
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
	_winner_label.text = "%s wins" % BrawlTheme.player_name(winner_index)
	_winner_label.add_theme_color_override("font_color", BrawlTheme.player_color(winner_index))
	_win_layer.show()


func _on_match_restarted() -> void:
	_win_layer.hide()
