# Crashing Leap Redesign: Death From Above

Replaces the Phase 8C fixed ballistic hop ([MOBILITY_REWORK.md](MOBILITY_REWORK.md) M3) with a
two-phase skyfall. The old leap reads as a long jump; the fantasy we want is *orbital strike
with a hammer*. Current code: `_begin_leap` / `_land_leap` in
[player.gd](../actors/player/player.gd), `leap_windup` / `leap_slam` in
[warhammer.gd](../weapons/warhammer.gd).

---

## Phase 1 — Ascent & aim

- Shift launches the earthshaker **straight up ~15m in ~0.4s** (punchy, not floaty), then
  holds a locked hover at the apex. Movement and attacks are disabled; mouse look stays live.
- During the ascent the camera **auto-pitches down ~55°** (tweened, additive to mouse look) so
  the player arrives already looking at the arena — no "where am I" beat. Slight FOV widen at
  apex for the bird's-eye feel.
- A **ground circle indicator** tracks the camera-center ray intersected with the ground plane
  (y=0), clamped to `Spawner.ARENA_HALF` on both axes and to a **max targeting range of ~14m**
  from the takeoff point (2× the old reach — generous, but not a free full-arena teleport;
  tunable). Indicator radius = the slam's real `OUTER_RADIUS × aoe_mult`, so what you see is
  exactly what dies.
- **Slow motion during the aim window**: `FreezeFrame.slow_motion(0.5, …)` from apex until the
  crash triggers. Sells the power moment and compensates for enemies drifting under a moving
  target. Restore on phase 2.
- **Not an invincibility button**: hurtbox stays live — spitter/caster/boss projectiles can
  tag you at the apex (same anti-roof-camp rule as levitate). Knockback is zeroed while locked
  so a stray hit can't shove the hover; damage does not cancel the skill.

## Phase 2 — The crash

Two triggers, whichever comes first:

- **Click** (primary attack; Shift re-press also accepted) → crash immediately at the
  indicator.
- **1.0s elapses** at the apex → crash at wherever the player is looking at that instant.

The crash itself:

- Dive in a straight line to the target at fixed **~0.22s regardless of distance** (speed
  scales with distance — every crash hits like a meteor, close ones don't feel weaker).
  **Intangible during the dive only** — it's a commit, and clipping a projectile mid-dive
  feels like being shot out of the sky by accident, not counterplay.
- Floor contact → existing `leap_slam()`: 360°, full-damage radius, shove + stagger.
  Epicenter's four seismic waves erupt from the new landing point unchanged.
- Impact juice scaled up from the current hop: shake ~0.35 (vs 0.15), the warhammer
  `HIT_PAUSE`, a bigger dust ring, and a low impact thump layered under `hammer_slam`
  (low-fundamental SFX rule). Descent gets a whoosh riser + a brief vertical trail streak.

## Fun adjustments (beyond the brief)

- **Indicator confirm glow**: the circle brightens/pulses when ≥1 living enemy is inside —
  a "yes, fire" signal that makes the click feel earned.
- **Camera pitch assist + slow-mo** (above) are the two big feel levers; ship them in M1/M2,
  not as polish.
- **Crosshair hides** during phase 1; the indicator *is* the crosshair.
- Landing keeps the wave-settle combo: Shift still bypasses the weapon `_cooldown` gate, so
  "wave → skyfall onto the drag-clump" survives the redesign and now aims itself.

## Guards & watch items

- Cooldown stays **5s** (Slipstream mult applies). The skill got stronger (aimed, longer
  range) but also slower to deliver (~1.6s worst case airborne, no attacks) — playtest before
  touching either number.
- The old leap was a semi-escape; the new one always returns you to ground within ~1.6s. If
  earthshaker survivability craters, the escape valve is *aiming the crash away* — check that
  reads in playtest before adding anything.
- Suicide-button watch item from 8C carries over: the slam's landing stagger is the guard.
- Verify the arena is open-air at 15m (levitate only rises 5m today) and that boss
  choreography (`set_ignore_time_scale`) behaves under the aim-window slow-mo.
- Make sure the player cannot jump out of the arena. (stop the indicator / camera from panning past the bounds of the arena)

## Milestones

- **M1 — State machine & ascent.** `_leap_phase` (ASCEND / AIM / CRASH) replaces
  `_leaping/_leap_airborne`; input lockout; camera pitch tween; indicator node (unshaded ring
  mesh, reuse dash dust color family).
- **M2 — Targeting & crash.** Ground-plane ray + arena/range clamps; the three phase-2
  triggers; distance-normalized dive; slam wiring; slow-mo in/out; intangibility window.
- **M3 — Juice & verify.** Impact/riser SFX, shake/dust scale-up, confirm glow, crosshair
  hide; update `test/mobility_smoke.gd` (assert ASCEND→AIM→CRASH→slam, timeout auto-fire);
  sync [MOBILITY_REWORK.md](MOBILITY_REWORK.md) M3 and [COMBAT.md](COMBAT.md).

## Playtest checklist

- The 10-second blind-test still names the loadout — faster, since skyfall is unmistakable.
- Click-to-crash latency feels instant; the 1s auto-fire never surprises anyone mid-aim.
- Slow-mo window: power fantasy, not pace-breaker (if it drags, shorten toward 0.65 scale).
- Landing on a Broodling clump / under the Hierophant's repulse: fair, readable, survivable.
