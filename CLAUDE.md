# Skyfall Brawl — agent guide

A browser 2D platform fighter in the spirit of Brawlhalla. TypeScript (strict), Vite,
Canvas 2D, Web Audio. **Zero runtime npm dependencies.** Deterministic 60 Hz
fixed-timestep simulation, fully separated from rendering so the sim runs in Node tests.

Read `docs/DESIGN.md` (what the game is: fighters, weapons, frame data, stages, feel) and
`docs/ARCHITECTURE.md` (module ownership, shared types, public signatures) before touching
code. Those documents are the spec. When the spec is silent, decide, note the decision in a
code comment at the call site, and keep going.

## Commands

```bash
npm run dev          # Vite dev server on http://127.0.0.1:5173
npm run typecheck    # tsc --noEmit (strict)
npm test             # Vitest unit tests (tests/**/*.test.ts, src/**/*.test.ts)
npm run build        # typecheck + production build to dist/
npm run test:e2e     # Playwright headless Chromium against `vite preview`
npm run check        # typecheck + test + build (run before every commit)
```

## Hard constraints

- No runtime dependencies. Dev deps only: vite, typescript, vitest, @playwright/test.
- `src/sim/**` and `src/shared/**` must never touch `window`, `document`, `performance`,
  `Math.random`, or `Date`. Randomness comes from the seeded PRNG passed in; time comes from
  the tick counter. A sim given the same inputs produces identical state, byte for byte.
- Rendering reads sim state; it never mutates it. Input produces `InputSnapshot`s; the sim
  consumes them. The bot produces the same `InputSnapshot` shape a keyboard does.
- All art is procedural (Canvas 2D paths, gradients, particles) and all sound is synthesized
  (Web Audio). No binary assets, no CDN, no external URLs.
- Original content only: invented fighter and stage names, no Brawlhalla legends, logo, or text.
- Each module owns the files listed in `docs/ARCHITECTURE.md`. Do not edit another module's
  files; if you need a change there, write it down in your report instead.

## How we work (distilled from the superpowers, agent-skills, mattpocock, and
## andrej-karpathy skill sets; see Credits)

**Think before coding.** State assumptions explicitly. If the spec admits two readings that
produce different code, pick one, say which, and say why. If a simpler approach exists, say so.

**Simplicity first.** Minimum code that solves the problem. No speculative abstractions, no
configurability nobody asked for, no error handling for impossible states. If a file could be
half as long, make it half as long. Would a senior engineer call it overcomplicated? Simplify.

**Surgical changes.** Every changed line traces to the task. Do not reformat, "improve", or
refactor neighbours. Remove only the imports and helpers your own change orphaned.

**Test-driven, at seams.** For sim logic (physics, collision, state machine, knockback,
stocks, spawn rules, bot decisions) write the failing test first, watch it fail for the right
reason, write the minimal code to pass, then refactor with the suite green. Tests live at the
public boundary of a module, never against private internals. Vertical slices: one test, one
implementation, repeat. Rendering and audio are verified by the e2e smoke test and by reading
the code, not by unit tests that assert canvas calls.

**Write tests that name the break.** Before writing a test body, name the production change
that would make it fail. Expected values are hand-derived literals from the spec's frame data
and formulas, never recomputed by the code under test. No change detectors (asserting a
constant equals itself), no mirror assertions, no assertions on mocks. Table-driven tests with
literal `want` values are the preferred shape.

**Verification before completion.** No claim of "done", "passing", or "fixed" without running
the proving command in the same breath and reading its output. Tests pass means `npm test`
showed 0 failures just now. Build passes means `npm run build` exited 0 just now. A report
that omits a red test it saw is a false report.

**Systematic debugging.** Root cause before fix. Read the whole error. Reproduce it. Form one
hypothesis, make the smallest change that tests it, verify, and only then fix. Three failed
fixes in a row means the design is wrong; stop and say so rather than attempt a fourth.

**Review on five axes** (correctness, readability, architecture, security, performance).
Approve when the change definitely improves code health, not when it is perfect. A new
conditional bolted onto an unrelated flow is a design smell, not a nit. Repeated conditionals
on the same shape mean a missing model or dispatcher.

## TypeScript rules

- `strict`, `noUncheckedIndexedAccess`, `noImplicitOverride` are on. No `any`. No non-null
  assertions in sim code; narrow instead.
- Model state machines as discriminated unions or a `FighterStateId` string-literal union with
  exhaustive `switch` statements that end in `assertNever`.
- `import type` for types. Prefer `readonly` arrays and objects for definitions (`FighterDef`,
  `WeaponDef`, `AttackDef`, `StageDef`); they are data, not state.
- Use `satisfies` for literal data tables so typos in attack definitions fail the typecheck.

## Game-loop performance rules

- 60 fps on a mid-range laptop is the requirement. Measure in the browser before optimizing,
  then optimize the thing that was measured.
- No allocations in the per-tick hot path where avoidable: reuse vectors, pool particles,
  precompute per-frame hitbox rectangles into existing arrays.
- Draw order: parallax background, stage, fighters, weapons/projectiles, particles, HUD.
  Batch `ctx.save`/`ctx.restore` and `fillStyle` changes; avoid shadows and blur per sprite.
- Every `requestAnimationFrame` callback does fixed-step sim catch-up (capped at 5 steps)
  then one render with interpolation alpha.

## Visual and UX direction (distilled from frontend-design, impeccable, and the UI skills)

- Ground every visual choice in the subject: a floating-island arena fighter. Choose a
  palette and typography deliberately for this world and write them down once in
  `src/render/theme.ts`. Avoid the generic defaults: purple-indigo gradients everywhere,
  glassmorphism on everything, rounded-everything, Inter on slate, one accented word in a
  headline, all-caps labels, numbered markers on things that are not sequences.
- Readability beats decoration. Fighter silhouettes must be distinguishable at 50% camera
  zoom; player colors must be colorblind-safe and used consistently in HUD, outline, and
  damage number.
- Feedback is the game feel: hitstop, screen shake scaled by knockback, hit sparks, landing
  dust, dodge afterimages, invulnerability shimmer, KO burst. Motion answers a player action;
  avoid idle decorative motion that competes with the fight.
- Menus: one orchestrated entrance, keyboard-navigable, with both players' controls visible on
  the controls screen. Text contrast at least 4.5:1 on its background.

## Credits

Working rules above are adapted from community skills discovered through the
awesome-claude-plugins index (https://github.com/quemsah/awesome-claude-plugins):
obra/superpowers (MIT), addyosmani/agent-skills (MIT), mattpocock/skills (MIT),
multica-ai/andrej-karpathy-skills, pbakaus/impeccable (Apache-2.0), and Anthropic's
frontend-design plugin. The project pins these plugins in `.claude/settings.json`.
