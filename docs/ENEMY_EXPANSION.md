# Enemy Expansion — Broodmother, Stalker, Gilded One, Scavenger

> **Status: ◯ Planned.** Four new non-boss enemies that widen the mid-run pool (75s–150s, the stretch between the Juggernaut and the Hierophant) and — the design goal — **interact with systems and enemies that already exist** rather than just adding stat lines: the death-burst spawner turns kill *positioning* into a decision, the hit-and-run Stalker attacks the guard meter, the Gilded One weaponizes the player's own greed against the horde, and the Scavenger attacks the reward-on-collection economy directly.

Guiding constraint (same as the progression and boss reworks): everything rides on machinery that already exists — the `EnemyBase` state machine with per-state overrides (Spitter is the template), the hurtbox pipeline (block/parry/dash counterplay works against every new attack for free), `apply_slow` routed through `move_speed()` (Frost Nova catches every runner for free), the physical-pickup economy, and `WaveTable`/`WaveEvent` scheduling. Three small pieces of genuinely new plumbing, each reusable beyond its first consumer (§0).

All numbers below are *first guesses*; the M5 balance pass calibrates by feel.

---

## 0. Shared plumbing (small, generic, built with its first consumer)

### 0.1 Death spawns — `EnemyData.death_spawns` + `death_spawn_count` *(built in M1)*

The spawner-mob mechanic as **data, not a script**: two new `EnemyData` fields (`death_spawns: EnemyData`, `death_spawn_count: int = 0`), handled generically in `EnemyBase._on_died` before the shrink tween — instantiate `count` children in a tight ring (radius ~1.2) around the corpse, clamped to the arena, each `setup()` with the parent's stored `_hp_mult/_dmg_mult/_reward_mult` so wave scaling inherits.

- **Hatch delay:** children spawn in `RECOVER` state (`_set_state(State.RECOVER)` after `_ready`), so they hold still for their `recover_time` with a scale-up pop tween before chasing — a readable "eggs hatching" beat instead of five instant attackers, and zero new state-machine code.
- **No recursion:** children's own `death_spawns` stays null. (Guard anyway: refuse to death-spawn if the child data also has death spawns.)
- **Cap note:** death spawns bypass the alive cap (like wave events). They *do* join `EnemyBase.alive`, so the spawner naturally throttles around them. Keep counts small.
- **Future payoff:** this is also the "elite splits into copies" hook ENEMIES.md's future-direction wanted, for free.

### 0.2 `WaveEvent.chance: float = 1.0` *(built in M3)*

One field: when `RunDirector`'s per-event clock fires, roll `randf() < chance` before spawning; `repeat_every` re-arms regardless of the roll. Gives the WaveTable random *rare* events (the Gilded One) without a parallel scheduling system. Existing events default to 1.0 — no behavior change.

### 0.3 `Pickup` ground registry + `consume()` *(built in M4)*

Mirror of the existing `Pickup.magnets` pattern: a `static var edible: Array[Pickup]` that **gold and XP pickups only** join in `_ready` and leave on collect/expire/free (relics, magnets, and health never register — boss loot and utility drops are theft-proof by construction). Plus `consume() -> int`: returns the value and frees the pickup *without* emitting `pickup_collected` — loot eaten by a Scavenger was never collected. Cheap: pickups already live in a manual-motion, no-physics lifecycle.

### 0.4 Minimap rare blip

The minimap already reads `enemy.state` for its color language (orange = winding up, blue = stunned). Add one check: `enemy.data.tags.has(&"rare")` → **gold blip** regardless of state. Consumer: Gilded One (and any future bounty-style enemy).

---

## 1. Broodmother — the death-burst spawner *(M1)*

**Fantasy:** a slow, swollen carrier. Killing it is never in question — *where* you kill it is the decision.

- **Behavior:** stock `EnemyBase`, no script. Slower than a Brute (2.2), heavy swat up close. All the mechanic lives in §0.1 data: on death it bursts into **5 Broodlings** — tiny, fast, fragile chasers that hatch (hold ~0.45s) then swarm.
- **The decision it creates:** her gold/XP fountain and her brood erupt *at the same spot* — the loot is guarded by its own drop. Melee-killing her point-blank means five hatching mouths inside magnet radius; the counterplays are killing her at range (staff bolts, fireball), kiting her into open ground first, or greeting the hatch with a hammer slam / Implosion gather (the brood is exactly what the Earthshaker's AoE kit is for). Blade Cyclone riposte and Scorched Earth also feast here — every AoE tool in the game gets a designed moment.
- **Interaction with existing enemies:** a Broodmother walking inside a Sprinter swarm is a trap for panic-AoE — burst her blind and the swarm gains five bodies at your feet.
- **Visual:** Brute-scale but bulbous (widened capsule), sickly green; Broodlings are ~0.45-scale Chasers in the same green so the parentage reads instantly. Death squelch + hatch chitter SFX (§6).

**Data:** `broodmother.tres` + `broodling.tres`, `BroodmotherEnemy.tscn` + `BroodlingEnemy.tscn` (Chaser duplicates, resized). Broodmother in the spawn pool; Broodling **not** in the pool (referenced only via `death_spawns` — and available later for swarm events, §5).

## 2. Stalker — the evasive skirmisher *(M2)*

**Fantasy:** a jackal. It doesn't want a fight; it wants a bite. Punishes turtling and tunnel vision.

- **Behavior:** subclass (`stalker_enemy.gd`, Spitter-sized). Two-phase `_chase()` override:
  - **Engage:** approach in a shallow arc (direct vector blended with a tangential component until ~4m out — it curves onto your flank rather than joining the conga line), then a fast strike: short windup **0.28s**, standard attack, short recover.
  - **Disengage:** after `_begin_recover()` completes, set a **2.5–3.5s** retreat timer — back away to orbit range ~8 with lateral drift (reusing the Spitter kite + Caster wall-slide steering patterns, all through `move_speed()`), then re-engage.
- **What it attacks:** the **guard meter**. Each blocked poke costs 0.5s of hold time and the Stalker never stands still to be punished afterward — turtling against two or three of them bleeds guard until something bigger lands the break. This deliberately sharpens the PLAN §6 block-design pressure; the answer is the same one the meter was built for:
- **Counterplay:** **parry it.** A perfect block stuns it mid-strike (the one moment it's committed), and at 18 HP one riposte deletes it — the Stalker is the Duelist's favorite food, the way the brood is the Earthshaker's. Frost Nova collapses its disengage (slows route through `move_speed()`); the staff just shoots it during orbit, though the lateral drift makes that an aim check rather than a freebie.
- **Visual:** low, lean, dark violet; eyes stay lit while disengaged (it's *watching*), which doubles as the "don't forget about me" tell. Disengage whoosh SFX.

## 3. Gilded One — the golden bait *(M3)*

**Fantasy:** a walking jackpot that is never free. It doesn't hurt you; it *positions* you.

- **Behavior:** subclass (`gilded_enemy.gd`), never attacks. Flee steering in `_chase()`: away-from-player as the base vector, **biased toward the densest nearby enemy cluster** (cheap: average position of the closest N entries in `EnemyBase.alive`) and wall-sliding at the arena edge — chasing it drags you into packs and corners *by construction*, no bespoke "bait AI" needed. A direction jitter re-rolled every ~1.2s keeps straight-line prediction honest.
- **Catching it:** speed **7.2** — above player run speed, below Sprinter. The tools are dash (blink through the gap), Frost Nova (slows work on it like everyone else), prediction, or ranged loadout. **Despawns after 30s** in a mocking shimmer — the timer is what creates the "do I commit?" spike mid-wave.
- **Reward:** a jackpot fountain — gold **60**, XP **25** (× reward mult, so late-run Gilded are genuinely rich), burst wide via the existing ring-fountain path (`_spawn_pickup_pieces` with `speed_mult ~1.6, ring = true`). Deliberate second bait: the payout scatters where it died — usually inside the pack it led you into — and collection-on-pickup means the kill alone pays nothing.
- **Spawning:** not pool-weighted. A **chance event** (§0.2): `time 90, count 1, repeat_every 70, chance 0.6`, no announcement — the spawn *glimmer* SFX plus the gold minimap blip (§0.4, tag `&"rare"`) are the announcement. At most one alive (skip the spawn if a `&"rare"` enemy is in `EnemyBase.alive`); skip entirely while boss-loot spawning is paused.
- **Visual:** small (~0.6-scale Chaser), gold emissive material, sparkle trail (`ShardBurst` motes). HP 30 — dies in ~2 hits; the fight is the catch, not the kill.

## 4. Scavenger — the loot-eater *(M4, designer's liberty)*

**Fantasy:** a fat burrowing rat that eats what you left on the ground. The one enemy aimed at this game's signature system — **rewards are physical and expire** — so "I'll grab the loot later" finally has a predator.

- **Behavior:** subclass (`scavenger_enemy.gd`). **Ignores the player entirely** — no attack, ever; its threat is economic. Seeks the nearest registered pickup (§0.3), eats anything within 1.3m at ~0.35s per piece (gold/XP only). Each meal inflates a visible belly and gold-tints it — the **bounty**, `eaten × 1.25` (rounded up).
- **Endgame:** after **12 pieces eaten or 18s alive**, it stops, telegraphs a 0.9s burrow (dust ring via the standard `GroundTelegraph`-adjacent VFX, rumble SFX), and digs out — **the loot is gone**. Kill it first and the bounty erupts back as a fountain: your loot, with interest.
- **Spawn trigger — the clever bit:** it isn't pool-weighted or scheduled. `RunDirector` spawns one (ring placement via the public `spawn_enemy()`) only when **uncollected edible pickups ≥ ~20**, at most one alive, ≥25s between spawns, never while boss-loot spawning is paused. It appears *precisely when the player is leaving money on the floor* — which is exactly the post-swarm moment (a Sprinter swarm's corpse-carpet is its dinner bell), and exactly when the player is busiest.
- **Interactions:** makes the **magnet pickup** better (vacuum the arena before the rat arrives); turns the ignored Gilded fountain into rat food; creates a pure target-priority question with zero damage threat — is 40 gold worth turning your back on a Brute windup?
- **Counterplay note:** it's a free kill *in a vacuum* — HP 45, speed 4.2 (5.8 fleeing once sated) — the cost is time and position while the horde presses. If it still feels like chores, first lever is raising the trigger threshold, not its stats.

## 5. Stats & registration

| | Broodmother | Broodling | Stalker | Gilded One | Scavenger |
|---|---|---|---|---|---|
| Enters at | **135s** (pool) | via death burst | **75s** (pool) | **90s** (chance event) | **150s** (loot-triggered) |
| HP | 70 | 6 | 18 | 30 | 45 |
| Speed | 2.2 | 7.0 | 6.8 (orbit 8) | 7.2 | 4.2 / 5.8 sated |
| Damage | 24 | 6 | 16 | — | — |
| Range | 2.2 | 1.4 | 1.7 | — | — |
| Windup / recover | 0.5 / 0.8 | 0.22 / 0.45 | 0.28 / 0.35 | — | — |
| Knockback | 8 | 2 | 4 | — | — |
| Gold / XP | 10 / 7 | 2 / 2 | 7 / 5 | **60 / 25** | bounty ×1.25 |
| Spawn weight | 0.35 | — | 0.5 | — | — |
| Tags | | | | `rare` | |

- All time gates sit **before the minute-5 Hierophant**, so the full roster is experienced in a staff-victory run; endless veterans get the complete late mix.
- **Pool dilution:** two new weighted entrants shift the late composition. M5 retunes weights against a target mix (roughly: Chaser 30% / Sprinter 20% / Spitter 15% / Brute 12% / Stalker 15% / Broodmother 8% by late-game weight share) and considers `weight_ramp_duration` on both newcomers so they fade in rather than spike.
- **New swarm event (M5):** one-shot at **240s** — 3 Broodmothers, "THE BROOD COMES" — a mid-run AoE exam between the two bosses, slotted into the rhythmic-cadence gap.

## 6. SFX (procedural, `SfxFactory`, low-pitched per the audio direction)

All fundamentals kept low; differentiation by timbre/envelope, not height. Per-id rate limiting via `AudioManager` as usual.

- **Brood burst:** wet squelch (filtered noise, fast low sweep) + a scatter of short chitters on hatch.
- **Stalker disengage:** a short reverse-whoosh (the existing swing-whoosh family, inverted envelope).
- **Gilded spawn glimmer:** two detuned low-mid tones with slow tremolo — audible "something rare is here" cue; **jackpot fountain** layers a deeper thunk under the existing coin blips.
- **Scavenger:** per-meal *gulp* (short downward sweep, comedic), burrow rumble (low filtered noise swell).

## 7. Milestones

Each milestone ends runtime-smoke-tested headless (console exe, `--quit-after`, scene loads + a scripted spawn), same protocol as the boss rework.

- **M1 — Death-spawn plumbing + Broodmother.** §0.1 `EnemyData` fields + generic `_on_died` handling (hatch-delay trick), `broodmother/broodling.tres` + scenes, pool registration. *Acceptance:* killing a Broodmother anywhere hatches 5 delayed Broodlings that inherit wave scaling; no recursion; teardown-safe.
- **M2 — Stalker.** Arc engage / timed disengage subclass; verify parry-stun interrupts a strike and slows collapse the orbit. *Acceptance:* it never idles in melee outside its strike, and a parry → riposte kills it.
- **M3 — Gilded One.** `WaveEvent.chance` (§0.2), flee-toward-crowds steering, 30s despawn shimmer, ring jackpot fountain, `rare` tag + gold minimap blip, glimmer/jackpot SFX, one-alive + boss-pause guards.
- **M4 — Scavenger.** `Pickup` edible registry + `consume()` (§0.3), seek/eat/belly/burrow loop, bounty fountain on death, loot-threshold trigger in `RunDirector` with cooldown + boss-pause guard, gulp/burrow SFX.
- **M5 — Integration & balance pass.** Pool weight retune (§5 target mix), the 240s brood event, a full-run playtest against the difficulty cadence (especially 240–300s: brood event → Hierophant), tuning from feel, then docs refresh (`ENEMIES.md` roster/authoring tables, `PLAN.md` phase row).

## 8. Risks / tuning watch

- **Alive-count spikes:** death bursts and events both bypass the cap; worst case (~90 cap + brood event + Gilded pack-chasing) stays far under the ~200 GDScript danger zone, but profile the 240s window on web before shipping M5.
- **Gilded frustration vs. bait:** if players report "impossible to catch" rather than "I got greedy and died," add a first-hit 20% self-slow (a wound) before touching its speed — keep the bait identity, soften the catch.
- **Scavenger reads as chores:** it must feel like a *raid on your wallet*, not a mandatory errand. Levers in order: raise trigger threshold (20 → 30 pieces), lower eat rate, cap spawns per run (~3).
- **Stalker × guard meter:** chip pressure is intended, but if guard breaks in swarms start feeling unfair (the standing PLAN §6 watch), cut Stalker spawn weight before touching the meter.
- **Kill-crediting:** Broodlings and the Scavenger emit `enemy_killed` and drop loot like anyone else; verify the kill counter and reward totals don't double-count the mother+brood package in run stats.
