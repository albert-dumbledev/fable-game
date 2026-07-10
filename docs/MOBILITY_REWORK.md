# Loadout Mobility Rework (Phase 8C)

Addresses the [FEEDBACK.md](FEEDBACK.md) dash block: one blink for all three loadouts wastes a
huge identity lever. Shift becomes **the loadout's signature movement verb** — duelist blinks,
Earthshaker leaps and crashes, Arcanist flies. This is the feature-sized plan; ship it after
8A/8B tuning so each move is balanced against the corrected curves.

Current state: dash is a player-level ability (`&"dash"`, granted by the Phantom Step boon),
implemented entirely in [player.gd](../actors/player/player.gd) (`_begin_dash` — 6m blink,
0.12s, intangible, 2s cooldown).

---

## M1 — Plumbing: mobility belongs to the weapon

- `Weapon` gains `mobility_id() -> StringName` (`&"dash"` / `&"hammer_leap"` /
  `&"levitate"`); player's Shift handler dispatches on it. The three implementations stay in
  `player.gd` (they move the body, own camera FX, and touch collision masks — same reasoning
  as `try_cast_fireball` living there), but all constants group per-mobility.
- **Phantom Step stays the unlock** for all three (rename copy to "unlock your loadout's
  mobility art"). Keeping it a boon preserves the early-run pickup ritual and means zero
  save-migration work. Open question flagged for later: make mobility baseline and give the
  boon a `+charges/-cooldown` role instead — decide after playtest.
- HUD cooldown slot reads the per-loadout id; three new/kept SFX (`dash` keeps, leap reuses a
  pitched-down `hammer_slam` layer, levitate gets a low sustained whoosh per the
  low-fundamental SFX rule).

## M2 — Duelist: blink, now with charges

- Keep the blink exactly as-is (feedback: it's right for this kit).
- New base-1.0 stat `dash_charges` (registered in `core/stats.gd`); charges refill
  sequentially through the cooldown, same pattern as fireball charges.
- **Phantom Reserves** (stat boon, sword-gated): `+1` dash charge; bespoke `rarity_mults`
  so legendary = +2, capped display at 4 total.
- **Shield Dash** (unique boon, from feedback): blinking through enemies stuns them (~0.8s,
  scaled by `parry_stun`) and **primes a riposte** (`_prime_riposte()` — the existing window,
  so it composes with Ruthless Riposte, Blade Cyclone, Second Wind for free). Detection:
  sphere-sweep the dash segment against `EnemyBase.alive`, reusing the seismic wave's
  segment-hit math.

## M3 — Earthshaker: Crashing Leap

Replaces the blink when the warhammer is mounted:

- Shift launches a ballistic hop toward facing: ~7m reach, ~0.45s airtime, fixed arc
  (velocity set once; normal gravity brings you down — works with the existing
  `move_and_slide` flow).
- Landing runs the hammer's `_slam()` at the impact point with **360° arc** (pass an
  arc-half override of 180°), ~0.8× primary damage in the (post-8A, smaller) core, full
  outer-ring shove. Camera shake + the heavy `HIT_PAUSE`.
- **No intangibility** — being airborne already dodges melee naturally; projectiles can still
  tag you mid-leap. That keeps the escape-tool crown on the duelist.
- Cooldown ~5s. **Seismic-slam follow-up** (from feedback): the leap is usable during the
  wave's settle time (skip the `_cooldown` gate for the leap specifically), so the combo
  "wave the pack → leap into the drag-clump → 360 slam" flows as one sentence. Implosion's
  gather makes the leap landing the payoff button.
- Watch item: leap into 20 enemies is also 20 windups on your landing spot — if it's a
  suicide button, add a 0.3s post-landing stagger to enemies in the core before touching
  numbers (same lesson as the Phase 5 gather-stun guards).

## M4 — Arcanist: Levitate

Replaces the blink when the staff is mounted:

- Shift boosts the player up (~5m) and holds a hover: gravity off, WASD air-strafe at
  ~0.8× move speed, full casting (bolts, fireball, nova all work — raining fireballs is the
  point). Ends after **2.5s**, on re-press, or on cast of the run-ending kind (none yet).
- Descent is a soft fall (no fall damage exists), cooldown ~8s starting on landing.
- **Anti-degenerate guards:** melee can't reach you up there, so — duration short, cooldown
  long, and spitter/caster/boss projectiles and the Hierophant's repulse still connect
  (hurtbox stays live; no intangibility). If Phase 8A's mana ships first, levitate drains
  ~8 mana/s while airborne, tying flight time to the same economy as the spells you're
  raining — this is the preferred coupling, flagged as a soft dependency.
- Feel: FOV lift + slight camera tilt-down bias so aiming at the ground feels intended;
  dust ring on takeoff/landing reusing the dash VFX.

## M5 — Integration pass

- Boon text, claim/death-screen loadout blurbs, and HUD slot icons per mobility.
- The Juggernaut charge / boulder arc / eruption rifts were all balanced around "dash
  escapes it" — re-verify each is escapable with leap (airborne over the wave?) and levitate
  (rise above the charge?), and adjust telegraph timings if a loadout has no answer.
- Headless smoke: mount each weapon, fire Shift, assert state transitions (charges decrement,
  leap lands and slams, levitate ends on timer).

---

## Playtest checklist

- Blind-test: a viewer watching 10 seconds of movement should name the loadout.
- Duelist: does Shield Dash + riposte feel like a designed line? Do charges change routes?
- Earthshaker: wave → leap combo lands in one breath; leap never feels like the *only* way
  to not die (it's an attack, not an escape).
- Arcanist: levitate feels like a power moment ~2× a minute, not a permanent roof camp.
- All three still have counterplay against each boss's signature attack.
