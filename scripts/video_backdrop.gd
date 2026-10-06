extends CanvasLayer
## Looping video backdrop (prefabs/VideoBackdrop.tscn): a CanvasLayer at layer -10 holding a
## poster TextureRect behind a muted, looping VideoStreamPlayer "Player". Both rects are 12 %
## larger than the 1280x720 view (a 77x43 px margin) so main.gd can scroll the layer for
## parallax without showing an edge.
##
## The poster is always shown so the first frame is never black; the player is hidden when
## the stream is missing or fails to load (e.g. a clip that has not been generated yet).
## Produce clips with tools/render_backdrop_clip.py (or tools/veo_backdrops.py) and
## tools/convert_backdrop.sh; see docs/VEO.md.

@export var stream_path: String = "res://assets/video/ossuary_nave.ogv"
@export var poster_path: String = "res://assets/video/ossuary_nave_poster.png"

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
