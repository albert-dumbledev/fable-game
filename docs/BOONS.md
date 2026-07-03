# Boons — run-scoped level-up rewards

Every level-up pauses the run and offers **3 boons**. Boons are the temporary half of the dual-track economy (PLAN.md §4): they die with the run, while gold buys permanent upgrades. Deliberately, a boon is *the same data shape as an upgrade* — a list of `StatModifier`s — so the stats system needed zero changes to support them.

## Architecture

| Piece | File | Role |
|---|---|---|
| `BoonData` | `core/boon_data.gd` | One boon: `id`, `display_name`, `description`, `weight`, `modifiers: Array[StatModifier]`, `unique: bool`, `grants_ability: StringName` |
| `BoonRegistry` | `core/boon_registry.gd` | Flat `Array[BoonData]`; the whole roll pool |
| Registry instance | `data/boons/registry.tres` | The pool the game actually loads |
| Boon screen | `ui/boon_screen.gd` + `BoonScreen.tscn` | Listens to `EventBus.level_up`, pauses the tree (`PROCESS_MODE_ALWAYS`), rolls offers, applies picks |
| Application | `Player.apply_boon(boon, value_mult)` | Duplicates each modifier, scales by rarity mult, adds to the player's `StatBlock`; grants ability flag if set |

Multiple level-ups in one kill burst queue (`_pending`) and present back-to-back. `level_up` fires mid-physics, so the screen shows itself via `call_deferred` — don't "fix" that.

## Rarity table (constants in `ui/boon_screen.gd`)

Rolled **per offer slot**, independent of the boon picked. The multiplier scales every modifier value; `BoonData.describe(mult)` regenerates the text so displayed numbers always match the roll.

| Rarity | Chance | Value mult | Color |
|---|---|---|---|
| COMMON | 55% | ×1.0 | grey `(0.85, 0.85, 0.85)` |
| RARE | 27% | ×1.6 | blue `(0.4, 0.65, 1.0)` |
| EPIC | 13% | ×2.4 | purple `(0.8, 0.45, 1.0)` |
| LEGENDARY | 5% | ×3.5 | gold `(1.0, 0.78, 0.2)` |

Boon selection itself is weighted sampling **without replacement** (no duplicate boons in one offer). Max-health boons also heal the gained amount (`Player.apply_boon`) so they never feel like an empty bar extension.

## Current pool (`data/boons/`)

| Boon | Effect (at ×1.0) | Weight |
|---|---|---|
| Sharpened Edge | +4 damage (flat) | 1.0 |
| Bulwark | +40 max health (flat, heals the gain) | 1.0 |
| Brutal Power | +15% damage | 0.8 |
| Frenzy | +20% attack speed | 0.8 |
| Fleet Footed | +12% move speed | 0.8 |
| Warrior Spirit | +5% damage, attack speed, move speed | 0.6 |
| Phantom Step *(unique)* | Dash ability (Space) | 0.35 |
| Spiked Bulwark *(unique)* | Thorns ability | 0.35 |
| Blood Drinker *(unique)* | Vampire ability | 0.35 |

## Unique boons & the ability-flag mechanism

Unique boons (`unique = true`) skip the rarity roll — tagged `[UNIQUE]`, orange, never scaled, hand-written description used verbatim — and are offered **at most once per run** (screen tracks `_taken_uniques`). Instead of modifiers they set `grants_ability`, which flows into the player's flag dictionary:

- `Player.grant_ability(id: StringName)` / `Player.has_ability(id)` — a plain `Dictionary[StringName, bool]`. Anything can branch on a flag; `grant_ability` is also the hook for one-time wiring (vampire connects to `EventBus.enemy_killed` there).
- **dash** — Space: fixed 6m blink over 0.12s (traveled, not teleported; walls still stop it), fully intangible during — enemy collision off, hurtbox dark so melee and projectiles pass through — 2s cooldown (constants in `player.gd`).
- **thorns** — successful blocks deal 15 damage back to the attacker via its `Hurtbox` (in `Player.mitigate_hit`).
- **vampire** — heal 2 HP per enemy kill.

This same flag system is how Phase 3 unlocks the Firebolt spell from an `UpgradeData` — abilities are ids, not subsystems.

## Skip / reroll economy

Both use persistent gold, making the boon screen a live meta-vs-run tradeoff:

- **Skip** pays `15 + 5 × current_level` gold. Emitted through `EventBus.pickup_collected(&"gold", …)` so RunDirector counts it as gold earned this run, identical to a dropped coin.
- **Reroll** costs 10 gold, **doubling per use** (10 → 20 → 40 …), reset per run (state lives on the screen node inside the arena scene). Rerolls the whole offer, rarities included — it's a legendary-fishing sink.

## Authoring a new boon

1. Create `data/boons/my_boon.tres`: a `Resource` with `script = core/boon_data.gd`. Set `id`, `display_name`, `weight`.
2. Stat boon: add `StatModifier` sub-resources (`stat` from `core/stats.gd`, `kind` 0=FLAT / 1=PERCENT_ADD / 2=PERCENT_MULT, `value`). Leave `description` empty-ish — it's auto-generated per rarity. Easiest: duplicate `sharp_edge.tres` (flat) or `brutal_power.tres` (percent) and edit.
3. Ability boon: set `unique = true`, `grants_ability = &"my_ability"`, write the `description` by hand, then implement the flag check wherever it acts (usually `player.gd`; add wiring in `grant_ability` if it needs a signal).
4. Add the boon to the `boons` array in `data/boons/registry.tres`. Nothing else — the screen, rarity scaling, and description text are all generic.

## Future direction

- **Rarity odds scaling with level** — shift weight off COMMON as `_current_level` rises (or as a meta "Luck" upgrade), so late-run level-ups stay exciting. Single touch point: `_roll_rarity()`.
- **Per-run synergies** — track picked boon ids per run (the screen already tracks uniques); a boon's availability or bonus could key off prior picks (e.g. Frenzy ×3 unlocks a bleed). Wants a `requires: Array[StringName]` field on `BoonData`.
- **Stacking display** — repeated boons currently just stack modifiers silently; show "Frenzy II" by counting picks.
- **Tuning watch:** skip payout vs drop income (see PLAN.md §6) — if skipping dominates, cut `SKIP_GOLD_PER_LEVEL` before touching drops.
