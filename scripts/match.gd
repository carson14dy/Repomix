class_name Match
extends Node
## Round flow for one stage: stocks, the blast zone, KO -> respawn, the win condition and the
## rematch. Frame-counted in _physics_process; the Match sits after the players in Main.tscn,
## so a fighter that leaves the zone is KO'd on the same physics frame.

signal stocks_changed(player_index: int, stocks: int)
signal fighter_koed(player_index: int)
signal fighter_respawned(player_index: int)
signal match_ended(winner_index: int)
signal match_restarted

@export var stocks_per_player: int = 3
## Physics frames between a KO and the respawn.
@export var respawn_delay_frames: int = 60
## A fighter whose position leaves this world-space rect is KO'd.
@export var blast_zone: Rect2 = Rect2(-260, -420, 1800, 1520)

## player_index -> stocks left; read-only from outside.
var stocks: Dictionary = {}
## 0 while the match runs, else the index of the fighter with stocks left.
var winner_index: int = 0

var _players: Dictionary = {}
## player_index -> frames until respawn; only KO'd fighters that still have stocks.
var _respawn_timers: Dictionary = {}
var _attack_held: Dictionary = {1: false, 2: false}


## Register both fighters ({1: Player, 2: Player}) and start the first match.
func set_players(players: Dictionary) -> void:
	_players = players
	restart()


func restart() -> void:
	winner_index = 0
	_respawn_timers.clear()
	for index: int in _players:
		stocks[index] = stocks_per_player
		_players[index].respawn()
		stocks_changed.emit(index, stocks[index])
	match_restarted.emit()


func _physics_process(_delta: float) -> void:
	# Polled every frame, win screen or not, so an attack held through the final KO is never
	# read as the rematch press (same reason main.gd polls Down every frame).
	var attack_pressed := _poll_attack_edges()
	if winner_index != 0:
		if attack_pressed:
			restart()
		return
	for index: int in _players:
		var player: Player = _players[index]
		if _respawn_timers.has(index):
			_respawn_timers[index] -= 1
			if _respawn_timers[index] <= 0:
				_respawn_timers.erase(index)
				player.respawn()
				fighter_respawned.emit(index)
		elif player.active and not blast_zone.has_point(player.global_position):
			_ko(index)
			# Decision: in a same-frame double KO on the last stocks the fighter processed first
			# (Player1) loses and the other keeps its stock, so match_ended fires once.
			if winner_index != 0:
				return


func _ko(index: int) -> void:
	var player: Player = _players[index]
	stocks[index] -= 1
	player.ko()
	stocks_changed.emit(index, stocks[index])
	fighter_koed.emit(index)
	if stocks[index] > 0:
		_respawn_timers[index] = respawn_delay_frames
		return
	for other: int in _players:
		if stocks[other] > 0:
			winner_index = other
	match_ended.emit(winner_index)


## True on a frame either fighter's attack goes down (edge, same rule as Player._just_pressed).
func _poll_attack_edges() -> bool:
	var pressed := false
	for index: int in _attack_held:
		var held := Input.is_action_pressed("p%d_attack" % index)
		pressed = pressed or (held and not _attack_held[index])
		_attack_held[index] = held
	return pressed
