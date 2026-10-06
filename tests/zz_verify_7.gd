extends SceneTree
## Throwaway verifier for VF-3: crop the fighters out of the screenshots at 4x. Deleted after use.

const OUT := "/tmp/claude-0/-home-user-Repomix/a68f15bc-b3dc-5fdc-ab0e-d11ddbe877bc/scratchpad/"


func _crop(src: String, rect: Rect2i, out: String) -> void:
	var img := Image.load_from_file(src)
	var region := img.get_region(rect)
	region.resize(rect.size.x * 4, rect.size.y * 4, Image.INTERPOLATE_NEAREST)
	region.save_png(out)
	print("wrote ", out, " ", region.get_size())


func _init() -> void:
	# Both fighters in the main shot (spawn framing).
	_crop("docs/screenshot-main.png", Rect2i(420, 480, 440, 200), OUT + "vf3_main_fighters_4x.png")
	# Zoomed-out shot: fighters at ~0.72 zoom (rows dropped rather than doubled).
	_crop("docs/screenshot-zoom.png", Rect2i(120, 440, 1040, 200), OUT + "vf3_zoom_fighters_4x.png")
	quit()
