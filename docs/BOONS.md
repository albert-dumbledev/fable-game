# Boons — run-scoped level-up rewards

Every level-up pauses the run and offers **3 boons**. Boons are the temporary half of the dual-track economy (PLAN.md §4): they die with the run, while gold buys permanent upgrades. Deliberately, a boon is *the same data shape as an upgrade* — a list of `StatModifier`s — so the stats system needed zero changes to support them.

## Architecture

| Piece | File | Role |
|---|---|---|
| `BoonData` | `core/boon_data.gd` | One boon: `id`, `display_name`, `description`, `weight`, `modifiers: Array[StatModifier]`, `unique: bool`, `grants_ability: StringName`, `requires_weapon` / `requires_any_ability` gating, and optional `rarity_mults: Array[float]` (custom per-rarity multiplier curve) |
| `BoonRegistry` | `core/boon_registry.gd` | Flat `Array[BoonData]`; the whole roll pool |
| Registry instance | `data/boons/registry.tres` | The pool the game actually loads |
| Boon screen | `ui/boon_screen.gd` + `BoonScreen.tscn` | Listens to `EventBus.level_up`, pauses the tree (`PROCESS_MODE_ALWAYS`), rolls offers, applies picks |
| Application | `Player.apply_boon(boon, value_mult)` | Duplicates each modifier, scales by rarity mult (custom curve if present), adds to the player's `StatBlock`; grants ability flag if set |

Multiple level-ups in one kill burst queue (`_pending`) and present back-to-back. `level_up` fires mid-physics, so the screen shows itself via `call_deferred` — don't "fix" that.

## Rarity table (constants in `ui/boon_screen.gd`)

Rolled **per offer slot**, independent of the boon picked. The multiplier scales every modifier value; `BoonData.describe(mult)` regenerates the text so displayed numbers always match the roll.

| Rarity | Chance | Value mult (default) | Color |
|---|---|---|---|
| COMMON | 55% | ×1.0 | grey `(0.85, 0.85, 0.85)` |
| RARE | 27% | ×1.6 | blue `(0.4, 0.65, 1.0)` |
| EPIC | 13% | ×2.4 | purple `(0.8, 0.45, 1.0)` |
| LEGENDARY | 5% | ×3.5 | gold `(1.0, 0.78, 0.2)` |

Most boons use these global multipliers. Some boons define a custom `rarity_mults` curve to scale differently — e.g. **Wide Tremor** uses `[1.0, 2.0, 2.5, 4.0]` (on its base 0.1 modifier → 10% / 20% / 25% / 40% slam size by rarity). When a boon has `rarity_mults`, those values override the global table for that boon only.

Boon selection itself is weighted sampling **without replacement** (no duplicate boons in one offer). Max-health boons also heal the gained amount (`Player.apply_boon`) so they never feel like an empty bar extension.

## Gating (build-specific boons)

`_is_offerable` in `ui/boon_screen.gd` filters the roll pool per offer:

- **`requires_weapon`** — only offered while that `WeaponData` id is mounted. The loadout-specific boons organize around this:
  - Sword & Shield: Duelist boons (parry, riposte, block utilities)
  - Warhammer: Seismic CC boons (shove, slam crowd control)
  - Battle Staff: Spell boons (cooldown, cast time, spell effects)
- **`requires_any_ability`** — only offered once the player owns *at least one* listed flag (spell boons further gate on owning the specific spell; ability flags come from meta upgrades or mid-run unique boons).

Gates are checked at roll time, so unlocking a spell or weapon mid-run immediately opens its boon family on the next level-up.

## Current pool (`data/boons/`)

### Universal boons

| Boon | Effect (at ×1.0) | Weight |
|---|---|---|
| Sharpened Edge | +4 damage (flat) | 1.0 |
| Bulwark | +40 max health (flat, heals the gain) | 1.0 |
| Brutal Power | +15% damage | 0.8 |
| Frenzy | +20% attack speed | 0.8 |
| Fleet Footed | +12% move speed | 0.8 |
| Warrior Spirit | +5% damage, attack speed, move speed | 0.6 |
| Phantom Step *(unique)* | Dash ability (Shift) | 0.35 |
| Blood Drinker *(unique)* | Vampire ability | 0.35 |

### Sword & Shield — Duelist boons

| Boon | Effect (at ×1.0) | Weight |
|---|---|---|
| Spiked Bulwark *(unique)* | Thorns ability (block damage back) | 0.35 |
| Duelist's Focus *(unique)* | Parry window 0.2s → 0.35s (`long_parry`) | 0.3 |
| Ruthless Riposte | +40% riposte damage | 0.5 |
| Punishing Stun | +30% parry stun duration | 0.5 |
| Retribution *(unique)* | Perfect blocks detonate a 3m pulse (`parry_nova`): 50% weapon damage + hard shove | 0.3 |
| Expose Weakness *(unique)* | Parried enemies take +35% damage while stunned (`exposing_parry`) | 0.3 |
| Second Wind *(unique)* | Perfect blocks steal life on next swing (`parry_heal`): 25% lifesteal | 0.3 |
| Blade Cyclone *(unique)* | Riposte swings strike in a full circle (`riposte_sweep`) | 0.3 |
| Reflex Guard *(unique)* | Raise guard blocks all directions for a moment (`omni_block`, 0.5s cooldown) | 0.3 |

### Warhammer — Seismic CC boons

| Boon | Effect (at ×1.0) | Weight |
|---|---|---|
| Wide Tremor | +10% slam size (uses custom rarity curve: ×1.0 / ×2.0 / ×2.5 / ×4.0) | 0.8 |
| Aftershock *(unique)* | Second, weaker shock after every slam | 0.3 |
| Wrecking Ball | +25% shove force | 0.8 |
| Implosion *(unique)* | Seismic Slam rakes enemies back to center and staggers (`slam_pull`) | 0.3 |
| Riptide *(unique)* | Seismic Slam wave drags enemies along, clusters at end (`wave_drag`) | 0.3 |
| Bone Breaker *(unique)* | Enemies shoved into walls take 30% hammer damage and stagger (`shove_impact`) | 0.3 |

### Battle Staff — Spell boons

| Boon | Effect (at ×1.0) | Weight | Requires ability |
|---|---|---|---|
| Quick Mind | −12% spell cooldown | 0.7 | firebolt or frost nova |
| Fast Hands | −15% cast time | 0.7 | firebolt |
| Greater Blast | +25% fireball blast size | 0.7 | firebolt |
| Twin Flame *(unique)* | +1 fireball charge | 0.3 | firebolt |
| Scorched Earth *(unique)* | Fireball blasts leave burning ground (`burning_ground`) | 0.3 | firebolt |
| Echo Nova *(unique)* | Frost Nova pulses again, weaker (`nova_echo`) | 0.3 | frost nova |
| Glacial Wave *(unique)* | Frost Nova shoves everything away (`nova_push`) | 0.3 | frost nova |

The spell/weapon numbers (cooldown, cast time, AoE, charges, damage) ride on base-1.0 multiplier stats in `core/stats.gd` — `riposte_damage`, `parry_stun`, `hammer_shove`, `spell_damage` are the newer ones. See docs/COMBAT.md for where each one lands in play.

## Unique boons & the ability-flag mechanism

Unique boons (`unique = true`) skip the rarity roll — tagged `[UNIQUE]`, orange, never scaled, hand-written description used verbatim — and are offered **at most once per run** (screen tracks `_taken_uniques`). Instead of modifiers they set `grants_ability`, which flows into the player's flag dictionary:

- `Player.grant_ability(id: StringName)` / `Player.has_ability(id)` — a plain `Dictionary[StringName, bool]`. Anything can branch on a flag; `grant_ability` is also the hook for one-time wiring (vampire connects to `EventBus.enemy_killed` there).

**Universal uniques:**
- **dash** — Shift: fixed 6m blink over 0.12s (traveled, not teleported; walls still stop it), fully intangible during — enemy collision off, hurtbox dark so melee and projectiles pass through — 2s cooldown (constants in `player.gd`).
- **vampire** — heal 2 HP per enemy kill.
- **thorns** — successful blocks deal 15 damage back to the attacker via its `Hurtbox` (in `Player.mitigate_hit`).

**Sword & Shield uniques:**
- **long_parry** — Duelist's Focus extends parry window from 0.2s to 0.35s.
- **parry_nova** — Retribution: perfect blocks detonate a 3m pulse.
- **exposing_parry** — Expose Weakness: parried enemies take +35% damage while stunned.
- **parry_heal** — Second Wind: perfect blocks grant lifesteal on next swing (25% of damage dealt).
- **riposte_sweep** — Blade Cyclone: riposte swings strike in a full circle.
- **omni_block** — Reflex Guard: raising guard blocks all directions briefly (0.5s cooldown).

**Warhammer uniques:**
- **aftershock** — second, weaker shock after every slam.
- **slam_pull** — Implosion: Seismic Slam rakes enemies back to its center.
- **wave_drag** — Riptide: Seismic Slam wave drags enemies and clusters them.
- **shove_impact** — Bone Breaker: enemies shoved into walls take 30% hammer damage and stagger.

**Spell uniques:**
- **burning_ground** — Scorched Earth: fireball blasts leave burning ground.
- **nova_echo** — Echo Nova: Frost Nova pulses again, weaker.
- **nova_push** — Glacial Wave: Frost Nova shoves everything away.

This same flag system is how spell and weapon unlocks work from `UpgradeData` — abilities are ids, not subsystems. A unique **can** also carry modifiers (Twin Flame: flat +1 `fireball_charges`); uniques never rarity-scale, so those values apply verbatim.

## Aspects (Phase 9 — a tier above unique)

**Aspects** are build-warping boons dropped as walk-over relics (teal gems, theft-proof) by **elite enemies** and **wave bosses**, opening a paused **pick-1-of-2** modal — scarcer than the level-up screen's 3, making each choice weighty. They live in `data/boons/aspects/` with their own `registry.tres` (never loaded by the level-up screen, zero cross-contamination) and are `unique = true`, flag-granting, and `requires_weapon`-gated per loadout. Expected yield: ~2–4 Aspects per run. Full design: **[docs/BOON_DROPS.md](docs/BOON_DROPS.md)**.

### Duelist Aspects (`requires_weapon = sword_and_shield`)

| Aspect | Effect |
|---|---|
| **Crescendo** | Riposte kills refresh the prime and don't consume it; each successive riposte in the chain deals +25% more damage (stacks until the window lapses) |
| **Mirror Ward** | Perfect-blocking a projectile hurls it back at the shooter, detonating in a ~4m blast at riposte-scaled damage |
| **Blade Waltz** | Blinking through enemies slashes each for riposte-scaled damage — the blink *is* the strike |

### Earthshaker Aspects (`requires_weapon = warhammer`)

| Aspect | Effect |
|---|---|
| **Fault Line** | Seismic Slam leaves a lingering fissure (~4s) that staggers enemies crossing it; every enemy the wave or fissure catches refunds ~0.75s of the slam's 6s cooldown |
| **Epicenter** | Crashing Leap's landing erupts Seismic waves outward in four directions (full wave boons apply) |
| **Mass Driver** | Shoved enemies become projectiles: anything they're driven through takes 30% hammer damage + stagger, one generation |

### Arcanist Aspects (`requires_weapon = battle_staff`)

| Aspect | Effect |
|---|---|
| **Blood Pact** | Spells can be cast without mana by paying ~0.5 HP per mana; a lethal cast is refused |
| **Stormcaller** | While levitating, Arcane Bolts fork into three, and bolt hits refund levitate's mana drain (base Levitate is unchanged without this flag) |
| **Shatterflux** | Frost-chilled enemies struck by Fireball shatter for ×2 damage plus a single-generation mini-nova that chills neighbors |

### Universal Aspects (`requires_weapon = ""`)

| Aspect | Effect |
|---|---|
| **Undying Will** | Once per run, lethal damage instead leaves you at 30% max HP with a hard 3m shockwave and ~1s of grace |
| **Prospector's Idol** | Enemies drop one extra gold piece and your collection radius is doubled |
| **Slipstream** | Your loadout's Shift verb improves: +1 blink charge or −20% leap/levitate cooldown |

## Skip / reroll economy

Both use persistent gold, making the boon screen a live meta-vs-run tradeoff:

- **Skip** pays `15 + 5 × current_level` gold. Emitted through `EventBus.pickup_collected(&"gold", …)` so RunDirector counts it as gold earned this run, identical to a dropped coin.
- **Reroll** costs 10 gold, **doubling per use** (10 → 20 → 40 …), reset per run (state lives on the screen node inside the arena scene). Rerolls the whole offer, rarities included — it's a legendary-fishing sink.

## Authoring a new boon

1. Create `data/boons/my_boon.tres`: a `Resource` with `script = core/boon_data.gd`. Set `id`, `display_name`, `weight`.
2. Stat boon: add `StatModifier` sub-resources (`stat` from `core/stats.gd`, `kind` 0=FLAT / 1=PERCENT_ADD / 2=PERCENT_MULT, `value`). Leave `description` empty-ish — it's auto-generated per rarity. Easiest: duplicate `sharp_edge.tres` (flat) or `brutal_power.tres` (percent) and edit. Optionally set `rarity_mults` (Array[float], length 4, indexed COMMON/RARE/EPIC/LEGENDARY) to use a custom scaling curve instead of the global one (see `wide_tremor.tres` for an example).
3. Ability boon: set `unique = true`, `grants_ability = &"my_ability"`, write the `description` by hand, then implement the flag check wherever it acts (usually `player.gd`; add wiring in `grant_ability` if it needs a signal).
4. Build-specific? Set `requires_weapon` (a `WeaponData` id) and/or `requires_any_ability` (ability flags, any-of).
5. Add the boon to the `boons` array in `data/boons/registry.tres`. Nothing else — the screen, rarity scaling, gating, and description text are all generic.

## Future direction

- **Rarity odds scaling with level** — shift weight off COMMON as `_current_level` rises (or as a meta "Luck" upgrade), so late-run level-ups stay exciting. Single touch point: `_roll_rarity()`.
- **Per-run synergies** — track picked boon ids per run (the screen already tracks uniques); a boon's availability or bonus could key off prior picks (e.g. Frenzy ×3 unlocks a bleed). The gating fields (`requires_any_ability`) already cover ability-based chains; picked-boon-count chains still need a tracker.
- **Stacking display** — repeated boons currently just stack modifiers silently; show "Frenzy II" by counting picks.
- **Tuning watch:** skip payout vs drop income (see PLAN.md §6) — if skipping dominates, cut `SKIP_GOLD_PER_LEVEL` before touching drops.
