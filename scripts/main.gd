extends Node2D
## Wyrm's Ossuary arena: points the fight camera at both fighters, scrolls the backdrop
## with a little parallax, and turns fighter signals into Vfx and camera shake.
## The HUD (HUD/Root, scripts/hud.gd) binds to the players' percentage_changed itself.

const SCREEN_CENTRE := Vector2(640, 360)
const PARALLAX := 0.06
## Hits at or past this percentage get the strong spark and the big shake.
const STRONG_HIT_PERCENT := 90.0

@onready var _players: Dictionary = {1: $Player1 as Player, 2: $Player2 as Player}
@onready var _camera: FightCamera = $Camera2D
@onready var _vfx: Vfx = $Vfx
@onready var _backdrop_layer: CanvasLayer = $BackdropLayer


func _ready() -> void:
	_camera.set_targets(_players[1], _players[2])
	for player: Player in _players.values():
		player.attack_started.connect(_on_attack_started)
		player.hit_landed.connect(_on_hit_landed)
		player.landed.connect(_on_landed)


func _process(_delta: float) -> void:
	_backdrop_layer.offset = -(_camera.global_position - SCREEN_CENTRE) * PARALLAX


func _on_attack_started(player_index: int, facing: int) -> void:
	var player: Player = _players[player_index]
	_vfx.slash_arc(player.global_position, facing, BrawlTheme.player_color(player_index))


func _on_hit_landed(attacker_index: int, victim_index: int) -> void:
	var victim: Player = _players[victim_index]
	var strong := victim.percentage >= STRONG_HIT_PERCENT
	_vfx.hit_spark(
		victim.global_position + Vector2(0, -10), BrawlTheme.player_color(attacker_index), strong
	)
	_camera.shake(9.0 if strong else 4.0, 8)


func _on_landed(player_index: int) -> void:
	var player: Player = _players[player_index]
	_vfx.dust(player.global_position + Vector2(0, 28))
