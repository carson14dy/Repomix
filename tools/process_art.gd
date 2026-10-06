extends SceneTree
## Art pipeline: turns the Gemini-generated sources in assets/art-src/ into game-ready PNGs.
##
##   assets/backdrops/ossuary_far.png        copy of the painted 1280x720 backdrop
##   assets/sprites/kage.png (64 px tall)    chroma-keyed, despilled, cropped, Lanczos-resized
##   assets/sprites/ignis.png (72 px tall)   same; both face RIGHT like the sources
##   assets/sprites/<name>_portrait.png      96x96 circular medallion portrait of the head
##
## Run:  $GODOT --headless --path . --script tools/process_art.gd
## then: $GODOT --headless --path . --import   (writes the .import sidecars)

const SRC_DIR := "res://assets/art-src/"
const BACKDROP_SRC := SRC_DIR + "ossuary_far_1280x720.png"
const BACKDROP_OUT := "res://assets/backdrops/ossuary_far.png"
const SPRITE_DIR := "res://assets/sprites/"

## name -> [source file, target sprite height in px]
const FIGHTERS := {
	"kage": ["kage_magenta_1024.png", 64],
	"ignis": ["ignis_magenta_1024.png", 72],
}

## Distance (RGB 0..255 space) to the key colour: transparent at or below KEY_FULL,
## opaque at or above KEY_FULL + KEY_RAMP. The key colour itself is sampled from the
## source's corners: the generated "magenta" is really a hot pink near (228, 39, 146) for
## Kage and (221, 38, 128) for Ignis, 115-135 away from pure #FF00FF, so keying against
## the literal magenta would leave the whole background 70-90% opaque.
const KEY_FULL := 70.0
const KEY_RAMP := 60.0
const KEY_SAMPLE := 16
const DESPILL_RADIUS := 2
const CROP_MARGIN := 2
const PORTRAIT_SIZE := 96
const PORTRAIT_RADIUS := 46.0
## Fraction of the cropped sprite's height that holds the head.
const HEAD_BAND := 0.32


func _initialize() -> void:
	var backdrop := _load(BACKDROP_SRC)
	if backdrop == null:
		return
	if not _save(backdrop, BACKDROP_OUT):
		return
	for fighter_name: String in FIGHTERS:
		var source := _load(SRC_DIR + String(FIGHTERS[fighter_name][0]))
		if source == null:
			return
		var keyed := _chroma_key(source)
		_despill(keyed)
		var cropped := _crop(keyed)
		var portrait := _portrait(cropped)
		var target_height: int = FIGHTERS[fighter_name][1]
		var sprite := _resize_to_height(cropped, target_height)
		if not _save(sprite, SPRITE_DIR + fighter_name + ".png"):
			return
		if not _save(portrait, SPRITE_DIR + fighter_name + "_portrait.png"):
			return
	quit(0)


func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		push_error("Failed to load %s" % path)
		quit(1)
	return img


func _save(img: Image, path: String) -> bool:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
		quit(1)
		return false
	print("wrote %s %dx%d" % [path, img.get_width(), img.get_height()])
	return true


## Alpha from the RGB distance to the sampled key colour, plus a hard cut for any other
## magenta-hued pixel (low green, high red, pinkish blue): the darker ground shadow under
## Ignis' feet is (170, 32, 102), which the distance ramp alone would keep half-opaque.
func _chroma_key(source: Image) -> Image:
	var img := Image.new()
	img.copy_from(source)
	img.convert(Image.FORMAT_RGBA8)
	var key := _sample_key(img)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var d := Vector3(c.r8 - key.r8, c.g8 - key.g8, c.b8 - key.b8).length()
			var a := clampf((d - KEY_FULL) / KEY_RAMP, 0.0, 1.0)
			if c.g8 < 90 and c.r8 > 150 and c.b8 > 90:
				a = 0.0
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return img


## Mean colour of the four KEY_SAMPLE-square corner patches (the fighter never touches them).
func _sample_key(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var w := img.get_width()
	var h := img.get_height()
	for corner: Vector2i in [
		Vector2i.ZERO,
		Vector2i(w - KEY_SAMPLE, 0),
		Vector2i(0, h - KEY_SAMPLE),
		Vector2i(w, h) - Vector2i.ONE * KEY_SAMPLE
	]:
		for y in range(corner.y, corner.y + KEY_SAMPLE):
			for x in range(corner.x, corner.x + KEY_SAMPLE):
				sum += img.get_pixel(x, y)
	var count := 4 * KEY_SAMPLE * KEY_SAMPLE
	return Color(sum.r / count, sum.g / count, sum.b / count)


## Edge pixels (alpha < 1) take the average colour of the fully opaque, non-pink pixels
## within DESPILL_RADIUS, so no magenta fringe survives the key. Opaque pixels that touch a
## keyed pixel and still lean pink (anti-aliased outline mixed with background) get the same
## treatment. Fully transparent pixels matter too: Image.resize interpolates straight (not
## premultiplied) RGBA, so pink RGB under alpha 0 would bleed back in at the edges; those with
## no opaque neighbour become OUTLINE. Reads from a copy so the pass order does not matter.
func _despill(img: Image) -> void:
	var ref := Image.new()
	ref.copy_from(img)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := ref.get_pixel(x, y)
			if c.a >= 1.0 and not (_is_pinkish(c) and _touches_keyed(ref, x, y)):
				continue
			var sum := Color(0, 0, 0, 0)
			var count := 0
			for ny in range(maxi(0, y - DESPILL_RADIUS), mini(h, y + DESPILL_RADIUS + 1)):
				for nx in range(maxi(0, x - DESPILL_RADIUS), mini(w, x + DESPILL_RADIUS + 1)):
					var n := ref.get_pixel(nx, ny)
					if n.a >= 1.0 and not _is_pinkish(n):
						sum += n
						count += 1
			if count > 0:
				img.set_pixel(x, y, Color(sum.r / count, sum.g / count, sum.b / count, c.a))
			elif c.a <= 0.0:
				img.set_pixel(x, y, Color(BrawlTheme.OUTLINE, 0.0))


func _is_pinkish(c: Color) -> bool:
	return c.r8 > c.g8 + 30 and c.b8 > c.g8 + 15


func _touches_keyed(img: Image, x: int, y: int) -> bool:
	for ny in range(maxi(0, y - DESPILL_RADIUS), mini(img.get_height(), y + DESPILL_RADIUS + 1)):
		for nx in range(maxi(0, x - DESPILL_RADIUS), mini(img.get_width(), x + DESPILL_RADIUS + 1)):
			if img.get_pixel(nx, ny).a < 1.0:
				return true
	return false


## Crop to the opaque bounds plus a transparent CROP_MARGIN on every side.
func _crop(img: Image) -> Image:
	var used := img.get_used_rect()
	var out := Image.create(
		used.size.x + 2 * CROP_MARGIN, used.size.y + 2 * CROP_MARGIN, false, Image.FORMAT_RGBA8
	)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, used, Vector2i(CROP_MARGIN, CROP_MARGIN))
	return out


func _resize_to_height(img: Image, height: int) -> Image:
	var out := Image.new()
	out.copy_from(img)
	var width := maxi(1, roundi(float(img.get_width()) * height / img.get_height()))
	out.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return out


## Head band = top HEAD_BAND of the sprite; a square of that height is centred on the
## opaque pixels of the band, resized to PORTRAIT_SIZE, composited over SLATE inside the
## medallion circle and cleared outside it.
func _portrait(sprite: Image) -> Image:
	var band_h := maxi(1, roundi(sprite.get_height() * HEAD_BAND))
	var opaque_min := sprite.get_width()
	var opaque_max := -1
	for y in range(band_h):
		for x in range(sprite.get_width()):
			if sprite.get_pixel(x, y).a >= 0.5:
				opaque_min = mini(opaque_min, x)
				opaque_max = maxi(opaque_max, x)
	var centre_x := sprite.get_width() / 2
	if opaque_max >= opaque_min:
		centre_x = (opaque_min + opaque_max) / 2
	var left := clampi(centre_x - band_h / 2, 0, maxi(0, sprite.get_width() - band_h))
	var square := Image.create(band_h, band_h, false, Image.FORMAT_RGBA8)
	square.fill(Color(0, 0, 0, 0))
	square.blit_rect(sprite, Rect2i(left, 0, band_h, band_h), Vector2i.ZERO)
	square.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
	var centre := Vector2(PORTRAIT_SIZE / 2.0, PORTRAIT_SIZE / 2.0)
	for y in range(PORTRAIT_SIZE):
		for x in range(PORTRAIT_SIZE):
			if Vector2(x + 0.5, y + 0.5).distance_to(centre) > PORTRAIT_RADIUS:
				square.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				square.set_pixel(x, y, BrawlTheme.SLATE.blend(square.get_pixel(x, y)))
	return square
