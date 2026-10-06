extends RefCounted
## The art pipeline's outputs (tools/process_art.gd + --import) are present and shaped as the
## contract says: keyed fighter sprites at their target heights, circular 96x96 portraits,
## and the painted backdrop.

const SPRITES := "res://assets/sprites/"
const BACKDROP := "res://assets/backdrops/ossuary_far.png"


func _image(ctx: TestContext, path: String) -> Image:
	var texture := load(path) as Texture2D
	ctx.check(
		texture != null, "%s loads as a Texture2D (missing PNG or .import breaks this)" % path
	)
	return texture.get_image() if texture != null else null


func test_backdrop_loads(ctx: TestContext) -> void:
	var img := _image(ctx, BACKDROP)
	if img == null:
		return
	ctx.check(img.get_size() == Vector2i(1280, 720), "backdrop is 1280x720")


func test_fighter_sprites_are_keyed_and_sized(ctx: TestContext) -> void:
	for row: Array in [["kage.png", 64], ["ignis.png", 72]]:
		var img := _image(ctx, SPRITES + String(row[0]))
		if img == null:
			continue
		ctx.check(img.get_height() == row[1], "%s is %d px tall" % [row[0], row[1]])
		ctx.check(
			img.get_pixel(0, 0).a == 0.0,
			"%s corner pixel is fully transparent (a failed chroma key breaks this)" % row[0]
		)
		var centre := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		ctx.check(centre.a == 1.0, "%s centre pixel is opaque" % row[0])


func test_portraits_are_circular_medallions(ctx: TestContext) -> void:
	for name in ["kage_portrait.png", "ignis_portrait.png"]:
		var img := _image(ctx, SPRITES + name)
		if img == null:
			continue
		ctx.check(img.get_size() == Vector2i(96, 96), "%s is 96x96" % name)
		ctx.check(img.get_pixel(0, 0).a == 0.0, "%s is transparent outside the circle" % name)
		ctx.check(img.get_pixel(48, 48).a == 1.0, "%s is opaque at its centre" % name)
