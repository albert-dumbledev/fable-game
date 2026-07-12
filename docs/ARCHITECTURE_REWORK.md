# Architecture Rework — Perf Headroom, Scaling Refactors, Tuning Knobs

> **Status (2026-07-12): plan authored, nothing shipped.** M0–M6 pending, in
> order. M0 (measurement) gates M2; M3 is the enabling step for M4; M6 waits
> for the next weapon. Record stress-harness numbers and per-milestone
> implementation notes here as they land.

## Why

An architecture pass over the whole codebase (2026-07-12) found the bones
healthy — data-driven `.tres` content, the EventBus, pooled VFX
([vfx_pool.gd](../core/vfx_pool.gd)), the static `EnemyBase.alive` list, and
graphics presets with `render_scale` already carrying the web-GPU side. Three
structural debts remain, and they compound if left:

1. **Perf ceiling is physics, not rendering.** The wave table ramps
   `max_alive` to 120, and every enemy is a `CharacterBody3D` with
   `collision_mask = 7` (world | player | enemy) — 120 kinematic capsules
   packed into a ring, all colliding with each other on the physics tick.
   On weak machines and the single-threaded web export this dominates long
   before draw calls do. On top of it sit a few genuine hot spots: the Mass
   Driver sweep is O(shoved × alive) *per physics frame* with an array
   duplication per enemy per frame, and every damage event allocates a fresh
   `Tween` for the scale punch.
2. **The Aspect flag pattern has outgrown itself.** Behavioral Aspects are a
   flag plus hand-placed `has_ability` branches: four live inline in
   [enemy_base.gd](../actors/enemies/enemy_base.gd) (Cold Blood, Dead Weight,
   Unclosed Wound, Floor Below), ~15 more in
   [player.gd](../actors/player/player.gd) (1,665 lines), and the hammer
   checks five flags per slam. Every forge wave grows three god files —
   the opposite of PLAN.md §3's "adding content means a `.tres` and at most
   one scene, no edits to core systems".
3. **Balance numbers live in code.** ~250 constants across player, enemy
   base, weapons, spawner, and run director. They are superbly commented
   (keep that), but retuning `COLD_BLOOD_MULT` or `ELITE_CHANCE` is a code
   edit + re-verify, and some constants are duplicated: `ARENA_HALF` appears
   in **seven** files, disagreeing (18.5 everywhere except
   [pickup.gd](../actors/pickups/pickup.gd)'s 19.0).

The milestones below are ordered: measure, then bank the cheap wins, then the
one feel-sensitive physics change, then the refactor pair that fixes 2 and 3
together, then the tuning sweep. Each is independently shippable and
headless-verifiable per the `godot-verify` skill.

---

## M0 — Measure first: perf overlay + stress harness

Nothing in M1/M2 gets argued from vibes. Two small tools:

- **Perf overlay**: a debug `CanvasLayer` showing FPS,
  `Performance.get_monitor()` for `TIME_PHYSICS_PROCESS` / `TIME_PROCESS` /
  `OBJECT_NODE_COUNT`, plus `EnemyBase.alive.size()` and `Pickup.edible.size()`.
  Toggle via a cheat word (`perfhud`), reusing the `postit` buffer mechanism
  in [settings.gd](../autoload/settings.gd) — no settings-panel real estate
  for a dev tool.
- **Stress harness**: `test/StressSmoke.tscn` following the existing smoke
  pattern — spawn N chasers (30 / 60 / 120) around the player in the real
  arena, run ~10 s, print average and worst physics-frame time, exit nonzero
  on script errors. Headless numbers miss the GPU but capture exactly the
  physics/script side M1–M2 target. For the web side: load the overlay in a
  web export build and eyeball the same three counts manually.

**Acceptance:** numbers for 30/60/120 alive recorded in this doc's status
block (desktop headless + one web run). They decide whether M2 ships at all.

## M1 — Quick wins pass (no behavior changes)

Five local fixes, one PR-sized pass, all covered by existing harnesses:

- **Mass Driver sweep** (`EnemyBase._mass_driver_sweep`): runs every physics
  frame while an enemy is hard-shoved and calls `alive.duplicate()` each
  time — a pack-wide hammer shove means ~30 enemies × 120 alive × one array
  copy each, per frame, during the most VFX-heavy beat. Fix: iterate `alive`
  directly, collect victims into a local array, apply hits after the scan
  (the duplicate only existed because `receive_hit` can kill mid-loop);
  compare `length_squared()` against `MASS_DRIVER_CONTACT²`. Same shape for
  `Player._open_grave_pull` (short-lived, but same per-frame duplicate).
  Event-scoped `duplicate()` calls (slams, novas, death tremors) stay — they
  fire once, not per frame.
- **Hit flash without tweens** (`EnemyBase._on_damaged`): a fresh `Tween` per
  damage event means a 30-enemy nova allocates 30 tweens in one frame.
  Replace with a `_hit_flash: float` set on hit and decayed in
  `_physics_process`, driving `mesh.scale` directly. Same look, zero
  allocation, no tween-lifetime bookkeeping.
- **Pickup node diet** (`Pickup._ready`): every pickup instantiates six
  kind-meshes and hides five. `queue_free()` the unused five in `_ready` —
  with hundreds of pickups alive late-run that's ~5/6 of their node count
  gone. `_start_pulse` already targets only the kept mesh.
- **Enemy shadow casters**: at cap, ~120 bodies plus eyes and fists render
  into the (web: 2048) shadow map whenever sun shadows are on. In
  `EnemyBase._ready`: eyes and fist `cast_shadow = OFF` unconditionally
  (never readable); body shadow gated on a new `enemy_shadows` setting folded
  into the presets in [settings.gd](../autoload/settings.gd) — high `true`,
  medium/low `false`. Read once at spawn (enemies are short-lived; a preset
  change applies to the next spawns — acceptable, note in the settings docs).
- **Arena bounds single source** (`ARENA_HALF` × 7): new
  `levels/arena_root.gd` on the Arena root with
  `@export var half_extent := 18.5`, writing a static `ArenaBounds.half` on
  `_enter_tree`. All seven call sites (spawner ring clamp, pickup scatter
  clamp, death-spawn clamp, boulder/caster/gilded/revenant arena checks,
  player leap/levitate clamps) read it. Unify pickup's 19.0 down to 18.5 —
  the wall inner face is at 19.5, so nothing visibly changes. This is also
  the prerequisite for any future second arena or Depth-specific geometry.

**Acceptance:** all existing smokes green; stress harness delta vs M0
recorded; a manual hammer-Mass-Driver run to confirm the sweep still reads
identically.

## M2 — Horde physics: separation steering replaces enemy-enemy collision

**Gated on M0** showing physics time dominating at 60+ alive. This is the one
feel-sensitive change in the plan, so it ships alone.

- Drop the enemy bit from enemy collision masks: `collision_mask 7 → 3`
  (world | player), set in `EnemyBase._ready` (`collision_mask &= ~4`) so all
  12 enemy scenes inherit it without scene edits. Enemies keep
  `collision_layer = 4`, so the **player** still collides with them
  (`Player.NORMAL_COLLISION_MASK = 5` is untouched — bodies still block you,
  dashes still pass through by mask swap exactly as today).
- Replace body-vs-body with script separation: each enemy, every 4th physics
  frame (staggered by `get_instance_id() % 4`), scans `EnemyBase.alive` for
  neighbors within ~1 m (squared distances), accumulates a normalized push,
  and caches it; the cached push is added to velocity every frame in the
  movement states. At 120 alive that's ~3.6k distance checks per frame of
  pure math — far cheaper than the solver contacts it replaces. Escalation
  if ever needed: a coarse spatial hash over the arena; **not** built now.
- Gameplay notes: shove plowing (boss charges, hammer) already works through
  script (`apply_shove`, the Mass Driver sweep), not solver contacts, so it
  survives unchanged. PLAN.md §1 named manager-driven steering as the
  sanctioned escalation path — this is that path's first half, without the
  data-oriented rewrite (still reserved for a 200+ cap that isn't planned).

**Acceptance:** stress harness shows the physics win; EnemySmoke green;
manual playtest watch items — packs shouldn't visibly interpenetrate at rest,
and windup spacing around the player should still read. If it fails the feel
check, the fallback knob is separation radius/strength, not reverting masks.

## M3 — Split player.gd along its seams (mechanical, enables M4)

Three subsystems in [player.gd](../actors/player/player.gd) already have
disjoint state, constants, and logic; extract each to a child node under
`actors/player/`:

- **`player_mobility.gd`** — dash / Crashing Leap / Levitate: the `LeapPhase`
  machine, charges/cooldown, indicator, camera tweens (~450 lines).
- **`player_casting.gd`** — mana pool, fireball + Deep Draught overcharge,
  frost nova + Waiting Cold rune, charge orbs (~350 lines).
- **`player_guard.gd`** — guard meter, block/parry resolution, riposte
  priming/chain, Patient Dark clock (~250 lines).

Rules for the split: `mitigate_hit` and `has_ability` stay on `Player` (the
hurtbox and every external caller depend on them) and delegate inward; the
HUD-facing API (`get_cooldown_remaining/_max`) stays on `Player` too. No
behavior change, no constant renames — constants move with their subsystem.

**Acceptance:** MobilitySmoke, AspectSmoke, DepthSmoke, RecapSmoke all green;
player.gd lands under ~500 lines.

## M4 — RunEffect hooks + Aspect knobs move into data (the big one)

Converts every future forge wave from "edit three core files" to "add one
script + one `.tres`", and gives Aspect numbers a data home in the same
stroke.

- **`core/run_effect.gd`** — `class_name RunEffect extends Resource`, with
  no-op virtual hooks mirroring where the inline branches live today:
  `modify_outgoing_hit(info, target, player) -> AttackInfo`,
  `modify_incoming_hit(info, player) -> AttackInfo`,
  `on_enemy_damaged(victim, info, player)`,
  `on_player_kill(victim, overkill_surplus, player)`,
  `on_perfect_block(attacker, player)`, `on_dash_sweep(...)`,
  `on_slam_hit(enemy, ...)`. Effects are Resources so every knob is an
  `@export` — editable per-Aspect in its existing `.tres`, doc comment
  attached to the export in the effect script (the script is the schema doc;
  the design "why" comments migrate there, not into thin air).
- **`BoonData` gains `@export var effect: RunEffect`.** `grant_ability` keeps
  setting the flag (cheap gates and save-compat are untouched) and
  additionally registers the boon's effect into a `Player._effects` array;
  dispatch is a plain loop at each hook site.
- **House rules stay central, not per-effect.** `no_proc` is checked once in
  `EnemyBase.mitigate_hit`/`_on_damaged` *before* dispatching proc-capable
  hooks — an effect never sees a hit it isn't allowed to amplify. The
  no-mutation rule is structural: `modify_*` hooks must return a fresh
  `AttackInfo` when they change anything (add an `AttackInfo.with_damage()`
  helper so effects can't get it wrong). The Dead Weight chain guard and its
  overkill accounting stay in EnemyBase.
- **Migration is incremental.** Wave 1 ports the four EnemyBase residents —
  Cold Blood, Unclosed Wound, Floor Below, Dead Weight — because that file
  has the worst god-file pressure and all four map 1:1 onto the hooks above.
  Player-side Aspects port opportunistically, one lane per touch. **New
  Aspects must use hooks from day one** — update the `add-content` skill in
  the same PR; it is the authoring workflow of record.

**Acceptance:** AspectSmoke/DepthSmoke green; enemy_base.gd no longer
mentions any Aspect by name; retuning Cold Blood (the DEPTHS.md
trim-to-1.35× escape hatch) is a `.tres` edit with no code change.

## M5 — Balance knobs into data (feel stays in code)

The split rule, applied file by file: **feel constants stay in code**
(tween poses, colors, FOV punches, `FIST_REST` and friends — they're
animation, not balance); **balance constants move to `data/tuning/`**
resources loaded once at run start via a static accessor
(`Tuning.player()`, `Tuning.economy()` — `.tres` over scene exports for
cleaner diffs, matching the registry conventions):

- **`PlayerTuning`** — guard economy (`GUARD_MAX/REGEN/HIT_COST`), parry
  windows (`PERFECT_BLOCK_WINDOW`, `PERFECT_BLOCK_STUN`, riposte numbers),
  mobility cooldowns, mana economy (`MANA_*`, spell costs).
- **`EconomyTuning`** — drop chances (`MAGNET_DROP_CHANCE`,
  `HEALTH_DROP_CHANCE`), elite gates (`ELITE_CHANCE`, `ELITE_MIN_ELAPSED`,
  `ELITE_COOLDOWN`, HP/reward mults), scavenger threshold/cooldown,
  `ASPECT_ELITE_CAP`.
- **XP curve** (`XP_BASE`, `XP_GROWTH` in
  [run_director.gd](../systems/run_director.gd)) → exports on
  [wave_table.gd](../core/wave_table.gd); it is the difficulty schedule of
  record and already owns every sibling curve.
- Optional, cheap after the above: a `retune` cheat word that re-loads the
  tuning `.tres` (`CACHE_MODE_IGNORE`) and re-applies — balance iteration
  becomes save + keypress instead of a restart.

Each doc comment moves with its knob onto the `@export`. Aspect-specific
numbers are **not** part of this milestone — they already moved in M4.

**Acceptance:** smokes green; one end-to-end proof retune (e.g. bump
`ELITE_CHANCE` in the `.tres`, watch DepthSmoke's elite assertions still
pass) recorded here.

## M6 — Weapon skill dispatch stops being stringly (when weapon #4 nears)

`Player.get_cooldown_remaining/_max` match on hardcoded skill ids and
[hud.gd](../ui/hud.gd)'s `SKILLS` table duplicates the list — a fourth weapon
currently touches three files. Move it onto the weapon:
`Weapon.skill_ids() -> Array[StringName]` plus
`skill_cooldown(id)/skill_cooldown_max(id)`; the HUD builds slots from the
mounted weapon's list plus the player-owned globals; Player delegates
weapon-owned ids. Ship it as the first commit of the next weapon's branch —
no reason to churn the HUD before then.

---

## Deliberately not doing (and what would change that)

- **Data-oriented enemy manager / `PhysicsServer3D`-direct bodies** — the
  PLAN.md §1 escalation reserved for a 200+ cap. M2's separation steering is
  expected to buy the current 120 comfortably; revisit only if M0 numbers
  post-M2 still miss the frame budget on target hardware.
- **MultiMesh pickup renderer** — only if M0 shows pickups mattering after
  the M1 node diet. The manual-motion design is already the cheap approach.
- **RunContext to own the run-scoped statics** (`EnemyBase.alive`,
  `depth_time_scale`, `dead_weight_chaining`, `Pickup.magnets/edible`) —
  each static carries a reset obligation RunDirector already handles
  defensively. Consolidate the day the *next* such static gets added, not
  before.
- **Splitting death_screen.gd** (842 lines: shop + recap + records) — split
  along those seams on its next feature touch, not as standalone churn.
- **Moving feel constants to data** — tween poses and juice numbers change
  with their code; a resource indirection would only slow that work down.
