# Fable FPS — First-Person Survivor-like

A first-person arena survival game. Monsters spawn continuously and run at you; you fight back with sword and shield. Difficulty ramps over time, punctuated by bosses. Dying is part of the loop: kills earn currency, and on death you spend it on permanent upgrades, then dive back in stronger.

---

## 1. Language: GDScript (chosen — platform flexibility first)

**Decision: GDScript**, prioritizing platform flexibility. GDScript exports everywhere Godot does — including web, which C# builds cannot target. Bonus: instant script reload (no build step) keeps combat-feel iteration fast, which matters a lot in Phase 1.

Discipline that makes GDScript hold up at full scope:

- **Static typing everywhere.** Type every variable, parameter, and return (`var speed: float`, `func take_damage(info: AttackInfo) -> void`). Enable the `untyped_declaration` warning as an error in project settings from day one. Typed GDScript catches most of what C#'s compiler would and is measurably faster at runtime.
- **`class_name` on every core type** (`AttackInfo`, `StatBlock`, `EnemyData`, …) so systems get real type checks and editor autocomplete instead of duck-typing.
- **Plan for the horde hot loop.** Script-side per-enemy logic (steering, attack timers) is GDScript's weak spot at scale. Mitigations, in escalation order: keep per-enemy `_physics_process` trivial → move steering into one manager iterating a packed array (data-oriented, see §3.6) → talk to `PhysicsServer3D` directly if node overhead ever dominates. The demo's 50-enemy target is comfortably fine; this matters at 200+.

Trade-off accepted: less compile-time safety and weaker refactoring tools than C#. The typing discipline above is the mitigation, not optional style. Stay single-language — no C# mixing.

---

## 2. Phase 1 — Playable Demo (the only priority right now)

**Goal:** one full loop — *spawn in → fight → die → buy upgrades → run again, measurably stronger* — with graybox visuals. Everything below is deliberately minimal but built on the real architecture from §3 so nothing gets thrown away.

### Demo scope

| Piece | Demo version |
|---|---|
| Arena | Flat graybox floor with boundary walls, one `WorldEnvironment` for basic lighting |
| Player | FPS controller (WASD + mouse look, sprint optional), capsule body |
| Sword | LMB swing: short cooldown, hits via an `Area3D` hitbox arc in front of camera; simple viewport-space swing animation (even just a rotating mesh) |
| Shield | Hold RMB to block: negates (or heavily reduces) damage from the front ~120°, drops move speed while held |
| Enemy | One melee chaser: capsule with eyes, straight-line steering toward player, windup → lunge attack → recover. No navmesh yet — open arena doesn't need it |
| Spawning | Timed spawner placing enemies in a ring outside player view; spawn interval shrinks and enemy HP/damage scale with elapsed run time |
| Damage/health | Shared health component on player and enemies; hit flash + death poof placeholder |
| Currency | Gold per kill, floats up in HUD |
| Death → upgrade | Death screen shows run stats + upgrade shop: **+Damage, +Max Health, +Attack Speed, +Move Speed** (escalating costs, no caps). Buy, then "Next Run" |
| Persistence | Gold + purchased upgrade levels saved to `user://save.json` so quitting doesn't wipe progress |
| HUD | Health bar, gold counter, run timer, kill counter |

### Demo acceptance criteria

1. A run lasts 2–5 minutes for a fresh character and visibly gets harder.
2. Dying never feels like a dead end — you always afford *something* after a run.
3. Three runs in, the power increase is obviously felt (kill speed, survivability).
4. 60 fps with 50+ live enemies on a mid-range machine.

### Explicitly *not* in the demo

Bosses, XP/level-ups, second weapon, spells, sound design, real models/animations, menus beyond death screen, prestige. All are Phase 2+ and the architecture leaves room for each.

---

## 3. Core Architecture (extensibility design)

Guiding rule: **behavior lives in scripts/scenes, numbers and content live in `Resource` files.** Adding an enemy, weapon, or upgrade should mean creating a `.tres` file and (at most) one scene — no edits to core systems.

### 3.1 Autoload singletons

| Autoload | Responsibility |
|---|---|
| `EventBus` | Global signals only, no logic: `EnemyKilled(EnemyData, position)`, `PlayerDamaged`, `PlayerDied`, `CurrencyChanged(id, amount)`, `RunStarted`, `RunEnded(RunStats)`. Decouples HUD, spawner, progression from each other |
| `GameManager` | Top-level state machine: `Menu → InRun → DeathScreen → (shop) → InRun`. Owns scene transitions |
| `MetaProgression` | Persistent state: currency balances (a `Dictionary[StringName, int]` keyed by currency id — this is the prestige hook), purchased upgrade levels, save/load to `user://`. Exposes `get_stat_modifiers()` consumed by the player on spawn |

### 3.2 Component scenes (composition over inheritance)

Small reusable nodes attached to any actor:

- **`HealthComponent`** — `Max`, `Current`, `TakeDamage(AttackInfo)`, signals `Damaged`, `Died`. Identical on player and monsters.
- **`HitboxComponent`** (Area3D) — carries an `AttackInfo` when active; **`HurtboxComponent`** (Area3D) — receives it, routes through the owner's mitigation (block check, armor later) into `HealthComponent`.
- **`AttackInfo`** (lightweight `RefCounted` class with `class_name`) — `source`, `damage`, `damage_type`, `knockback_dir/force`. Every damage event in the game flows through this one pipeline, so adding crits, elemental types, lifesteal, or damage numbers later is a change in one place.

### 3.3 Stats system (the most important extensibility piece)

- **`StatBlock`** — dictionary of `StatId → base value` (MoveSpeed, MaxHealth, Damage, AttackSpeed, BlockAngle, …) plus a modifier list.
- **`StatModifier`** — `{ StatId, Flat | PercentAdd | PercentMult, value, source }`. Resolution order: base → sum flats → sum additive % → product of multiplicative %.
- Upgrades, in-run boons, weapon bonuses, and future prestige multipliers are *all just modifier sources*. Nothing else in the game hardcodes a stat formula.

### 3.4 Data resources (content as `.tres` files)

- **`EnemyData`** — display name, base stats, scene to instance, gold/XP reward, spawn weight, tags (`boss`, `ranged`, …).
- **`WeaponData`** — damage, swing time, reach/arc, scene for the viewmodel. Weapon behavior = a `Weapon` base class (`try_attack()`, `try_block()`); sword-and-board is the first subclass, spells later implement the same interface (a spell is a weapon with a cast time and a projectile/AoE payload).
- **`UpgradeData`** — id, name, description, currency id + cost curve, `StatModifier[]` granted per level, max level (0 = infinite), optional prerequisite id. The death-screen shop is 100% generated from a folder of these.
- **`WaveTable` / `DifficultyCurve`** — spawn interval over time, weighted enemy pool per time band, scheduled events (`t=120s: spawn boss X`). The spawner reads this; new content = new rows, and bosses are just scheduled entries pointing at an `EnemyData` with the `boss` tag.

### 3.5 Run Director (per-run scene node)

Owns the in-run loop: elapsed time, difficulty scalar `t`, reads the `WaveTable`, spawns enemies (ring outside camera, live-count cap), applies time-based HP/damage multipliers to spawned `EnemyData`, fires scheduled boss events, accumulates `RunStats` (kills, gold, time survived) for the death screen.

### 3.6 Enemy AI

Demo: straight-chase steering + a tiny state machine (`Chase → Windup → Attack → Recover`) directly on the enemy script. Structured so states are methods on a base `Enemy` class — ranged/boss enemies override behavior, not the plumbing. NavigationAgent3D only if/when arenas gain obstacles. If live counts ever threaten frame time, the escape hatch is moving steering into a single manager iterating a list (data-oriented), which the component split keeps easy.

### 3.7 Scene/folder layout

```
res://
  autoload/        event_bus.gd, game_manager.gd, meta_progression.gd
  components/      HealthComponent, Hitbox/HurtboxComponent
  core/            StatBlock, StatModifier, AttackInfo
  data/
    enemies/       *.tres (EnemyData)
    weapons/       *.tres (WeaponData)
    upgrades/      *.tres (UpgradeData)
    waves/         *.tres (WaveTable)
  actors/
    player/        Player.tscn + controller, camera rig, weapon mount
    enemies/       EnemyBase.tscn, ChaserEnemy.tscn
  weapons/         weapon.gd, SwordAndShield.tscn
  systems/         run_director.gd, spawner.gd
  ui/              HUD.tscn, DeathScreen.tscn, UpgradeShop.tscn
  levels/          Arena.tscn
```

---

## 4. Progression & Balance Dimensions

**Demo:** single currency (gold) → permanent upgrades on death. Simple, proves the loop.

**Phase 2 — dual-track progression** (this is where playstyle choice emerges):

- **Gold** (persistent): dropped per kill, spent on *permanent* meta upgrades between runs.
- **XP** (per-run): fills a bar; each in-run level-up pauses briefly and offers a choice of 3 temporary boons (this run only) — the Vampire Survivors moment.

Balance levers this creates: risky play (fighting bosses/packs) can reward more XP for a stronger *current* run, while safe farming maximizes gold for *permanent* growth. Upgrades can later specialize into builds (block-counter tank vs attack-speed glass cannon vs spell caster) because everything is `StatModifier`s on a shared `StatBlock`.

**Prestige (design for, don't build):** the hooks already exist — currencies are keyed by id in `MetaProgression`, so prestige is: add a `prestige_shards` currency earned from a reset condition, a "reset gold + upgrades" operation, and a prestige upgrade folder whose modifiers apply globally. No system rewrites required.

---

## 5. Phased Roadmap

| Phase | Content | Exit criteria |
|---|---|---|
| **0. Setup** | Folder skeleton, autoloads registered, input map (`move_*`, `look`, `attack`, `block`, `sprint`), GDScript strictness warnings (`untyped_declaration` etc.) set to error in project settings | Empty arena runs clean with zero warnings |
| **1. Demo** | Everything in §2 | Acceptance criteria in §2 met |
| **2. Depth** | XP + in-run boon choices, 2–3 new enemy types (fast/tanky/ranged) via `EnemyData`, hit feedback pass (damage numbers, screen shake, SFX) | A run has meaningful in-run decisions |
| **3. Bosses & arsenal** | First boss (scheduled `WaveTable` event, unique attack pattern), second weapon, first 1–2 spells on the `Weapon` interface, weapon/spell unlocks as upgrades | Boss fight at ~3 min is a run highlight |
| **4. Meta & polish** | Main menu, settings, upgrade tree UI (replacing flat shop), balance pass on curves, art/audio pass | Shippable demo build |
| **5+ (parked)** | Prestige layer, multiple arenas, achievements | — |

---

## 6. Risks / open questions

- **Melee feel in first person is the make-or-break.** Budget real time in Phase 1 for swing timing, hit pause, and reach tuning — a survivor-like where hitting things feels mushy fails regardless of systems quality.
- **Renderer:** project is on GL Compatibility — with GDScript that's the right default, since it's the only renderer that reaches web and low-end hardware, which is exactly the platform flexibility being prioritized. Revisit Forward+ in Phase 4 only if the visual target demands it *and* web is off the table by then.
- **GDScript horde performance:** the 50-enemy demo target is safe, but if enemy counts grow past ~200, per-node scripting may bottleneck before anything else does. The escalation path in §1/§3.6 (typed scripts → manager-iterated steering → PhysicsServer3D) is the plan; profile before escalating.
- **Block design:** free hold-to-block vs stamina/timing-based (parry). Demo ships hold-to-block; revisit once combat feel is testable.
