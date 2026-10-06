# Skyfall Brawl

A local-multiplayer 2D platform fighter built in **Godot 4.4+** (GDScript, GL Compatibility
renderer). Two fighters on floating islands, one keyboard (or one controller each), damage
percentages, knockback that grows with damage. The genre is inspired by games like Brawlhalla;
all names, art and code here are original.

Local multiplayer only: there is no online play and none is planned.

## Open and run

1. Install [Godot 4.4 or newer](https://godotengine.org/download) (the standard build; no
   .NET needed).
2. In the Project Manager choose **Import**, select this folder's `project.godot`, then **Edit**.
3. Press **F5** (Run Project). `scenes/Main.tscn` is the main scene: a floor, two one-way
   platforms, both players and a damage HUD.

Or from a terminal, with `GODOT` pointing at your Godot binary:

```bash
GODOT=/path/to/godot      # e.g. ~/Downloads/Godot_v4.4.1-stable_linux.x86_64
$GODOT --path .            # run the main scene
$GODOT --path . --editor   # open the editor
```

## Controls

| Action | Player 1 (keyboard) | Player 1 (joypad 0) | Player 2 (keyboard) | Player 2 (joypad 1) |
| ------ | ------------------- | ------------------- | ------------------- | ------------------- |
| Left   | A                   | Left stick / D-pad  | Left arrow          | Left stick / D-pad  |
| Right  | D                   | Left stick / D-pad  | Right arrow         | Left stick / D-pad  |
| Jump   | W                   | A (bottom face)     | Up arrow            | A (bottom face)     |
| Down / fast-fall | S         | Left stick / D-pad down | Down arrow      | Left stick / D-pad down |
| Attack | G                   | X (left face)       | L                   | X (left face)       |

Bindings live in `project.godot` under `[input]` as actions `p1_left`, `p1_right`, `p1_jump`,
`p1_down`, `p1_attack` and the matching `p2_*` set. Scripts only ever read those actions
(`"p%d_%s" % [player_index, name]`), so rebinding in **Project > Project Settings > Input Map**
needs no code changes. Joypad bindings are per device: device 0 drives P1, device 1 drives P2.

## Folder layout

```
project.godot          settings, input map, physics layers, display
scenes/Main.tscn       the arena: floor, two platforms, Player1/Player2, camera, HUD
scripts/main.gd        HUD wiring (damage_changed -> labels)
scripts/player.gd      fighter movement, fast-fall, air friction, jump buffer, attack
scripts/hitbox.gd      Area2D attack hitbox (one hit per activation)
prefabs/Player.tscn    CharacterBody2D + Sprite2D + CollisionShape2D + Hitbox (Area2D)
prefabs/Platform.tscn  one-way StaticBody2D platform, 240x20
assets/sprites/        fighter_p1.png (teal), fighter_p2.png (orange) + .import sidecars
tools/make_sprites.gd  regenerates the placeholder sprites
tests/                 headless test runner (run_tests.gd), TestContext, test_*.gd suites
docs/                  design reference material
```

Physics layers: 1 `world` (floor, platforms), 2 `players`, 3 `hitboxes`. Player bodies are on
layer 2 and collide only with layer 1, so fighters pass through each other. Hitboxes are on
layer 3 and scan layer 2.

## Tunables

Every physics constant is an `@export` on `scripts/player.gd`, editable per instance in the
Inspector. Units: px, px/s, px/s², physics frames at 60 Hz.

| Export                        | Default | Unit     | Meaning |
| ----------------------------- | ------- | -------- | ------- |
| `run_speed`                   | 340.0   | px/s     | horizontal top speed from input |
| `ground_acceleration`         | 2600.0  | px/s²    | toward target speed while grounded |
| `ground_friction`             | 2400.0  | px/s²    | toward zero while grounded, no input |
| `air_acceleration`            | 1300.0  | px/s²    | toward target speed while airborne |
| `air_friction`                | 320.0   | px/s²    | toward zero while airborne, no input (slight resistance) |
| `gravity`                     | 1500.0  | px/s²    | downward acceleration while airborne |
| `max_fall_speed`              | 900.0   | px/s     | normal terminal velocity |
| `fast_fall_gravity_multiplier`| 2.5     | ×        | gravity multiplier while holding down in the air |
| `fast_fall_max_speed`         | 1500.0  | px/s     | terminal velocity while fast-falling |
| `jump_velocity`               | -620.0  | px/s     | initial vertical speed of a jump (up is negative) |
| `jump_buffer_frames`          | 6       | frames   | a jump pressed this many frames before landing still fires |
| `attack_startup_frames`       | 3       | frames   | frames before the hitbox turns on |
| `attack_active_frames`        | 6       | frames   | frames the hitbox is on |
| `attack_recovery_frames`      | 10      | frames   | frames after the hitbox before another attack |
| `attack_damage`               | 8.0     | %        | damage added per hit |
| `attack_base_knockback`       | 260.0   | px/s     | knockback speed at 0% |
| `attack_knockback_scaling`    | 7.0     | px/s per % | knockback speed = base + scaling × victim damage (after the hit) |
| `respawn_below_y`             | 1200.0  | px       | falling past this y respawns the fighter at 0% |

## Tests and static checks

Everything runs headlessly with the same Godot binary you play with. From the repository root,
with `GODOT` set to your binary:

```bash
GODOT=/path/to/godot

# (Re)import assets. Required after adding or changing PNG files. Prints nothing when clean.
$GODOT --headless --path . --import 2>&1 | grep -iE "error|SCRIPT"

# Parse + static-check one script (exit 0, no "SCRIPT ERROR" lines).
$GODOT --headless --path . --check-only --script scripts/player.gd

# Full test suite. Last line is "==== N passed, M failed ===="; exit code 1 on any failure.
$GODOT --headless --path . --fixed-fps 60 --script tests/run_tests.gd 2>&1 | grep -vE "^(Godot Engine|$)"

# Lint + formatting (pip install gdtoolkit). "gdformat <files>" rewrites in place.
gdlint scripts tests tools && gdformat --check scripts tests tools

# Run Main.tscn for 2 s with software rendering (Linux, needs xvfb). Must print no SCRIPT ERROR.
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
  --rendering-driver opengl3 --audio-driver Dummy --quit-after 120 2>&1 | grep -iE "error|SCRIPT"
```

Tests are plain GDScript: `tests/run_tests.gd` discovers `tests/test_*.gd`, instantiates each
suite and awaits every `test_*(ctx: TestContext)` method. `TestContext` spawns players and
floors, presses InputMap actions, steps physics frames and records `check`/`check_near`
assertions. Expected values are hand-derived from the tunables above (dt = 1/60), so a change to
a default fails the test that encodes it.

## What is implemented / next steps

Implemented:

- Two players on one keyboard or on two joypads, through the `p1_*` / `p2_*` InputMap actions.
- Platform-fighter movement: run with separate ground and air acceleration, ground friction,
  **air friction** (slight horizontal resistance when no direction is held in the air),
  gravity with a terminal velocity, **fast-falling** (holding down in the air multiplies
  gravity and raises the fall cap), and **jump buffering** (a jump pressed up to 6 frames
  before landing fires on the landing frame).
- One attack per player with startup / active / recovery frame counters, an Area2D hitbox that
  hits each opponent once per swing, damage percentages, knockback that scales with damage,
  a respawn when a fighter falls off the bottom, and a HUD showing both damages.
- One-way platforms and a floor on a dark arena, two placeholder fighter sprites.

Not yet:

- Double jump, dodge / dash, wall slide, ledge grab.
- Weapons and more than one attack per fighter.
- Stocks, KO blast zones on the sides and top, round flow, win screen.
- Hitstop, screen shake, hit sparks and sound.
- Menus and a controls screen.
