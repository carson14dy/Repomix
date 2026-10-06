class_name Sfx
extends Node
## Procedural sound effects. Every sample is synthesized once in _ready (44100 Hz, 16-bit
## mono) from a RandomNumberGenerator seeded by `seed`, so the same seed always renders the
## same bytes. The render_* functions are pure and static so tests can inspect samples
## without an audio device; the AudioStreamPlayer children of prefabs/Sfx.tscn are the
## voices, picked first-idle-else-oldest for polyphony.

const SAMPLE_RATE := 44100

const SWING_SECONDS := 0.12
const HIT_LIGHT_SECONDS := 0.10
const HIT_HEAVY_SECONDS := 0.22
const JUMP_SECONDS := 0.14
const LAND_SECONDS := 0.08
const KO_SECONDS := 0.6

@export var seed: int = 7
@export var master_volume_db: float = -6.0

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
## Per-voice start order; the smallest value is the oldest voice to steal.
var _started: Array[int] = []
var _play_counter: int = 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_streams = {
		"swing": to_wav(render_swing(rng)),
		"hit_light": to_wav(render_hit(false, rng)),
		"hit_heavy": to_wav(render_hit(true, rng)),
		"jump": to_wav(render_jump()),
		"land": to_wav(render_land(rng)),
		"ko": to_wav(render_ko(rng)),
	}
	for child in get_children():
		if child is AudioStreamPlayer:
			child.volume_db = master_volume_db
			_voices.append(child)
			_started.append(0)
	if _voices.is_empty():
		push_error("Sfx has no AudioStreamPlayer children; use prefabs/Sfx.tscn")


func play_swing() -> void:
	_play("swing")


func play_hit(strong: bool) -> void:
	_play("hit_heavy" if strong else "hit_light")


func play_jump() -> void:
	_play("jump")


func play_land() -> void:
	_play("land")


func play_ko() -> void:
	_play("ko")


func _play(stream_name: String) -> void:
	if _voices.is_empty():
		return
	var pick := -1
	for i in _voices.size():
		if not _voices[i].playing:
			pick = i
			break
		if pick < 0 or _started[i] < _started[pick]:
			pick = i
	_play_counter += 1
	_started[pick] = _play_counter
	_voices[pick].stream = _streams[stream_name]
	_voices[pick].play()


## 0.12 s band-passed noise whoosh: 10 ms attack, then a fast exponential fade.
static func render_swing(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _noise(SWING_SECONDS, rng)
	samples = _band_pass(samples, 1400.0, 1.2)
	for i in samples.size():
		var t := float(i) / SAMPLE_RATE
		samples[i] *= minf(1.0, t / 0.01) * exp(-t * 30.0)
	return _normalize(samples, 0.8)


## Light (0.10 s): noise burst + 160 Hz thump, exponential decay. Heavy (0.22 s): a 90 Hz
## thump whose pitch drops from 210 Hz over the first ~60 ms, plus noise, slower decay.
## No attack ramp: a hit must be audible from its very first sample.
static func render_hit(strong: bool, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds := HIT_HEAVY_SECONDS if strong else HIT_LIGHT_SECONDS
	var samples := _noise(seconds, rng)
	var phase := 0.0
	for i in samples.size():
		var t := float(i) / SAMPLE_RATE
		var hz := 90.0 + 120.0 * exp(-t / 0.03) if strong else 160.0
		phase += TAU * hz / SAMPLE_RATE
		var decay := exp(-t * (18.0 if strong else 40.0))
		samples[i] = (0.6 * samples[i] + sin(phase)) * decay
	return _normalize(samples, 0.95)


## 0.14 s sine sweep rising linearly from 220 Hz to 660 Hz, 5 ms attack, 40 ms release.
static func render_jump() -> PackedFloat32Array:
	var count := _sample_count(JUMP_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var hz := lerpf(220.0, 660.0, t / JUMP_SECONDS)
		phase += TAU * hz / SAMPLE_RATE
		var env := minf(1.0, t / 0.005) * minf(1.0, (JUMP_SECONDS - t) / 0.04)
		samples[i] = 0.6 * sin(phase) * env
	return samples


## 0.08 s low-passed noise thud with a fast exponential decay.
static func render_land(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _low_pass(_noise(LAND_SECONDS, rng), 300.0, 0.9)
	for i in samples.size():
		samples[i] *= exp(-float(i) / SAMPLE_RATE * 45.0)
	return _normalize(samples, 0.7)


## 0.6 s boom: 60 Hz sine under low-passed noise, 5 ms attack, slow exponential decay.
static func render_ko(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _low_pass(_noise(KO_SECONDS, rng), 500.0, 0.8)
	var phase := 0.0
	for i in samples.size():
		var t := float(i) / SAMPLE_RATE
		phase += TAU * 60.0 / SAMPLE_RATE
		var env := minf(1.0, t / 0.005) * exp(-t * 5.0)
		samples[i] = (0.8 * sin(phase) + 0.5 * samples[i]) * env
	return _normalize(samples, 0.95)


## Clamp to [-1, 1] and pack as 16-bit little-endian PCM at 44100 Hz mono.
static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## roundi, not int(): 0.12 * 44100 is 5291.999... in binary floating point.
static func _sample_count(seconds: float) -> int:
	return roundi(seconds * SAMPLE_RATE)


static func _noise(seconds: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(_sample_count(seconds))
	for i in samples.size():
		samples[i] = rng.randf_range(-1.0, 1.0)
	return samples


static func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var current := 0.0
	for v in samples:
		current = maxf(current, absf(v))
	if current > 0.0:
		for i in samples.size():
			samples[i] *= peak / current
	return samples


## RBJ cookbook biquads (constant-skirt band-pass, low-pass).
static func _band_pass(samples: PackedFloat32Array, hz: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * hz / SAMPLE_RATE
	var alpha := sin(w0) / (2.0 * q)
	return _biquad(samples, [alpha, 0.0, -alpha, 1.0 + alpha, -2.0 * cos(w0), 1.0 - alpha])


static func _low_pass(samples: PackedFloat32Array, hz: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * hz / SAMPLE_RATE
	var alpha := sin(w0) / (2.0 * q)
	var b1 := 1.0 - cos(w0)
	return _biquad(samples, [b1 / 2.0, b1, b1 / 2.0, 1.0 + alpha, -2.0 * cos(w0), 1.0 - alpha])


## Direct form I; `c` is [b0, b1, b2, a0, a1, a2].
static func _biquad(samples: PackedFloat32Array, c: Array[float]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in samples.size():
		var x0 := samples[i]
		var y0 := (c[0] * x0 + c[1] * x1 + c[2] * x2 - c[4] * y1 - c[5] * y2) / c[3]
		out[i] = y0
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
	return out
