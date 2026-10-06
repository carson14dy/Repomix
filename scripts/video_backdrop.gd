extends CanvasLayer
## Looping video backdrop (prefabs/VideoBackdrop.tscn): a CanvasLayer at layer -10 holding a
## full-screen poster TextureRect behind a muted, looping VideoStreamPlayer "Player".
##
## The poster is always shown so the first frame is never black; the player is hidden when
## the stream is missing or fails to load (e.g. a clip that has not been generated yet).
## Produce clips with tools/veo_backdrops.py + tools/convert_backdrop.sh; see docs/VEO.md.

@export var stream_path: String = "res://assets/video/test_pattern.ogv"
@export var poster_path: String = "res://assets/video/test_pattern_poster.png"

@onready var _player: VideoStreamPlayer = $Player
@onready var _poster: TextureRect = $Poster


func _ready() -> void:
	# ResourceLoader.exists() first: load() on a missing path logs an engine error, and a
	# missing clip is an expected state, not a bug.
	if poster_path != "" and ResourceLoader.exists(poster_path):
		_poster.texture = load(poster_path) as Texture2D
	var stream: VideoStream = null
	if stream_path != "" and ResourceLoader.exists(stream_path):
		stream = load(stream_path) as VideoStream
	if stream == null:
		_player.hide()
		return
	_player.stream = stream
	_player.show()
	# Children are ready before their parent, so autoplay already ran with no stream.
	_player.play()
