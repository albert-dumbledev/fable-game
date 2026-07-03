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

## EnemyData (`core/enemy_data.gd`) and the four types

Fields: `display_name`, `scene`, `max_health`, `move_speed`, `damage`, `attack_range`, `windup_time`, `recover_time`, `gold_reward`, `xp_reward`, `spawn_weight`, `min_elapsed` (time gate, seconds), `tags`.

| | Chaser | Sprinter | Brute | Spitter |
|---|---|---|---|---|
| Unlocks at | 0s | **45s** | **90s** | **120s** |
| HP | 25 | 12 | 80 | 20 |
| Speed | 4.5 | 7.0 | 2.8 | 3.5 |
| Damage | 10 | 6 | 22 | 8 |
| Range | 1.8 | 1.6 | 2.2 | **9.0 (ranged)** |
| Windup / recover | 0.4 / 0.8 | 0.3 / 0.6 | 0.7 / 1.2 | 0.6 / 1.4 |
| Gold / XP | 5 / 4 | 4 / 3 | 15 / 10 | 8 / 6 |
| Spawn weight | 1.0 | 0.8 | 0.35 | 0.5 |

Roles: Chaser is the baseline; Sprinter forces backpedal discipline (fast, fragile, quick windup); Brute is the parry tutor (long telegraph, big hit, worst recovery); Spitter breaks camping. Only the Spitter has a script (`spitter_enemy.gd`, ~45 lines): overrides `_chase()` — kites away inside `RETREAT_RANGE 4.0`, closes to 9.0 — and `_begin_attack()` — spawns a `Projectile` (speed 12, lifetime 4s) aimed at the player, through the same hurtbox pipeline so shields work. Everything else inherits.

## Spawner + WaveTable scaling

`RunDirector` ticks the `Spawner` (`systems/spawner.gd`) each physics frame; all pacing comes from `data/waves/default.tres` (`core/wave_table.gd`). Placement: random ring **14–22** around the player, clamped to arena half-extent 18.5.

| Knob | Formula | Default |
|---|---|---|
| Spawn interval | lerp `start → min` over `interval_ramp_time` | 2.5s → 0.4s over 240s |
| Enemy HP | `× (1 + hp_growth_per_min · min)` | +50%/min |
| Enemy damage | `× (1 + dmg_growth_per_min · min)` | +25%/min |
| Reward (gold & XP drops) | `× (1 + reward_growth_per_min · min)` | +30%/min |
| Alive cap | lerp `start → end` over ramp | 15 → 60 over 300s |
| Pool pick | weight-roll among entries with `elapsed ≥ min_elapsed` | — |

Multipliers are baked per-enemy at spawn via `enemy.setup(data, hp_mult, dmg_mult, reward_mult)` — `EnemyData` resources are never mutated. Damage growth is deliberately half of HP growth: runs end by attrition and being swarmed, not one-shots. `spawn_enemy()` is public so scheduled `WaveTable` events (bosses — **Phase 3, in progress**) reuse ring placement and scaling.

## Death → pickups (`actors/pickups/pickup.gd`)

On death, an enemy emits `EventBus.enemy_killed` and explodes its gold and XP rewards (× reward_mult) into physical pickups — up to **8 pieces per resource**, value split evenly with remainder spread. Rewards are granted **on collection** (`EventBus.pickup_collected` → RunDirector), not on kill.

Pickup lifecycle (manual motion, no physics body — hundreds stay cheap):
1. **Burst:** launched up/outward (3–6.5 lateral, 7–11 vertical), gravity 18, damped floor bounce, clamped to the arena.
2. **Grace period:** no magnet/collection for `MAGNET_DELAY 0.6s`, so melee-kill fountains visibly play out instead of vacuuming on frame one.
3. **Magnet:** within `MAGNET_RADIUS 4.5` of the player, accelerates (50/s²) toward them at up to 13 u/s; collects at 0.85.
4. **Expiry:** despawns after 30s — uncollected loot is lost. That's the risk/reward point; don't extend it casually.

## Authoring a new enemy

1. **Data:** duplicate `data/enemies/chaser.tres`, retune fields. Set `min_elapsed` to gate it and `spawn_weight` for its share.
2. **Scene:** duplicate `ChaserEnemy.tscn` (mesh/material/collision are the usual edits). Must keep the `Health`, `Hurtbox`, `AttackHitbox`, `Mesh`, `FistPivot` nodes `enemy_base.gd` expects.
3. **Behavior (only if needed):** subclass `EnemyBase`, override state methods (`_chase`, `_begin_attack`, `stun`, …) — never the `_physics_process` plumbing. Spitter is the template.
4. **Register:** add the `.tres` to the `enemies` array in `data/waves/default.tres`. Spawner, scaling, minimap, drops, telegraphs all come free.
5. Boss-type enemies: `spawn_weight 0.0` + a scheduled `WaveTable` event instead of the pool (Phase 3 pattern), tag `boss`.

## Future direction

- Elite modifiers (fast/tanky/thorny variants) as spawn-time `EnemyData` tweaks rather than new files.
- Per-band spawn weights (weights that change over time, not just gates) if late runs feel too Chaser-heavy.
- NavigationAgent3D only when arenas gain obstacles; data-oriented steering manager only past ~200 alive (PLAN.md §6).
