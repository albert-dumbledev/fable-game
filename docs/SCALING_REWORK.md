# Late-Game Scaling & Threat Rework (Phase 8B)

Addresses the [FEEDBACK.md](FEEDBACK.md) "late game scaling doesn't feel impactful" block:
player power (boons) outruns enemy HP, so minute 5+ collapses into one-shotting chaff. The fix
is two-sided — **flatten the player curve a little, steepen the enemy curve a lot** — plus two
targeted enemy-threat buffs (broodlings, stalkers) so the third act has teeth.

This is almost entirely number tuning; it should land before (or alongside) Phase 8A so the
weapon rework is evaluated against the corrected difficulty curve.

---

## M1 — Boon power pass

In [boon_screen.gd](../ui/boon_screen.gd) `RARITIES`:

- Rarity multipliers `{1.0, 1.6, 2.4, 3.5} → {1.0, 1.4, 1.9, 3.5}` — commons stay the
  baseline, mid rarities compress, **legendary keeps its full 3.5× "extra" feel**.
- Legendary chance `0.05 → 0.02`; redistribute to common: `{0.58, 0.27, 0.13, 0.02}`.
- **Time-scaled rarity (own idea):** shift weight from COMMON toward RARE/EPIC as the run
  progresses (e.g. lerp COMMON 0.58 → 0.40 into RARE/EPIC over the 7:30). Late-run level-ups
  stay exciting *because enemies got harder*, without touching the legendary jackpot rate.
  `_roll_rarity_index()` takes the run's elapsed time as a parameter.
- Flat stat-boon trim where the compounding is worst: `sharp_edge +4 → +3` damage; sweep the
  other plain stat boons (`frenzy`, `fleet_footed`, `bulwark`, `brutal_power`, …) ~-20% in the
  same pass. Uniques and Wide Tremor/Aftershock are handled in Phase 8A.

## M2 — Enemy HP: linear → compounding

Current ([wave_table.gd](../core/wave_table.gd)): `hp_mult_at = 1 + 0.5 × min` — only ×4.75
by 7:30, while boon multipliers compound. Change the curve shape, not just the slope:

- `hp_mult_at(elapsed) = pow(1.0 + hp_growth_per_min, elapsed / 60.0)` — geometric, like the
  player's own scaling.
- Retune `hp_growth_per_min 0.5 → 0.35` for the new curve: ×1.35/min ≈ ×2.1 @ 2:30,
  ×4.5 @ 5:00, ×9.5 @ 7:30. Early game barely moves; late game stops being one-shottable.
- Leave `dmg_growth_per_min` linear and untouched — the complaint is about kill speed, not
  incoming damage; lethality was tuned deliberately in Phase 3.5.
- Watch: XP pacing. Slower kills = slower levels. If level cadence drags past ~30s late-run,
  raise `reward_growth_per_min` or per-enemy `xp_reward` rather than softening the HP curve.

## M3 — Boss HP: much higher

Bosses also gain the M2 multiplier at spawn (the spawner applies `hp_mult_at` to scheduled
events too), so base values are set to hit an **effective** target of roughly 45–60s of
focused DPS per boss:

| Boss | Base HP now | Proposed base | Effective @ spawn (M2 curve) |
|---|---|---|---|
| Juggernaut (2:30) | 500 | ~750 | ~1 600 |
| Hierophant (5:00) | 420 | ~550 | ~2 500 |
| Revenant (7:30) | 380 | ~500 | ~4 700 |

Numbers are first-guess; derive finals *after* M2 lands by timing real kills per loadout.
The Revenant is mid-implementation (`revenant_boss.gd`) — set its base in that branch.

## M4 — Broodling swarm burst

Current ([broodling.tres](../data/enemies/broodling.tres)): `move_speed 7.0` — slower than a
sprinter (8.5), so the death-burst is a shrug.

- `move_speed 7.0 → 9.6` — faster than anything else on the field; the burst *is* the threat.
- **Hatch frenzy (own idea):** for the first ~2s after spawning, broodlings get ×1.25 speed
  and skip their spawn stagger — the moment the broodmother pops, the ring closes. (Small
  override in the broodling scene script or a `death_spawns` speed-burst flag on `EnemyBase`.)
- Their 6 HP / 6 dmg stays — they should die to one hit of anything; the question they ask is
  "do you have a hit ready *right now*, times five."

## M5 — Stalker: predator, not jogger

Current ([stalker_enemy.gd](../actors/enemies/stalker_enemy.gd) /
[stalker.tres](../data/enemies/stalker.tres)): approach at 6.8 speed, windup 0.28, disengage
for 2.5–3.5s.

- **Engage burst:** ×1.4 move speed while in `ENGAGE` mode (both the arc and the final
  straight) — it should *pounce*, reading clearly different from chaser traffic. Plain
  multiplier inside `_chase()`; frost slow still stacks on top, keeping that counter.
- **Snappier strike:** `windup_time 0.28 → 0.20`, `recover_time 0.35 → 0.28`. Still inside
  the 0.2s parry window if the block is raised on the pounce read — the parry stays the
  counter, it just now requires the read instead of a casual reaction.
- **Faster cycle:** `DISENGAGE_MIN/MAX 2.5/3.5 → 1.2/2.0` so a pair of stalkers keeps
  near-constant pressure instead of politely queueing.
- Bump `damage 16 → 18` only if the above still isn't scary; speed first, numbers second.

## M6 (stretch) — Elite variants

Optional texture if the late game still feels flat after M1–M5: a rare (~3%) "elite" roll on
pool spawns past 4:00 — ×4 HP, ×1.3 scale, emissive tint, guaranteed magnet-or-health drop.
No new AI, pure `EnemyData`/spawner flag, gives the one-shot-proof curve a visible face.
Park it unless playtest asks for it.

---

## Playtest checklist

- At 6:00+, pool chaff should take 2–4 hits (duelist) instead of vaporizing; swarm events
  should demand the AoE tools rather than dying to incidental contact.
- Each boss fight lasts long enough to see its full kit twice (~45–60s).
- Broodmother positioning should matter again: killing her point-blank should usually cost HP.
- A stalker pounce should force a reaction 100% of the time it's off-screen-then-on.
- Level-up cadence stays in the ~10–30s band through the whole 7:30.
