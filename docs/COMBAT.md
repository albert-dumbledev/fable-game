# Combat — the damage pipeline and melee feel

One rule: **every point of damage in the game flows through the same pipeline.** Player sword, enemy punch, spitter projectile, thorns reflection — all of them. That's why block, parry, damage numbers, and thorns each landed as a change in exactly one place.

## The pipeline

```
AttackInfo(source, damage)
  → HitboxComponent.activate(info, duration)     # dealer side (Area3D)
  → HurtboxComponent.receive_hit(info)           # receiver side (Area3D)
	  → owner.mitigate_hit(info) if it exists    # may return null = fully blocked, or a scaled AttackInfo
  → HealthComponent.take_damage(final_info)      # signals: health_changed, damaged, died
```

- **`AttackInfo`** (`core/attack_info.gd`) — `RefCounted` with `source: Node3D`, `damage: float`, `knockback: float` (impulse strength; direction is always away from `source`). Crits and damage types remain future fields here, nowhere else.
- **`HitboxComponent`** (`components/hitbox_component.gd`) — armed with an `AttackInfo` for a duration; each hurtbox is hit **at most once per activation**. Monitoring stays on permanently: targets already overlapping at activation are swept via `get_overlapping_areas()`, which toggling `monitoring` would miss. Don't "optimize" that.
- **`HurtboxComponent`** (`components/hurtbox_component.gd`) — routes into an exported `HealthComponent`, but first calls the scene root's `mitigate_hit(info) -> AttackInfo` if defined. Returning `null` cancels the hit entirely. This duck-typed hook is where the player's shield lives; armor/resistances go here too. **`EnemyBase.mitigate_hit`** applies Expose Weakness (×1.35 damage multiplier) while the vulnerability window is open, returning a fresh scaled `AttackInfo` without mutating the shared swing info.
- **`Projectile`** (`actors/enemies/projectile.gd`) — straight-line mover that calls `receive_hit` directly, so shields work against spit unchanged.

## Weapons and the loadout (`core/weapon_data.gd`, `weapons/weapon.gd`)

The player picks **one weapon per run** on the death screen (hidden until a second weapon is unlocked). Weapons live in `data/weapons/registry.tres` (`WeaponRegistry`); each `WeaponData` carries `id`, `damage`, `swing_time`, `can_block`, `scene_path` (a path string, not a `PackedScene`, to avoid a .tres↔.tscn load cycle), and `unlock_ability` — weapon unlocks are ability-granting `UpgradeData`, exactly like spell unlocks. `MetaProgression.selected_weapon` persists in the save; `get_selected_weapon()` falls back to the first unlocked weapon if the id is unknown or no longer unlocked.

The player instantiates the chosen scene into `WeaponMount` at runtime (`_mount_weapon`), which means scene `owner` is never set — weapons carry an explicit **`wielder`** (set via `setup(stats, wielder)`) and every `AttackInfo` sources from it. `Weapon.set_blocking` refuses to raise when `can_block` is false, so two-handed weapons need no player-side special-casing.

## Block and perfect block (`player.gd`)

`mitigate_hit` blocks a hit when **all** hold: block held (RMB), valid `info.source`, and the attacker within **60°** (`BLOCK_HALF_ANGLE_DEG`) of player forward, flat-plane. Blocked damage is fully negated. Blocking costs mobility: **×0.5 move speed** (`BLOCK_SPEED_MULT`). Only weapons with `can_block = true` can raise a block at all — the warhammer's whole trade is giving this up (its RMB is Seismic Slam instead, see below).

**Guard meter (anti-turtle):** blocking is a depleting resource — `GUARD_MAX 3.0s` drains 1/s while the shield is up, and every *non-perfect* blocked hit costs an extra `GUARD_HIT_COST 0.5s`; **perfect blocks cost nothing**. Hitting zero breaks the block (forced down, 0.3 shake) and blocking stays locked out until the meter refills completely (`GUARD_REGEN 1/s` while lowered — ~3s exposed after a full break). Quick parry taps are nearly free, so the perfect-block game is untouched; corner-hiding is dead. The HUD shows an RMB "Block" slot whose overlay fills with guard spent and drains as it recovers.

**Perfect block:** the player timestamps every block *raise* (`_block_started_ms`). If a hit arrives within **`PERFECT_BLOCK_WINDOW = 0.2s`** of the raise (0.35s with the Duelist's Focus boon, `long_parry`), the attack is negated *and* the attacker is stunned for **`PERFECT_BLOCK_STUN = 1.5s`** scaled by the **`parry_stun`** stat via a duck-typed `stun(duration)` call (see docs/ENEMIES.md — bosses can override). Holding block permanently never parries; you must re-raise with timing.

Feedback split: `EventBus.attack_blocked` vs `EventBus.perfect_block`; the shield flashes white vs gold, kicks inward vs punches outward (`sword_and_shield.gd::notify_block_success`), and the HUD vignette tints white vs gold. Thorns (unique boon) hooks blocked melee hits here — 15 damage back through the attacker's hurtbox.

The stun can land **synchronously inside** `hitbox.activate()` (enemy punches into a raised shield on frame one) — enemy attack code checks its state after activating for exactly this reason.

## Sword Riposte (core mechanic)

**Priming:** a perfect block primes a **2s window** (`RIPOSTE_WINDOW`) for a buffed swing. The player sees the blade light gold, fading over the window as a visual countdown. The prime is single-use: exactly one sword swing consumes it — parrying again only refreshes the window, never banks multiples.

**Riposte swing:** when the sword swings within the window, its damage gets a **+75%** bonus (`RIPOSTE_BASE_BONUS`) scaled by the **`riposte_damage`** stat, applied to every enemy the swing hits. The riposte damage multiplier is `1.0 + (RIPOSTE_BASE_BONUS × riposte_damage_stat)`. On hit, the blade flashes bright gold as a punish signal and fades over the swing duration. After the swing, the prime is consumed and a new parry is needed to rearm.

Riposte swings are the payoff for shield mastery: land the parry, land the counter, heal/apply vulnerabilities/trigger boons — the whole sword fantasy lives here.

## Knockback and shoves

Two parallel impulse systems, both "set once, decay on top of normal movement":

- **Player knockback** (`player.gd`) — a landed hit shoves the player away from `info.source` at `info.knockback` strength (per-enemy in `EnemyData`: sprinter 3 → juggernaut 12, boss charge 18) with a small vertical pop; decays at 25/s. **Blocked hits impart nothing** — the shield is also a positioning tool. Dashing clears any active knockback.
- **Enemy shove** (`EnemyBase.apply_shove(impulse)`) — damage-free physical fling, decaying at 18/s, riding on top of AI movement in any state. Used by the boss charge (plowing minions aside) and the fireball explosion.

## Movement: dash and jump (`player.gd`)

**Dash (unique boon, Shift):** fixed **6m blink over 0.12s** — traveled, not teleported, so walls still stop it. Fully intangible during: enemy collision dropped from the mask, hurtbox `monitorable = false` (melee hitboxes *and* projectiles pass through without being consumed), plus a `mitigate_hit` guard for the re-enable boundary frame. 2s cooldown carries the balance. FOV punch 75→84→75 sells it. Dash stays available mid-fireball-charge — the deliberate escape valve.

**Jump (Space):** plain on-floor impulse (`JUMP_VELOCITY 4.8`). Sprint was removed when dash took Shift (2026-07-03): dash is the mobility tool, base move speed and Fleet Footed carry the rest.

## Warhammer (loadout weapon; `weapons/warhammer.gd`)

Two-handed slam, `swing_time 1.4s`, `damage 20` + damage stat. **No shield, no block** (`can_block = false`) — dash and Frost Nova are the defense. The swing is three tween phases like the sword (40% telegraph haul-up / 15% crash / 45% recover), but damage is **not a hitbox sweep**: at the crash moment, a ground AoE lands `IMPACT_DISTANCE 2.2m` in front of the player — full damage within `INNER_RADIUS 2.0m` of the impact point, `×0.4` splash out to `OUTER_RADIUS 3.6m`, and a radial shove (strength scaled by the **`hammer_shove`** stat) **only to enemies in the inner radius** (splash takes damage but no knockback). All damage flows through hurtboxes as usual. Flattened blast ring + 0.5 camera shake sell the hit.

The slam covers a **210° frontal arc** (`SLAM_ARC_HALF_DEG 105°`), leaving a **~150° blind wedge directly behind the player** to punish careless facing. Enemies closer to you than 0.1m always count.

Boon hooks: both radii scale with the **`hammer_aoe`** stat (Wide Tremor); **Aftershock** (`aftershock` flag) re-slams the same point 0.45s later at ×0.5 damage / ×0.8 radii / ×0.6 shove. **Bone Breaker** (`shove_impact` flag) — when a shoved enemy hits a wall while the impulse is strong, it takes ×0.3 hammer damage as a wall-impact hit (damage only, no stun).

**Seismic Slam (RMB):** the hammer's secondary (`Weapon.try_secondary` — RMB routes here for any `can_block = false` weapon). A **1.1s** overhead windup — deliberately much longer than the primary's telegraph — then a slam that launches a `GroundShockwave` (`weapons/ground_shockwave.gd`) forward in a straight line: speed 14, range 16m, hit radius 2.2m × `hammer_aoe`, dealing `(hammer damage) × 1.2` to each enemy **at most once** and carrying it along the wave with a shove (scaled by **`hammer_shove`** stat, base 12). 6s cooldown (HUD slot "Shockwave"); the committed animation locks the primary out for its full duration. **Implosion** (`slam_pull` flag) — the wave rakes enemies back to the cast origin and staggers them there (gather, not scatter), applying a ~0.5s stun. **Riptide** (`wave_drag` flag) — enemies are dragged harder and left staggered as a clump when the wave ends.

## Frost Nova (spell unlock; `player.gd`)

E casts an **instant** AoE — no charge, no weapon stow; the defensive counterpart to fireball's committed offense. Every enemy within **6m** takes `8 + 0.4× damage stat` (both scaled by **`spell_damage`** stat) and is slowed to **×0.35 move speed for 3.5s** (`EnemyBase.apply_slow` — movement only, never attack timings; see docs/ENEMIES.md). 8s base cooldown × `spell_cooldown`. Flattened icy blast sphere + enemies tint blue while chilled.

Boon hooks: **Echo Nova** (`nova_echo`) pulses again 1s later at ×0.5 damage with a weaker slow (×0.6 for 2s — it *overwrites* the first slow, deliberately); **Glacial Wave** (`nova_push`) adds a 12-impulse radial shove to every pulse.

## Fireball (spell unlock; `player.gd` + `weapons/fireball.gd`)

RMB (or Q via staff/legacy code) starts a **committed charge** (`0.8s × cast_time`): the weapon viewmodel stows (`Weapon.set_stowed` — both hands busy, no attacking or blocking), an orb grows in front of the camera, then the fireball auto-releases toward the crosshair. The projectile (speed 18) **explodes on any contact** — enemy hurtbox, world, or 4s lifetime: every enemy within **4m × `fireball_aoe`** takes `30 + 1.5× damage stat` (both scaled by **`spell_damage`** stat) through its hurtbox (numbers/drops as usual) and is shoved 10 away from the blast; expanding emissive sphere scaled to the true damage radius; camera shake within 9m. The 1.5× stat scaling (vs sword's 1.0×) is the caster-build axis.

**Charges:** casts spend from a bank of `fireball_charges` (base 1; Twin Flame +1) that refills one charge per `3s × spell_cooldown` — the HUD slot shows a count when the bank exceeds 1. **Scorched Earth** (`burning_ground`): the explosion leaves a `FlamePatch` at the blast point (`weapons/flame_patch.gd` — ground circle at ×0.55 of the blast radius, ticking ×0.2 of the fireball's damage every 0.4s for 3s), so the zone stays denied after the hit.

**Staff access:** the staff mounts with `grants_abilities` set to `&"firebolt"`, so RMB cast works identically. The staff does not stow during the charge — it's the cast focus and stays drawn.

## Spell and combat stats (`core/stats.gd`)

**Multipliers (base 1.0):** `spell_cooldown`, `cast_time`, `fireball_aoe`, `hammer_aoe`, `riposte_damage`, `parry_stun`, `hammer_shove`, `spell_damage` are all base-1.0 stats moved by `PERCENT_ADD` boons (negative = reduction). Cooldowns clamp at ×0.25 and cast time at ×0.2 so stacked reduction can't zero out. Radii scale with their `*_aoe` or `*_shove` stats as noted in each weapon section. **`spell_damage`** scales all spell/bolt damage (Arcane Bolt, Fireball, Frost Nova, and any future spells).

## Sword swing (`weapons/sword_and_shield.gd`)

Cooldown/timing from `weapon.gd`: `duration = swing_time / max(0.1, attack_speed)`. Sword data: `swing_time 0.7s`, `damage 10` + the player's flat `damage` stat.

The viewmodel is a **rigid arm-swing around a virtual shoulder** (`SHOULDER`, `ARM_LENGTH 0.4`): handle and blade are locked to one arm direction, so the tip sweeps ~3.5× further than the base and the cut reads as an arc, not a wrist-flick. Alternating swing sides. Three chained phases of `duration`:

| Phase | Time | What happens |
|---|---|---|
| 1. Windup | 25% | Arm cocks back **past** the arc start (`WINDUP_ANGLE 0.55 rad`), opposite the swing |
| 2. Attack sweep | 30% | One cut from windup through to arc end; **hitbox activates here, for 35%** of duration — hits land with the visible cut, never the windup. If a riposte is primed, the sweep is replaced with `_sweep_hit` (Blade Cyclone: radial strike in a ~2.8m circle) |
| 3. Backswing | 45% | Settle to the low bottom-right ready stance |

**Sword-only boons (Duelist family):**
- **Ruthless Riposte** (`riposte_damage` stat boost): +flat multiplicative damage to the riposte swing
- **Punishing Stun** (`parry_stun` stat boost): perfect blocks stun the attacker longer
- **Retribution** (`parry_nova`): perfect block detonates a ~3m radial pulse dealing ~50% weapon damage + a shove to everything caught
- **Expose Weakness** (`exposing_parry`): parried enemies take +35% damage from all sources while stunned
- **Second Wind** (`parry_heal`): a perfect block primes lifesteal on the next swing — 25% of the damage dealt goes back to the player's health, plus a guard-meter refund
- **Blade Cyclone** (`riposte_sweep`): a riposte swing strikes a full circle (~2.8m radius) instead of an arc
- **Reflex Guard** (`omni_block`): for ~0.15s after raising the shield, it guards **all directions** (omnidirectional block), then goes on cooldown so it can't be spammed by re-tapping

History (see git log): handle-pivot → bezier arc → shoulder-orbit, and 0.45s → 0.7s base swing. The shoulder-orbit version is the keeper; the others fought themselves.

## Staff (Arcanist loadout; `weapons/staff.gd`)

**No shield, no block** (`can_block = false`) — the pure DPS choice. LMB fires **Arcane Bolt**, a fast single-target projectile, and RMB casts the player's Fireball (weapon doesn't stow during charge — it's the cast focus). Both scale with the **`spell_damage`** stat.

**Arcane Bolt (LMB):** a spammable projectile (`weapons/arcane_bolt.gd`) that deals `8 + (0.8 × damage stat)` scaled by `spell_damage`, travels at speed 24, and has a 3s lifetime. Hits the first enemy hurtbox or world geometry it touches. All damage flows through hurtboxes so vulnerabilities and drops apply. A brief purple flash at impact.

**Fireball (RMB):** identical to the Duelist's fireball (see section above), but the staff mounts with `grants_abilities &"firebolt"` so casting works the same way.

**Spells (E):** Frost Nova and future arcane purchases (E casts) only work when the staff is the active weapon — checking `weapon is Staff` at runtime. This gates the arcane kit to the arcanist loadout.

**Arcana-only boons:** future staff/spell enhancers arrive here, similarly gated by loadout.

## Stats resolution (`core/stat_block.gd`)

`(base + Σflat) × (1 + Σpercent_add) × ∏(1 + percent_mult)` — cached per stat, invalidated on any change to that stat. Canonical ids in `core/stats.gd`: `max_health`, `damage`, `attack_speed`, `move_speed`, plus the base-1.0 multipliers `spell_cooldown`, `cast_time`, `fireball_aoe`, `hammer_aoe`, `riposte_damage`, `parry_stun`, `hammer_shove`, `spell_damage`, and the flat `fireball_charges`.

Modifier sources, in spawn order: player base values (**100 HP** — a fresh run dies in a handful of early hits; 6.0 speed, 0 dmg, 1.0 AS in `player.gd::_ready`) → `MetaProgression.get_stat_modifiers()` (purchased upgrades × level) → boons as they're picked (rarity-scaled duplicates; see docs/BOONS.md). Enemies do **not** use StatBlock — their numbers come from `EnemyData` × wave multipliers.

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
| Block cone, block speed penalty, parry window/stun, riposte window/bonus | consts atop `player.gd` |
| Guard meter (hold time, hit cost, regen) | `GUARD_*` consts atop `player.gd` |
| Sword-only boon hooks (riposte, parry nova, lifesteal, etc.) | `player.gd::mitigate_hit`, `_parry_nova`, `sword_and_shield.gd` |
| Hammer base damage, impact point/radii/splash/shove | `data/weapons/warhammer.tres` (damage), consts atop `weapons/warhammer.gd` |
| Hammer slam arc, Aftershock/Bone Breaker timing | consts atop `weapons/warhammer.gd` |
| Seismic Slam windup/cooldown/damage, wave speed/range/shove | `WAVE_*` in `warhammer.gd`, consts in `ground_shockwave.gd` |
| Implosion/Riptide wave behavior | consts in `ground_shockwave.gd` |
| Staff base damage, Arcane Bolt speed/lifetime | `data/weapons/staff.tres`, `weapons/staff.gd`, `weapons/arcane_bolt.gd` |
| Swing time / damage (sword, staff) | `data/weapons/sword.tres`, `data/weapons/warhammer.tres`, `data/weapons/staff.tres` |
| Swing phase proportions, arc endpoints, shoulder | consts + `_do_attack` in `sword_and_shield.gd` |
| Riposte blade glow/flash | `sword_and_shield.gd::notify_riposte_primed`, `_flash_riposte` |
| Blade Cyclone sweep radius | `SWEEP_RADIUS` in `sword_and_shield.gd` |
| Frost nova radius/slow/cooldown/damage | `FROST_NOVA_*` consts atop `player.gd` |
| Echo Nova timing/damage/slow | `NOVA_ECHO_*` consts atop `player.gd` |
| Shake decay/intensity | `player.gd::_process`, `add_shake` calls |
| Enemy hit-window length | `ATTACK_ACTIVE_TIME` in `enemy_base.gd` |
| Per-enemy knockback strength | `knockback` in each `data/enemies/*.tres` |
| Dash distance/duration/cooldown | `DASH_*` consts atop `player.gd` |
| Fireball charge/cooldown/damage | `FIREBALL_*` consts atop `player.gd` |
| Explosion radius/shove | consts atop `weapons/fireball.gd` |
| Expose Weakness vulnerability window / damage multiplier | `EnemyBase.mark_vulnerable`, `VULNERABLE_MULT` in `enemy_base.gd` |
