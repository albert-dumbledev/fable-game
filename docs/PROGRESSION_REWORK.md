# Progression Rework — rare drops, boss-drop unlocks, loadout identity

Restructures three progression systems: (A) rare utility drops (magnet, health), (B) weapon unlocks move from the gold shop to boss drops, and (C) each loadout gets its own stat/boon identity — sword = parry/duelist, hammer = AoE/crowd-control, and a new staff loadout that takes the spells with it.

Guiding constraint: everything below rides on machinery that already exists — `Pickup` kinds are plain StringNames, unlocks are ability flags, boons already gate per-weapon, and shoves/stuns are the CC primitives. No new subsystems; mostly new `.tres` files, a handful of new stat ids, and small hooks at existing effect sites.

---

## A. Rare utility drops

Two new `Pickup` kinds alongside `&"gold"` / `&"xp"`. Both are **rare enough to be an event**, not part of the income stream.

### A1. Magnet

- **Effect:** on collect, every gold/XP pickup currently in the arena immediately magnets to the player, regardless of distance or `MAGNET_DELAY`.
- **Drop roll:** in `EnemyBase` death, after the normal gold/XP fountains — `MAGNET_DROP_CHANCE ≈ 0.007` per non-boss kill *(first guess)*. At late-run kill rates that's roughly one every 2–3 minutes. At most **one magnet on the ground at a time** (skip the roll if the pickups group already contains one) so they can't bank up.
- **Behavior:** does **not** magnet to the player — walking to it is the decision (do I dive for the vacuum now, or save it for after the swarm?). Longer `lifetime` (45s), pulsing emissive mesh so it reads across the arena, minimap ping (same hook the boss uses).
- **Implementation:**
  - Add all pickups to a `&"pickups"` group in `pickup.gd::_ready` (nothing iterates pickups today; the group is the cheap index).
  - `Pickup.force_magnet()` — sets `magnet_radius = INF` and marks `_age >= MAGNET_DELAY` so collection starts this frame. Manual-motion pickups are already cheap; 300 simultaneously homing pieces is fine on web.
  - Collect path: `pickup_collected(&"magnet", 1)` fires as usual (SFX/stats hook), and the magnet pickup itself iterates the group and calls `force_magnet()` — it's standing in the scene and already knows the tree; no new EventBus plumbing.
  - SFX: new `SfxFactory` cue — big, low whoomp + rising coin-swell as the loot arrives (keep fundamentals low per the audio direction; differentiate by timbre, not pitch).

### A2. Health

- **Effect:** heal **25% of max health** *(first guess — scales with Bulwark stacking, unlike a flat value)*.
- **Drop roll:** `HEALTH_DROP_CHANCE ≈ 0.02` per non-boss kill *(first guess)*. Plus **one guaranteed health drop in the first loot wave of every boss kill** — the boss fight is where you bled for it.
- **Behavior:** normal pickup physics *including* magnet-to-player (it's a reward, not a decision), red cross / heart mesh, distinct low warm SFX blip.
- **Implementation:** collect path emits `pickup_collected(&"health", pct)`; the **player** listens (it owns `HealthComponent`) — `RunDirector`'s match statement ignores unknown kinds already, so gold/XP bookkeeping is untouched. HUD: reuse the heal feedback from Bulwark's heal-on-pick.
- **Balance watch:** interaction with Blood Drinker (vampire). If sustain stacks too well, cut the drop chance before the heal amount — frequency is the knob that keeps drops feeling like events.

Files touched: `actors/pickups/pickup.gd` (+ 2 meshes in `Pickup.tscn`), `actors/enemies/enemy_base.gd` (drop roll consts + roll in `_on_died`), `actors/enemies/boss_enemy.gd` (guaranteed health piece), `actors/player/player.gd` (health handler), `core/sfx_factory.gd`, `ui/minimap.gd`.

---

## B. Boss-drop unlocks (warhammer first)

Weapon unlocks leave the gold shop. Bosses become the unlock gate: **each boss kill drops the next weapon in its loot table that the player doesn't own yet.**

### B1. The generic mechanism (build once, staff reuses it)

- `EnemyData` gains `@export var unlock_drops: Array[StringName] = []` — ordered ability flags. On boss death, the first entry the player doesn't own spawns as a **weapon relic pickup**; if all are owned, nothing drops. Juggernaut: `[&"weapon_warhammer", &"weapon_staff"]` — so the *first* juggernaut you kill drops the hammer, and the first one you kill *after owning the hammer* drops the staff (in practice: the second boss encounter, without needing to count waves — kill-order gating is robust against skipped/died-before bosses in a way that clock-time gating isn't).
- **Relic pickup:** a `Pickup` with `kind = &"unlock"` plus a new `ability: StringName` field. Oversized glowing mesh, infinite lifetime, no magnet (walk to it), spawned after the loot waves in `BossEnemy._on_died`'s choreography tween — the fountain finale.
- **On collect:** `MetaProgression.grant_meta_ability(ability)` → appends to a new persisted `unlocked_abilities: Array[StringName]`, saves immediately (dying two seconds later must not eat the drop), fires the wave-banner ("WARHAMMER CLAIMED — equip it from your loadout") + a unique stinger. `get_granted_abilities()` returns upgrades ∪ `unlocked_abilities`; nothing downstream changes — `is_weapon_unlocked`, the loadout picker, and boon gating all read that one function.
- The weapon equips **next run** via the existing death-screen loadout picker. No mid-run weapon swapping — that's a different feature.

### B2. Warhammer migration

- Remove `warhammer.tres` from `data/upgrades/registry.tres` (the Might branch loses its capstone — B4 in section C refills it).
- **Save migration:** add `save_version` to the save (absent = v1). On load of a v1 save: if `upgrade_levels.warhammer_unlock > 0`, move it to `unlocked_abilities` and **refund the 250 gold** — the player keeps the weapon they earned *and* the boss drop stays meaningful for fresh saves only. Delete the stale `upgrade_levels` entry.

Files touched: `core/enemy_data.gd`, `actors/pickups/pickup.gd`, `actors/enemies/boss_enemy.gd`, `autoload/meta_progression.gd` (grant + save_version + migration), `data/enemies/juggernaut.tres`, `data/upgrades/registry.tres`.

---

## C. Loadout identity — stats, boons, and the staff split

Design target: picking a loadout should pick a *game*, not a damage skin. Each weapon gets (1) a small core mechanic in the base kit, (2) a boon family that deepens it, (3) a meta-shop subtree that appears once the weapon is owned.

**Shared plumbing (do first):**

- `UpgradeData` gains `@export var requires_ability: StringName = &""` — the shop hides the node entirely (not just locks it) until the flag is owned. This is how hammer/staff subtrees appear in the tree only after their boss drop. One check in the death-screen tree builder.
- New stat ids in `core/stats.gd` (all base-1.0 multipliers unless noted): `riposte_damage`, `parry_stun`, `hammer_shove`, `spell_damage`. Registered in `display_name` so boon descriptions auto-generate.
- Loadout-specific meta upgrades **don't need equip-time gating**: `riposte_damage` on a hammer run simply never gets read. Purchase-gating via `requires_ability` is enough.

### C1. Sword & Shield — the Duelist

**Core mechanic (base kit, no boon): Riposte.** A perfect block primes a riposte for **2.0s**: the next swing deals **+75% damage** *(first guess)* and flashes the blade gold. Two rules keep it clean:

- **The bonus applies to every enemy that swing connects with**, not just the first — it's consumed when the swing *ends*, not on first contact. One parry into a pack pays out on the whole pack.
- **The prime never stacks.** Parrying again while primed just refreshes the 2.0s window; there is exactly one riposte buff at any time, so chained perfect blocks can't bank a multi-hit burst.

Implemented as `_riposte_until` on the player, read in `sword_and_shield.gd::_do_attack` (the swing snapshots the bonus at activation and clears the prime at deactivation — the hitbox already hits each hurtbox at most once per activation, which is exactly the "whole swing, once each" semantics for free). This makes "parry → punish" the sword's fundamental loop that everything below scales — the reward for parrying today (1.5s stun) is defense-only; riposte makes it offense.

**Boon family** (all `requires_weapon = &"sword_and_shield"`, joining thorns + Duelist's Focus):

| Boon | Effect (×1.0) | Type |
|---|---|---|
| Ruthless Riposte | +40% riposte damage (`riposte_damage`) | stat, stackable |
| Punishing Stun | +30% parry stun duration (`parry_stun`) | stat, stackable |
| Retribution | Perfect blocks detonate a 3m pulse: 50% weapon damage + shove 8 to everything around you | unique (`parry_nova`) |
| Expose Weakness | Parried enemies take +35% damage from **all** sources while stunned | unique (`exposing_parry`) |
| Second Wind | Perfect blocks heal 8 HP and refund 0.5s guard | unique (`parry_heal`) |
| Blade Cyclone | Riposte swings hit in a full circle around you | unique (`riposte_sweep`) |

Effect sites: `player.gd::mitigate_hit` (nova, heal, stun scaling — the perfect-block branch already exists), `EnemyBase` (a `vulnerable_until` timestamp checked in `take_damage` routing, tint like the chill tint), `sword_and_shield.gd` (riposte damage + sweep arc).

**Meta subtree (Vigor branch, always visible — sword is the starter):** "Counterweight" — +10% riposte damage per level, uncapped, behind Vitality. Vigor is the defense branch; the parry game is defense-as-offense, it fits.

### C2. Warhammer — the Earthshaker

**Core tweak:** shove force scales with the new `hammer_shove` stat (base kit unchanged otherwise — the primary slam + Seismic Slam are already the AoE identity).

**The skill-expression axis is pull → slam.** The hammer can already push everything; giving it *gather* tools creates the setup/payoff combo loop:

| Boon | Effect (×1.0) | Type |
|---|---|---|
| Wrecking Ball | +25% shove force (`hammer_shove`) | stat, stackable |
| Implosion | The slam's **outer splash band pulls inward** toward the impact point instead of shoving out — the crash gathers a pack onto the crater, briefly staggered | unique (`slam_pull`) |
| Riptide | The Seismic Slam wave **drags enemies along with it**, depositing them in a briefly staggered clump at the end of the line | unique (`wave_drag`) |
| Bone Breaker | Enemies shoved into a wall take 30% of hammer damage and stagger briefly | unique (`shove_impact`) |

**Pulled enemies get a mini-stun on arrival** — **0.5s** *(first guess)* through the existing `stun(duration)` path (same tint/freeze the parry stun uses, just shorter). Deliberately **shorter than the 1.4s hammer swing**: you can't pull, *then* react — you have to start the follow-up slam while the pull is still resolving, which is the skill expression. The stagger is there so a freshly gathered pack doesn't get a free windup on you, not so you can stand in it.

Combo lines this creates: Riptide gathers a corridor into a pile → primary slam the pile; Implosion + Aftershock (existing) — the pull feeds staggered bodies into the echo hit; Bone Breaker + Wrecking Ball turns arena walls into a weapon. All three uniques are variations on the existing `apply_shove` + `stun` (negate the shove direction for pulls; for Bone Breaker, check `is_on_wall()` in `EnemyBase` while the shove impulse is above a threshold and apply one-shot damage).

**Meta subtree (Might branch, `requires_ability = &"weapon_warhammer"` — refills the slot the shop lost in B2):** "Heavyweight" — +10% shove force per level, behind Ferocity.

### C3. Staff — the Arcanist (recommended: yes, split the spells out)

**Recommendation: do the split.** Q/E spells on top of melee were pre-loadout-identity design; keeping them global fights this whole rework (the sword's parry family and fireball spam compete for the same build). The staff gives the "caster fantasy" a real home, the second juggernaut a reason to matter, and melee loadouts get their new boon families as compensation for losing the spells. Trade-off accepted: melee/caster hybrids die — that's the point of loadouts.

- **New `WeaponData`:** `battle_staff`, `can_block = false`, `unlock_ability = &"weapon_staff"`, dropped by the mechanism in B1 (juggernaut kill while the hammer is owned).
- **Kit — one free spell, the rest are unlockables:**
  - **LMB — Arcane Bolt:** a fast unlimited projectile (speed ~24, damage `8 + 0.8× damage stat`, 0.5s swing × attack speed; reuse the projectile pattern with a small impact flash). The spammable primary is what makes it a survivor-game weapon rather than two cooldowns and a prayer.
  - **RMB — Fireball, built into the staff.** RMB already routes to `Weapon.try_secondary` for every `can_block = false` weapon — the exact slot Seismic Slam occupies on the hammer, so the input plumbing is zero. Charge mechanics, charge bank, and all fireball boons unchanged; one tweak: the staff doesn't stow during the charge (it *is* the cast focus — the orb grows at the staff tip instead).
  - **E — Frost Nova, back in the shop** as an Arcana unlock upgrade, now gated `requires_ability = &"weapon_staff"`. Same spell, same key, just purchased.
  - **Q — open slot for future unlockable spells.** Freed up by fireball's move to RMB. First candidate when the content well needs refilling: a Chain Lightning (sustained single-target pressure — the niche bolt + fireball + nova leave open) as a deeper Arcana purchase.
- **How the flags move:** `WeaponData` gains `@export var grants_abilities: Array[StringName]` — flags granted while the weapon is mounted. `staff.tres` grants `firebolt`; `frost_nova` keeps arriving from its shop upgrade. This keeps ability flags as the single mechanism: the spell-cast checks, all spell boon gates (`requires_any_ability`), and the HUD skill slots work **unchanged** — fireball's flag just arrives from the mount instead of the shop.
- **Shop:** remove `firebolt.tres`; the **Arcana branch becomes the staff's meta subtree** (all `requires_ability = &"weapon_staff"`): Frost Nova (the returning unlock, now the branch root), then e.g. Attunement (−5% spell cooldown/level), Overcharge (+8% `spell_damage`/level — new stat multiplying bolt/fireball/nova damage), and future spell unlocks as capstones.
- **Save migration (v1 → v2, same pass as B2):** owned `firebolt` → grant `weapon_staff` (they paid for the caster fantasy; don't make them re-earn it from the boss) and refund the purchase, since fireball is now built in. Owned `frost_nova` → grant `weapon_staff` and **keep the upgrade level** — it's still a valid purchase, just re-gated behind the staff they now own.
- **Existing spell boons** (Quick Mind, Fast Hands, Greater Blast, Twin Flame, Scorched Earth, Echo Nova, Glacial Wave) need **zero changes** — their `requires_any_ability` gates follow the flags to the staff automatically.

Files touched: `core/weapon_data.gd`, `data/weapons/staff.tres` + registry, `weapons/staff.gd` + scene (new, smallest `Weapon` subclass yet), `player.gd` (mount-granted flags union, fireball trigger moves to `try_secondary`), `data/upgrades/` (remove firebolt, re-gate frost nova, add ~3), `autoload/meta_progression.gd` (migration).

---

## Implementation order

Each milestone ships independently and is smoke-testable headless (scene loads + a scripted kill/collect):

1. **M1 — Utility drops (A).** Self-contained, no save-format risk. Immediate playtest value.
2. **M2 — Boss-drop pipeline + warhammer move (B).** Includes `save_version` + v1 migration. Gate: a fresh save must reach the hammer via boss kill; a veteran save must keep it + refund.
3. **M3 — Shared plumbing + sword package (C-shared, C1).** Riposte core first, boons after — riposte alone is playtestable.
4. **M4 — Hammer package (C2).** Pure additive boons/stats on M3's plumbing.
5. **M5 — Staff loadout (C3).** Biggest chunk, deliberately last: depends on M2 (drop pipeline) and M3 (`requires_ability`, new stats), and it's the one to cut/defer if the milestone before it reveals balance fires.

## Risks / tuning watch

- **Boss-gated power on a death-loop game:** a fresh player must survive to 150s to see the hammer. That's the design (bosses matter), but if playtests show players stuck pre-boss, the lever is boss timing in `data/waves/default.tres`, not the drop mechanism.
- **Riposte number stacking:** the prime itself can't stack (one buff, refresh-only) and pays out once per swing, which kills the burst-banking exploit by design. What remains is stat stacking: +75% base × Ruthless Riposte picks × Expose Weakness (+35%) still multiplies — three Legendary Ruthless Ripostes ≈ +420%. And whole-swing application means the bonus is per-*enemy-hit*, so its value scales with pack density; that's the intended fantasy, but it's also why the boss (a single target) is the right balance check. If parry builds one-shot the juggernaut, drop the *base* riposte bonus first — the boons are the build, the base is just the hook.
- **Pull boons vs the horde cap:** Implosion/Riptide deliberately create dense clumps at 90 alive; dense clumps are also 90 windups pointed at one player position. The 0.5s arrival mini-stun is the safety margin — tune the *stun* before the shove impulse if gather-then-slam turns out to be a suicide button. Opposite failure mode: Implosion + Aftershock re-pulls into a re-stun every slam — watch for a stun-lock loop that trivializes packs; the fix is making the mini-stun not refresh on already-staggered enemies, not removing it.
- **Magnet/health drop rates** are pure first guesses; tune frequency before magnitude (rarity is what makes them events).
- **Spell exclusivity fallout:** melee saves that leaned on Frost Nova as their defensive cooldown lose it. C1's Second Wind / Retribution and C2's CC are the intended replacements — if melee survivability craters in playtests, that's where to compensate, not by un-splitting the spells.
- **Save migration is one-way.** Version the save (`save_version = 2`), migrate on load, keep the v1 branch until at least one release later.
