extends SceneTree
## Captures Main.tscn to docs/screenshot-main.png, then hits Player2 for 24% (with the slash
## arc and hit spark a real hitbox hit would trigger through main.gd) and captures
## docs/screenshot-hit.png (knockback tint, Vfx, "24%" medallion), then moves Player2 to the
## far right of the spine and lets the fight camera settle for docs/screenshot-zoom.png
## (zoomed-out framing), then drops Player2 past the blast zone on its last stock for
## docs/screenshot-win.png (the win screen).
##
## Run:  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
##         --rendering-driver opengl3 --audio-driver Dummy --script tools/screenshot.gd

const MAIN_SCENE := "res://scenes/Main.tscn"
const MAIN_PNG := "res://docs/screenshot-main.png"
const HIT_PNG := "res://docs/screenshot-hit.png"
const ZOOM_PNG := "res://docs/screenshot-zoom.png"
const WIN_PNG := "res://docs/screenshot-win.png"
## Player2 spawn for the zoom shot: still on the spine (collider x 190..1090), far from Player1.
const ZOOM_P2_POSITION := Vector2(1050, 540)


func _initialize() -> void:
	# Under software rendering a frame can take 100+ ms, so one process frame would otherwise
	# run up to 8 physics steps and the 9-frame Vfx would be gone before the capture.
	Engine.max_physics_steps_per_frame = 1
	_capture()


func _capture() -> void:
	change_scene_to_file(MAIN_SCENE)
	await _frames(40)
	_save(MAIN_PNG)
	var player1: Player = current_scene.get_node("Player1")
	var player2: Player = current_scene.get_node("Player2")
	var vfx: Vfx = current_scene.get_node("Vfx")
	player2.take_damage(260.0, Vector2(1, -0.75).normalized(), 24.0)
	vfx.slash_arc(player1.global_position, 1, BrawlTheme.P1_COLOR)
	vfx.hit_spark(player2.global_position + Vector2(0, -10), BrawlTheme.P1_COLOR, false)
	await _frames(3)
	_save(HIT_PNG)
	player2.global_position = ZOOM_P2_POSITION
	player2.velocity = Vector2.ZERO
	# 90 physics frames: the camera lerps 8% per step, so it has settled; awaiting physics
	# frames (not process frames) keeps the count exact however slow the software renderer is.
	await _physics_frames(90)
	_save(ZOOM_PNG)
	var match_node: Match = current_scene.get_node("Match")
	match_node.stocks[2] = 1
	player2.global_position = Vector2(640, 1150)
	await _physics_frames(2)
	await _frames(2)
	_save(WIN_PNG)
	quit(0)


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func _save(path: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
		quit(1)
		return
	print("saved %s used_rect=%s" % [path, image.get_used_rect()])
