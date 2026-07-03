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

- **`AttackInfo`** (`core/attack_info.gd`) — `RefCounted` with `source: Node3D`, `damage: float`, `knockback: float` (impulse strength; direction is always away from `source`). Crits and damage types remain future fields here, nowhere else.
- **`HitboxComponent`** (`components/hitbox_component.gd`) — armed with an `AttackInfo` for a duration; each hurtbox is hit **at most once per activation**. Monitoring stays on permanently: targets already overlapping at activation are swept via `get_overlapping_areas()`, which toggling `monitoring` would miss. Don't "optimize" that.
- **`HurtboxComponent`** (`components/hurtbox_component.gd`) — routes into an exported `HealthComponent`, but first calls the scene root's `mitigate_hit(info) -> AttackInfo` if defined. Returning `null` cancels the hit entirely. This duck-typed hook is where the player's shield lives; armor/resistances go here too.
- **`Projectile`** (`actors/enemies/projectile.gd`) — straight-line mover that calls `receive_hit` directly, so shields work against spit unchanged.

## Weapons and the loadout (`core/weapon_data.gd`, `weapons/weapon.gd`)

The player picks **one weapon per run** on the death screen (hidden until a second weapon is unlocked). Weapons live in `data/weapons/registry.tres` (`WeaponRegistry`); each `WeaponData` carries `id`, `damage`, `swing_time`, `can_block`, `scene_path` (a path string, not a `PackedScene`, to avoid a .tres↔.tscn load cycle), and `unlock_ability` — weapon unlocks are ability-granting `UpgradeData`, exactly like spell unlocks. `MetaProgression.selected_weapon` persists in the save; `get_selected_weapon()` falls back to the first unlocked weapon if the id is unknown or no longer unlocked.

The player instantiates the chosen scene into `WeaponMount` at runtime (`_mount_weapon`), which means scene `owner` is never set — weapons carry an explicit **`wielder`** (set via `setup(stats, wielder)`) and every `AttackInfo` sources from it. `Weapon.set_blocking` refuses to raise when `can_block` is false, so two-handed weapons need no player-side special-casing.

## Block and perfect block (`player.gd`)

`mitigate_hit` blocks a hit when **all** hold: block held (RMB), valid `info.source`, and the attacker within **60°** (`BLOCK_HALF_ANGLE_DEG`) of player forward, flat-plane. Blocked damage is fully negated. Blocking costs mobility: **×0.5 move speed** (`BLOCK_SPEED_MULT`). Only weapons with `can_block = true` can raise a block at all — the warhammer's whole trade is giving this up.

**Perfect block:** the player timestamps every block *raise* (`_block_started_ms`). If a hit arrives within **`PERFECT_BLOCK_WINDOW = 0.2s`** of the raise (0.35s with the Duelist's Focus boon, `long_parry`), the attack is negated *and* the attacker is stunned for **`PERFECT_BLOCK_STUN = 1.5s`** via a duck-typed `stun(duration)` call (see docs/ENEMIES.md — bosses can override). Holding block permanently never parries; you must re-raise with timing.

Feedback split: `EventBus.attack_blocked` vs `EventBus.perfect_block`; the shield flashes white vs gold, kicks inward vs punches outward (`sword_and_shield.gd::notify_block_success`), and the HUD vignette tints white vs gold. Thorns (unique boon) hooks blocked melee hits here — 15 damage back through the attacker's hurtbox.

The stun can land **synchronously inside** `hitbox.activate()` (enemy punches into a raised shield on frame one) — enemy attack code checks its state after activating for exactly this reason.

## Knockback and shoves

Two parallel impulse systems, both "set once, decay on top of normal movement":

- **Player knockback** (`player.gd`) — a landed hit shoves the player away from `info.source` at `info.knockback` strength (per-enemy in `EnemyData`: sprinter 3 → juggernaut 12, boss charge 18) with a small vertical pop; decays at 25/s. **Blocked hits impart nothing** — the shield is also a positioning tool. Dashing clears any active knockback.
- **Enemy shove** (`EnemyBase.apply_shove(impulse)`) — damage-free physical fling, decaying at 18/s, riding on top of AI movement in any state. Used by the boss charge (plowing minions aside) and the fireball explosion.

## Movement: dash and jump (`player.gd`)

**Dash (unique boon, Shift):** fixed **6m blink over 0.12s** — traveled, not teleported, so walls still stop it. Fully intangible during: enemy collision dropped from the mask, hurtbox `monitorable = false` (melee hitboxes *and* projectiles pass through without being consumed), plus a `mitigate_hit` guard for the re-enable boundary frame. 2s cooldown carries the balance. FOV punch 75→84→75 sells it. Dash stays available mid-fireball-charge — the deliberate escape valve.

**Jump (Space):** plain on-floor impulse (`JUMP_VELOCITY 4.8`). Sprint was removed when dash took Shift (2026-07-03): dash is the mobility tool, base move speed and Fleet Footed carry the rest.

## Warhammer (loadout weapon; `weapons/warhammer.gd`)

Two-handed slam, `swing_time 1.4s`, `damage 26` + damage stat. **No shield, no block** (`can_block = false`) — dash and Frost Nova are the defense. The swing is three tween phases like the sword (40% telegraph haul-up / 15% crash / 45% recover), but damage is **not a hitbox sweep**: at the crash moment, a ground AoE lands `IMPACT_DISTANCE 2.2m` in front of the player — full damage within `INNER_RADIUS 2.4m` of the impact point, `×0.4` splash out to `OUTER_RADIUS 4.2m`, and a radial 9-impulse shove for everything caught (same `apply_shove` the fireball uses). All damage flows through hurtboxes as usual. Flattened blast ring + 0.5 camera shake sell the hit.

Boon hooks: both radii scale with the **`hammer_aoe`** stat (Wide Tremor); **Aftershock** (`aftershock` flag) re-slams the same point 0.45s later at ×0.5 damage / ×0.8 radii / ×0.6 shove.

## Frost Nova (spell unlock; `player.gd`)

E casts an **instant** AoE — no charge, no weapon stow; the defensive counterpart to fireball's committed offense. Every enemy within **6m** takes `8 + 0.4× damage stat` and is slowed to **×0.35 move speed for 3.5s** (`EnemyBase.apply_slow` — movement only, never attack timings; see docs/ENEMIES.md). 8s base cooldown × `spell_cooldown`. Flattened icy blast sphere + enemies tint blue while chilled.

Boon hooks: **Echo Nova** (`nova_echo`) pulses again 1s later at ×0.5 damage with a weaker slow (×0.6 for 2s — it *overwrites* the first slow, deliberately); **Glacial Wave** (`nova_push`) adds a 12-impulse radial shove to every pulse.

## Fireball (spell unlock; `player.gd` + `weapons/fireball.gd`)

Q starts a **committed charge** (`0.8s × cast_time`): the weapon viewmodel stows (`Weapon.set_stowed` — both hands busy, no attacking or blocking), an orb grows in front of the camera, then the fireball auto-releases toward the crosshair. The projectile (speed 18) **explodes on any contact** — enemy hurtbox, world, or 4s lifetime: every enemy within **4m × `fireball_aoe`** takes `30 + 1.5× damage stat` through its hurtbox (numbers/drops as usual) and is shoved 10 away from the blast; expanding emissive sphere scaled to the true damage radius; camera shake within 9m. The 1.5× stat scaling (vs sword's 1.0×) is the caster-build axis.

**Charges:** casts spend from a bank of `fireball_charges` (base 1; Twin Flame +1) that refills one charge per `3s × spell_cooldown` — the HUD slot shows a count when the bank exceeds 1. **Scorched Earth** (`fire_trail`): while flying, the ball drops a `FlamePatch` every 0.18s (`weapons/flame_patch.gd` — 1.3m ground circle ticking ×0.12 of the fireball's damage every 0.4s for 2.5s).

## Spell stats (`core/stats.gd`)

`spell_cooldown` and `cast_time` are base-1.0 multipliers moved by negative `PERCENT_ADD` boons (Quick Mind −12%/pick, Fast Hands −15%/pick, rarity-scaled). Cooldowns clamp at ×0.25 and cast time at ×0.2 so stacked reduction can't zero out. `fireball_aoe` / `hammer_aoe` scale radii; `fireball_charges` is flat.

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

`(base + Σflat) × (1 + Σpercent_add) × ∏(1 + percent_mult)` — cached per stat, invalidated on any change to that stat. Canonical ids in `core/stats.gd`: `max_health`, `damage`, `attack_speed`, `move_speed`, plus the base-1.0 multipliers `spell_cooldown`, `cast_time`, `fireball_aoe`, `hammer_aoe` and the flat `fireball_charges`.

Modifier sources, in spawn order: player base values (**80 HP** — tuned so ~4 early hits kill a fresh run; 6.0 speed, 0 dmg, 1.0 AS in `player.gd::_ready`) → `MetaProgression.get_stat_modifiers()` (purchased upgrades × level) → boons as they're picked (rarity-scaled duplicates; see docs/BOONS.md). Enemies do **not** use StatBlock — their numbers come from `EnemyData` × wave multipliers.

## Feedback layer

- **Damage numbers** (`core/damage_number.gd`) — static `DamageNumber.spawn(parent, pos, amount)`; code-built `Label3D`, billboard, no-depth-test, floats up 0.9 and fades in ~0.55s. Fire-and-forget; enemies call it in `_on_damaged`.
- **Blast VFX** (`core/blast_vfx.gd`) — static `BlastVfx.spawn(parent, pos, radius, color, flatten, duration)`; the one expanding-sphere used by fireball explosions (sphere), hammer shockwaves (ground ring), and frost nova (squashed dome). Scale it to the true damage radius so the visual never lies.
- **Trauma camera shake** (`player.gd`) — `add_shake(amount)` accumulates trauma (cap 1.0), decays at 1.8/s, applied as **quadratic** jitter on the camera node so the viewmodel shakes with the view. Taking a hit adds 0.4.
- **Hit pop** — enemies scale to 1.18 and tween back in 0.12s on damage.
- **HUD vignette** (`ui/hud.gd`) — red flash on damage, white on block, gold on perfect block.
- **Missing on purpose:** hit-pause and SFX. Audio is Phase 4; if melee still feels dry after SFX, hit-pause is the next lever (a one-line `Engine.time_scale` dip or a hitstop timer in `_do_attack`).

## Tuning knobs (one place each)

| Knob | Where |
|---|---|
| Block cone, block speed penalty, parry window/stun | consts atop `player.gd` |
| Swing time / damage | `data/weapons/sword.tres`, `data/weapons/warhammer.tres` |
| Hammer impact point/radii/splash/shove | consts atop `weapons/warhammer.gd` |
| Frost nova radius/slow/cooldown | `FROST_NOVA_*` consts atop `player.gd` |
| Swing phase proportions, arc endpoints, shoulder | consts + `_do_attack` in `sword_and_shield.gd` |
| Shake decay/intensity | `player.gd::_process`, `add_shake` calls |
| Enemy hit-window length | `ATTACK_ACTIVE_TIME` in `enemy_base.gd` |
| Per-enemy knockback strength | `knockback` in each `data/enemies/*.tres` |
| Dash distance/duration/cooldown | `DASH_*` consts atop `player.gd` |
| Fireball charge/cooldown/damage | `FIREBALL_*` consts atop `player.gd` |
| Explosion radius/shove | consts atop `weapons/fireball.gd` |
