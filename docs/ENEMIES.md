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

## EnemyData (`core/enemy_data.gd`) and the four types

Fields: `display_name`, `scene`, `max_health`, `move_speed`, `damage`, `attack_range`, `windup_time`, `recover_time`, `knockback` (impulse shoving the player on a landed hit), `gold_reward`, `xp_reward`, `spawn_weight`, `min_elapsed` (time gate, seconds), `tags`, `unlock_drops` (ordered `Array[StringName]` of ability flags; on a boss wave clearing, the first flag the player doesn't own drops as a weapon-relic pickup).

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
| Spawn weight | 1.0 | 0.8 | 0.35 | 0.5 |

Numbers were re-tuned in the chaos/lethality pass (2026-07-03): every hit is meant to matter against a fresh 100-HP player (~5 chaser hits early), telegraphs are ~25% snappier across the board, and the Spitter's recovery halved so it genuinely suppresses.

Roles: Chaser is the baseline; Sprinter forces backpedal discipline (fast, fragile, quick windup); Brute is the parry tutor (long telegraph, big hit, worst recovery); Spitter breaks camping. Only the Spitter has a script (`spitter_enemy.gd`, ~45 lines): overrides `_chase()` — kites away inside `RETREAT_RANGE 4.0`, closes to 9.0 — and `_begin_attack()` — spawns a `Projectile` (speed 12, lifetime 4s) aimed at the player, through the same hurtbox pipeline so shields work. Everything else inherits.

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

## Wave events, swarms & the Juggernaut boss

`WaveTable.events` is an `Array[WaveEvent]` (`time`, `enemy`, `count`, `announcement`, `repeat_every`), fired by `RunDirector` off a per-event next-fire clock, **bypassing the alive cap**. `repeat_every = 0` means one-shot; anything greater re-arms the event that many seconds after each firing — that's the SWARM mechanism. An event whose enemy is tagged `boss` also emits `EventBus.boss_spawned` — the HUD binds a name + health bar to it; announcements show a fading banner.

Default table: one Juggernaut at **150s** (drops `weapon_warhammer`), two Juggernauts at **300s** (drops `weapon_staff`, one-shots), **12 Sprinters at 45s repeating every 50s** ("A SWARM APPROACHES"), **16 Chasers at 120s repeating every 80s** ("THEY POUR IN"), and **24 Spitters at 120s repeating every 360s** ("THEY'RE EVERYWHERE").

**Juggernaut** (`boss_enemy.gd` extends EnemyBase; `juggernaut.tres`): 500 HP base (× wave HP mult at spawn), melee slam with 3.4 reach / 0.6 windup / 0.6 recover / knockback 12. Signature: every **5.5s** it telegraphs (yellow tween + fist cock, 0.7s) then **charges** at 24 u/s for 1.5s — effectively wall to wall:

- During the rush its collision mask drops to **world-only**: it phases through the player (the live hitbox at 1.5× damage + knockback 18 does the work) and through minions, flinging any minion within 2.8m sideways out of its path via `EnemyBase.apply_shove` (damage-free decaying impulse — also used by the fireball explosion).
- Counterplay is skill-expressive twice over: a **perfect block cancels the charge** outright (overridden `stun()` → `_end_charge()`) and stuns it; **dash** blinks through it untouched.
- Ends on wall impact, timeout, or parry; mask restores in `_end_charge()` in all cases.

**Boss-loot flow:** the weapon relic drops from `RunDirector`, not the boss, and only once EVERY boss of the wave is dead (the second boss wave spawns two juggernauts — `count = 2`). When the last boss falls and a relic is owed, the arena clears its remaining minions and **spawning PAUSES** (run timer keeps advancing) so the player can walk to the relic in peace. The HUD shows one health bar PER living boss. The relic is an infinite-lifetime pickup; collecting it opens a paused claim-screen modal (`ClaimScreen`) and resumes spawning on acknowledge. See `RunDirector._track_boss`, `_on_boss_died`, `_on_boss_wave_cleared`, `_spawn_relic`, `_on_unlock_claimed`; `EventBus.unlock_claimed`; and `Pickup` kind `&"unlock"`.

## Death → pickups (`actors/pickups/pickup.gd`)

On death, an enemy emits `EventBus.enemy_killed` and explodes its gold and XP rewards (× reward_mult) into physical pickups — up to **8 pieces per resource**, value split evenly with remainder spread. Rewards are granted **on collection** (`EventBus.pickup_collected` → RunDirector), not on kill.

Pickup kinds: **gold** (standard drop), **xp** (standard drop), **magnet** (walk to it — on collect, force-magnets every other pickup in the arena), **health** (heals 25% max health, ignored while at full HP), **unlock** (boss weapon relic — infinite lifetime, walk to it, once collected opens a paused claim modal).

Pickup lifecycle (manual motion, no physics body — hundreds stay cheap):
1. **Burst:** launched up/outward (3–6.5 lateral, 7–11 vertical), gravity 18, damped floor bounce, clamped to the arena.
2. **Grace period:** no magnet/collection for `MAGNET_DELAY 0.4s`, so melee-kill fountains visibly play out instead of vacuuming on frame one.
3. **Magnet:** within `MAGNET_RADIUS 4.5` of the player, accelerates (50/s²) toward them at up to 13 u/s; collects at `COLLECT_RADIUS 1.1`. An overshoot guard prevents a laggy frame from skimming a magneted pickup past the player — if this frame's step would cross into the collect zone, it collects now instead of orbiting.
4. **Expiry:** despawns after 30s (boss loot: 60s, magnets: 45s) — uncollected loot is lost. That's the risk/reward point; don't extend it casually.

## Authoring a new enemy

1. **Data:** duplicate `data/enemies/chaser.tres`, retune fields. Set `min_elapsed` to gate it and `spawn_weight` for its share.
2. **Scene:** duplicate `ChaserEnemy.tscn` (mesh/material/collision are the usual edits). Must keep the `Health`, `Hurtbox`, `AttackHitbox`, `Mesh`, `FistPivot` nodes `enemy_base.gd` expects.
3. **Behavior (only if needed):** subclass `EnemyBase`, override state methods (`_chase`, `_begin_attack`, `stun`, …) — never the `_physics_process` plumbing. Spitter is the template.
4. **Register:** add the `.tres` to the `enemies` array in `data/waves/default.tres`. Spawner, scaling, minimap, drops, telegraphs all come free.
5. Boss-type enemies: `spawn_weight 0.0` + a scheduled `WaveTable` event instead of the pool, tag `boss` (the HUD bar/banner then come free). The Juggernaut is the template.

## Future direction

- Elite modifiers (fast/tanky/thorny variants) as spawn-time `EnemyData` tweaks rather than new files.
- Per-band spawn weights (weights that change over time, not just gates) if late runs feel too Chaser-heavy.
- NavigationAgent3D only when arenas gain obstacles; data-oriented steering manager only past ~200 alive (PLAN.md §6).
