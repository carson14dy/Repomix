extends SceneTree
## Captures Main.tscn to docs/screenshot-main.png, then hits Player2 for 24% and captures
## docs/screenshot-hit.png (knockback tint + "P2  24%" HUD) for the lead's review.
##
## Run:  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
##         --rendering-driver opengl3 --audio-driver Dummy --script tools/screenshot.gd

const MAIN_SCENE := "res://scenes/Main.tscn"
const MAIN_PNG := "res://docs/screenshot-main.png"
const HIT_PNG := "res://docs/screenshot-hit.png"


func _initialize() -> void:
	_capture()


func _capture() -> void:
	change_scene_to_file(MAIN_SCENE)
	await _frames(12)
	_save(MAIN_PNG)
	var player2: Player = current_scene.get_node("Player2")
	player2.take_damage(260.0, Vector2(1, -0.75).normalized(), 24.0)
	await _frames(3)
	_save(HIT_PNG)
	quit(0)


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _save(path: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
		quit(1)
		return
	print("saved %s used_rect=%s" % [path, image.get_used_rect()])
