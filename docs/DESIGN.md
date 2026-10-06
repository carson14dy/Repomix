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
| Zephyr | The Tempest Valkyrie     | mist `#4f7f8c` (`BrawlTheme.MIST`) | 6.4 / 13.2 / 95 / 3  | 7 / 7 / 6 / 10 | 340 | 95  |

Proposed speeds scale the current 340 by the prototype ratio (340 × 7.2 / 6.4 ≈ 382,
340 × 5.2 / 6.4 ≈ 276), rounded. Weight enters knockback as `100 / weight` (section 4.3).

### 2.2 Kage — sprite Implemented, moveset Planned

Hooded assassin woven from the twilight mist under the dragon bones. `assets/sprites/kage.png`
57x64, `kage_portrait.png` 96x96; the default Player 1 pick (`MatchConfig`; any fighter can
take either slot). Fastest run, highest jump, lightest; multi-hit strings that rack percentage
fast but launch late.

* Normals: twin shadow knives, short reach, low base knockback, fast recovery.
* **Veil Step**: a 12-frame phantom dash through the opponent leaving a cyan afterimage;
  frames 3–8 intangible; no damage, pure repositioning.
* **Twilight Fan**: three shadow knives in a fan, 3 × 3% with weak fixed knockback; the last
  pops the target up for a follow-up.

### 2.3 Ignis — sprite Implemented, moveset Planned

Colossal sentinel in blackened plate lit by crimson soul-fire. `assets/sprites/ignis.png`
66x72, `ignis_portrait.png` 96x96; the default Player 2 pick. Slow, heavy, ends stocks early.

* Normals: greatsword sweeps, long reach, high base knockback, long recovery.
* **Pyre Cleave**: overhead slam, 14 startup frames; on contact a 120 px fire pillar rises
  for 10 frames and launches at 70°. Highest base knockback in the game.
* **Bulwark Flare**: shoulder charge with super armour for its first 10 frames (takes
  percentage, ignores knockback), then a flare burst that launches horizontally.

### 2.4 Zephyr — selectable, no assets yet

Winged duelist from the tempests that howl through the ossuary cliffs; gale lance. Three jumps,
floaty descent, the longest poke. On the roster today with Kage's sprite and a placeholder
portrait disc (`scripts/portrait_placeholder.gd`, select screen and HUD medallion); the
player-colour chevron over each fighter keeps a Zephyr-vs-Kage match readable. Sprite follows
the Kage/Ignis pipeline at 68 px tall.

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
| `jump_buffer_frames` | 6 | frames | A press up to 100 ms before landing still fires on landing (only once the air jump is spent). |
| `air_jumps` | 1 | jumps | Air jumps per airtime, restored on landing; a fresh press each, never buffered. |
| `air_jump_velocity` | -560.0 | px/s | Air jump apex ~105 px (560² / 2·1500). |

Rules that are code, not numbers:

* Presses are edge-detected from `Input.is_action_pressed` (`_just_pressed`) because Godot 4.4
  reports `is_action_just_pressed` one physics frame late. A button held through hitstop or
  knockback, across `ko()` → `respawn()`, or when the fighter enters the tree never counts as a
  fresh press.
* Facing follows the last non-zero horizontal input in `State.NORMAL`, updated before the
  attack starts so `attack_started`, the hitbox and the slash arc agree on a turn-and-swing
  frame; `Hitbox.set_facing` mirrors the hitbox, `fighter_visual.gd` flips the sprite.
* Movement is **not** locked during an attack (decision in `_apply_attack`): a two-button game
  needs the fighter to stay responsive.
* Fighters sit on physics layer 2 and collide only with layer 1 (world), so they pass through
  each other; hitboxes are on layer 3 and scan layer 2.

Tuning note (hand-derived): the shard tops (y 460) are 136 px above the spine top (y 596) and
one jump rises ~133 px, so reaching a shard from the spine in one jump is marginal; the air
jump (`air_jumps` 1) makes the shards a real second storey.

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

### 4.4 Stocks and KO flow — Implemented (`scripts/match.gd`, `Main/Match`)

* `stocks_per_player` **3** each (`MatchConfig.stocks`), shown as diamond pips under each
  medallion (`stock_pips.gd`, `max_stocks` from `MatchConfig.stocks`).
* `blast_zone` **Rect2(-260, -420, 1800, 1520)**, i.e. (-260, -420)..(1540, 1100); the
  camera limits in `Main.tscn` are the same rect (5.1). A fighter whose position leaves it is
  KO'd on that physics frame (the Match sits after the players in the tree): `ko()` hides it
  at its spawn point, inactive and unhittable (a hit scanned on the KO frame does not land),
  one stock removed, `fighter_koed` → camera shake 14 for 12 frames and the KO boom.
* **Respawn**: `respawn_delay_frames` **60** later the fighter is back at its spawn point at
  0% with its air jump, no hitstop and buttons held through the wait ignored.
* **Match end**: the KO that takes the last stock sets `winner_index` and emits
  `match_ended` once (a same-frame double KO on the last stocks KOs the first fighter processed,
  Player 1, and the other keeps its stock); the win layer (dim, slate backing, "<fighter> wins"
  in the winner's colour with an 8 px outline, hint) replaces the controls hint. Either
  fighter's **attack press** (edge, polled every frame so a button held through the KO is not a
  press) rematches: `restart()` refills the stocks and respawns both; **Down** returns to the
  character select (`main.gd`).

Planned: a flash in the fighter's colour at the crossing, a bone **respawn platform** 120 px
above the spawn point (held up to 120 frames or until any input), **60 frames of
invulnerability** drawn as a bone-white shimmer, the camera zooming to `max_zoom` on the
winner, and victory stats (damage dealt, KOs, highest combo).

### 4.5 Planned: defensive options

* **Dodge**: down + jump grounded, or attack while holding down in the air. 22 frames with
  **8 intangible frames** (3–10), 40-frame cooldown, afterimage in the player colour. Grounded:
  a 120 px roll. Air: a 160 px dash in the stick direction, once per airtime.
* **Double jump**: Implemented as `air_jumps` 1 / `air_jump_velocity` -560 (section 3); Planned:
  Zephyr 3, consumed by an air dodge.
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
| Camera limits | (-260, -420)..(1540, 1100) | = `Match.blast_zone` (4.4), so a live fighter is on screen; the 1800x1520 span holds the widest view (6). |

The test floor from `TestContext.make_floor` is 1200x40 with its top at y 580; the bot's
default `stage_top_y` 580 matches the tests, while the Main floor top is 596.

Art layers, back to front: `VideoBackdrop` (`prefabs/VideoBackdrop.tscn`, CanvasLayer -10:
the looping `ossuary_nave.ogv` over its poster, both 1434x806 (12% margin), linear-filtered,
scrolled by `main.gd` at parallax 0.06 from the camera's clamped screen centre) → `StageArt`
(static `_draw`, ~120 calls: the centre rib bows like its neighbours, the platform ends are
jagged breaks inside the platform height) → `Mist` (three teal blobs, radii 210/270/190, peak
alpha 0.16/0.18/0.13, sine drift) → fighters with ground shadows and a player-colour chevron →
`Vfx` (z 5) → `VignetteLayer` (CanvasLayer 5, darkens the top and bottom 20%) → `HUD`
(CanvasLayer 10) → `WinLayer` (CanvasLayer 20, hidden until the match ends).

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
`Camera2D.limit_*` keep the view inside the limits, no manual clamp. That clamp only tracks
while the view is narrower than the limit span, so the limits (1800x1520) must hold the widest
view (1778x1000) — a `min_zoom` below 0.711 or narrower limits would pin the view to one side.
`shake(intensity, frames)` sets a random `offset` with linear falloff; `main.gd` calls
`shake(4.0, 8)` on a hit, `shake(9.0, 8)` when the victim is at or above `STRONG_HIT_PERCENT`
90, and `shake(14.0, 12)` on a KO. Runs in `_physics_process` so tests step it by frame.

Planned: on a KO the camera frames the survivor alone until the respawn platform appears.

---

## 7. HUD and screens

### 7.1 Fight HUD — Implemented (`scripts/hud.gd`, `scripts/medallion_ring.gd`, `Main.tscn`)

* Stage name centred at the top (font 20, `BONE_SHADOW`).
* Two **medallions**, P1 at (28, 20) and P2 mirrored at (952, 20), 300x110 each: a 112x112
  ring (radius 50, width 6, `OUTLINE` rim) around a 96x96 portrait inset 8 px (a fighter
  without portrait art gets the placeholder disc there), the name in the player colour (font
  26), the read-out (font 40) and the stock pips (`stock_pips.gd`): `MatchConfig.stocks`
  diamonds, pitch 22, filled in the player colour with an `OUTLINE` stroke, lost ones hollow
  slate with a `BONE_SHADOW` stroke.
* Read-out `"%d%%" % roundi(percentage)`; text and ring follow `BrawlTheme.percent_color`:
  white < 35, yellow < 75, orange < 120, red above.
* Controls hint at the bottom (font 16, `PERCENT_WHITE` at 0.9 over a 4 px `OUTLINE` outline):
  `P1  WASD + G      P2  Arrows + L      3 stocks, double jump, fall or fly out to lose one`;
  hidden while the win screen is up.
* The HUD binds to `percentage_changed` itself; a missing node is `push_error`ed and skipped.

### 7.2 Screens — title, select and win screen Implemented; pause, training and stats Planned

Implemented (`scripts/title.gd`, `scripts/character_select.gd`, `scripts/match_config.gd`,
`scripts/roster.gd`, `scripts/main.gd`): `Title → CharacterSelect → Main (arena) → win screen
→ rematch (Attack) or CharacterSelect (Down)`. Modes: local 2P and Versus CPU, recorded in
`MatchConfig.p2_is_cpu`; `MatchConfig.difficulty` (1 = NORMAL) and `stocks` (3) exist but no
menu changes them yet. Planned: `TRAINING` (percentage reset, hitbox overlay), `PAUSED`.

* **Title** (Implemented): wordmark, *Versus* / *Versus CPU* / *Controls*, 0.45 s fade-in;
  jump / down move, attack confirms, for either player, mouse too; the Controls panel lists both
  keyboard layouts read from the InputMap. Planned: the skull backdrop and mist behind it.
* **Character select** (Implemented): two columns (portrait or placeholder disc, name, title,
  S/P/D/R bars, description, control hint); left / right browse, attack locks in, down unlocks,
  Player 1's down with nothing locked returns to the title; the CPU column is auto-picked (the
  fighter after Player 1's); a 30-frame FIGHT flash, then `Main.tscn`. A key held over from the
  title is ignored.
* **Arena wiring** (Implemented, `main.gd`): sprites from `Roster` through
  `Player.set_fighter_sprite()`, HUD names and portraits, `Match.stocks_per_player`,
  `BotController` in CPU mode, "<fighter> wins" on the win screen, Down → character select.
* **Win screen** (Implemented, `WinLayer` in `Main.tscn`): a 0.6 dim, a `SLATE` 0.85 backing
  (x 240..1040, y 216..430), "<fighter> wins" (font 72, winner's colour, 8 px `OUTLINE`
  outline) and the rematch / character-select hint (font 24, `PERCENT_WHITE`).
* **Pause** (Planned): dims the arena; resume / controls / quit. **Victory stats** (Planned):
  winner portrait, damage dealt, KOs. Planned: a 10-frame pop on the stock pip lost to a KO.

---

## 8. VFX and SFX

### 8.1 VFX — Implemented (`scripts/vfx.gd`, `scripts/fighter_visual.gd`, `main.gd`)

Effects age in `_physics_process` (deterministic lifetimes), drawn in world space.

| Effect | Trigger | Spec |
| ------ | ------- | ---- |
| Slash arc | `attack_started` | Crescent at fighter + (22·facing, -34): radius 48, 12 px, white 3 px arc at 52; sweeps 140° from -80° over the first third of 9 frames; mirrored for facing -1; player colour. |
| Hit spark | `hit_landed` | 8 spikes in the attacker's colour, radius 40 (64 at ≥ 90%), expanding white ring and centre flash; 9 frames (14 strong); 10 px above the victim. |
| Camera shake | `hit_landed` / `fighter_koed` | Intensity 4 (9 strong), 8 frames / 14, 12 frames. |
| Landing dust | `landed`, air jump (`jumped(_, true)`) | 4 `BONE_SHADOW` puffs at the feet, radius 5 → 14, alpha 0.5 → 0, 12 frames. |
| Idle bob | grounded, speed < 10 | Height pulse `1 + 0.02·sin(t·4)` about the feet (~1.3 px at the head). |
| Run lean | grounded, speed > 100 | 0.08 rad toward facing. |
| Air stretch / landing squash | `velocity.y < -200` / `landed` | scale (0.94, 1.08) / (1.08, 0.92) for 6 frames, pivoting at the feet (the Sprite2D sits at `FEET_Y` 28, art lifted by `offset.y = -height / 2`). |
| Knockback tilt | `State.KNOCKBACK` | 0.35 rad, head trailing the launch; tint (1.0, 0.6, 0.6). |
| Ground shadow | grounded | 22x5 ellipse, `OUTLINE` alpha 0.35, 2 px under the feet. |
| Player chevron | always | 12x8 triangle in the player colour, tip 6 px above the texture top; drawn in Player space so it ignores the squash and lean. |

Transforms ease at 0.25 per frame. Planned: dodge afterimages (3 ghosts, 6 frames apart),
invulnerability shimmer (alpha pulse at 8 Hz), KO burst (ring 0 → 160 px over 18 frames plus
24 bone fragments), respawn-platform dissolve, medallion pop on damage (scale 1.3 → 1.0 over 8
frames), floating damage number.

### 8.2 SFX — Implemented (`scripts/sfx.gd`, `prefabs/Sfx.tscn`, wired by `scripts/main.gd`)

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

Wiring (`main.gd`): `attack_started → play_swing()` (ignored on the win screen),
`hit_landed → play_hit(victim.percentage >= 90)`, `landed → play_land()`,
`jumped → play_jump()`, `Match.fighter_koed → play_ko()`.

---

## 9. CPU opponent (Implemented, `scripts/bot_controller.gd`, wired by `scripts/main.gd`)

`BotController` drives one `Player` through `Input.action_press/release` on that player's
`p%d_*` actions, exactly like a keyboard, so `player.gd` has no bot code. One RNG seeded with
`seed` 11. Being hit is a reflex: in `KNOCKBACK` the bot releases everything every frame, and
it idles while either fighter is KO'd (`Player.active` false). Ported from the prototype's
`ai.ts`. Wiring: when `MatchConfig.p2_is_cpu`, `main.gd` adds `prefabs/BotController.tscn`
under `Main` on Player 2 with `MatchConfig.difficulty`, disables it on `match_ended` (so it
cannot press the rematch attack) and re-enables it on `match_restarted`.

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
  centred horizontally on the opaque pixels of the top `HEAD_CENTRE_ROWS` 0.08 (the crown, so
  a trailing hood or pauldron does not pull the face sideways), clipped to `PORTRAIT_RADIUS`
  46 over `SLATE`.

Sizes are the design: fighters must read at `min_zoom` 0.72 (Kage is 46 screen px there) and
portraits must fill the 112 px ring with an 8 px inset. Zephyr joins at 68 px. The sprites
are anti-aliased downsamples, not pixel art, so they are drawn with linear filtering
(`texture_filter` 2 on the Sprite2D) under the camera's continuously changing zoom.

### 10.2 Veo backdrops — tooling and wiring Implemented (`tools/veo_backdrops.py`, `docs/VEO.md`, `prefabs/VideoBackdrop.tscn`)

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
  audio) + `<name>_poster.png`. The clip in the repository, `assets/video/ossuary_nave.ogv`
  (8 s, 30 fps), is rendered procedurally from the painting by `tools/render_backdrop_clip.py`;
  no Veo spend has happened yet.

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
  `test_menus` (title and select screens), `test_arena_config` (MatchConfig in the arena).
* Static: `--check-only` per script, `gdlint` + `gdformat --check`, `--import | grep error`.
* Rendering: an Xvfb smoke run of the main scene (`Title.tscn`) must print no `SCRIPT ERROR`;
  `tools/screenshot.gd` (arena) and `tools/screenshot_menus.gd` (title, select) refresh
  `docs/screenshot-*.png` for review.
* Python: `python3 -m unittest tools.test_veo_backdrops` with network and sleep mocked.

Planned features follow the same shape: suites at the public boundary (stocks, KO, dodge
i-frames, double jump, drop-through), developed under `tests/wip/` until green.

---

## 13. Roadmap

| Milestone | Scope | Status |
| --------- | ----- | ------ |
| M0 Core | Two players, movement, one attack, percentage/knockback, hitstop, respawn | Implemented |
| M1 Identity | Ossuary art, sprites, camera, medallion HUD, VFX, palette | Implemented |
| M2 Features | SFX wiring, CPU bot in `Main.tscn`, video backdrop, title and select screens, DESIGN.md | Implemented |
| M3 Match | 3 stocks, blast zones, KO flow, win screen, rematch, double jump | Implemented |
| M3b Match polish | Respawn platform, 60-frame invulnerability, KO flash, victory stats | Planned |
| M4 Movement 2 | Dodge (8 i-frames), drop-through, hitstun/hitstop scaling | Planned |
| M5 Screens | Pause, training, controls screen | Planned |
| M6 Roster | Zephyr, per-fighter stats, two signatures each | Planned |
| M7 Stages | Candle Crypt, Abyss Spine, Veo clips under the $28 cap | Planned |
| M8 Weapons | Drifting pickups swapping movesets | Planned |
