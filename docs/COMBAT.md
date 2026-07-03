# Combat — the damage pipeline and melee feel

One rule: **every point of damage in the game flows through the same pipeline.** Player sword, enemy punch, spitter projectile, thorns reflection — all of them. That's why block, parry, damage numbers, and thorns each landed as a change in exactly one place.

## The pipeline

```
AttackInfo(source, damage)
  → HitboxComponent.activate(info, duration)     # dealer side (Area3D)
  → HurtboxComponent.receive_hit(info)           # receiver side (Area3D)
	  → owner.mitigate_hit(info) if it exists    # may return null = fully blocked
  → HealthComponent.take_damage(final_info)      # signals: health_changed, damaged, died
```

- **`AttackInfo`** (`core/attack_info.gd`) — `RefCounted` with `source: Node3D` + `damage: float`. Crits, damage types, knockback are future fields here, nowhere else.
- **`HitboxComponent`** (`components/hitbox_component.gd`) — armed with an `AttackInfo` for a duration; each hurtbox is hit **at most once per activation**. Monitoring stays on permanently: targets already overlapping at activation are swept via `get_overlapping_areas()`, which toggling `monitoring` would miss. Don't "optimize" that.
- **`HurtboxComponent`** (`components/hurtbox_component.gd`) — routes into an exported `HealthComponent`, but first calls the scene root's `mitigate_hit(info) -> AttackInfo` if defined. Returning `null` cancels the hit entirely. This duck-typed hook is where the player's shield lives; armor/resistances go here too.
- **`Projectile`** (`actors/enemies/projectile.gd`) — straight-line mover that calls `receive_hit` directly, so shields work against spit unchanged.

## Block and perfect block (`player.gd`)

`mitigate_hit` blocks a hit when **all** hold: block held (RMB), valid `info.source`, and the attacker within **60°** (`BLOCK_HALF_ANGLE_DEG`) of player forward, flat-plane. Blocked damage is fully negated. Blocking costs mobility: **×0.5 move speed** (`BLOCK_SPEED_MULT`).

**Perfect block:** the player timestamps every block *raise* (`_block_started_ms`). If a hit arrives within **`PERFECT_BLOCK_WINDOW = 0.2s`** of the raise, the attack is negated *and* the attacker is stunned for **`PERFECT_BLOCK_STUN = 1.5s`** via a duck-typed `stun(duration)` call (see docs/ENEMIES.md — bosses can override). Holding block permanently never parries; you must re-raise with timing.

Feedback split: `EventBus.attack_blocked` vs `EventBus.perfect_block`; the shield flashes white vs gold, kicks inward vs punches outward (`sword_and_shield.gd::notify_block_success`), and the HUD vignette tints white vs gold. Thorns (unique boon) hooks blocked melee hits here — 15 damage back through the attacker's hurtbox.

The stun can land **synchronously inside** `hitbox.activate()` (enemy punches into a raised shield on frame one) — enemy attack code checks its state after activating for exactly this reason.

## Sword swing (`weapons/sword_and_shield.gd`)

Cooldown/timing from `weapon.gd`: `duration = swing_time / max(0.1, attack_speed)`. Sword data: `swing_time 0.7s`, `damage 10` + the player's flat `damage` stat.

The viewmodel is a **rigid arm-swing around a virtual shoulder** (`SHOULDER`, `ARM_LENGTH 0.4`): handle and blade are locked to one arm direction, so the tip sweeps ~3.5× further than the base and the cut reads as an arc, not a wrist-flick. Alternating swing sides. Three chained phases of `duration`:

| Phase | Time | What happens |
|---|---|---|
| 1. Windup | 25% | Arm cocks back **past** the arc start (`WINDUP_ANGLE 0.55 rad`), opposite the swing |
| 2. Attack sweep | 30% | One cut from windup through to arc end; **hitbox activates here, for 35%** of duration — hits land with the visible cut, never the windup |
| 3. Backswing | 45% | Settle to the low bottom-right ready stance |

History (see git log): handle-pivot → bezier arc → shoulder-orbit, and 0.45s → 0.7s base swing. The shoulder-orbit version is the keeper; the others fought themselves.

## Stats resolution (`core/stat_block.gd`)

`(base + Σflat) × (1 + Σpercent_add) × ∏(1 + percent_mult)` — cached per stat, invalidated on any change to that stat. Canonical ids in `core/stats.gd`: `max_health`, `damage`, `attack_speed`, `move_speed`.

Modifier sources, in spawn order: player base values (100 HP, 6.0 speed, 0 dmg, 1.0 AS in `player.gd::_ready`) → `MetaProgression.get_stat_modifiers()` (purchased upgrades × level) → boons as they're picked (rarity-scaled duplicates; see docs/BOONS.md). Enemies do **not** use StatBlock — their numbers come from `EnemyData` × wave multipliers.

## Feedback layer

- **Damage numbers** (`core/damage_number.gd`) — static `DamageNumber.spawn(parent, pos, amount)`; code-built `Label3D`, billboard, no-depth-test, floats up 0.9 and fades in ~0.55s. Fire-and-forget; enemies call it in `_on_damaged`.
- **Trauma camera shake** (`player.gd`) — `add_shake(amount)` accumulates trauma (cap 1.0), decays at 1.8/s, applied as **quadratic** jitter on the camera node so the viewmodel shakes with the view. Taking a hit adds 0.4.
- **Hit pop** — enemies scale to 1.18 and tween back in 0.12s on damage.
- **HUD vignette** (`ui/hud.gd`) — red flash on damage, white on block, gold on perfect block.
- **Missing on purpose:** hit-pause and SFX. Audio is Phase 4; if melee still feels dry after SFX, hit-pause is the next lever (a one-line `Engine.time_scale` dip or a hitstop timer in `_do_attack`).

## Tuning knobs (one place each)

| Knob | Where |
|---|---|
| Block cone, block speed penalty, parry window/stun | consts atop `player.gd` |
| Swing time / damage | `data/weapons/sword.tres` |
| Swing phase proportions, arc endpoints, shoulder | consts + `_do_attack` in `sword_and_shield.gd` |
| Shake decay/intensity | `player.gd::_process`, `add_shake` calls |
| Enemy hit-window length | `ATTACK_ACTIVE_TIME` in `enemy_base.gd` |
