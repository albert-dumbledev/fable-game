# Run Recap & Personal Bests

## Why

The death/victory screen shows three numbers — time, kills, gold — then drops you
into the shop. A run full of decisions (boons picked, Aspects claimed, bosses
felled, the fight that finally killed you) leaves no trace. Survivor-likes live
on the post-run recap: it teaches ("casters are what kills me"), it rewards
("Lv 17, new best"), and it makes each run a story instead of a timer.

This is also the "real `RunStats` class" that PLAN.md §3.5 has listed as future
work since Phase 1, and it lays the attribution groundwork (the `player_hit`
signal) that the Phase 10 telemetry plan (docs/GAMEPLAY_TELEMETRY.md) already
specs — telemetry can later reuse the same seams.

## What the player sees

On the death/victory screen, between the headline stats and the shop:

1. **Killer headline** — "Slain by CASTER" under the RUN OVER title (deaths
   only; self-inflicted Blood Pact deaths say so).
2. **Recap panel** — three compact columns:
   - **BOONS** — every boon picked this run, in pick order, tinted by rarity
     (duplicates collapse to "×N" at the highest rarity taken); Aspects listed
     on top in their gold accent.
   - **SLAIN** — kills by enemy type, sorted desc, with counts. Bosses get a
     skull prefix and their kill clock time.
   - **DAMAGE TAKEN** — per enemy type, sorted desc, with hit counts; total row.
3. **Records line** — lifetime bests (longest run, most kills, best level, most
   gold in a run, victory count). Any best set *this run* gets a gold
   **NEW BEST** badge.

Abandoned runs show the recap but never set records (quitting isn't surviving);
they still count toward total runs.

## Architecture

Behavior in scripts, one damage pipeline, EventBus-only coupling — all existing
rules hold. Everything below is additive; no `.tres` or `.tscn` edits.

### New: `core/run_stats.gd` (`class_name RunStats extends Node`)

Created in code by `RunDirector._ready()` as a child; dies with the run scene,
so no signal-leak bookkeeping. Connects to EventBus and accumulates:

| Field | Fed by | Shape |
|---|---|---|
| `kills_by_enemy` | `enemy_killed` | id → `{name, count}` |
| `bosses` | `enemy_killed` (data tags has `boss`) | `[{name, t}]` |
| `damage_taken` | `player_hit` *(new signal)* | id → `{name, dmg, hits}` |
| `killer` | last `player_hit` before `player_died` | `{id, name}` |
| `boons` | `boon_picked` *(new signal)* | `[{id, name, rarity, color, mult}]` |
| `aspects` | `aspect_picked` *(new signal)* | `[{id, name}]` |

Enemy ids derive from `data.resource_path` basename (`chaser`, `caster`, …) —
the same rule the telemetry plan verified; `EnemyData.display_name` supplies UI
names. `to_dict()` returns a plain Dictionary that rides the existing
`GameManager.end_run(stats)` handoff as `stats["recap"]`.

Attribution notes (verified against the codebase):
- `AttackInfo.source` is always the attacking `EnemyBase`, even for projectiles
  and boss AoE — one damage pipeline pays off again.
- `player_hit` is emitted from `Player._on_damaged`, i.e. **post-mitigation**:
  blocked hits and dash i-frames never count, which is exactly what "damage
  taken" should mean.
- Blood Pact self-damage arrives with `source == Player`; mapped to a
  `self` id ("Blood Pact") so a self-kill reads honestly.

### New EventBus signals (signals only, no state — rule holds)

- `player_hit(info: AttackInfo)` — full-attribution damage taken. One-line emit
  in `Player._on_damaged`. (Same signal the telemetry plan needs.)
- `boon_picked(ctx: Dictionary)` — `{id, name, rarity, color, mult}`, emitted in
  `BoonScreen._on_pick` from the resolved `Offer` (rarity tag + color come from
  the roll, so the recap shows exactly what the player saw).
- `aspect_picked(ctx: Dictionary)` — `{id, name}`, emitted in
  `AspectScreen._on_pick`.

### `MetaProgression` — personal bests

New persisted `records: Dictionary` (String keys, save-version untouched;
missing key just defaults — same additive pattern as every save change so far):

```
longest_run, most_kills, best_level, most_gold   (per-run maxima)
victories, runs                                  (counters)
fastest_victory                                  (min time among victories, 0 = none)
```

`record_run(stats) -> Array[String]` applies a finished run and returns which
records were newly set; `RunDirector` calls it in the death/victory paths (not
abandon) before the existing `save_game()`, and stashes the result in the stats
dict as `new_records` for the death screen.

### `RunDirector`

- Instantiates the `RunStats` child in `_ready()`.
- All three end paths (`_on_player_died`, `abandon_run`, `finish_victory`) gain
  `level`, `recap`, and (death/victory) `new_records` in the stats dict.

### `ui/death_screen.gd`

Recap panel + records line, code-built like the rest of the screen (no scene
edits), inserted after `StatsLabel` in the existing `Box` VBox. Column rows cap
at 8 with a "+N more" tail so a long run can't push the shop off-screen.

## Files touched

| File | Change |
|---|---|
| `core/run_stats.gd` | **new** — accumulator node |
| `autoload/event_bus.gd` | +3 signals |
| `actors/player/player.gd` | 1 line: emit `player_hit` |
| `ui/boon_screen.gd` | emit `boon_picked` in `_on_pick` |
| `ui/aspect_screen.gd` | emit `aspect_picked` in `_on_pick` |
| `systems/run_director.gd` | own tracker; enrich end-run stats; call `record_run` |
| `autoload/meta_progression.gd` | `records` + persistence + `record_run()` |
| `ui/death_screen.gd` | recap panel, killer headline, records badges |
| `test/recap_smoke.gd` + `RecapSmoke.tscn` | **new** — headless harness |
| `docs/RUN_RECAP.md`, `PLAN.md` | this doc; §3.5/§5 rows |

## Verification

`test/recap_smoke.gd` (pattern of `enemy_smoke.gd`): boot Arena → spawn a
chaser → route an `AttackInfo(chaser, dmg)` through the player hurtbox → kill
the chaser → emit a synthetic `boon_picked` → kill the player via
`take_damage` → assert `GameManager.last_run_stats.recap` has the kill, the
damage attribution, the boon, and `killer` == chaser; assert
`MetaProgression.records` updated and `new_records` non-empty on a fresh save.
Run: `--headless res://test/RecapSmoke.tscn --quit-after 900`. Existing smoke
harnesses must still pass.

## Non-goals (this pass)

- **Damage *dealt* by ability** — needs an `AttackInfo` label at ~15 weapon
  call sites plus re-wrap copies (`enemy_base.gd` vulnerable path). Great v2;
  the recap panel gets a fourth column when it lands.
- Telemetry upload — separate Phase 10 plan; this feature only builds seams it
  already wants.
- Run history (list of past runs) — records are aggregates only for now.
