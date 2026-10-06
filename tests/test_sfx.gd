extends RefCounted
## Sfx: deterministic sample rendering (lengths, loudness, onsets, the jump sweep), the
## 16-bit WAV packing, and the six-voice prefab playing under the headless Dummy driver.
##
## Dummy driver facts (measured with a probe): play() is accepted and `playing` reads true
## at once; the driver mixes in real time on its own thread (~11.6 ms per 512-frame buffer),
## so a voice does finish on its own after its wall-clock length. A --fixed-fps headless frame
## takes well under a millisecond of wall-clock, so a 0.22 s hit is still playing one frame
## later. Stopped playbacks leave the AudioServer list only on a mix step, hence _drain().
## Nodes added at process frame 0 are not inside the tree yet (_ready has not run), so each
## prefab test steps one frame before touching the voices.

const SFX_SCENE_PATH := "res://prefabs/Sfx.tscn"
## 2 ms at 44100 Hz.
const ONSET_SAMPLES := 88


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Every render_* keyed by name, each with a fresh seeded rng so rows are independent.
func _renders() -> Dictionary:
	return {
		"swing": Sfx.render_swing(_rng()),
		"hit_light": Sfx.render_hit(false, _rng()),
		"hit_heavy": Sfx.render_hit(true, _rng()),
		"jump": Sfx.render_jump(),
		"land": Sfx.render_land(_rng()),
		"ko": Sfx.render_ko(_rng()),
	}


func _peak(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	return peak


func _zero_crossings(samples: PackedFloat32Array, from: int, to: int) -> int:
	var count := 0
	for i in range(from + 1, to):
		if (samples[i - 1] < 0.0) != (samples[i] < 0.0):
			count += 1
	return count


func test_render_sample_counts(ctx: TestContext) -> void:
	# Hand-derived: seconds * 44100.
	var want := {
		"swing": 5292,
		"hit_light": 4410,
		"hit_heavy": 9702,
		"jump": 6174,
		"land": 3528,
		"ko": 26460,
	}
	var renders := _renders()
	for name: String in want:
		var got: int = renders[name].size()
		ctx.check(got == want[name], "%s renders %d samples (got %d)" % [name, want[name], got])
	await ctx.step(1)


func test_peak_amplitude_in_range(ctx: TestContext) -> void:
	var renders := _renders()
	for name: String in renders:
		var peak := _peak(renders[name])
		ctx.check(peak >= 0.3 and peak <= 1.0, "%s peak %.3f is within [0.3, 1.0]" % [name, peak])
	await ctx.step(1)


func test_hits_are_loud_from_the_first_2ms(ctx: TestContext) -> void:
	for strong: bool in [false, true]:
		var samples := Sfx.render_hit(strong, _rng())
		var onset := _peak(samples.slice(0, ONSET_SAMPLES))
		ctx.check(onset > 0.2, "hit strong=%s first 2 ms peak %.3f is non-silent" % [strong, onset])
	await ctx.step(1)


func test_jump_sweep_pitch_rises(ctx: TestContext) -> void:
	var samples := Sfx.render_jump()
	var quarter := samples.size() / 4
	var first := _zero_crossings(samples, 0, quarter)
	var last := _zero_crossings(samples, samples.size() - quarter, samples.size())
	# 220->660 Hz linear over 0.14 s: 9.625 cycles in the first quarter, 21.175 in the last.
	ctx.check_near(first, 19, 2, "first-quarter zero crossings (~2 per cycle)")
	ctx.check_near(last, 42, 2, "last-quarter zero crossings")
	ctx.check(last > first, "the sweep rises: %d -> %d crossings" % [first, last])
	await ctx.step(1)


func test_render_is_deterministic_for_a_seed(ctx: TestContext) -> void:
	var first := Sfx.render_hit(true, _rng(7))
	var again := Sfx.render_hit(true, _rng(7))
	var other := Sfx.render_hit(true, _rng(8))
	ctx.check(first == again, "the same seed renders identical samples")
	ctx.check(first != other, "a different seed renders different noise")
	await ctx.step(1)


func test_to_wav_format_and_length(ctx: TestContext) -> void:
	var want_seconds := {
		"swing": 0.12, "hit_light": 0.10, "hit_heavy": 0.22, "jump": 0.14, "land": 0.08, "ko": 0.6
	}
	var renders := _renders()
	for name: String in want_seconds:
		var stream := Sfx.to_wav(renders[name])
		ctx.check_near(stream.get_length(), want_seconds[name], 0.001, "%s wav length" % name)
	var stream := Sfx.to_wav(renders["ko"])
	ctx.check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "wav is 16-bit")
	ctx.check(stream.mix_rate == 44100 and not stream.stereo, "wav is 44100 Hz mono")
	ctx.check(stream.data.size() == 26460 * 2, "ko wav holds 2 bytes per sample")
	# Clamping: 2.0 is clamped to 1.0 (32767) and -2.0 to -1.0 (-32767, symmetric scale).
	var clipped := Sfx.to_wav(PackedFloat32Array([2.0, -2.0, 0.5]))
	ctx.check(clipped.data.decode_s16(0) == 32767, "+2.0 clamps to 32767")
	ctx.check(clipped.data.decode_s16(2) == -32767, "-2.0 clamps to -32767")
	ctx.check(clipped.data.decode_s16(4) == 16384, "0.5 packs to 16384")
	await ctx.step(1)


func _voices(sfx: Node) -> Array[AudioStreamPlayer]:
	var voices: Array[AudioStreamPlayer] = []
	for child in sfx.get_children():
		if child is AudioStreamPlayer:
			voices.append(child)
	return voices


## Stop every voice and give the Dummy mixer thread a few buffer periods of wall-clock to
## erase the stopped playbacks, then one frame for AudioServer.update() to free them.
## Without this the run ends with "ObjectDB instances leaked" (AudioStreamPlaybackWAV).
func _drain(ctx: TestContext, voices: Array[AudioStreamPlayer]) -> void:
	for v in voices:
		v.stop()
	OS.delay_msec(50)
	await ctx.step(1)


func test_prefab_plays_under_dummy_driver(ctx: TestContext) -> void:
	var sfx := ctx.add(load(SFX_SCENE_PATH).instantiate()) as Sfx
	var voices := _voices(sfx)
	ctx.check(
		voices.size() == 6, "Sfx.tscn has 6 AudioStreamPlayer voices (got %d)" % voices.size()
	)
	# volume_db is applied in _ready, which has not run at frame 0: check it after a step so
	# this test does not depend on an earlier test having advanced the tree.
	await ctx.step(1)
	ctx.check(
		voices.all(func(v: AudioStreamPlayer) -> bool: return v.volume_db == -6.0),
		"every voice starts at master_volume_db (-6 dB)"
	)
	sfx.play_hit(true)
	await ctx.step(1)
	var playing := voices.filter(func(v: AudioStreamPlayer) -> bool: return v.playing)
	ctx.check(
		playing.size() == 1, "one voice is playing a frame after play_hit (got %d)" % playing.size()
	)
	if playing.size() == 1:
		var stream := playing[0].stream as AudioStreamWAV
		ctx.check(
			stream != null and absf(stream.get_length() - 0.22) <= 0.001,
			"the playing voice holds the 0.22 s heavy hit"
		)
	await _drain(ctx, voices)


func test_polyphony_fills_idle_voices_then_steals_oldest(ctx: TestContext) -> void:
	var sfx := ctx.add(load(SFX_SCENE_PATH).instantiate()) as Sfx
	var voices := _voices(sfx)
	await ctx.step(1)
	sfx.play_ko()
	sfx.play_ko()
	sfx.play_ko()
	sfx.play_ko()
	sfx.play_ko()
	sfx.play_ko()
	await ctx.step(1)
	var playing := voices.filter(func(v: AudioStreamPlayer) -> bool: return v.playing)
	ctx.check(
		playing.size() == 6,
		"six overlapping ko sounds use all six voices (got %d)" % playing.size()
	)
	# A seventh sound steals the oldest voice (the first one started) instead of erroring.
	sfx.play_swing()
	await ctx.step(1)
	var first := voices[0].stream as AudioStreamWAV
	ctx.check(
		first != null and absf(first.get_length() - 0.12) <= 0.001,
		"the seventh sound replaced the oldest voice's stream with the 0.12 s swing"
	)
	await _drain(ctx, voices)
