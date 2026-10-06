extends SceneTree
## Captures Main.tscn to docs/screenshot-main.png, then hits Player2 for 24% (with the slash
## arc and hit spark a real hitbox hit would trigger through main.gd) and captures
## docs/screenshot-hit.png (knockback tint, Vfx, "24%" medallion) for the lead's review.
##
## Run:  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
##         --rendering-driver opengl3 --audio-driver Dummy --script tools/screenshot.gd

const MAIN_SCENE := "res://scenes/Main.tscn"
const MAIN_PNG := "res://docs/screenshot-main.png"
const HIT_PNG := "res://docs/screenshot-hit.png"


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
