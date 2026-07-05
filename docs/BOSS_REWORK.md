# Boss Rework — Juggernaut weapon kit + the minute-5 Caster

> **Status: 🔨 In progress (M1 done).** Reworks the Juggernaut from "big chaser with a charge" into a two-mode warhammer boss (boulder throw at range, telegraphed hammer slam up close), and replaces the minute-5 double-Juggernaut wave with a new **Caster boss** that kites, retaliates with a zero-damage repulse, and carries the staff drop. Collecting the staff **ends the run (victory)** for now.

Guiding constraint (same as the progression rework): everything rides on machinery that already exists — the EnemyBase state machine with per-state overrides, the hurtbox pipeline (so block/parry/dash counterplay works against every new attack for free), `apply_shove`/`AttackInfo.knockback` as the displacement primitives, `Projectile`/`Fireball` as templates, and the boss-relic flow in `RunDirector`. Two genuinely new pieces of tech: a **ground telegraph** VFX and a **public push API on the player**.

All numbers below are *first guesses* unless stated otherwise.

---

## 0. Shared tech (build first)

### 0.1 `GroundTelegraph` (`core/ground_telegraph.gd`)

The one reusable piece every new attack needs: a flat danger-zone decal on the ground that warns, fills, then fires a callback.

- **API:** `GroundTelegraph.spawn(parent, position, radius, duration, color) -> GroundTelegraph`, plus a `fired(position)`-style completion the attacker awaits (or the attacker just times its own state machine and treats the telegraph as pure VFX — simpler, preferred: **the attack owns the timing, the telegraph is display-only** with a `duration` after which it frees itself).
- **Look:** unshaded emissive ring at the outer radius + an inner disc that scales from 0 → radius over `duration` (classic "hit lands when the fill reaches the rim"), brief flash at the end. Built in code like `GroundShockwave` (no scene); mesh from `VfxPool.unit_sphere()` flattened to ~0.05 Y, so it's cheap and pool-friendly.
- **Color language:** enemy telegraphs use the windup orange-red family (`EnemyBase.WINDUP_COLOR`-ish, alpha ~0.5). Keep it distinct from the player's own warm-orange hammer shockwave by pushing enemy telegraphs toward red.
- **Consumers:** Juggernaut boulder landing spot, Juggernaut hammer slam zone, Caster eruption rifts. Future AoE enemies get it free.

### 0.2 `Player.apply_shove(impulse)` (`actors/player/player.gd`)

Mirror of `EnemyBase.apply_shove`: sets the existing private `_knockback` directly and adds the small vertical pop (`velocity.y += min(impulse.length() * 0.15, 3.0)`), no damage event, no HUD flash, no shake side-effects beyond what the caller adds. Used by the Caster's repulse and the eruption rifts. Dash keeps its existing rule (`_dash()` zeroes `_knockback`, so a well-timed dash still escapes a shove).

### 0.3 Delivery rule for enemy ground AoEs

Enemy AoE damage vs the player routes through `player.get_node("Hurtbox").receive_hit(AttackInfo.new(boss, dmg, kb))` — never direct `health.take_damage`. That keeps dash i-frames, the block cone, perfect-block parries (which stun the boss via `info.source.stun()` — the punish window survives the rework), and future mitigation working unchanged. Same pattern the player's hammer uses against enemies, just pointed the other way.

---

## 1. Juggernaut rework (`boss_enemy.gd`, `BossEnemy.tscn`, `juggernaut.tres`)

The base "windup punch" melee attack is **gone**. The Juggernaut gets a warhammer and two attacks chosen by distance, plus the existing charge unchanged as its signature.

### 1.1 Model: give it the hammer

- Replace the fist sphere under `FistPivot` with a boss-scale warhammer: cylinder handle + box head, roughly 2× the player's proportions, dark iron material matching the existing fist color. **Keep the node name `FistPivot`** — `enemy_base.gd` resolves it in `@onready`.
- The existing `FIST_REST / FIST_WINDUP / FIST_PUNCH` pose constants get boss-local replacements: rest (hammer at its side), overhead raise (slam windup — read as the player's own Seismic Slam telegraph), throw-arm poses for the boulder. Reuse `_tween_fist` for all of them; it's just positions.

### 1.2 Boulder throw — the ranged default

Replaces the punch whenever the player is **beyond `SLAM_RANGE` (4.5)**.

- **Targeting:** at windup start, compute the landing point as *player position + horizontal player velocity × (windup + flight time)*, lead clamped to ~6 m and to the arena bounds — "a spot in front of the player," honestly committed up front. Spawn the `GroundTelegraph` there immediately (radius = impact radius, duration = windup + flight ≈ **1.9 s**) so the warning covers the whole threat.
- **Windup 1.0 s:** reuses the WINDUP state and its existing tells (orange tween, eye ignite) plus an arm-back hammer pose. Facing may keep tracking here — the *landing point* is what's locked, and the telegraph shows it.
- **Boulder:** new `actors/enemies/boulder_projectile.gd` (Node3D, code-built like `GroundShockwave`): big stone sphere, ballistic arc solved for a fixed **flight time 0.9 s** to the committed point, slow tumble for flavor. No mid-flight collision — it's a mortar, the landing is the attack (dashing *through* its arc shouldn't kill you; the zone on the ground is the truth).
- **Impact:** AoE **radius 2.8** at the landing point. Player inside → hurtbox hit with `damage × dmg_mult × 0.75` (~30 base) + knockback 8. Minions inside get `apply_shove` away from the impact (flavor, no damage — same courtesy the charge gives them). `BlastVfx` ground ring + dust `ShardBurst` in stone grey + a low thud (`SfxFactory`: keep the fundamental low per the audio direction).
- **Cooldown 3.5 s** between throws; suspended during charge phases. Between throws it keeps advancing at `move_speed()` — the boulder suppresses camping, the walk keeps the pressure.

Blocking: the impact routes through `mitigate_hit`, so facing the Juggernaut and blocking works; a *perfect* block stuns it across the arena, same as parrying a Spitter glob today. Consistent, keep it.

### 1.3 Hammer slam — the close-range punish

Triggers instead of the boulder when the player is **within `SLAM_RANGE` (4.5)** at decision time.

- **Windup 0.9 s, facing locked:** capture facing and the impact point at windup start, then **stop turning** — override `_face_target()` to early-out while the slam is winding up (that's the "walk behind it" counterplay the user asked for; `EnemyBase._physics_process` calls `_face_target()` every frame otherwise). Big overhead raise pose + the standard color/eye telegraph + `GroundTelegraph` on the impact zone.
- **Impact point:** `IMPACT_DISTANCE 3.2` in front of the *locked* facing — the spot the player stood on when the windup began, exactly like the player's hammer but scaled up.
- **Properties (player warhammer, boss-sized):** the player's slam is inner 2.0 full damage + shove / outer 3.6 at 40% splash / shove 9 / only-the-core-pushes. Juggernaut version: **inner 3.0** full `damage × dmg_mult` (40 base) + knockback **14**; **outer 5.5** at **40% splash, no knockback**; point-centered circle (no frontal-arc cutout — the facing lock already provides the blind spot). Delivery per §0.3, so parry-stunning the slam cancels into the stun state via the existing synchronous-stun handling.
- **Recover 1.0 s** — the punish window, slightly longer than the old 0.6 because the attack is now avoidable rather than tankable.
- Minions in the inner radius get shoved (no damage), same as the charge plow.

### 1.4 What stays

- **The charge is untouched** — signature move, every 5.5 s, parry-cancellable, dash-through-able. Boulder/slam decisions only happen while `_charge_phase == NONE` (the existing `_chase` match already structures this).
- Stun/parry/death choreography, loot waves, HUD bar: unchanged.

### 1.5 Data changes (`juggernaut.tres`)

- `attack_range` → large (**26**) so the base state machine always considers an attack and the script picks the mode by distance (Spitter precedent: behavior overrides, data stays dumb).
- `windup_time` 0.6 → **0.9** (slam), `recover_time` 0.6 → **1.0**. Boulder-specific timings live as consts in `boss_enemy.gd` next to the CHARGE_* block (same precedent).
- `unlock_drops` → **`[&"weapon_warhammer"]` only** — the staff moves to the Caster (§3.3).

---

## 2. Caster boss — the minute-5 encounter

New enemy: `actors/enemies/caster_boss.gd` + `CasterBoss.tscn` + `data/enemies/caster.tres`. Working name **"THE HIEROPHANT"** (alternatives: ARCHON, MAGUS — pick at implementation).

### 2.1 Scene & model

- Tall, slim silhouette (narrow capsule, robe-like cone skirt mesh if cheap), cold color (deep violet) so it reads against the red Juggernaut. Eyes as usual (the windup tell comes free).
- **Staff mounted under `FistPivot`** (node name kept for `enemy_base.gd`): rod + emissive orb, a scaled-up echo of the player's staff — the orb flares on every cast (`_tween_fist` + an orb material tween, same trick as `staff.gd::_recoil`).
- Standard `Health/Hurtbox/AttackHitbox/Mesh/FistPivot` skeleton so all base plumbing works.

### 2.2 Data (`caster.tres`)

| Field | Value | Note |
|---|---|---|
| max_health | **420** | ×3.5 wave HP mult at 300s ≈ 1470. One boss vs the old two Juggernauts (3500 total) — it's harder to *reach*, not a damage sponge |
| move_speed | **2.4** | slow, per design |
| damage | **20** | the fireball baseline; other spells scale off it |
| attack_range | **18** | casts from far |
| windup / recover | 0.8 / 0.8 | per-cast telegraph timing |
| knockback | 4 | on fireball hits |
| gold / xp | 150 / 90 | boss-tier |
| spawn_weight | 0.0 | event-only |
| tags | `[&"boss"]` | HUD bar + banner free |
| unlock_drops | **`[&"weapon_staff"]`** | the point of the fight |

### 2.3 Movement — kite, slowly

Override `_chase()` (Spitter is the template, inverted priorities):

- Player closer than **RETREAT_RANGE 13** → move directly away at `move_speed()`.
- Near the arena edge (position beyond ~85% of half-extent 18.5) blend in a tangential component so it slides along the wall instead of pinning itself in a corner. If genuinely cornered (player close AND wall behind), commit to the lateral direction with the bigger escape angle. This stays dumb-simple steering; if it still corners badly in playtests, the escalation is a short **blink teleport** on a long cooldown — noted as a reserve, not in scope.
- All steering through `move_speed()` so Frost-Nova-style slows keep working (staff isn't owned yet during the canonical first fight, but veterans replay it).

### 2.4 Repulse — the anti-melee retaliation

**A delayed-trigger push: the first hit the Caster takes arms a 1.5 s fuse; when it elapses, the player is flung far away, taking 0 damage.**

- **Arming:** override `_on_damaged(info)` (already connected via `health.damaged`) → after `super()`, if the fuse isn't already armed, arm it: `_repulse_at = 1.5 s` from now. **Further hits while armed do NOT reset or extend the fuse** — the first hit starts the clock, period. After firing it disarms; the next hit taken arms it again (the delay itself is the pacing, no separate cooldown).
- **Firing:** `player.apply_shove(away_dir * 26)` (§0.2) — delivered directly, **not through the hurtbox pipeline: it cannot be blocked or parried** (dash's knockback-clear can still cheat it; that's fine, dash is the universal out). Expanding `BlastVfx` ring at the caster, dedicated low *whoomp* cue, tiny screen shake on the player. Skip firing entirely if the player is already beyond ~RETREAT_RANGE — no point yeeting someone who already left.
- **Tell:** the fuse must be readable — the staff orb flares and an inflating `BlastVfx`-style ring builds at the caster over the 1.5 s, so the player *sees* the push coming and chooses: squeeze in one more swing, or disengage/dash on the pop.
- **Stun pauses the fuse:** the timer only ticks while `state != STUNNED`. The repulse itself can't be parried, but the Caster's own projectiles can — a perfect block on a bolt/fireball stuns it remotely (existing pipeline), the fuse freezes for the stun duration, and burst time is extended by exactly that much. Fight loop: dodge spells in → first hit starts the fuse → 1.5 s of free swings, parry mid-window to stretch it → eat the pop or dash it → re-approach.
- 0 damage, explicitly — it's a pacing mechanic, not a thorns clone (the existing `thorns` boon stays player-only).

### 2.5 Spell kit

A cast rotation driven from `_chase()` by per-spell cooldowns + a **global cast lockout 1.2 s**; each cast reuses WINDUP (orange/eye telegraph + staff-orb flare) → fires in `_begin_attack` → RECOVER. Priority when several are ready: **Eruption > Triple Fireball > Bolt**.

1. **Arcane Bolt** *(filler — "attack with projectile, like spitter/staff")*, every **2.5 s**: one straight `Projectile` (reuse the Spitter's scene/pipeline), speed **16**, damage `data.damage × 0.6` (~12). Cheap constant pressure so the player is never allowed to just stroll over.

2. **Triple Fireball** *(the main spell)*, every **7 s**: three fireballs in a horizontal fan **centered on the player** — center ball aimed at the player's predicted position, flankers at **±14°**. New `actors/enemies/enemy_fireball.gd` (the player's `Fireball` targets `EnemyBase.alive`; the enemy version is the mirror): speed **10** (deliberately dodgeable), ember trail in the Caster's violet so ownership is unambiguous, explodes on player-hurtbox contact / wall / 4 s timeout — **explosion radius 3.0** vs the player through the hurtbox, `data.damage × dmg_mult` + knockback 10, and shoves (not damages) minions caught. The fan geometry is the design: sidestepping the center ball walks toward a flanker; the clean answers are dash-through, block, or radial retreat.

3. **Arcane Eruption** *(the repositioning challenge)*, every **10 s**: **three chained rifts**, each targeting the player's *current* position at its own start — telegraph (`GroundTelegraph`, radius **2.6**, fill **0.8 s**) then eruption: `data.damage × 1.2` + `Player.apply_shove` (impulse 18, mostly upward pop) through the hurtbox, **0.55 s** between rift starts. Standing still eats rift two; the spell forces continuous movement and combos naturally with the repulse (getting pushed *into* a telegraph is the signature "oh no"). Reuses GroundTelegraph + BlastVfx + a `FlamePatch`-style residue only if it reads well — no new subsystem.

### 2.6 What comes free

`boss` tag → HUD health bar + spawn banner; spawner ring placement (14–22 from the player — a fine opening distance for a kiter); minimap orange-windup blips; boss death choreography if we extend `BossEnemy`… **decision: extend `EnemyBase` directly** (the Caster shares none of the charge machinery) and lift the death-spectacle + loot-wave block out of `boss_enemy.gd` into either a small `BossDeath` helper or a shared intermediate class `BossBase` — whichever diff is smaller at implementation time. The guaranteed first-wave health drop applies to it too.

---

## 3. Schedule, drops, and ending the run

### 3.1 Wave table (`data/waves/default.tres`)

- **300 s event:** two Juggernauts → **one Caster**, announcement `"THE HIEROPHANT APPROACHES"`.
- 150 s single Juggernaut, all swarm events: unchanged.
- The double-Juggernaut spectacle is cut, not lost — worth re-adding later as a *post-staff* repeating event once the run doesn't end at minute 5. Out of scope here.

### 3.2 Boss-loot flow

No mechanism changes: `RunDirector._track_boss / _on_boss_wave_cleared / _spawn_relic` and the arena-clear + spawn-pause all key off `unlock_drops`, which just moves. Kill-order gating keeps working per boss type (first Juggernaut kill ever → hammer; first Caster kill ever → staff).

### 3.3 Staff pickup ends the run

- `RunDirector._on_unlock_claimed(ability)`: if `ability == &"weapon_staff"` → instead of clearing `_spawning_paused`, call the existing end-run handoff with a **victory flag**: `GameManager.end_run.call_deferred({time, kills, gold, victory: true})` (same deferred pattern as `_on_player_died`; MetaProgression already saved inside the grant, and the arena is already cleared + paused, so nothing can kill the player in between).
- `ClaimScreen`: for the staff, swap the subtitle to run-complete framing ("THE STAFF IS YOURS — RUN COMPLETE"); its Continue button unpauses into the (already scheduled) scene change.
- `DeathScreen`: read the `victory` flag from the stats dict → title "VICTORY" instead of the death framing; stats + shop otherwise identical (it already handles the `abandoned` variant, so the pattern exists).
- **Veteran saves that already own the staff:** the Caster drops nothing, no claim fires, the run continues endless past minute 5. That's acceptable for "end the run *for now*" — the victory gate is the progression moment, not a hard wall. No save migration needed anywhere in this rework.

---

## 4. Implementation order

Each milestone ships independently and smoke-tests headless (scene loads; scripted spawn + attack tick):

1. **M1 — Shared tech:** ✅ **Done.** `GroundTelegraph` (`core/ground_telegraph.gd` — display-only filling-disc decal, `ENEMY_COLOR` windup red), `Player.apply_shove` (`actors/player/player.gd`, mirror of `EnemyBase.apply_shove`, dash still escapes). Tiny, unblocks everything.
2. **M2 — Juggernaut kit:** split into two chunks.
   - **M2a — hammer model + slam:** ✅ **Done (pending playtest).** Warhammer mesh under `FistPivot` (handle + head), boss-local `BOSS_FIST_*` poses, hammer slam via the base WINDUP→ATTACK→RECOVER path (facing lock through `_face_target` early-out, committed `_slam_point` + `GroundTelegraph`, inner 3.0 full / outer 5.5 @ 40% splash, kb 14), retuned `juggernaut.tres` (attack_range 26, windup 0.9, recover 1.0), charge preserved (fist poses repointed to boss-scale). `unlock_drops` still carries the staff — moves off in M5. Placeholder `hammer_slam` SFX until M4.
   - **M2b — boulder throw:** ✅ **Done (pending playtest).** `boulder_projectile.gd` (Node3D mortar — lead-clamped landing, ballistic arc, impact AoE 2.8, minion shove, no mid-flight collision), `BoulderPhase` sub-phase in `_chase` (interleave-gated against the charge: boulder freezes charge cooldown and vice versa), 3.5 s cooldown, `stun()` cancels an in-flight windup. Placeholder `hammer_slam` thud until M4.
   - **Runtime-validated** via a throwaway headless harness (`Godot --headless res://<scene>` with autoloads live): boulder end-to-end dealt the exact expected 105 dmg through the player hurtbox and the projectile cleaned up; slam WINDUP→ATTACK→RECOVER cycled with no errors; distance-based mode selection confirmed.
   - Playtest gate (owner): the 150 s fight, with every loadout — pose/timing feel + telegraph honesty.
3. **M3 — Caster core:** scene/data, kiting + wall-slide, repulse (with stun suppression), Arcane Bolt, Triple Fireball. Test via a temporary early `WaveTable` event time.
   - **M3a — `BossBase` refactor:** ✅ **Done.** Extracted the death-spectacle + loot-wave block (consts + `_on_died`/`_death_burst`/`_spawn_loot_wave`/`_wave_share`) from `boss_enemy.gd` into a new `actors/enemies/boss_base.gd` (`BossBase extends EnemyBase`). `BossEnemy` now `extends BossBase` and keeps only a thin `_on_died` that cancels an in-progress charge before `super()`. The Caster will `extend BossBase` for the same death/loot free. Behavior-preserving; Juggernaut death verified to still run its choreography at runtime.
   - **M3b — Caster scene + data + kiting + Arcane Bolt:** ✅ **Done.** `caster.tres` (THE HIEROPHANT, 420 hp, event-only, staff drop), `CasterBoss.tscn` (tall violet capsule, robe skirt, staff `Rod`+`Orb` under `FistPivot`), `caster_boss.gd` (`CasterBoss extends BossBase`): kiting `_chase` (flee inside RETREAT_RANGE 13 with wall-slide/corner-escape steering), cast scaffold (per-spell cooldown + 1.2 s global lockout, WINDUP colour/eye tell → `_begin_attack` fires spell → RECOVER, staff untouched so no fist-pose glitch; `stun()` restores the staff rest), Arcane Bolt (reuses `Projectile`, speed 16, 0.6× dmg), orb-flare on cast. **Runtime-validated:** bolt dealt the exact 12 dmg through a correctly-configured (layer-8) player hurtbox; kiting confirmed.
   - **M3c — repulse + Triple Fireball:** ✅ **Done.** Repulse (`_on_damaged` arms a 1.5 s fuse on the first hit; `_physics_process` override ticks it across all live non-stunned states; `_fire_repulse` does a direct **un-blockable** `player.apply_shove(26)`, 0 damage, skipped if the player already left; orb brightens as the fuse fills). `enemy_fireball.gd` (`EnemyFireball` — violet code-built Area3D mirror of the player Fireball, mask 9 → player hurtbox + walls, radius-3 AoE + minion shove). Triple Fireball (`_cast_fireball` fans three at ±14° around a lightly-led aim; 7 s cd; priority over bolt). **Runtime-validated:** repulse armed → held at 1.20 through a 0.6 s stun → fired at exactly 2.1 s (1.5 + stun) for 0 damage; fireball fan spawned 3, centre dealt exactly 20 dmg, flankers spread; cooldown priority (fireball→bolt) confirmed. Placeholder SFX (`magnet_collect` whoomp, `explosion`) until M4.
4. **M4 — Eruption + rotation polish:** the third spell, cast priorities, orb-flare/SFX pass (new cues: repulse whoomp, boulder thud, eruption crack — low fundamentals, differentiate by timbre).
   - **M4a — Arcane Eruption:** ✅ **Done.** Three chained rifts (`_cast_eruption` schedules `_spawn_rift` at 0/0.55/1.1 s via `create_timer`; each snapshots the player's *current* position, telegraphs 0.8 s in violet, then `_erupt` hits through the hurtbox for 1.2× dmg + an up-and-out `apply_shove` pop, shoving minions). Sequence outlives the cast's RECOVER; guarded against death/untree. `_choose_spell` priority now Eruption > Fireball > Bolt. **Runtime-validated:** 3 rifts staggered 0.55 s, each erupted ~0.8 s later for exactly 24 dmg (72 total on a parked dummy). Placeholder `explosion` SFX until M4b.
   - **M4b — SFX pass:** ✅ **Done.** Three new procedural cues in `SfxFactory` (`boulder_impact` — rocky boom+debris+crack; `repulse` — low outward whoomp with a rising-cutoff swell; `eruption` — sharp crack over a sub thump + rising geyser tone), all low-fundamental / timbre-differentiated per the audio direction. Wired out the placeholders: boulder → `boulder_impact`, repulse → `repulse`, eruption → `eruption`. The slam keeps `hammer_slam` (it *is* a hammer slam — no new cue called for). Verified all three synthesize + play headless.
5. **M5 — Schedule + victory:** wave-table swap, `unlock_drops` moves, run-end-on-staff + ClaimScreen/DeathScreen framing. Update `docs/ENEMIES.md` + `PLAN.md` after it all lands (the usual doc refresh).

## 5. Risks / tuning watch

- **Melee vs a kiting repulse boss = tedium risk.** The 1.5 s fuse (§2.4) is the designed answer — every approach buys a guaranteed burst window, and parries stretch it. The knobs, in order: fuse duration ↑, parry-stun window (already boosted by Punishing Stun builds; each parry pauses the fuse for its full duration), retreat range ↓, move speed ↓. **Note the hammer can't block at all** (`can_block=false`), so it can't parry-stretch the window — its fuse window must be worth it on its own (a full slam + Aftershock should fit inside 1.5 s); if the hammer still struggles, lengthen the fuse or give the push a distance falloff before touching anything else.
- **Telegraph honesty.** Boulder and slam both commit their impact point at windup start — never retarget mid-windup, or the indicator lies and dodging feels random. The facing lock is part of the same contract.
- **Remote parry-stuns** (block a bolt → boss stunned at 18 m) get *stronger* with two projectile bosses. It's the sword's identity, keep it, but watch Punishing Stun + Expose Weakness stacking against the Caster — the single-target riposte check from the progression rework applies here doubly.
- **Charge/boulder interleave:** cooldowns must not let a charge fire during a boulder windup (gate both on `_charge_phase == NONE` and vice versa) or the boss teleports out of its own telegraph.
- **Minute-5 difficulty cliff:** the Caster arrives while swarm events keep firing (spawning only pauses *after* it dies). Dodging eruptions while a Sprinter swarm closes may be brutal — if so, thin the 300 s-adjacent swarm timing rather than nerfing the boss kit.
- **Player shove vs arena walls:** repulse impulse 26 near a wall does nothing (no player wall-slam mechanic — fine), but repulse + eruption pop can juggle; cap total `_knockback` magnitude in `apply_shove` if playtests show stun-juggling.
