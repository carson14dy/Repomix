extends SceneTree
## Captures Title.tscn to docs/screenshot-title.png and CharacterSelect.tscn (Player 1 locked
## in) to docs/screenshot-select.png for layout review; tools/screenshot.gd covers the arena.
##
## Run:  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
##         --rendering-driver opengl3 --audio-driver Dummy --script tools/screenshot_menus.gd

const TITLE_SCENE := "res://scenes/Title.tscn"
const SELECT_SCENE := "res://scenes/CharacterSelect.tscn"
const TITLE_PNG := "res://docs/screenshot-title.png"
const SELECT_PNG := "res://docs/screenshot-select.png"


func _initialize() -> void:
	_capture()


func _capture() -> void:
	change_scene_to_file(TITLE_SCENE)
	await _frames(60)
	_save(TITLE_PNG)
	current_scene.set("change_scenes", false)
	MatchConfig.reset()
	change_scene_to_file(SELECT_SCENE)
	await _frames(5)
	current_scene.set("change_scenes", false)
	Input.action_press("p1_attack")
	await _frames(2)
	Input.action_release("p1_attack")
	await _frames(30)
	_save(SELECT_PNG)
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
