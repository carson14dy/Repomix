extends RefCounted
## prefabs/VideoBackdrop.tscn: a layer -10 CanvasLayer with a poster TextureRect behind a muted,
## looping VideoStreamPlayer "Player". The imported test pattern (assets/video/test_pattern.ogv)
## must load as a VideoStreamTheora (direct loader, no .import); a missing clip hides the
## player and keeps the poster.

const SCENE_PATH := "res://prefabs/VideoBackdrop.tscn"


func _spawn(ctx: TestContext, stream_path: String = "") -> CanvasLayer:
	var scene: PackedScene = load(SCENE_PATH)
	ctx.check(scene != null, "VideoBackdrop.tscn loads")
	if scene == null:
		return null
	var backdrop := scene.instantiate() as CanvasLayer
	ctx.check(backdrop != null, "VideoBackdrop root instantiates as CanvasLayer")
	if backdrop == null:
		return null
	if stream_path != "":
		backdrop.set("stream_path", stream_path)
	ctx.add(backdrop)
	return backdrop


func test_test_pattern_plays_looped_behind_poster(ctx: TestContext) -> void:
	var backdrop := _spawn(ctx)
	if backdrop == null:
		return
	await ctx.step(1)
	ctx.check(backdrop.layer == -10, "VideoBackdrop is a CanvasLayer at layer -10")
	var player := backdrop.get_node_or_null("Player") as VideoStreamPlayer
	ctx.check(player != null, "VideoBackdrop has a VideoStreamPlayer named Player")
	if player == null:
		return
	ctx.check(
		player.stream != null,
		"Player.stream is non-null for test_pattern.ogv (missing .ogv or theora module breaks this)"
	)
	ctx.check(player.stream is VideoStreamTheora, "Player.stream loads as VideoStreamTheora")
	ctx.check(player.loop, "Player loops")
	ctx.check(player.autoplay, "Player autoplays")
	ctx.check(player.expand, "Player expands the video to its rect")
	ctx.check(player.size == Vector2(1280, 720), "Player covers the 1280x720 viewport")
	ctx.check(player.volume_db <= -80.0, "Player is muted (volume_db -80)")
	ctx.check(player.visible, "Player is visible when the stream loaded")
	ctx.check(player.is_playing(), "Player is playing after _ready")
	var poster := backdrop.get_node_or_null("Poster") as TextureRect
	ctx.check(poster != null and poster.texture != null, "Poster shows a texture")
	if poster == null:
		return
	ctx.check(poster.size == Vector2(1280, 720), "Poster covers the 1280x720 viewport")
	ctx.check(
		poster.get_index() < player.get_index(), "Poster is drawn behind Player (child order)"
	)


func test_missing_stream_hides_player_and_keeps_poster(ctx: TestContext) -> void:
	var backdrop := _spawn(ctx, "res://assets/video/does_not_exist.ogv")
	if backdrop == null:
		return
	await ctx.step(1)
	var player := backdrop.get_node("Player") as VideoStreamPlayer
	var poster := backdrop.get_node("Poster") as TextureRect
	ctx.check(not player.visible, "Player is hidden when the stream path does not exist")
	ctx.check(player.stream == null, "Player.stream stays null for a missing clip")
	ctx.check(poster.visible and poster.texture != null, "Poster stays visible as the fallback")


func test_default_poster_is_the_test_pattern_frame(ctx: TestContext) -> void:
	var texture := load("res://assets/video/test_pattern_poster.png") as Texture2D
	ctx.check(texture != null, "test_pattern_poster.png loads as a Texture2D")
	if texture == null:
		return
	ctx.check(texture.get_size() == Vector2(1280, 720), "poster is 1280x720")
