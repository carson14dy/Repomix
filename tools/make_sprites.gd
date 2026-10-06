extends SceneTree
## Generates the two placeholder fighter sprites (32x56 RGBA8) into assets/sprites/.
##
## Run:  $GODOT --headless --path . --script tools/make_sprites.gd
## then: $GODOT --headless --path . --import   (creates the .import sidecars)

const WIDTH := 32
const HEIGHT := 56
const OUTLINE := Color("#14213d")
const VISOR := Color("#f8f9fa")

const FIGHTERS := {
	"res://assets/sprites/fighter_p1.png": Color("#2ec4b6"),
	"res://assets/sprites/fighter_p2.png": Color("#ff9f1c"),
}


func _initialize() -> void:
	for path: String in FIGHTERS:
		var err := _make_fighter(FIGHTERS[path]).save_png(path)
		if err != OK:
			push_error("Failed to save %s (error %d)" % [path, err])
			quit(1)
			return
		print("wrote %s" % path)
	quit(0)


## Blocky fighter: head on top, torso, two legs. The visor sits on the RIGHT side of
## the head so Sprite2D.flip_h visibly changes which way the fighter faces.
func _make_fighter(body: Color) -> Image:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_outlined_rect(img, Rect2i(7, 0, 18, 18), body)  # head
	_outlined_rect(img, Rect2i(4, 18, 24, 22), body)  # torso
	_outlined_rect(img, Rect2i(5, 40, 9, 16), body)  # left leg
	_outlined_rect(img, Rect2i(18, 40, 9, 16), body)  # right leg
	img.fill_rect(Rect2i(16, 5, 7, 5), VISOR)  # visor, right side of head
	img.fill_rect(Rect2i(20, 6, 2, 3), OUTLINE)  # pupil
	return img


func _outlined_rect(img: Image, rect: Rect2i, fill: Color) -> void:
	img.fill_rect(rect, OUTLINE)
	img.fill_rect(rect.grow(-1), fill)
