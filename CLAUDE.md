# BrawlCrypt — agent guide

A **Godot 4.x** 2D gothic platform fighter in the spirit of Brawlhalla. Local multiplayer only:
two players on one keyboard (or one controller each), or one player against the CPU. GDScript,
statically typed. Stage: Wyrm's Ossuary, a dragon's bone spine over a painted skull.

Layout:

```
project.godot          # settings, input map (p1_* / p2_* actions), physics, display, main scene
scenes/                # Title.tscn -> CharacterSelect.tscn -> Main.tscn (the arena)
prefabs/               # Player, Platform, Sfx, BotController, VideoBackdrop
scripts/               # one script per concern (see Modules)
assets/art-src/        # generated source art (Gemini): magenta-keyed sprites, backdrop plate
assets/sprites/        # keyed fighter sprites and 96 px portraits (made by tools/process_art.gd)
assets/backdrops/      # painted backdrop plate
assets/video/          # looping backdrop clip (.ogv) + poster; raw/ holds ignored mp4 sources
tests/                 # headless runner (run_tests.gd), TestContext (context.gd), test_*.gd suites
tools/                 # process_art.gd, screenshot.gd, veo_backdrops.py, render_backdrop_clip.py,
                       # convert_backdrop.sh and their Python unit tests
docs/                  # DESIGN.md (design reference), VEO.md (clip pipeline), screenshots; .gdignore
```

## Modules

- `player.gd` (Player): movement, fast-fall (only once no longer rising), air friction, jump
  buffer, one air jump, attack frames, `percentage`, `take_damage(base_knockback, direction,
  damage_amount)`, knockback state, hitstop, `ko()` / `respawn()`, `active`. Signals:
  `percentage_changed`, `hit_landed`, `attack_started`, `landed`, `jumped(index, air)`.
- `hitbox.gd` (Hitbox): the attack Area2D; one hit per activation, resolved at end of tick.
- `match.gd` (Match): stocks, blast zone, KO -> respawn delay, win condition, rematch on attack.
- `main.gd`: wires fighters, Match, FightCamera, Vfx, Sfx, HUD and the win layer together.
- `fight_camera.gd`, `stage_art.gd`, `mist.gd`, `vfx.gd`, `fighter_visual.gd`, `hud.gd`,
  `medallion_ring.gd`, `stock_pips.gd`, `video_backdrop.gd`, `brawl_theme.gd` (palette).
- `sfx.gd` (Sfx): procedurally synthesized AudioStreamWAV effects, deterministic.
- `bot_controller.gd` (BotController): CPU opponent that presses a player's InputMap actions.
- `title.gd`, `character_select.gd`, `menu_input.gd`, `roster.gd` (Roster), `match_config.gd`
  (MatchConfig: static match settings written by the menus, read by the arena).

## Commands

The project is verified with a headless Godot editor binary. Set `GODOT` to its path.

```bash
$GODOT --headless --path . --import                                   # import assets
$GODOT --headless --path . --check-only --script scripts/player.gd    # parse + static check
$GODOT --headless --path . --fixed-fps 60 --script tests/run_tests.gd # full suite
TEST_FILTER=test_bot $GODOT --headless --path . --fixed-fps 60 --script tests/run_tests.gd
gdlint scripts tests tools && gdformat --check scripts tests tools    # pip install gdtoolkit
python3 -m unittest tools.test_veo_backdrops tools.test_render_backdrop_clip
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
  --rendering-driver opengl3 --audio-driver Dummy --script tools/screenshot.gd   # docs/*.png
```

## Hard constraints

- Godot 4.4 compatible project (`config_version=5`, GL Compatibility renderer). Use only APIs
  that exist in 4.4 so the project opens in any current 4.x editor.
- Everything that affects gameplay runs in `_physics_process` at 60 Hz with frame counters,
  not `Timer` nodes, so behaviour is deterministic and testable headlessly. Randomness in
  gameplay (bot, sound synthesis) comes from a seeded `RandomNumberGenerator`.
- Input is read only through InputMap actions prefixed `p1_` / `p2_` (`left`, `right`,
  `jump`, `down`, `attack`). Never read raw keys in gameplay scripts. The CPU opponent drives
  the same actions with `Input.action_press` / `action_release`.
- Static typing everywhere (`var x: float`, `-> void`). `@export` tunables for every physics
  constant, with the default values from the README table.
- Scenes are text `.tscn` files committed to git. `.godot/` is never committed; `*.import` and
  `*.uid` sidecars are. `docs/` and `assets/video/raw/` carry a `.gdignore`.
- Original content only: invented names, no Brawlhalla legends, logo, or text.
- Do not edit files owned by another module in a parallel task. If you need a change there,
  write it in your report instead.

## How we work (distilled from the superpowers, agent-skills, mattpocock, and
## andrej-karpathy skill sets; see Credits)

**Think before coding.** State assumptions explicitly. If the spec admits two readings that
produce different code, pick one, say which, and say why. If a simpler approach exists, say so.

**Simplicity first.** Minimum code that solves the problem. No speculative abstractions, no
configurability nobody asked for, no error handling for impossible states.

**Surgical changes.** Every changed line traces to the task. Do not reformat or refactor
neighbours. Remove only the code your own change orphaned.

**Test-driven, at seams.** For movement, combat, match flow, menus and bot logic: write the
failing test in `tests/` first, run it headless and watch it fail for the right reason, write
the minimal code to pass, then refactor with the suite green. Tests drive players through
InputMap actions and observe `velocity`, `global_position`, `is_on_floor()`, signals and node
state. They never call private helpers or assert fields beginning with `_`.

**Write tests that name the break.** Expected values are hand-derived literals from the
tunables, never recomputed by the code under test. No change detectors, no mirror assertions.
Every test records at least one check (the runner fails a test that records none).

**Verification before completion.** No claim of "done", "passing", or "fixed" without running
the proving command right then and reading its output. A report that omits a red test it saw
is a false report.

**Systematic debugging.** Root cause before fix. Read the whole error (Godot prints script
path and line). Reproduce it in a test. One hypothesis, smallest change, verify. Three failed
fixes in a row means the design is wrong; stop and say so.

## GDScript rules

- `move_and_slide()` takes no arguments in Godot 4 and uses `velocity`. Gravity is applied by
  the script. `is_on_floor()` reflects the previous `move_and_slide()`, so read it before
  moving in the current frame.
- Detect press edges (jump, attack) by comparing `Input.is_action_pressed` against the
  previous frame's held flag (see `Player._just_pressed`); `Input.is_action_just_pressed`
  lags a physics frame under `--fixed-fps` and must not be used in gameplay scripts. Use
  `Input.get_axis(left, right)` for horizontal movement.
- Frame counters are `int` and count physics frames; durations in the README are frames at
  60 Hz. Speeds are px/s and accelerations px/s², scaled by `delta`.
- `@onready var sprite: Sprite2D = $Sprite2D` style for child references; node names are
  part of the contract between scene and script (HUD medallions, Player children, Main nodes).
- Signals for cross-node communication; no `get_parent()` chains into siblings.
- Keep `gdlint` clean with its default config and `gdformat` formatting (tabs, 100 columns).

## Visual direction

Painterly bone-and-teal ossuary: BrawlTheme palette (P1 cyan, P2 crimson, BONE, BONE_SHADOW,
MIST, SLATE, OUTLINE). Fighters are keyed Gemini sprites about 9% of screen height, feet
anchored to the collider; the stage is a procedurally drawn bone spine with hanging ribs over
the painted skull; the HUD uses portrait medallions whose rings follow the percentage colour
bands (white, yellow, orange, red). Feedback is the game feel: hitstop, shake, slash arcs, hit
sparks, dust. Avoid generic defaults (purple gradients, glassmorphism, all-caps labels except
the title wordmark).

## Credits

Working rules adapted from community skills discovered through the awesome-claude-plugins
index (https://github.com/quemsah/awesome-claude-plugins): obra/superpowers (MIT),
addyosmani/agent-skills (MIT), mattpocock/skills (MIT), multica-ai/andrej-karpathy-skills,
pbakaus/impeccable (Apache-2.0), and Anthropic's frontend-design plugin.
