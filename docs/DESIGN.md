# BrawlCrypt — Game Design Reference

Status key: **Implemented** = in the repository today, covered by a scene file or a headless
test; **Planned** = agreed direction, not yet in code. Every number in an Implemented section is
copied from the file named beside it. Units: px, px/s, px/s² and physics frames at 60 Hz
(`physics/common/physics_ticks_per_second=60` in `project.godot`).

Sources of truth, in order: `scripts/*.gd` and `scenes/Main.tscn`, `README.md`, and the user's
web prototype (`characters.ts`, `game.ts`, `physics.ts`, `ai.ts`) for everything Planned.

---

## 1. Concept and pillars

BrawlCrypt is a local-multiplayer 2D gothic platform fighter for Godot 4.4 (GDScript, GL
Compatibility, 1280x720 `canvas_items` stretch). Two fighters brawl on the spine of a dead
dragon; hits add damage percentage, knockback grows with percentage, and a match is won by
ringing the opponent out. The genre is inspired by platform fighters such as Brawlhalla; every
name, sprite, sound and line of code here is original.

1. **Two buttons, deep movement.** Left/right, jump, down, attack. Depth comes from momentum,
   fast-falling, spacing and the percentage curve, not a command list.
2. **Readable at a glance.** Bone white over teal-grey; cyan for Player 1, crimson for Player 2
   in sprite tint, slash, spark and HUD. Damage read-outs change colour at fixed thresholds.
3. **Feel first.** Every hit freezes both fighters (hitstop), shakes the camera in proportion
   and bursts a spark in the attacker's colour. Motion answers a player action; the only idle
   motion is the drifting mist.
4. **Deterministic and testable.** Fighters read InputMap actions only, the bot presses the same
   actions, every random choice that affects play comes from a seeded RNG (the camera shake
   offset in `fight_camera.gd` is the one unseeded, purely cosmetic exception), and every
   tunable is an `@export` with a hand-derived expected value in `tests/`.
5. **Local only.** One keyboard or two joypads. No online play is planned.

---

## 2. Roster

The three fighters cover the classic triangle: fast/light, slow/heavy, aerial/floaty.

### 2.1 Stat cards (Planned; from the prototype `characters.ts`)

Prototype units are relative. The Godot port has one shared tunable set today (section 3);
per-fighter values will arrive as overrides on those exports.

| Fighter | Title | Colour | Proto speed / jump / weight / jumps | Stats S/P/D/R | Proposed `run_speed` | Weight |
| ------- | ----- | ------ | ----------------------------------- | ------------- | -------------------- | ------ |
| Kage   | The Shadow Weaver        | cyan `#38bdf8`    | 7.2 / 13.8 / 85 / 2  | 9 / 6 / 5 / 9  | 380 | 85  |
| Ignis  | The Spectral Dreadnought | crimson `#ef4444` | 5.2 / 12.0 / 125 / 2 | 5 / 9 / 9 / 5  | 275 | 125 |
| Zephyr | The Tempest Valkyrie     | teal `#2dd4bf`    | 6.4 / 13.2 / 95 / 3  | 7 / 7 / 6 / 10 | 340 | 95  |

Proposed speeds scale the current 340 by the prototype ratio (340 × 7.2 / 6.4 ≈ 382,
340 × 5.2 / 6.4 ≈ 276), rounded. Weight enters knockback as `100 / weight` (section 4.3).

### 2.2 Kage — sprite Implemented, moveset Planned

Hooded assassin woven from the twilight mist under the dragon bones. `assets/sprites/kage.png`
57x64, `kage_portrait.png` 96x96; always Player 1 today (`player.gd` swaps to the Ignis texture
only for `player_index == 2`). Fastest run, highest jump, lightest; multi-hit strings that rack
percentage fast but launch late.

* Normals: twin shadow knives, short reach, low base knockback, fast recovery.
* **Veil Step**: a 12-frame phantom dash through the opponent leaving a cyan afterimage;
  frames 3–8 intangible; no damage, pure repositioning.
* **Twilight Fan**: three shadow knives in a fan, 3 × 3% with weak fixed knockback; the last
  pops the target up for a follow-up.

### 2.3 Ignis — sprite Implemented, moveset Planned

Colossal sentinel in blackened plate lit by crimson soul-fire. `assets/sprites/ignis.png`
66x72, `ignis_portrait.png` 96x96; always Player 2 today. Slow, heavy, ends stocks early.

* Normals: greatsword sweeps, long reach, high base knockback, long recovery.
* **Pyre Cleave**: overhead slam, 14 startup frames; on contact a 120 px fire pillar rises
  for 10 frames and launches at 70°. Highest base knockback in the game.
* **Bulwark Flare**: shoulder charge with super armour for its first 10 frames (takes
  percentage, ignores knockback), then a flare burst that launches horizontally.

### 2.4 Zephyr — Planned, no assets yet

Winged duelist from the tempests that howl through the ossuary cliffs; gale lance. Three jumps,
floaty descent, the longest poke. Sprite follows the Kage/Ignis pipeline at 68 px tall.

* Normals: lance thrusts, narrow long hitboxes, mid knockback.
* **Gale Lance**: a 160 px forward thrust that carries Zephyr with it; horizontal recovery.
* **Updraft**: a rising spiral lifting Zephyr 200 px and dragging an adjacent opponent along;
  vertical recovery and combo starter.

---

## 3. Movement (Implemented, `scripts/player.gd`)

All values are `@export` defaults on `Player`, overridable per instance.

| Tunable | Value | Unit | Design intent |
| ------- | ----- | ---- | ------------- |
| `run_speed` | 340.0 | px/s | Crossing the 900 px spine takes ~2.6 s: spacing matters, nobody camps. |
| `ground_acceleration` | 2600.0 | px/s² | 0 → 340 in 0.13 s (~8 frames): snappy turns, not instant velocity. |
| `ground_friction` | 2400.0 | px/s² | 340 → 0 in 0.14 s (~9 frames): a short skid sells weight. |
| `air_acceleration` | 1300.0 | px/s² | 0 → 340 in 0.26 s: jump arcs commit but can be bent. |
| `air_friction` | 320.0 | px/s² | Only with no air input; 340 → 0 takes 1.06 s, so a neutral jump drifts rather than stalls. |
| `gravity` | 1500.0 | px/s² | Heavy arcade gravity. |
| `max_fall_speed` | 900.0 | px/s | Terminal velocity, reached 0.6 s after the apex. |
| `fast_fall_gravity_multiplier` | 2.5 | × | Down while `velocity.y >= 0` gives 3750 px/s²; never cuts a rising jump short. |
| `fast_fall_max_speed` | 1500.0 | px/s | Fast-fall terminal velocity. |
| `jump_velocity` | -620.0 | px/s | Hand-derived apex ~133 px after 25 rising frames (continuous 620² / 2·1500 = 128 px). |
| `jump_buffer_frames` | 6 | frames | A press up to 100 ms before landing still fires on landing. |
| `respawn_below_y` | 1200.0 | px | Falling past this respawns at the spawn point with 0% (replaced by blast zones, 4.4). |

Rules that are code, not numbers:

* Presses are edge-detected from `Input.is_action_pressed` (`_just_pressed`) because Godot 4.4
  reports `is_action_just_pressed` one physics frame late. A button held through hitstop or
  knockback never counts as a fresh press.
* Facing follows the last non-zero horizontal input in `State.NORMAL`; `Hitbox.set_facing`
  mirrors the hitbox, `fighter_visual.gd` flips the sprite.
* Movement is **not** locked during an attack (decision in `_apply_attack`): a two-button game
  needs the fighter to stay responsive.
* Fighters sit on physics layer 2 and collide only with layer 1 (world), so they pass through
  each other; hitboxes are on layer 3 and scan layer 2.

Tuning note (hand-derived): the shard tops (y 460) are 136 px above the spine top (y 596) and
one jump rises ~133 px, so reaching a shard from the spine in one jump is marginal today; the
Planned double jump (4.5) makes the shards a real second storey.

---

## 4. Combat

### 4.1 Implemented: percentage and knockback (`player.gd`, `hitbox.gd`)

`take_damage(base_knockback, direction, damage_amount = 10.0)`:

```
percentage += damage_amount
actual_knockback = base_knockback * (percentage / 10.0)   # percentage AFTER this hit
velocity = normalize(direction) * actual_knockback        # zero direction -> Vector2.UP
enter KNOCKBACK, emit percentage_changed
```

The hitbox launches the victim away from the attacker with a fixed lift,
`normalize(±1, -0.75) = (±0.8, -0.6)`, and resolves hits with `call_deferred` at the end of
the tick so a same-frame trade hits both fighters.

Launch speed of the default attack (`attack_damage` 8, `attack_base_knockback` 260):

| Victim % after hit | Speed | (x, y) |
| --- | --- | --- |
| 8   | 208  | (166.4, -124.8) |
| 40  | 1040 | (832, -624) |
| 80  | 2080 | (1664, -1248) |
| 120 | 3120 | (2496, -1872) |

`State.KNOCKBACK` lasts `knockback_stun_frames` **20**: no input, gravity only (no air
friction, so a launch is never damped), grounded knockback slides out under `ground_friction`,
tint `Color(1.0, 0.6, 0.6)`. Being hit cancels an attack in progress and disables the hitbox.

### 4.2 Implemented: attack frame data

| Phase | Frames | Notes |
| ----- | ------ | ----- |
| Startup | `attack_startup_frames` 3 | `attack_started` fires on frame 1 (slash VFX). |
| Active | `attack_active_frames` 6 | Hitbox 40x32 at (26·facing, -8): reaches 6..46 px ahead, y -24..8; one hit per opponent per activation. |
| Recovery | `attack_recovery_frames` 10 | No new attack until the counter hits 0. |
| **Total** | **19** | `attack_damage` 8.0 %, `attack_base_knockback` 260 px/s. |

**Hitstop** (`hitstop_frames` 5): on contact attacker and victim freeze for 5 frames (longest
pending freeze wins); velocity, stun and attack counters pause, and the hitbox keeps its own
counter so it never resumes a frame early.

### 4.3 Planned: scaled knockback, hitstun and hitstop (from `physics.ts`)

Per-attack `baseKnockback`, `knockbackScaling`, `angle`, `hitstun`; per-fighter weight:

```
knockback = (baseKnockback + percentage * knockbackScaling * 0.08) * (100 / weight)
hitstun   = floor(knockback * 1.5 + attackHitstun)      # replaces the fixed 20 frames
hitstop   = clamp(floor(damage * 0.7), 4, 14)          # replaces the fixed 5 frames
percentage capped at 999, rounded to 0.1; angle mirrored (180 - angle) when facing left
```

`base * (percentage / 10)` stays as the fallback for attacks without scaling so the existing
test literals hold.

### 4.4 Planned: stocks and KO flow

* **3 stocks** each (prototype default), shown as pips under each medallion.
* **Blast zones** = the camera limits already in `Main.tscn`: left **-200**, right **1480**,
  top **-240**, bottom **960**. Crossing one KOs the fighter: KO boom, a flash in the fighter's
  colour at the crossing, camera shake 12 for 12 frames, one stock removed.
* **Respawn**: after a 60-frame pause the fighter appears at 0% on a bone **respawn platform**
  120 px above its spawn point (held up to 120 frames or until any input), then
  **60 frames of invulnerability**, drawn as a bone-white shimmer.
* **Match end**: at 0 stocks the sim stops after 30 frames, the camera zooms to `max_zoom` on
  the winner, and the Victory screen shows damage dealt, KOs and highest combo.

### 4.5 Planned: defensive options

* **Dodge**: down + jump grounded, or attack while holding down in the air. 22 frames with
  **8 intangible frames** (3–10), 40-frame cooldown, afterimage in the player colour. Grounded:
  a 120 px roll. Air: a 160 px dash in the stick direction, once per airtime.
* **Double jump**: `max_jumps` 2 (Zephyr 3), restored on landing, consumed by an air dodge.
* **Drop-through**: down held 2 frames on a shard disables that collision for 10 frames.
* Shields exist in the prototype but are **cut**: two buttons, and the dodge is the defence.

### 4.6 Planned: weapons

Last on the roadmap. A pickup drifts down on a bone shard every 20 s, lands on a random
platform, and swaps the holder's normals and signatures for that weapon's set (lance,
greatsword, knives). Dropped on KO.

---

## 5. Stage design

### 5.1 Wyrm's Ossuary — Implemented (`scenes/Main.tscn`, `scripts/stage_art.gd`)

| Element | Geometry | Notes |
| ------- | -------- | ----- |
| Floor (dragon spine) | `StaticBody2D` at (640, 620), shape 900x48: x **190..1090**, top **y 596** | Bone slab, 11 vertebrae (first x 230, spacing 80), 9 front ribs to y 800, 4 inner ribs, cracks, chipped ends. |
| Left shard | `Platform.tscn` at (380, 470), 240x20 one-way: x 260..500, top y 460 | Three teeth hang under it. |
| Right shard | `Platform.tscn` at (900, 470), 240x20 one-way: x 780..1020, top y 460 | Same. |
| Spawns | P1 (520, 540) facing right; P2 (760, 540) facing left | Fall 28 px onto the spine. |
| Camera limits | (-200, -240)..(1480, 960) | Become the blast zones (4.4). |

The test floor from `TestContext.make_floor` is 1200x40 with its top at y 580; the bot's
default `stage_top_y` 580 matches the tests, while the Main floor top is 596.

Art layers, back to front: `BackdropLayer` (CanvasLayer -10; painted skull `ossuary_far.png`
at scale 1.12, modulate (0.82, 0.88, 0.92), scrolled by `main.gd` at parallax 0.06) →
`StageArt` (static `_draw`, ~120 calls) → `Mist` (three teal blobs, radii 210/270/190, peak
alpha 0.16/0.18/0.13, sine drift) → fighters with ground shadows → `Vfx` (z 5) →
`VignetteLayer` (CanvasLayer 5, darkens the top and bottom 20%) → `HUD` (CanvasLayer 10).
Planned: `prefabs/VideoBackdrop.tscn` under or instead of `BackdropLayer` (10.2).

### 5.2 Future stages (Planned)

Both reuse prompts already in `tools/veo_prompts.json`.

* **Candle Crypt** (`ossuary_crypt`): one 760 px spine between two vertebra columns, a centre
  shard at y 420 and two chain-hung shards at the column tops (y 300) swaying ±20 px. Tighter
  side blast zones (-120 / 1400) for short, aggressive matches.
* **Abyss Spine** (`ossuary_abyss`): two bone islands (x 150..550 and 730..1130, top y 600)
  with a 180 px gap and one bridge shard at (640, 480). Higher bottom blast zone (1040) so edge
  play and recovery matter.

---

## 6. Camera (Implemented, `scripts/fight_camera.gd`)

| Export | Value | Meaning |
| ------ | ----- | ------- |
| `min_zoom` | 0.72 | Widest view, 1778x1000 px visible. |
| `max_zoom` | 1.15 | Tightest view, 1113x626 px visible. |
| `lerp_factor` | 0.08 | Per-frame fraction toward target position and zoom. |
| `y_offset` | -40.0 | Frames the midpoint 40 px above the fighters. |

`target_zoom = clamp(700 / (distance + 300), 0.72, 1.15)`: 1.15 at the 240 px spawn distance,
1.0 at 400 px, 0.72 from 672 px. Position is the fighters' midpoint plus `y_offset`;
`Camera2D.limit_*` keep the view inside the limits, no manual clamp. `shake(intensity, frames)`
sets a random `offset` with linear falloff; `main.gd` calls `shake(4.0, 8)` on a hit and
`shake(9.0, 8)` when the victim is at or above `STRONG_HIT_PERCENT` 90. Runs in
`_physics_process` so tests step it by frame.

Planned: on a KO the camera frames the survivor alone until the respawn platform appears.

---

## 7. HUD and screens

### 7.1 Fight HUD — Implemented (`scripts/hud.gd`, `scripts/medallion_ring.gd`, `Main.tscn`)

* Stage name centred at the top (font 20, `BONE_SHADOW`).
* Two **medallions**, P1 at (28, 20) and P2 mirrored at (952, 20), 300x110 each: a 112x112
  ring (radius 50, width 6, `OUTLINE` rim) around a 96x96 portrait inset 8 px, the name in the
  player colour (font 26) and the read-out (font 40).
* Read-out `"%d%%" % roundi(percentage)`; text and ring follow `BrawlTheme.percent_color`:
  white < 35, yellow < 75, orange < 120, red above.
* Controls hint at the bottom (font 16): `P1  WASD + G      P2  Arrows + L`.
* The HUD binds to `percentage_changed` itself; a missing node is `push_error`ed and skipped.

### 7.2 Screens — Planned (prototype `GameState`; title and select scenes are in progress)

`TITLE → CHARACTER_SELECT → FIGHTING ⇄ PAUSED → VICTORY → CHARACTER_SELECT`. Modes `LOCAL_2P`,
`VS_CPU` (with difficulty), `TRAINING` (percentage reset, hitbox overlay).

* **Title**: wordmark over the skull backdrop with the mist running; one orchestrated entrance
  (wordmark drops 0.4 s, menu fades in 0.3 s later); keyboard and joypad navigable.
* **Character select**: three medallions, each player's cursor in their colour, S/P/D/R bars,
  both control schemes on screen.
* **Pause**: dims the arena; resume / controls / quit. **Victory**: winner portrait and stats;
  rematch / select / title.
* Stock pips: three bone circles under each medallion, emptied with a 10-frame pop on KO.

---

## 8. VFX and SFX

### 8.1 VFX — Implemented (`scripts/vfx.gd`, `scripts/fighter_visual.gd`, `main.gd`)

Effects age in `_physics_process` (deterministic lifetimes), drawn in world space.

| Effect | Trigger | Spec |
| ------ | ------- | ---- |
| Slash arc | `attack_started` | Crescent at fighter + (22·facing, -34): radius 48, 12 px, white 3 px arc at 52; sweeps 140° from -80° over the first third of 9 frames; mirrored for facing -1; player colour. |
| Hit spark | `hit_landed` | 8 spikes in the attacker's colour, radius 40 (64 at ≥ 90%), expanding white ring and centre flash; 9 frames (14 strong); 10 px above the victim. |
| Camera shake | `hit_landed` | Intensity 4 (9 strong), 8 frames. |
| Landing dust | `landed` | 4 `BONE_SHADOW` puffs at the feet, radius 5 → 14, alpha 0.5 → 0, 12 frames. |
| Idle bob | grounded, speed < 10 | `sin(t·4) · 1.5` px. |
| Run lean | grounded, speed > 100 | 0.08 rad toward facing. |
| Air stretch / landing squash | `velocity.y < -200` / `landed` | scale (0.94, 1.08) / (1.08, 0.92) for 6 frames. |
| Knockback tilt | `State.KNOCKBACK` | 0.35 rad, head trailing the launch; tint (1.0, 0.6, 0.6). |
| Ground shadow | grounded | 22x5 ellipse, `OUTLINE` alpha 0.35, 2 px under the feet. |

Transforms ease at 0.25 per frame. Planned: dodge afterimages (3 ghosts, 6 frames apart),
invulnerability shimmer (alpha pulse at 8 Hz), KO burst (ring 0 → 160 px over 18 frames plus
24 bone fragments), respawn-platform dissolve, medallion pop on damage (scale 1.3 → 1.0 over 8
frames), floating damage number.

### 8.2 SFX — module Implemented (`scripts/sfx.gd`, `prefabs/Sfx.tscn`), wiring Planned

Samples are synthesized in `_ready` at 44100 Hz, 16-bit mono, from an RNG seeded with `seed`
7, so the bytes are reproducible; `master_volume_db` -6; voices are the `AudioStreamPlayer`
children, picked first-idle-else-oldest.

| Cue | Length | Recipe |
| --- | ------ | ------ |
| `play_swing()` | 0.12 s | Noise band-passed at 1400 Hz, 10 ms attack, `exp(-30t)`. |
| `play_hit(false)` | 0.10 s | Noise + 160 Hz thump, `exp(-40t)`, no attack ramp. |
| `play_hit(true)` | 0.22 s | 90 Hz thump sweeping down from 210 Hz, `exp(-18t)`. |
| `play_jump()` | 0.14 s | Sine 220 → 660 Hz, 5 ms attack, 40 ms release. |
| `play_land()` | 0.08 s | Noise low-passed at 300 Hz, `exp(-45t)`. |
| `play_ko()` | 0.6 s | 60 Hz sine under 500 Hz low-passed noise, `exp(-5t)`. |

Wiring intent: `attack_started → swing`, `hit_landed → hit(victim.percentage >= 90)`,
`landed → land`, jump on the `velocity.y == jump_velocity` edge, KO on a blast-zone crossing.

---

## 9. CPU opponent (module Implemented, `scripts/bot_controller.gd`; wiring Planned)

`BotController` drives one `Player` through `Input.action_press/release` on that player's
`p%d_*` actions, exactly like a keyboard, so `player.gd` has no bot code. One RNG seeded with
`seed` 11. Being hit is a reflex: in `KNOCKBACK` the bot releases everything every frame.
Ported from the prototype's `ai.ts`.

| Tier | Interval (frames) | Recover | Attack | Jump | Idle |
| ---- | ----------------- | ------- | ------ | ---- | ---- |
| EASY   | 12 | 0.5 | 0.35 | 0.3 | 0.25 |
| NORMAL | 6  | 0.8 | 0.7  | 0.6 | 0.1  |
| BRUTAL | 2  | 1.0 | 1.0  | 0.9 | 0.0  |

Rules in order: off stage (`x` outside `stage_left_x` 190..`stage_right_x` 1090) → steer to the
stage centre and tap jump while falling with probability *Recover* (the jump buffer fires it on
touchdown too); else roll *Idle* and release all; else move toward the opponent unless within
`RANGE_X` 48 × `RANGE_Y` 40 (the hitbox's reach), hold down to fast-fall when falling more than
`FAST_FALL_HEIGHT` 160 px above `stage_top_y` 580, tap attack in range with probability
*Attack*, tap jump when the opponent is over `JUMP_UP_DY` 60 px higher with probability *Jump*.
Taps release next frame so the Player sees a press edge.

Planned: dodge when the opponent swings within 80 px (BRUTAL 0.75, NORMAL and EASY 0.4, from
the prototype's shield rule), signatures at 180–420 px, and a per-tier reaction delay on the first
frame of an opponent's attack.

---

## 10. Art pipeline

### 10.1 Stills — Implemented (`tools/process_art.gd`)

Sources in `assets/art-src/` come from Google's Gemini image model: the backdrop as a finished
1280x720 painting (`ossuary_far_1280x720.png`), each fighter as a 1024 px full-body sprite
facing right on flat magenta (`kage_magenta_1024.png`, `ignis_magenta_1024.png`). Outputs:

* `assets/backdrops/ossuary_far.png`: a copy of the backdrop.
* `assets/sprites/kage.png` (57x64) and `ignis.png` (66x72): key colour = mean of four 16 px
  corner patches (`KEY_SAMPLE`); alpha ramps from 0 at RGB distance `KEY_FULL` 70 to 1 at
  70 + `KEY_RAMP` 60; pixels with g < 90, r > 150, b > 90 are cut outright; edges despilled
  from opaque neighbours within `DESPILL_RADIUS` 2; crop to the used rect + `CROP_MARGIN` 2;
  Lanczos resize to 64 (Kage) or 72 (Ignis) px tall.
* `<name>_portrait.png`: `PORTRAIT_SIZE` 96x96 from the top `HEAD_BAND` 0.32 of the sprite,
  clipped to `PORTRAIT_RADIUS` 46 over `SLATE`.

Sizes are the design: fighters must read at `min_zoom` 0.72 (Kage is 46 screen px there) and
portraits must fill the 112 px ring with an 8 px inset. Zephyr joins at 68 px.

### 10.2 Veo backdrops — tooling Implemented (`tools/veo_backdrops.py`, `docs/VEO.md`), wiring Planned

Looping clips from the Gemini API's Veo models, converted to Ogg Theora and played by
`prefabs/VideoBackdrop.tscn` (CanvasLayer -10: an always-visible poster `TextureRect` under a
muted looping `VideoStreamPlayer`; a missing clip hides the player and keeps the poster).

* Model `veo-3.1-fast-generate-preview`, 8 s clips, 16:9, `personGeneration: dont_allow`.
* Three prompts (`ossuary_nave`, `ossuary_crypt`, `ossuary_abyss`): locked-off camera, slow
  teal mist, bone/slate palette, no characters or text, so an 8 s clip loops without a seam.
* **Budget $28 total**, enforced by the script: spend is estimated as
  `duration × price-per-second` (0.15 fast, 0.40 standard; 3 clips ≈ $3.60) and written to
  `tools/veo_spend.json` **before** each request; a clip that would exceed the cap is refused
  (exit 2) with no network call; failed clips stay in the ledger and count.
* `tools/convert_backdrop.sh`: `.mp4 → assets/video/<name>.ogv` (1280x720, libtheora q 7, no
  audio) + `<name>_poster.png`. `assets/video/test_pattern.ogv` is a 2 s test stream so the
  suite always has a real Theora file.

---

## 11. Visual direction (palette Implemented, `scripts/brawl_theme.gd`)

| Token | Hex | Use |
| ----- | --- | --- |
| `P1_COLOR` / `P2_COLOR` | `#38bdf8` / `#ef4444` | Kage / Ignis: name, slash, spark, tint. |
| `BONE` / `BONE_SHADOW` / `BONE_DARK` | `#dfe6e9` / `#93a9b3` / `#5f7681` | Lit bone / undersides, dust, labels / seams, cracks. |
| `OUTLINE` | `#1b2a33` | 3 px ink outline on every stage shape. |
| `MIST` / `SLATE` | `#4f7f8c` / `#14202a` | Mist blobs / portrait fill, vignette. |
| `PERCENT_WHITE/YELLOW/ORANGE/RED` | `#f1f5f9` `#facc15` `#f97316` `#f43f5e` | Thresholds 35 / 75 / 120. |

Mood board (genre footage, not copied): a fossil skeleton as the playable surface, a painted
skull behind, cold teal haze, portrait medallions with stock counts, bright slash trails. Our
translation: bone slab and ribs, parallax skull, teal mist, medallions in both top corners.

---

## 12. Testing approach (Implemented, `tests/`)

* `tests/run_tests.gd` discovers `tests/test_*.gd` and awaits every `test_*(ctx: TestContext)`;
  120 s watchdog; exit 1 on any failed check; `TEST_FILTER` narrows by file name.
* `TestContext` spawns players and floors, presses InputMap actions, steps frames and records
  `check` / `check_near`. Expected values are hand-derived literals (20 stun frames,
  `260 × 0.8 × (0.8, -0.6) = (166.4, -124.8)`), never recomputed from the code under test.
* Suites: `test_player_movement`, `test_player_combat`, `test_input_map`, `test_scenes`,
  `test_vfx_hud`, `test_art_assets`, `test_sfx`, `test_video_backdrop`, `test_bot`,
  `test_menus` (title and select screens, in progress).
* Static: `--check-only` per script, `gdlint` + `gdformat --check`, `--import | grep error`.
* Rendering: an Xvfb smoke run of `Main.tscn` must print no `SCRIPT ERROR`;
  `tools/screenshot.gd` refreshes `docs/screenshot-*.png` for review.
* Python: `python3 -m unittest tools.test_veo_backdrops` with network and sleep mocked.

Planned features follow the same shape: suites at the public boundary (stocks, KO, dodge
i-frames, double jump, drop-through), developed under `tests/wip/` until green.

---

## 13. Roadmap

| Milestone | Scope | Status |
| --------- | ----- | ------ |
| M0 Core | Two players, movement, one attack, percentage/knockback, hitstop, respawn | Implemented |
| M1 Identity | Ossuary art, sprites, camera, medallion HUD, VFX, palette | Implemented |
| M2 Features | SFX wiring, CPU bot in `Main.tscn`, video backdrop, title and select screens, DESIGN.md | In progress |
| M3 Match | 3 stocks, blast zones, KO flow, respawn platform, 60-frame invulnerability, victory | Planned |
| M4 Movement 2 | Dodge (8 i-frames), double jump, drop-through, hitstun/hitstop scaling | Planned |
| M5 Screens | Pause, training, controls screen | Planned |
| M6 Roster | Zephyr, per-fighter stats, two signatures each | Planned |
| M7 Stages | Candle Crypt, Abyss Spine, Veo clips under the $28 cap | Planned |
| M8 Weapons | Drifting pickups swapping movesets | Planned |
