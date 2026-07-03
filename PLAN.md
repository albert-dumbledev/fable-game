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

## 2. Phase 1 — Playable Demo ✅ SHIPPED (and exceeded)

**Status:** done. The full loop — *spawn in → fight → die → buy upgrades → run again, measurably stronger* — is playable, and the demo overshot its scope: perfect-block parry (stuns the attacker), a three-phase sword swing animation, a rotating minimap, physical gold/XP pickups that burst from corpses and magnet to the player, and the full XP → level-up → boon-choice system with rarities all shipped ahead of schedule. See §5 for the per-phase record.

**Original goal (kept for the record):** one full loop with graybox visuals. Everything below was deliberately minimal but built on the real architecture from §3 so nothing got thrown away — which is exactly what happened.

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

### Explicitly *not* in the demo (then)

Bosses, XP/level-ups, second weapon, spells, sound design, real models/animations, menus beyond death screen, prestige. Of these, **XP/level-ups shipped in Phase 2** and **bosses, the second weapon, and two spells shipped in Phase 3**; the rest remain Phase 4+.

---

## 3. Core Architecture (extensibility design)

Guiding rule: **behavior lives in scripts/scenes, numbers and content live in `Resource` files.** Adding an enemy, weapon, or upgrade should mean creating a `.tres` file and (at most) one scene — no edits to core systems.

### 3.1 Autoload singletons

| Autoload | Responsibility |
|---|---|
| `EventBus` | Global signals only, no logic. The list has grown past the original five — it now covers the run lifecycle (`run_started`, `run_ended`), combat (`enemy_killed`, `player_damaged`, `player_died`, `attack_blocked`, `perfect_block`), economy (`currency_changed`, `pickup_collected(kind, value)`), and progression (`xp_changed`, `level_up`). See `autoload/event_bus.gd` for the canonical list; the rule stands: signals only, no state |
| `GameManager` | Top-level state machine: `Menu → InRun → DeathScreen → (shop) → InRun`. Owns scene transitions |
| `MetaProgression` | Persistent state: currency balances (a `Dictionary[StringName, int]` keyed by currency id — this is the prestige hook), purchased upgrade levels, save/load to `user://`. Exposes `get_stat_modifiers()` consumed by the player on spawn |

### 3.2 Component scenes (composition over inheritance)

Small reusable nodes attached to any actor:

- **`HealthComponent`** — `Max`, `Current`, `TakeDamage(AttackInfo)`, signals `Damaged`, `Died`. Identical on player and monsters.
- **`HitboxComponent`** (Area3D) — carries an `AttackInfo` when active; **`HurtboxComponent`** (Area3D) — receives it, routes through the owner's mitigation (block check, armor later) into `HealthComponent`.
- **`AttackInfo`** (lightweight `RefCounted` class with `class_name`) — currently `source` + `damage` (damage types/knockback are still future fields). Every damage event flows through this one pipeline — melee, enemy punches, and spitter projectiles alike — which is how blocking, thorns, and damage numbers all hooked in without touching callers. Full pipeline documented in **[docs/COMBAT.md](docs/COMBAT.md)**.

### 3.3 Stats system (the most important extensibility piece)

- **`StatBlock`** — dictionary of stat id → base value plus a modifier list, with per-stat caching. Canonical ids live in `core/stats.gd` (`max_health`, `damage`, `attack_speed`, `move_speed` so far).
- **`StatModifier`** — `{ stat, Flat | PercentAdd | PercentMult, value }` as a `Resource`, so `.tres` files can embed them. Resolution order: base → sum flats → ×(1 + sum additive %) → ×∏(1 + multiplicative %).
- Upgrades, in-run boons, weapon bonuses, and future prestige multipliers are *all just modifier sources*. Nothing else in the game hardcodes a stat formula. This bet paid off: the entire boon rarity system is "duplicate the modifier, multiply its value" (see [docs/BOONS.md](docs/BOONS.md)).

### 3.4 Data resources (content as `.tres` files)

- **`EnemyData`** — display name, scene, base stats, attack timing (`windup_time`, `recover_time`, `attack_range`), gold/XP reward, spawn weight, `min_elapsed` time gate, tags (`boss`, …). Four enemy types exist as pure data files. Full reference: **[docs/ENEMIES.md](docs/ENEMIES.md)**.
- **`WeaponData` / `WeaponRegistry`** — id, damage, swing time, `can_block`, scene path, unlock ability. Weapon behavior = a `Weapon` base class (`try_attack()`, `set_blocking()`, `set_stowed()`, `notify_block_success()`); Sword & Shield and the Warhammer are the two subclasses. **Loadout:** one weapon per run, picked on the death screen from `data/weapons/registry.tres`; unlocks are ability-granting `UpgradeData` like spells; the choice persists in the save (`MetaProgression.selected_weapon`) and the player instances the scene into its weapon mount on spawn. Details: [docs/COMBAT.md](docs/COMBAT.md).
- **`UpgradeData`** — id, name, description, base cost + geometric cost growth, `StatModifier[]` granted per level, max level (0 = infinite). The death-screen shop is 100% generated from `data/upgrades/registry.tres`.
- **`BoonData` / `BoonRegistry`** *(new since the original plan)* — run-scoped level-up rewards. Same `StatModifier` machinery as upgrades, only the lifetime differs; unique boons grant ability flags instead. Full reference: **[docs/BOONS.md](docs/BOONS.md)**.
- **`WaveTable`** — spawn interval ramp, HP/damage/reward growth per minute, alive-cap ramp, weighted + time-gated enemy pool, and scheduled one-shot events (bosses — Phase 3, in progress). The spawner reads this; new content = new rows.

### 3.5 Run Director (per-run scene node)

Owns the in-run loop: elapsed time, spawner pacing, XP/level bookkeeping (level-ups fire the boon choice), and the death → stats handoff to `GameManager`. Kill and gold tallies count *collected pickups*, not kills — rewards are physical drops now (§4). Stats are still a plain `Dictionary` (`time`, `kills`, `gold`); a real `RunStats` class remains future work.

### 3.6 Enemy AI

Shipped as designed, plus one state: `Chase → Windup → Attack → Recover`, with **`Stunned`** added for the perfect-block reward. States are methods on `EnemyBase` — the ranged Spitter overrides `_chase()` (kiting) and `_begin_attack()` (projectile) and inherits everything else, which validated the "override behavior, not plumbing" bet. Attacks are telegraphed (windup color shift + fist cock-back, then a punch lunge). Details and authoring guide: **[docs/ENEMIES.md](docs/ENEMIES.md)**. NavigationAgent3D still deferred until arenas gain obstacles; the data-oriented steering escape hatch remains unused and available.

### 3.7 Scene/folder layout

```
res://
  autoload/        event_bus.gd, game_manager.gd, meta_progression.gd
  components/      HealthComponent, Hitbox/HurtboxComponent
  core/            StatBlock, StatModifier, Stats (id registry), AttackInfo,
				   EnemyData, WeaponData, UpgradeData(+Registry),
				   BoonData(+Registry), WaveTable, DamageNumber
  data/
	enemies/       *.tres (EnemyData) — chaser, sprinter, brute, spitter, …
	weapons/       sword.tres, warhammer.tres + registry.tres (loadout pool)
	upgrades/      *.tres + registry.tres (drives the death-screen shop)
	boons/         *.tres + registry.tres (drives the level-up screen)
	waves/         default.tres (WaveTable)
  actors/
	player/        Player.tscn + controller, camera rig, weapon mount
	enemies/       enemy_base.gd, ChaserEnemy/Sprinter/Brute/SpitterEnemy.tscn,
				   Projectile.tscn
	pickups/       Pickup.tscn (gold/XP drops)
  weapons/         weapon.gd, SwordAndShield.tscn, Warhammer.tscn, Fireball.tscn
  systems/         run_director.gd, spawner.gd
  ui/              HUD.tscn (incl. minimap), DeathScreen.tscn, BoonScreen.tscn
  levels/          Arena.tscn
  docs/            BOONS.md, COMBAT.md, ENEMIES.md (system sub-plans)
```

---

## 4. Progression & Balance Dimensions

**Shipped: the dual-track economy, with a twist the original plan didn't have — rewards are physical objects.**

- **Gold** (persistent): spent on permanent meta upgrades at the death screen (`data/upgrades/`, geometric cost growth ~×1.4/level), and doubles as an *in-run* sink (boon rerolls) and *in-run* source (boon skips).
- **XP** (per-run): fills the HUD bar; threshold is `20 + 15×level`. Each level-up pauses the run and offers 3 boons with rolled rarities (Common ×1.0 → Legendary ×3.5) — the Vampire Survivors moment, working as intended. Full design: **[docs/BOONS.md](docs/BOONS.md)**.
- **Both drop as pickups, not HUD increments.** Enemies explode into up to 8 gold + 8 XP pieces that burst ballistically, bounce, then magnet to the player. Rewards are granted on *collection*, not on kill — leaving loot on the ground when overwhelmed is a real cost, and diving into a pack to vacuum a fountain is a real risk. Drop values scale with run time (`WaveTable.reward_growth_per_min`, +30%/min) so late-run kills stay worth collecting.

Balance levers this creates: risky play rewards a stronger *current* run (XP boons, loot diving), safe farming maximizes *permanent* growth (gold), and the skip-vs-take boon decision converts unwanted level-ups into meta progress. Builds can specialize (block-counter tank vs attack-speed glass cannon vs spell caster) because everything is `StatModifier`s on a shared `StatBlock` — the unique-boon ability flags (dash/thorns/vampire) are the first non-stat build differentiators.

**Prestige (design for, don't build):** the hooks already exist — currencies are keyed by id in `MetaProgression`, so prestige is: add a `prestige_shards` currency earned from a reset condition, a "reset gold + upgrades" operation, and a prestige upgrade folder whose modifiers apply globally. No system rewrites required.

---

## 5. Phased Roadmap

| Phase | Status | What shipped / what's left |
|---|---|---|
| **0. Setup** | ✅ Done | Folder skeleton, autoloads, input map (incl. a later `dash` action), `untyped_declaration` as error. |
| **1. Demo** | ✅ Done | Full loop per §2 — FPS controller, sword/shield with three-phase swing, chaser enemy with telegraphed attacks, ring spawner, gold economy, death-screen shop, JSON save. Plus unplanned extras: perfect-block parry, block feedback pass. |
| **2. Depth** | ✅ Done (SFX deferred) | XP + boon choices with rarities and unique ability boons; three new enemy types (Sprinter/Brute/Spitter) as pure `EnemyData`; hit feedback (damage numbers, trauma camera shake, hit-pop, damage vignette); rotating minimap; physical gold/XP pickups. **SFX was cut from this phase — no audio assets exist yet; it moves to the Phase 4 audio pass.** |
| **3. Bosses & arsenal** | ✅ Done | **Juggernaut boss** via scheduled `WaveTable` events (telegraphed wall-to-wall charge that phases through the player and plows minions aside; parry cancels it) with boss HP bar + spawn banner; **hit knockback** on every enemy attack (`AttackInfo.knockback`, per-enemy strength); **Fireball** — 0.8s committed charge (sword/shield stow, both hands busy) → AoE explosion — unlocked via ability-granting `UpgradeData`; **dash reworked** into a fixed-distance intangible blink; skill cooldown HUD; **weapon loadout** — one weapon per run, picked on the death screen, unlocked via the same ability-upgrade path; **Warhammer** — slow two-handed slam with a ground-AoE shockwave and shove, `can_block = false` (the shield is the price); **Frost Nova** — instant defensive AoE (E) that chills enemy *movement* to ×0.35 for 3.5s, never attack telegraphs. |
| **3.5 Depth & chaos** *(unplanned)* | ✅ Done | **Controls:** dash moved to Shift (sprint removed — dash is the mobility tool), jump on Space. **Build-specific boons:** `BoonData` gained `requires_weapon`/`requires_any_ability` gating; new stats (`spell_cooldown`, `cast_time`, `fireball_aoe`, `fireball_charges`, `hammer_aoe`); 10 new boons — sword (thorns now gated here + Duelist's Focus parry window), hammer (Wide Tremor, Aftershock), spells (Quick Mind, Fast Hands, Greater Blast, Twin Flame, Scorched Earth fire trail, Echo Nova, Glacial Wave). **Lethality:** base HP 100→80, Vitality upgrade halved to +10, enemy damage up ~1.5–1.8×, damage growth +25%→+40%/min — a fresh player dies in ~4 hits; Bulwark picks are the counterplay. **Chaos:** sprinters 8.5 speed, spitters fire ~2× as often, all telegraphs ~25% snappier, spawn interval 1.8→0.25s, alive cap 24→90, and repeating **SWARM events** (`WaveEvent.repeat_every`): 12 sprinters every 75s, 16 chasers every 150s. |
| **4. Meta & polish** | Not started | Main menu, settings, upgrade tree UI (replacing flat shop), balance pass on curves, art/**audio** pass (now owns the deferred SFX work). |
| **5+ (parked)** | — | Prestige layer, multiple arenas, achievements. |

---

## 6. Risks / open questions

- **Melee feel in first person is the make-or-break.** Substantially addressed: the swing went through several iterations (bezier arc → shoulder-orbit rigid arm → three-phase windup/sweep/backswing, base swing slowed to 0.7s) and hits land with damage numbers, scale-pop, and camera shake. Still no hit-pause or SFX — the feel ceiling is audio-shaped now; revisit after the Phase 4 audio pass. Mechanics: [docs/COMBAT.md](docs/COMBAT.md).
- **Renderer:** project is on GL Compatibility — with GDScript that's the right default, since it's the only renderer that reaches web and low-end hardware, which is exactly the platform flexibility being prioritized. Revisit Forward+ in Phase 4 only if the visual target demands it *and* web is off the table by then.
- **GDScript horde performance:** holding. The alive cap ramps 15 → 60 (`WaveTable`), well under the ~200 danger zone, and pickups were deliberately built without physics bodies so hundreds of coins stay cheap. If counts grow past ~200, the escalation path in §1/§3.6 (typed scripts → manager-iterated steering → PhysicsServer3D) is the plan; profile before escalating.
- **Block design:** shipped as resolved — hold-to-block negates frontal (60° half-angle) damage, and raising the block within 0.2s of a hit is a *perfect block* that stuns the attacker 1.5s. Thorns (unique boon) stacks damage reflection on top. Stamina costs remain an option if blocking proves too dominant — watch this once the boss lands, since stun-locking a boss with parry timing may need a boss-side override (`stun()` is already overridable).
- **Boon economy tuning (new):** reroll doubling (10 → 20 → 40 …) and skip payouts (15 + 5×level gold) are first-guess numbers; skip could become the dominant strategy for meta-focused players. Track gold-per-run from skips vs drops. Levers listed in [docs/BOONS.md](docs/BOONS.md).
- **Warhammer balance:** all numbers are first guesses (26 dmg / 1.4s swing / 2.4m full + 4.2m splash). The dead-pick problem is solved — boon gating means hammer runs never see thorns/parry boons — but slam AoE (+ Wide Tremor + Aftershock) + Frost Nova may trivialize packs that the sword has to respect. A full playtest across both loadouts is the next step before any new content.
- **Lethality & chaos tuning (2026-07-03, first guesses):** the "die in 3–4 hits" target is calibrated against a *fresh* 80-HP player vs early chasers (18 dmg). Watch two failure modes: meta Vitality stacking (now +10/level, uncapped) re-softening the game for veteran saves, and the +40%/min damage growth one-shotting non-tank builds past ~8 minutes. Swarm cadence (75s/150s) vs the 90 alive cap is untested at the perf level under real kill rates — the ~200-enemy GDScript danger zone (§1) is still comfortably far, but profile if swarms ever stack with both bosses alive.
