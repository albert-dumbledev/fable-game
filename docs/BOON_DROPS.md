# Aspect Drops (Phase 9)

A loot tier above the level-up screen: **Aspects** — build-warping boons dropped as physical
relics by **elite enemies** and **wave bosses**. Where a legendary boon makes a number bigger,
an Aspect rewires one of the loadout's verbs (riposte chains, slams refund, blinks cut). This
is also the system that finally justifies building the elite variants parked in
[SCALING_REWORK.md](SCALING_REWORK.md) M6 — an elite is a visible ×15-HP problem with a
promise attached.

Design decisions (settled 2026-07-10):

- **Sources:** elites (guaranteed relic, first 2 per run) + wave bosses (Juggernaut/Hierophant
  waves — only when no weapon relic is owed). **The Revenant finale drops nothing**: killing
  it ends the run, so a drop there would be dead loot. Expected yield: ~2–4 Aspects/run.
- **Delivery:** a glowing relic pickup (walk-over, never magnets, theft-proof) opening a
  paused **pick-1-of-2** modal — scarcer than the level-up screen's 3, so the tier feels
  weighty. Reuses the weapon-relic + ClaimScreen pattern.
- **Power tier:** above unique. No rarity roll, verbatim descriptions, once per run each.
- **Pool:** 3 bespoke Aspects per loadout + 3 universals (the "round out my build" valve).
- **Run-scoped** like all boons; no meta persistence.

Current state this builds on: relic flow lives in
[run_director.gd](../systems/run_director.gd) (`_on_boss_wave_cleared` → `_spawn_relic`,
resume on `unlock_claimed`) and [pickup.gd](../actors/pickups/pickup.gd) (`&"unlock"` kind:
no magnet, infinite lifetime, pulse). Boon application is `Player.apply_boon` +
`grant_ability`; every Aspect grants an ability flag, so `Player.has_ability` doubles as the
taken-this-run tracker for free.

---

## M1 — Elite variants (SCALING_REWORK M6, revived)

Per the parked sketch, pure data/spawner work — no new AI:

- Elite roll on **pool spawns only** (never wave events, never death spawns) past **4:00**:
  `Spawner._spawn` rolls ~3% and calls `spawn_enemy` with an elite flag →
  `EnemyBase.make_elite()`: **×15 HP, ×1.3 scale, emissive tint** (reuse the material-override
  pattern from the pickup pulse), **×5 gold/XP reward**.
- **Rate limiting** (the 3% raw rate is ~7/min at late spawn cadence — way too hot):
  at most **one elite alive**, and a **≥50s cooldown** between elite spawns. Mirrors the
  magnet's one-at-a-time rule.
- Elite death drop, this milestone: guaranteed **magnet-or-health** + the ×5 bounty (the
  original M6 spec). M2 upgrades the first two elites to Aspect relics; this stays the
  fallback for elite #3+ and for an exhausted Aspect pool.
- Minimap ping (magnet-blip pattern, distinct color) + a low spawn cue — new SFX obeys the
  low-fundamental rule (differentiate by timbre, not pitch).
- Excluded from elite rolls: anything tagged `boss`/`finale`, Broodlings (death spawns are
  already exempt by the pool-only rule), the Gilded One and Scavenger (their identity *is*
  their drop; keep `WaveEvent`-spawned mobs out entirely).

Watch item: a ×15 HP Brute at 4:00 on a fresh hammer/staff save (per-loadout trees = no base
upgrades) may be a wall. Elites must stay skippable — normal steering, no forced engage.

## M2 — Aspect plumbing: registry, relic, pick screen

- **Data:** Aspects are plain `BoonData` resources in `data/boons/aspects/` with their own
  `registry.tres` (the boon screen never loads it — zero cross-contamination). All are
  `unique = true` with `grants_ability` set; `requires_weapon` gates the loadout trios.
- **Pickup:** new `&"aspect"` kind in [pickup.gd](../actors/pickups/pickup.gd) — same
  contract as `&"unlock"` (no magnet, `lifetime = INF`, not edible, pulse; new mesh/tint).
  Walking onto it emits a new `EventBus.aspect_relic_claimed` — *walking to it is the
  decision*, so elite relics never pause spawning while they sit there.
- **Pick screen:** `AspectScreen` modeled on [claim_screen.gd](../ui/claim_screen.gd) (pause
  handling, `call_deferred` show — the claim fires mid-physics) but with **two boon cards**
  (reuse the boon screen's card + description rendering). Roll: weighted sample of 2 from
  {mounted loadout's Aspects + universals} minus already-owned flags; 1 card if only one
  candidate remains; if zero, the relic never spawns (bounty fallback fires instead). No
  reroll, no skip — the scarcity is the point.
- **Boss hook:** in `RunDirector._on_boss_wave_cleared`, when `_next_unlock_drop` returns
  empty (all weapons owned — every veteran, and new players after their drops), spawn an
  Aspect relic instead via the same arena-clear + spawn-pause spectacle; resume on claim.
  Weapon relics keep priority — the progression arc is weapons first, Aspects after.
- **Elite hook:** first **2** elite kills per run drop the Aspect relic (RunDirector counts
  via `enemy_killed` + elite flag), later elites use the M1 bounty.
- Claim stinger: reuse `unlock_claim` for now; HUD banner announces the picked Aspect.

## M3 — Duelist Aspects

| Aspect | Flag | Effect |
|---|---|---|
| **Crescendo** | `riposte_chain` | Riposte kills don't consume the prime and refresh its window; each successive riposte in the chain deals +25% more (stacks until the window lapses) |
| **Mirror Ward** | `mirror_ward` | Perfect-blocking a projectile hurls it back at the shooter; it detonates on impact in a ~4m blast at riposte-scaled weapon damage |
| **Blade Waltz** | `blade_waltz` | Blinking through enemies slashes each for riposte-scaled weapon damage — the blink *is* the strike, no prime needed |

Implementation notes:

- **Crescendo:** the riposte consume/lapse logic in [player.gd](../actors/player/player.gd);
  kill attribution via the riposte-flagged swing's hit path (not `enemy_killed` — swarm
  deaths would false-positive). Stack counter resets when the window lapses.
- **Mirror Ward:** the perfect-block branch of `Player.mitigate_hit` already has
  `AttackInfo.source`; reflect only when the source is an in-flight projectile (Spitter
  bolt, Hierophant `EnemyFireball`). Boulders are excluded by construction — the mortar has
  no mid-flight collision, so it can never be perfect-blocked. The return shot homes to the
  shooter; blast damage = weapon damage × `riposte_damage` (Ruthless Riposte feeds it).
- **Blade Waltz:** rides the Shield Dash segment-sweep from 8C M2 — run the sweep when
  *either* flag is owned; Blade Waltz deals the damage, Shield Dash (if also owned) stuns
  and primes. Stacking both is the intended dash-weaving fantasy.

## M4 — Earthshaker Aspects

| Aspect | Flag | Effect |
|---|---|---|
| **Fault Line** | `fault_line` | Seismic Slam's wave leaves a quaking fissure (~4s) that slows enemies crossing it to 50% speed — and every enemy the wave or fissure catches refunds ~0.75s of the slam's 6s cooldown |
| **Epicenter** | `leap_epicenter` | Crashing Leap's landing also erupts Seismic waves outward in four directions (full wave boons apply — Riptide drags, Implosion pulls) |
| **Mass Driver** | `mass_driver` | Shoved enemies become projectiles: anything they're driven through takes the Bone Breaker impact treatment (30% hammer damage + stagger), walls included |

Implementation notes:

- **Fault Line:** fissure = a strip decal along the wave's path (GroundTelegraph rendering,
  danger semantics inverted — it hurts *them*); it slows to 50% via `apply_slow` (reapplied
  each tick, never a stun-lock — a stun here perma-locks given how often the wave recasts).
  Refund: per-enemy-once against `Weapon._secondary_cooldown`. This is
  the slam-as-primary flip: strays keep it a 6s tool, a dense third-act pack pays for the
  next cast almost immediately.
- **Epicenter:** the leap *already* runs a full-damage 360° `_slam()` on landing (8C M3) and
  procs Aftershock — the delta here is the **wave volley**: four `GroundShockwave`s at the
  cardinal points of facing, ~0.75× wave damage each so RMB stays the aimed tool. With
  Fault Line, landing in a pack refunds the RMB slam too — leap becomes the artillery button.
- **Mass Driver:** during shove displacement (slam, wave, leap), sweep the displaced enemy
  against `EnemyBase.alive` and apply `_wall_impact`-equivalent damage+stagger to whatever it
  hits; no chaining off victims (one generation, same anti-recursion stance as death spawns).
  Perf: only actively-shoved enemies are tracked — a handful at a time even at the 120 cap.

## M5 — Arcanist Aspects

| Aspect | Flag | Effect |
|---|---|---|
| **Blood Pact** | `blood_pact` | Spells can be cast without mana: the missing mana is paid as health (~0.5 HP per mana). A cast that would kill you is refused |
| **Stormcaller** | `stormcaller` | While levitating, Arcane Bolts fork into three, and bolt hits refund levitate's mana drain |
| **Shatterflux** | `shatterflux` | Frost-chilled enemies struck by Fireball shatter: double blast damage to them plus a mini-nova that chills their neighbors |

Implementation notes:

- **Blood Pact:** hooks the insufficient-mana refusal from 8A M4 — instead of the thunk,
  drain HP for the deficit (0.5 HP/mana → a from-empty Fireball ≈ 20 HP). HUD: flash the
  deficit portion red on the mana bar. Bulwark and health pickups become mana stats.
- **Stormcaller:** fork ±10° at bolt spawn while `_levitating`; mana restore stays capped at
  the base 8 per trigger pull (the 8A M6 anti-printer rule — forks refund *drain*, not
  income). Turns levitate from an escape into an artillery stance the generator loop funds.
- **Shatterflux:** enemies already carry the Frost Nova chill state; on Fireball blast
  application to a chilled target, ×2 damage + a ~2.5m mini-nova (2s chill) at the target.
  Mini-novas are single-generation — their chill can prime the *next* Fireball, not
  cascade within this one.

## M6 — Universals, integration, tuning

| Aspect | Flag | Effect |
|---|---|---|
| **Undying Will** | `undying_will` | Once per run, lethal damage instead leaves you at 30% max HP, with a hard 3m shockwave and ~1s of grace |
| **Prospector's Idol** | `prospectors_idol` | Enemies drop one extra gold piece and your collection radius is doubled |
| **Slipstream** | `slipstream` | Your loadout's Shift verb improves: +1 blink charge / −20% leap or levitate cooldown |

- Undying Will intercepts in the player's death path before `player_died`; the shockwave
  reuses the parry-nova pulse. Prospector's Idol: extra piece in `_spawn_pickups` (flag
  check on the player), radius on the pickup's target lookup. Slipstream: carries both a
  `dash_charges` flat modifier and the flag; leap/levitate read a cooldown multiplier.
- **Integration pass:** BOONS.md gains an Aspects section; death-screen run stats could list
  Aspects taken (nice-to-have); headless smoke — force-spawn an elite, kill it, assert relic
  → claim → flag granted; boss path asserted with all weapons owned.
- **PLAN.md** roadmap row + §6 watch items updated.

---

## Tuning levers & watch items

- **Yield:** elite Aspect cap (2), elite cooldown (50s), elite chance (3%), boss fallback.
  If runs feel Aspect-flooded, cut the elite cap to 1 before touching boss drops.
- **Fault Line refund** (0.75s/enemy) is the scariest number in the set — a wave through 8+
  enemies near-resets a 6s cooldown. If slam-spam trivializes the third act, halve the
  refund before shrinking the fissure.
- **Crescendo** turns swarms into riposte fuel; watch it against Stalker packs (their whole
  counter is parry→riposte already).
- **Blood Pact + Undying Will** in one run = a deliberate glass-cannon enabler; fine, but
  confirm Undying's once-per-run actually resets nothing else.
- Elites must read as *optional* bounties, not gates — if playtest says "I have to kill it,"
  soften HP before rate.

## Playtest checklist

- Does an elite spawn read instantly (scale + glow + ping + cue) and feel worth the detour?
- Is the 1-of-2 pick a real decision at least half the time?
- Each loadout: does at least one Aspect visibly change *how* you play by minute 6?
- Boss kill with all weapons owned: does the Aspect relic land in the same satisfying
  spectacle beat as weapon relics did?
- Fresh-save runs: do weapon relics still take priority cleanly, with Aspects appearing
  only after?
