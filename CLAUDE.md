# Skyfall Brawl — agent guide

A **Godot 4.x** 2D platform fighter in the spirit of Brawlhalla. Local multiplayer only:
two players on one keyboard (or one controller each). GDScript, statically typed.

Layout:

```
project.godot          # settings, input map (p1_* / p2_* actions), physics, display
scenes/                # playable scenes (Main.tscn is the test arena)
prefabs/               # reusable instanced scenes (Player.tscn, Platform.tscn)
scripts/               # GDScript attached to scenes (player.gd, hitbox.gd, ...)
assets/sprites/        # textures (+ their .import sidecars, which are committed)
tests/                 # headless test runner and test scripts (no external framework)
tools/                 # one-off generator scripts (placeholder sprite generation)
docs/                  # design reference material
```

## Commands

The project is verified with a headless Godot editor binary. Set `GODOT` to its path.

```bash
$GODOT --headless --path . --import                       # import assets, build .godot/ cache
$GODOT --headless --path . --check-only --script scripts/player.gd   # parse + static check one script
$GODOT --headless --path . --script tests/run_tests.gd    # run the physics/input test suite
gdlint scripts tests tools && gdformat --check scripts tests tools   # style (pip install gdtoolkit)
xvfb-run -a $GODOT --path . --rendering-driver opengl3 --quit-after 120   # software-rendered run
```

## Hard constraints

- Godot 4.4 compatible project (`config_version=5`, GL Compatibility renderer). Use only APIs
  that exist in 4.4 so the project opens in any current 4.x editor.
- Everything that affects gameplay runs in `_physics_process` at 60 Hz with frame counters,
  not `Timer` nodes, so behaviour is deterministic and testable headlessly.
- Input is read only through InputMap actions prefixed `p1_` / `p2_` (`left`, `right`,
  `jump`, `down`, `attack`). Never read raw keys in gameplay scripts. Player index selects the
  prefix; the same script serves both players.
- Static typing everywhere (`var x: float`, `-> void`). No `Variant` where a type is known.
  `@export` tunables for every physics constant, with the default values from the README table.
- Scenes are text `.tscn` files committed to git. `.godot/` is never committed; `*.import`
  sidecars are.
- Original content only: invented names, no Brawlhalla legends, logo, or text.
- Do not edit files owned by another module (see the task's ownership table). If you need a
  change there, write it in your report instead.

## How we work (distilled from the superpowers, agent-skills, mattpocock, and
## andrej-karpathy skill sets; see Credits)

**Think before coding.** State assumptions explicitly. If the spec admits two readings that
produce different code, pick one, say which, and say why. If a simpler approach exists, say so.

**Simplicity first.** Minimum code that solves the problem. No speculative abstractions, no
configurability nobody asked for, no error handling for impossible states. If a file could be
half as long, make it half as long.

**Surgical changes.** Every changed line traces to the task. Do not reformat or refactor
neighbours. Remove only the code your own change orphaned.

**Test-driven, at seams.** For movement and input logic: write the failing test in `tests/`
first, run it headless and watch it fail for the right reason, write the minimal code to pass,
then refactor with the suite green. Tests drive the player through InputMap actions
(`Input.action_press` / `action_release`) and observe `velocity`, `global_position`,
`is_on_floor()`, and node state. They never call private helpers.

**Write tests that name the break.** Before writing a test body, name the production change
that would make it fail. Expected values are hand-derived literals from the tunables (for
example: gravity 1500 px/s² for 30 frames at 1/60 s adds 750 px/s), never recomputed by the
code under test. No change detectors, no mirror assertions.

**Verification before completion.** No claim of "done", "passing", or "fixed" without running
the proving command right then and reading its output: the test runner printed 0 failures,
`--check-only` exited 0, `gdlint` printed no problems. A report that omits a red test it saw
is a false report.

**Systematic debugging.** Root cause before fix. Read the whole error (Godot prints script
path and line). Reproduce it in a test. One hypothesis, smallest change, verify. Three failed
fixes in a row means the design is wrong; stop and say so.

## GDScript rules

- `move_and_slide()` takes no arguments in Godot 4 and uses `velocity`. Gravity is applied by
  the script, not the engine. `is_on_floor()` is valid only after `move_and_slide()` ran in a
  previous frame, so read it before moving in the current frame.
- Use `Input.is_action_just_pressed` for edge-triggered inputs (jump, attack) and
  `Input.get_axis(left, right)` for horizontal movement.
- Frame counters are `int` and count physics frames; durations in the README are given in
  frames at 60 Hz. Speeds are px/s and accelerations px/s², scaled by `delta`.
- `@onready var sprite: Sprite2D = $Sprite2D` style for child references; node names are
  part of the contract between scene and script.
- Signals for cross-node communication (`damage_changed`, `hit_landed`); no `get_parent()`
  chains into siblings.
- Keep `gdlint` clean with its default config and `gdformat` formatting (tabs, 100 columns).

## Visual direction

Placeholder sprites are generated procedurally and must read at a glance: distinct
colorblind-safe player colors (P1 teal, P2 orange), a visor or marker that shows facing, and
a silhouette that differs from the arena's grey platforms. Real art arrives later; keep the
`Sprite2D` texture swap trivial (same pivot, same frame size).

## Credits

Working rules adapted from community skills discovered through the awesome-claude-plugins
index (https://github.com/quemsah/awesome-claude-plugins): obra/superpowers (MIT),
addyosmani/agent-skills (MIT), mattpocock/skills (MIT), multica-ai/andrej-karpathy-skills,
pbakaus/impeccable (Apache-2.0), and Anthropic's frontend-design plugin.
