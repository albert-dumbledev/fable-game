# Enemies — state machine, data, spawning, drops

Design rule from PLAN.md §3 held: **a new enemy is a `.tres` file + (usually) a scene that reuses `enemy_base.gd`.** Behavior overrides are methods; numbers never live in scripts.

## EnemyBase state machine (`actors/enemies/enemy_base.gd`)

`CHASE → WINDUP → ATTACK → RECOVER → CHASE`, plus `STUNNED` and `DEAD`. All transition timings come from `EnemyData`; the only script-side timing is `ATTACK_ACTIVE_TIME = 0.25s` (the hit window).

| State | Behavior | Exits |
|---|---|---|
| CHASE | Straight-line steer at `move_speed`, face target | In `attack_range` → WINDUP |
| WINDUP | Hold still; **telegraph:** albedo tweens to orange, fist cocks back | After `windup_time` → ATTACK |
| ATTACK | Hitbox live 0.25s with `damage × dmg_mult`; punch fist forward + **lunge** at 1.8× move_speed, bleeding off | After 0.25s → RECOVER |
| RECOVER | Hold still (the punish window) | After `recover_time` → CHASE |
| STUNNED | Perfect-block reward: frozen, blue tint, 14° tilt, hitbox killed, attack cancelled | After stun duration → CHASE |
| DEAD | No steering; shrink tween then `queue_free` | — |

`stun(duration)` is called duck-typed from `Player.mitigate_hit` and **can land synchronously inside `hitbox.activate()`** — `_begin_attack` re-checks its state after activating before lunging. Bosses should override `stun()` (resistance/diminishing returns) rather than the parry code. The minimap reads `enemy.state` directly: orange blip = winding up/attacking, blue = stunned.

**Parry scaling (Expose Weakness):** `mitigate_hit(info)` scales incoming damage ×1.35 while a vulnerable window is open (`mark_vulnerable` sets the deadline to the parry-stun duration; returns a fresh `AttackInfo`, never mutates the shared one).

**Slows (Frost Nova):** `apply_slow(mult, duration)` scales *movement only* — chase, kiting, and attack lunges — never windup/recover timings, so telegraphs stay readable. All steering must route through `move_speed()` (variant `_chase()` overrides included) or it silently ignores slows. Reapplying overwrites the previous slow; the icy tint rides on `_resting_color()` so it never fights the windup/stun color tweens. The boss's committed charge deliberately ignores slows (it's `CHARGE_SPEED`, not `move_speed()`-based).

**Shove & Bone Breaker:** `apply_shove(impulse, wall_damage, source)` physically flings an enemy (no damage); impulse decays over ~a second. Bone Breaker carries an optional wall-damage payload: if the shoved enemy hits a wall while the impulse is still strong (≥5.0 u/s), it takes that damage once (via the hurtbox, so vulnerability/scaling apply), then the payload clears. No stun on wall impact — damage only.

## EnemyData (`core/enemy_data.gd`) and the enemy roster

Fields: `display_name`, `scene`, `max_health`, `move_speed`, `damage`, `attack_range`, `windup_time`, `recover_time`, `knockback` (impulse shoving the player on a landed hit), `gold_reward`, `xp_reward`, `spawn_weight`, `min_elapsed` (time gate, seconds), `tags`, `unlock_drops` (ordered `Array[StringName]` of ability flags; on a boss wave clearing, the first flag the player doesn't own drops as a weapon-relic pickup), `death_spawns` (optional `EnemyData` to spawn on death), `death_spawn_count` (count spawned, default 0).

### Core four

| | Chaser | Sprinter | Brute | Spitter |
|---|---|---|---|---|
| Unlocks at | 0s | **45s** | **90s** | **120s** |
| HP | 25 | 12 | 80 | 20 |
| Speed | 4.5 | 8.5 | 2.8 | 3.5 |
| Damage | 18 | 10 | 32 | 14 |
| Range | 1.8 | 1.6 | 2.2 | **9.0 (ranged)** |
| Windup / recover | 0.3 / 0.5 | 0.25 / 0.5 | 0.55 / 0.8 | 0.45 / 0.7 |
| Knockback | 5 | 3 | 9 | 2 |
| Gold / XP | 5 / 4 | 4 / 3 | 15 / 10 | 8 / 6 |
| Spawn weight | 1.0 | **0.67** | **0.4** | 0.5 |

Numbers were re-tuned in the chaos/lethality pass (2026-07-03): every hit is meant to matter against a fresh 100-HP player (~5 chaser hits early), telegraphs are ~25% snappier across the board, and the Spitter's recovery halved so it genuinely suppresses. M5 spawn weights retuned toward a late-game target mix (Chaser 30% / Sprinter 20% / Spitter 15% / Brute 12% / Stalker 15% / Broodmother 8%).

Roles: Chaser is the baseline; Sprinter forces backpedal discipline (fast, fragile, quick windup); Brute is the parry tutor (long telegraph, big hit, worst recovery); Spitter breaks camping. Only the Spitter has a script (`spitter_enemy.gd`, ~45 lines): overrides `_chase()` — kites away inside `RETREAT_RANGE 4.0`, closes to 9.0 — and `_begin_attack()` — spawns a `Projectile` (speed 12, lifetime 4s) aimed at the player, through the same hurtbox pipeline so shields work. Everything else inherits.

### New enemies (Phase 7)

| | Broodmother | Broodling | Stalker | Gilded One | Scavenger |
|---|---|---|---|---|---|
| Enters at | 135s (pool) | via death burst | 75s (pool) | 90s (chance event) | 150s (loot-triggered) |
| HP | 70 | 6 | 18 | 30 | 45 |
| Speed | 2.2 | 7.0 | 6.8 (orbit 8) | 7.2 | 4.2 / 5.8 sated |
| Damage | 24 | 6 | 16 | — | — |
| Range | 2.2 | 1.4 | 1.7 | — | — |
| Windup / recover | 0.5 / 0.8 | 0.22 / 0.45 | 0.28 / 0.35 | — | — |
| Knockback | 8 | 2 | 4 | — | — |
| Gold / XP | 10 / 7 | 2 / 2 | 7 / 5 | 60 / 25 | bounty ×1.25 |
| Spawn weight | 0.27 | — (not pooled) | 0.5 | — (event) | — (triggered) |
| Tags | — | — | — | `rare` | — |

**Broodmother** (`broodmother.tres`, stock `EnemyBase`): a slow swollen carrier. On death, bursts via the `death_spawns` mechanic into **5 Broodlings** — tiny fast fragile chasers that hatch (recover state for ~0.45s) then swarm. The kill *position* is the decision: loot and brood erupt at the corpse, so point-blank kills bring reinforcements into magnet radius, while ranged kills buy time. Feeds the Earthshaker AoE kit.

**Broodling** (`broodling.tres`, stock `EnemyBase`): a 0.45-scale Chaser. Only spawned via Broodmother death, never in the pool. Fragile (6 HP) but fast (7.0) — a swarm of them punishes panic.

**Stalker** (`stalker_enemy.gd`): evasive skirmisher. Two-mode `_chase()` override — **engage** mode curves onto the flank via a tangential blend until ~4m out, then strikes with a fast 0.28s windup; **disengage** mode retreats to orbit ~8m for 2.5–3.5s with lateral drift (eyes stay lit as the "still watching" tell), then re-engages. Chips the guard meter with its pokes and never idles in melee. **Counterplay:** parry it (perfect block stuns mid-strike), and at 18 HP one riposte deletes it. Frost slow collapses the disengage for free.

**Gilded One** (`gilded_enemy.gd`, tag `rare`): never-attacking fleeing jackpot. Flees biased toward the densest nearby enemy cluster (average of the closest 5 in `EnemyBase.alive`, recomputed ~1.2s) and wall-slides at the arena edge, so chasing it drags you into packs. Speed 7.2; **despawns after 30s** in a shimmer (drops nothing). Killed → a wide gold(60)/XP(25) jackpot ring burst plus a jackpot thunk SFX.

**Scavenger** (`scavenger_enemy.gd`): fat burrowing rat, **ignores the player entirely**. Seeks the nearest registered ground pickup, eats gold/XP within 1.3m at ~0.35s each (belly inflates, gold-tints itself), growing a bounty of `eaten × 1.25`. After **12 pieces or 18s** it telegraphs a 0.9s burrow and digs out — the loot is **gone**. Kill it first and the bounty erupts as a fountain. Sated (≥6 eaten) it speeds up to 5.8.

## Spawner + WaveTable scaling

`RunDirector` ticks the `Spawner` (`systems/spawner.gd`) each physics frame; all pacing comes from `data/waves/default.tres` (`core/wave_table.gd`). Placement: random ring **14–22** around the player, clamped to arena half-extent 18.5.

| Knob | Formula | Default |
|---|---|---|
| Spawn interval | lerp `start → min` over `interval_ramp_time` | 1.8s → 0.25s over 210s |
| Enemy HP | `× (1 + hp_growth_per_min · min)` | +50%/min |
| Enemy damage | `× (1 + dmg_growth_per_min · min)` | +40%/min |
| Reward (gold & XP drops) | `× (1 + reward_growth_per_min · min)` | +30%/min |
| Alive cap | lerp `start → end` over ramp | 24 → 90 over 270s |
| Pool pick | weight-roll among entries with `elapsed ≥ min_elapsed` | — |

Multipliers are baked per-enemy at spawn via `enemy.setup(data, hp_mult, dmg_mult, reward_mult)` — `EnemyData` resources are never mutated. Damage growth stays under HP growth so runs still end by attrition and being swarmed rather than pure one-shots, but at +40%/min it bites: with the 80-HP player baseline, "3–4 hits from death" holds through the midgame unless health boons are picked. The 90 alive cap is still well under the ~200 GDScript danger zone (PLAN §6); profile before raising it again. `spawn_enemy()` is public so scheduled `WaveTable` events reuse ring placement and scaling.

## Wave events, swarms & bosses

`WaveTable.events` is an `Array[WaveEvent]` (`time`, `enemy`, `count`, `announcement`, `repeat_every`, `chance = 1.0`), fired by `RunDirector` off a per-event next-fire clock, **bypassing the alive cap**. `repeat_every = 0` means one-shot; anything greater re-arms the event that many seconds after each firing — that's the SWARM mechanism. `chance` is a roll; if `randf() < chance` the spawn fires, but `repeat_every` re-arms regardless. An event whose enemy is tagged `boss` also emits `EventBus.boss_spawned` — the HUD binds a name + health bar to it; announcements show a fading banner.

**Rare event guards:** the `_rare_alive()` check ensures at most one enemy tagged `rare` is alive at a time (one Gilded One per spawn window). Boss-loot and loot-triggered spawns also guard against firing while spawning is paused.

Default table: one Juggernaut at **150s** ("THE JUGGERNAUT APPROACHES", drops `weapon_warhammer`), one Caster at **300s** ("THE HIEROPHANT APPROACHES", drops `weapon_staff` — collecting it **wins the run**), **12 Sprinters at 45s repeating every 50s** ("A SWARM APPROACHES"), **16 Chasers at 120s repeating every 80s** ("THEY POUR IN"), **24 Spitters at 360s repeating every 60s** ("THEY'RE EVERYWHERE"), **one Gilded One at 90s repeating every 70s** (chance 0.6, silent — spawn glimmer SFX + gold minimap blip are the announcement), and **3 Broodmothers at 240s** (one-shot "THE BROOD COMES" — a mid-run AoE exam between the two bosses).

**Shared boss tech.** `GroundTelegraph` (`core/ground_telegraph.gd`): a display-only ground danger decal that fills centre→rim over a windup then frees itself — the attack owns the timing, the telegraph is pure VFX. `Player.apply_shove(impulse)`: the mirror of `EnemyBase.apply_shove`, a no-damage push (a well-timed dash still escapes it, since `_dash` zeroes `_knockback`). Enemy ground-AoE damage vs the player always routes through `player.get_node("Hurtbox").receive_hit(...)`, never `health.take_damage`, so block/dash/perfect-block counterplay works unchanged. `BossBase` (`boss_base.gd`) holds the shared death spectacle + three-fountain loot wave; both bosses extend it.

**Juggernaut** (`boss_enemy.gd` extends `BossBase`; `juggernaut.tres`): 500 HP base (× wave HP mult), a warhammer with two distance-picked attacks plus the unchanged charge. `attack_range` is a dummy-large **26** so the base state machine always "attacks" and the script picks the mode by distance:

- **Hammer slam** (within `SLAM_RANGE 4.5`): rides the base WINDUP→ATTACK→RECOVER path (0.9 windup / 1.0 recover). At windup start it **locks facing** (overridden `_face_target` early-out — the "walk behind it" counterplay) and commits the impact point + a `GroundTelegraph`; the slam is a ground AoE mirroring the player's hammer (inner 3.0 full `damage × dmg_mult` + kb 14, outer 5.5 at 40% splash).
- **Boulder throw** (beyond `SLAM_RANGE`, 3.5s cooldown): a `BoulderProjectile` mortar (`boulder_projectile.gd`) lobbed on a fixed ballistic arc to a lead-clamped committed point — **no mid-flight collision**, the ground zone (radius 2.8) is the attack, so dashing through the arc is safe. Between throws it keeps advancing.
- **Charge** (unchanged signature): every **5.5s** it telegraphs (0.7s) then rushes at 24 u/s for 1.5s, collision mask dropping to **world-only** so it phases through the player (live hitbox at 1.5× damage + kb 18) and minions (shoved aside via `apply_shove`). A **perfect block cancels the charge** and stuns it; **dash** blinks through. Boulder/slam decisions only run while `_charge_phase == NONE`, and a boulder windup freezes the charge cooldown (and vice versa) so neither fires inside the other's window.

**Caster — THE HIEROPHANT** (`caster_boss.gd` extends `BossBase`; `caster.tres`): the minute-5 encounter. 420 HP base, slow (2.4), casts from **18** range. A kiter — `_chase` backs away inside `RETREAT_RANGE 13`, sliding along the arena walls rather than cornering itself. Cast rotation (per-spell cooldown + a 1.2s global lockout, priority **Eruption > Fireball > Bolt**):

- **Arcane Bolt** (2.5s): one straight `Projectile`, filler pressure so the player can't just stroll in.
- **Triple Fireball** (7s): three `EnemyFireball`s (`enemy_fireball.gd`, the violet mirror of the player's) fanned ±14° around a lightly-led aim — sidestepping the centre walks toward a flanker.
- **Arcane Eruption** (10s): three chained rifts, each telegraphing where the player *currently* stands then erupting (1.2× damage + an up-and-out pop) 0.55s apart — forces constant movement, combos with the repulse.
- **Repulse** (`_on_damaged` fuse): the first hit taken arms a **1.5s fuse**; when it elapses the player is flung clear (impulse 26, **0 damage**) as a direct, un-blockable `apply_shove` (dash still escapes). Later hits don't reset it; a **stun pauses the fuse** (a remote parry-stun on a bolt/fireball stretches the burst window). The staff orb brightens as the fuse fills. This is the anti-melee pacing valve — every approach buys a guaranteed burst window.

**Boss-loot flow:** the weapon relic drops from `RunDirector`, not the boss, and only once EVERY boss of the wave is dead. When the last boss falls and a relic is owed, the arena clears its remaining minions and **spawning PAUSES** (run timer keeps advancing) so the player can walk to the relic in peace. The HUD shows one health bar PER living boss. The relic is an infinite-lifetime pickup; collecting it opens a paused `ClaimScreen` modal. On acknowledge a normal relic resumes spawning — **but the staff ends the run in victory**: `RunDirector._on_unlock_claimed` leaves spawning paused, and the ClaimScreen's Continue calls `finish_victory` → `GameManager.end_run({victory: true})` → the "VICTORY" `DeathScreen`. (Veteran saves already owning the staff get no drop and play on endless.) See `RunDirector._track_boss`, `_on_boss_died`, `_on_boss_wave_cleared`, `_spawn_relic`, `_on_unlock_claimed`, `finish_victory`; `EventBus.unlock_claimed`; and `Pickup` kind `&"unlock"`.

## Death → pickups (`actors/pickups/pickup.gd`)

On death, an enemy emits `EventBus.enemy_killed` and explodes its gold and XP rewards (× reward_mult) into physical pickups — up to **8 pieces per resource**, value split evenly with remainder spread. Rewards are granted **on collection** (`EventBus.pickup_collected` → RunDirector), not on kill.

Pickup kinds: **gold** (standard drop), **xp** (standard drop), **magnet** (walk to it — on collect, force-magnets every other pickup in the arena), **health** (heals 25% max health, ignored while at full HP), **unlock** (boss weapon relic — infinite lifetime, walk to it, once collected opens a paused claim modal).

**Gold/XP collection registry:** gold and XP pickups only register in the static `Pickup.edible` array in `_ready`, and leave on collect/expire/free. Relics, magnets, health never register — boss loot and utility drops are theft-proof by construction. The **Scavenger** searches this array for ground loot. `consume() -> int` returns a pickup's value and frees it **without** emitting `pickup_collected` — loot eaten by the Scavenger was never collected by the player.

**Minimap:** enemy blips read `enemy.state` for color (orange = winding up, blue = stunned). An enemy whose `data.tags` has `&"rare"` draws a **gold blip regardless of state** (Gilded One).

Pickup lifecycle (manual motion, no physics body — hundreds stay cheap):
1. **Burst:** launched up/outward (3–6.5 lateral, 7–11 vertical), gravity 18, damped floor bounce, clamped to the arena.
2. **Grace period:** no magnet/collection for `MAGNET_DELAY 0.4s`, so melee-kill fountains visibly play out instead of vacuuming on frame one.
3. **Magnet:** within `MAGNET_RADIUS 4.5` of the player, accelerates (50/s²) toward them at up to 13 u/s; collects at `COLLECT_RADIUS 1.1`. An overshoot guard prevents a laggy frame from skimming a magneted pickup past the player — if this frame's step would cross into the collect zone, it collects now instead of orbiting.
4. **Expiry:** despawns after 30s (boss loot: 60s, magnets: 45s) — uncollected loot is lost. That's the risk/reward point; don't extend it casually.

## Authoring a new enemy

1. **Data:** duplicate `data/enemies/chaser.tres`, retune fields. Set `min_elapsed` to gate it and `spawn_weight` for its share. For **spawner mobs**, set `death_spawns` (the child `EnemyData`) and `death_spawn_count` (no script needed — generic `EnemyBase._on_died` handles the ring burst and hatch delay).
2. **Scene:** duplicate `ChaserEnemy.tscn` (mesh/material/collision are the usual edits). Must keep the `Health`, `Hurtbox`, `AttackHitbox`, `Mesh`, `FistPivot` nodes `enemy_base.gd` expects.
3. **Behavior (only if needed):** subclass `EnemyBase`, override state methods (`_chase`, `_begin_attack`, `stun`, …) — never the `_physics_process` plumbing. Spitter is the template.
4. **Register:** add the `.tres` to the `enemies` array in `data/waves/default.tres`. Spawner, scaling, minimap, drops, telegraphs all come free.
5. **Rare or event-triggered enemies:** instead of pool weight, use `WaveEvent` with `chance` (for rare rolls), schedule a specific `time` + `repeat_every` (for chance events or loot triggers), and guard with `_rare_alive()` (one at a time) or `_maybe_spawn_X()` (loot-threshold triggering). The Gilded One (chance event) and Scavenger (loot-triggered) are templates.
6. Boss-type enemies: extend `BossBase` (death spectacle + loot wave come free), `spawn_weight 0.0` + a scheduled `WaveTable` event instead of the pool, tag `boss` (the HUD bar/banner then come free). The Juggernaut (charge/melee kit) and Caster (kiting/spell kit) are the two templates; both reuse `GroundTelegraph` for telegraphed ground AoEs.

## Future direction

- Elite modifiers (fast/tanky/thorny variants) as spawn-time `EnemyData` tweaks rather than new files.
- Per-band spawn weights (weights that change over time, not just gates) if late runs feel too Chaser-heavy.
- Elite spawner mobs (an elite splits into multiple copies on death) — enabled by `death_spawns` plumbing now available.
- NavigationAgent3D only when arenas gain obstacles; data-oriented steering manager only past ~200 alive (PLAN.md §6).
