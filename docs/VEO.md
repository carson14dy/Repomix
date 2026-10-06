# Veo backdrop clips

Looping video backdrops for the Wyrm's Ossuary stage, generated with the Gemini API's Veo
models, converted to Ogg Theora, and played by `prefabs/VideoBackdrop.tscn` behind the fight.

```
tools/veo_prompts.json   --veo_backdrops.py-->  assets/video/raw/<name>.mp4
                         --convert_backdrop.sh-->  assets/video/<name>.ogv + <name>_poster.png
                         --VideoBackdrop.tscn-->  CanvasLayer -10 in scenes/Main.tscn
```

## 1. Generate (`tools/veo_backdrops.py`)

Python 3.11, standard library only (`urllib`). The API key is read from the environment and is
never accepted as an argument, written to the ledger, or printed.

```bash
# Always start here: prints every request (key redacted) and the spend plan. No network.
python3 tools/veo_backdrops.py --dry-run

# Generate one clip, then review it before spending more.
export GEMINI_API_KEY=...          # or: GEMINI_API_KEY=... python3 tools/veo_backdrops.py ...
python3 tools/veo_backdrops.py --max-clips 1

# All prompts in tools/veo_prompts.json (3 clips ≈ $3.60 on the fast model).
python3 tools/veo_backdrops.py
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--prompt-file` | `tools/veo_prompts.json` | JSON list of `{"name", "prompt"}`; `name` becomes the file name |
| `--model` | `veo-3.1-fast-generate-preview` | any Veo model id; `fast` in the name selects the fast price |
| `--out` | `assets/video/raw` | where `<name>.mp4` lands (has a `.gdignore`, Godot never scans it); a clip that already exists there is skipped, not re-billed |
| `--max-clips N` | all | stop after N prompts |
| `--budget-usd` | `28` | hard cap on cumulative estimated spend (see policy) |
| `--price-per-second` | `0.15` fast / `0.40` standard | USD per generated second; override when prices change |
| `--duration` | `8` | seconds per clip (Veo 3.x accepts 4, 6 or 8) |
| `--aspect` | `16:9` | aspect ratio |
| `--ledger` | `tools/veo_spend.json` | spend ledger (only change it for tests) |
| `--dry-run` | off | print requests and plan; writes nothing, sends nothing |

Per clip the script sends
`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:predictLongRunning` with
header `x-goog-api-key` and body
`{"instances":[{"prompt":...}],"parameters":{"aspectRatio":"16:9","durationSeconds":8,"personGeneration":"dont_allow"}}`,
polls `GET v1beta/{operation.name}` every 10 s (10 min timeout), then downloads
`response.generateVideoResponse.generatedSamples[0].video.uri` (authenticated with the same
header, so the key never appears in a URL) to `assets/video/raw/<name>.mp4`.

Exit codes: `0` ok, `1` error (missing key, network/HTTP/API failure), `2` budget refusal.

### Budget policy

* The budget for backdrop generation is **$28 total**, enforced by the script, not by habit.
* Spend is *estimated* as `duration × price-per-second` and recorded in `tools/veo_spend.json`
  **before** the request is sent. A clip whose estimate would push `spent_usd` past the budget
  is refused and the run stops (exit 2) without touching the network.
* A clip that fails after it was started (API error, safety filter, timeout) stays in the ledger
  with `status: "failed"` and still counts: Google may or may not bill it, and the cap is meant
  to be conservative. If the Cloud console shows it was not billed, edit the ledger by hand and
  say so in the commit message.
* `--dry-run` never writes the ledger. Commit `tools/veo_spend.json` with the clips so the
  ledger travels with the repository.
* Check the ledger before every run: `cat tools/veo_spend.json`.

### Prompts

`tools/veo_prompts.json` holds three loop-friendly prompts (`ossuary_nave`, `ossuary_crypt`,
`ossuary_abyss`): static locked-off camera, slow-motion teal mist, bone and slate palette,
explicitly no characters, animals or text. Keep new prompts in that shape: a locked camera and
slow ambient motion are what make an 8 s clip loop without a visible seam.

### Tests

```bash
python3 -m unittest tools.test_veo_backdrops      # or: python3 -m unittest tools/test_veo_backdrops.py
```

`urllib.request.urlopen` and `time.sleep` are mocked; the tests cover budget refusal (ledger and
network untouched), ledger update on success and failure, the exact request payload, and the
dry-run output.

## 2. Convert (`tools/convert_backdrop.sh`)

```bash
tools/convert_backdrop.sh                       # every assets/video/raw/*.mp4
tools/convert_backdrop.sh assets/video/raw/ossuary_nave.mp4
$GODOT --headless --path . --import             # imports the poster PNGs
```

Each clip becomes `assets/video/<name>.ogv` (1280x720, no audio, libtheora `-q:v 7`) and
`assets/video/<name>_poster.png` (first frame, 1280x720). ffmpeg comes from `$FFMPEG` or the
static binary bundled with the `imageio_ffmpeg` Python package. Godot 4.4 loads `.ogv` directly
as `VideoStreamTheora` (no `.import` sidecar is produced; only the PNG is imported).

`assets/video/test_pattern.ogv` + `_poster.png` is a 2 s ffmpeg `testsrc` clip kept so the
Godot test suite always has a real Theora stream; replace the default paths with a real clip
when wiring.

## 3. Play (`prefabs/VideoBackdrop.tscn`, `scripts/video_backdrop.gd`)

A `CanvasLayer` at `layer -10` containing, in draw order:

* `Poster` – `TextureRect`, 1280x720, shows `poster_path`. Always visible, so there is never a
  black frame while the first video frame decodes.
* `Player` – `VideoStreamPlayer`, 1280x720, `expand`, `loop`, `autoplay`, `volume_db -80`.
  `_ready()` loads `stream_path`; when the file is missing or fails to load the player is hidden
  and the poster stays (no engine errors: the script checks `ResourceLoader.exists()` first).

Exports: `stream_path` (default `res://assets/video/test_pattern.ogv`) and `poster_path`
(default `res://assets/video/test_pattern_poster.png`).

Test: `TEST_FILTER=test_video_backdrop $GODOT --headless --path . --fixed-fps 60 --script tests/run_tests.gd`.

### WIRING NEEDED (lead)

`scenes/Main.tscn` currently has a static `BackdropLayer` (CanvasLayer -10 with the painted
`Backdrop` Sprite2D). To use a video backdrop, either replace it or put the video under it:

1. Add an ext_resource: `[ext_resource type="PackedScene" path="res://prefabs/VideoBackdrop.tscn" id="13_video_backdrop"]`
2. Add, as the **first child** of `Main` (before `BackdropLayer`):

   ```
   [node name="VideoBackdrop" parent="." instance=ExtResource("13_video_backdrop")]
   stream_path = "res://assets/video/ossuary_nave.ogv"
   poster_path = "res://assets/video/ossuary_nave_poster.png"
   ```

3. Then either delete `BackdropLayer` (the poster takes over the never-black guarantee), or keep
   it and set `VideoBackdrop.layer = -11` so the painting draws over the video while the mist
   layer stays on top. `tests/test_scenes.gd::test_ossuary_layers_are_present` asserts that
   `BackdropLayer` exists at layer -10 with the painting at scale 1.12, so deleting it needs that
   test updated too.
4. Add `assets/video/raw/*.mp4` to `.gitignore` (raw Veo output is large and not used at runtime).
