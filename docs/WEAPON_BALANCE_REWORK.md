# Weapon Balance Rework (Phase 8A)

Addresses the [FEEDBACK.md](FEEDBACK.md) duelist-vs-AoE items: the duelist isn't weak so much as
AoE is overtuned. This plan **nerfs hammer AoE damage into a control identity**, **converts the
staff from cooldown-spam to a mana economy**, and **deepens the staff's primary fire** so the
Arcanist has a skill loop (land bolts → earn mana → spend on big casts) instead of a spam loop.

Design goal: each loadout wins differently. Duelist = single-target execution via parry/riposte.
Earthshaker = space control, damage concentrated under the hammer head. Arcanist = resource
management + aim skill.

---

## M1 — Hammer slam: damage core shrinks, outer ring becomes pure control

Current ([warhammer.gd](../weapons/warhammer.gd)): full damage within `INNER_RADIUS 2.0`,
`0.4×` splash out to `OUTER_RADIUS 3.6`, shove only within the inner core.

New model — **invert damage and shove**:

- `INNER_RADIUS 2.0 → 1.6` — damage **only** inside the core, plus the strong shove.
- Outer ring (keep `3.6`): **no damage at all**, shove only, at ~`0.6×` force — it's the
  "create space" tool. Delete `SPLASH_DAMAGE_MULT`.
- `Bone Breaker` (wall-impact damage) now attaches to outer-ring shoves too — intentional:
  it becomes *the* way to convert control into damage, which is a boon identity, not a default.
- VFX: render two distinct rings (hot core flash + dusty outer ripple) so the no-damage shove
  reads honestly. Splash `melee_hit` sound goes away; only core hits sound meaty.

Aftershock inherits all of this automatically (it re-runs `_slam`).

## M2 — Seismic Slam: snappier cast, wall-to-wall travel

Current: `WAVE_WINDUP 1.1`s, wave dies after `GroundShockwave.RANGE 16`m.

- `WAVE_WINDUP 1.1 → 0.6` (and `WAVE_SETTLE_TIME 0.45 → 0.35`) — still a committed cast,
  no longer an eternity.
- `GroundShockwave.spawn()` gains a `range` parameter (default keeps `RANGE` for any other
  caller); the hammer passes `40.0` so the wave crosses the whole arena (`ARENA_HALF 18.5`).
  Riptide's end-of-line stagger and Implosion's gather still fire wherever the wave ends.
- Keep `WAVE_COOLDOWN 6.0` and `WAVE_DAMAGE_MULT 1.2` — the wave is a line, it already obeys
  the "damage where the hammer is" rule.

## M3 — Hammer AoE boons scaled down

- **Wide Tremor** ([wide_tremor.tres](../data/boons/wide_tremor.tres)): `+10% → +6%` per pick,
  bespoke `rarity_mults [1.0, 2.0, 2.5, 4.0] → [1.0, 1.5, 2.0, 3.0]`. (Radius scales area
  quadratically — a legendary was +40% radius ≈ ×2 area on the *damage* core.)
- **Aftershock**: `AFTERSHOCK_DAMAGE_MULT 0.5 → 0.4`, `AFTERSHOCK_AOE_MULT 0.8 → 0.7`.
- Leave the shove/CC boons (Wrecking Ball, Implosion, Riptide, Bone Breaker) alone — control
  is the identity we're steering toward.

## M4 — Staff mana bar

The core anti-spam change. Mana lives on `Player` (fields only active while `weapon is Staff`,
same pattern as the frost-nova gate), HUD gets a mana bar under the guard/spell slots.

- `MANA_MAX 100`, passive regen `4/s` (25s to fill from empty — slow on purpose).
- **Arcane Bolt is the generator**: costs nothing; each bolt that hits an *enemy* (not walls
  or ground) restores `8` mana. `ArcaneBolt` needs an on-hit callback to the wielder.
- **Every loadout spell costs mana**: Fireball `40`, Frost Nova `30`; future spells priced
  on impact. Insufficient mana blocks the cast (thunk SFX + bar flash, no cooldown consumed).
- Cooldowns stay but become a pacing floor, not the limiter — see M5.
- HUD: spell slots grey out when unaffordable; show cost on the slot.

Feel target: opening a fight with a banked fireball is right; chaining three back-to-back
without weaving bolts is not.

## M5 — Fireball identity: big, committed, expensive

- **Remove the shove**: delete the `apply_shove` loop in [fireball.gd](../weapons/fireball.gd)
  (`EXPLOSION_SHOVE` gone). The Hierophant's `EnemyFireball` is a separate class — untouched.
- **Raise the payoff**: `FIREBALL_BASE_DAMAGE 30 → 45` (keeps `damage ×1.5 + spell_damage`
  scaling). Cast time stays `0.8`s — cost + cast time are the counterweights now.
- **CDR abuse guard**: raise the `_spell_cooldown` clamp floor `0.25 → 0.5` in
  [player.gd](../actors/player/player.gd). With mana as the true limiter this is belt-and-braces;
  if playtest shows mana alone suffices, the floor can relax again. Quick Mind / Attunement keep
  their value (faster charge refill still matters for burst banking via Twin Flame).

## M6 — Staff primary-fire boon family

New uniques, all `requires_weapon` = the staff id ([staff.tres](../data/weapons/staff.tres)).
These make the *generator* the build canvas, which the mana economy now rewards directly:

- **Split Shot** (unique): a bolt that hits an enemy splits into 3 mini-bolts (`40%` damage)
  fanning onward from the impact point. No split on walls/ground; children never re-split;
  children restore half mana on hit.
- **Scatter Shot** (unique): LMB fires 3 bolts in a flat ±6° fan, each `55%` damage. More total
  damage up close, worse at range — a positioning trade.
- **Burst Fire** (unique): LMB fires a 3-round burst (0.08s apart) then a longer pause; the
  whole cycle scales with `attack_speed`, per the feedback. ~+25% throughput with a rhythm
  you have to aim around.
- **Arcane Surge** (stat boon, own idea): while mana ≥ 80%, bolts deal `+30%` damage —
  rewards *not* hoarding casts and gives a "bolt-primary" build a capstone.

Stacking: allow all of them to coexist (scatter children can split; burst fires scatters).
That's the legendary fantasy — but mana restore per hit is per-*bolt* capped at the base `8`
per trigger pull to stop scatter+split turning into a mana printer. Watch item for playtest.

---

## Playtest checklist

- Hammer time-to-kill on a mid-run pack should drop noticeably vs. duelist's — but the pack
  should end up shoved into a wall, not dead from splash.
- Seismic Slam should feel castable in combat, and crossing the arena should visibly matter.
- Staff: count fireballs per minute before/after. Target roughly halved sustained rate, with
  the *option* to bank + burst two.
- Duelist untouched — re-rate its relative power only after these land.
