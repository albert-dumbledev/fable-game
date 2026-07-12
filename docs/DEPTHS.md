# Depths — Post-Victory Ascension

> **Status (2026-07-11): M1–M5 shipped** on branch `depths`, headless-verified
> (`test/DepthSmoke.tscn`; all prior harnesses green). **Forge wave 2 shipped
> (2026-07-12)** on branch `forge-wave-2` — all 11 planned Aspects + forge
> nodes are in, headless-verified. **M6 (balance playtest) pending** for both.
> **2026-07-12: pre-run hub split out of the death screen.** `ui/DeathScreen.tscn`
> is now recap-only (title, banners, killer headline, stats, BOONS/SLAIN/DAMAGE
> panel, records line, gold) with a single Continue button. The Depth picker,
> loadout picker, loadout × Depth badge grid, loadout banner, and both shops
> (gold might/vigor/arcana + the shard Reliquary, now its own bordered section
> rather than a fourth gold column) moved to a new `ui/LoadoutScreen.tscn`.
> Flow: Menu → Loadout → InRun → DeathScreen (recap) → Loadout. `test/depth_smoke.gd`
> re-points its picker/grid/banner/shop assertions at a new `_boot_loadout_screen()`
> boot; the VictoryBanner/records-line checks stay on `_boot_death_screen()`.
> Implementation notes recorded against the design below:
>
> - The five `.tres` are authored as **compounded supersets** — each deeper
>   Depth carries every shallower twist (Depth IV/V also run the twin
>   Juggernaut, the elite window, etc.), per the "already compounded" rule.
> - `DepthData` gained two fields beyond the schema below: `theme_color` (the
>   saturated badge/trim identity hue — `ambient_tint` stays a near-white mood
>   nudge; Depth V echoes the Revenant TrimRing teal) — plus static
>   `numeral()` / `ordinal_word()` helpers shared by every numeral call site.
> - Reliquary **QoL nodes read plain upgrade levels** (`get_upgrade_level`),
>   not ability flags — cleaner for leveled universal QoL; **forge nodes use
>   `grants_ability`** exactly as designed. Deep Cache spawns a magnet pickup
>   at run start via the elite-bounty path (primes on Surface too).
> - Boss-kill shard banking **saves immediately** (grant_meta_ability's
>   rationale: a death seconds later must not eat the bank). Full clear =
>   3 boss kills × N + 2×N = 5×N, matching the income table.
> - Forged Aspects shipped: **THE FLOOR BELOW** (universal — 15% on-kill
>   tremor, 4 m slow-to-0.55×/1.5 s + 0.25 s stagger that skips the already
>   stunned), **THE PRESSING DARK** (hammer — every slam-caught enemy slowed
>   to 0.5× for 2.5 s), **THE TWIN COURT** (sword — 0.22 s after a riposte
>   swing, a phantom radial twin hits everything within 3 m for 0.5×).
> - `BoonScreen`/`AspectScreen` gained `class_name`s (harness typing); the
>   shard glyph in UI is ◆ (proven in-font, same as the recap's Aspect mark).
> - **Forge wave 2 implementation notes:** `AttackInfo.no_proc` is new house
>   infra — DoT ticks and Dead Weight carries set it so they never re-proc
>   riposte/Cold-Blood-style multipliers or re-open a wound (anti-recursion).
>   `EnemyBase` gained a reusable ticking-stack DoT tracker (Unclosed Wound
>   today; burn/poison ride the same rails later). `notify_riposte_chain_kill`
>   was renamed **`notify_riposte_kill`** and is now shared by Crescendo and
>   The Vanishing Stair's blink refund. `FrostRune` (`weapons/frost_rune.gd`)
>   is a code-built node — 0.5 s arm, 6 s auto-fire, a recast replaces the live
>   rune, and detonation always routes back through the player's shared
>   `_do_nova` at 1.5× so every nova boon still applies. The Deep Draught
>   overcharge clamps the mana spend to whatever the pool covers but never
>   below the base cast (`_release_draught`). The Drowned Veil absorption
>   builds a **fresh** `AttackInfo` rather than mutating the incoming one (the
>   house no-mutation rule) — and a fully-absorbed hit still counts as a hit
>   for Patient Dark's reset and similar on-hit trackers. `EventBus` gained
>   `mana_absorbed` with a matching HUD mana-bar flash. `_do_nova` took a
>   `center` param so a flagless Echo Nova still tracks the player while
>   Waiting Cold's rune detonates from a fixed point. Cold Blood's "held" test
>   is `state == STUNNED or _slow_time > 0.0` at **1.5×**; the doc's own
>   trim-to-1.35× escape hatch is unused for now pending playtest.

## Why

The Revenant kill is the game's best moment and also where the reason to press
NEXT RUN evaporates: after the first victory the only remaining goals are
passive records. Meanwhile every run is the same run — `data/waves/default.tres`
is fully deterministic, so by run ~10 the opening minutes are rote execution.

Depths answers both with one system: each victory opens the next Depth — a
harder overlay on the same 7:30 run — and the goal ladder becomes **3 loadouts
× 5 Depths** of victories instead of one. This is the Hades heat / Risk of
Rain ascension pattern: "just one more run, but deeper."

**Reward philosophy (jam outcome, 2026-07-11):** a raw gold multiplier rewards
the players who need it least — a Depth-III-capable veteran has bought out
their tree and gold's marginal value has collapsed. So Depth rewards run in
**three lanes that never overlap**:

1. **In-run juice** — deep runs roll rarer boons and drop more Aspect relics.
   The pitch is not "same run, spongier enemies"; it's *god-runs live down
   there*. The build ceiling is higher at depth.
2. **Shards (durable)** — a depth-only currency banked by *attempting* depths
   (boss kills), spent in a new shop branch on choice-widening nodes and
   **forging depth-themed Aspects into the drop pool**.
3. **Badges & trim (status)** — first clears pay in visible identity: grid
   badges, per-loadout weapon trim, death-screen titles. No gold bounties —
   a one-time payout is spent and forgotten; a trim is re-earned every time
   you look at your weapon.

Gold stays the run-scale economy on both Surface and Depth (deep runs pay more
via `reward_mult`, which quietly self-funds a fresh loadout's climb).

Design constraints that shaped everything below:

- **Content as data.** A Depth is a `.tres` file; a shard node is an
  `UpgradeData`; a forged Aspect is a `BoonData`. Adding more later means
  authoring resources, not touching systems.
- **Never mutate the shared `WaveTable`.** Resources are cached; runtime edits
  would leak across runs. All Depth effects apply at the *consumption points*
  (Spawner, RunDirector, BoonScreen), leaving `default.tres` untouched.
- **Additive save changes only.** Missing keys default to base behavior — the
  same pattern as `records` (docs/RUN_RECAP.md); no migration. Shards reuse the
  id-keyed `MetaProgression.currencies` hook built for exactly this.

## What the player sees

1. **First Revenant kill:** the victory screen adds a banner — *"THE WAY DOWN
   OPENS — DEPTH I UNLOCKED"*. This is the moment the system exists.
2. **Loadout screen** (the pre-run hub; split out of the death screen
   2026-07-12): a **Depth picker** row (mirroring the loadout picker,
   hidden until the first victory): `SURFACE · I · II · III …` up to the
   deepest cleared + 1. Selection persists in the save like the loadout.
3. **In run:** a run-start announcement (*"DEPTH II — THE FLOOR BELOW"*) with a
   low descend stinger, a tinted `DEPTH II` chip by the HUD timer, and a subtle
   arena ambient tint. Boon rolls skew rarer the deeper you are; boss waves at
   Depth III+ drop **two** Aspect relics; killing a boss at Depth N banks
   **N shards** on the spot (HUD blip, kept on death — attempts pay).
4. **Clearing Depth N:** victory banner *"DEPTH II CLEARED — DEPTH III
   UNLOCKED"* plus the clear's shard bonus; the records line gains
   **Deepest: II**; the **loadout × Depth victory grid** near the picker earns
   a badge in that cell; the loadout's weapon gains a **trim tint** for its
   deepest clear; the loadout banner gains a **title** ("DUELIST OF THE
   THIRD").
5. **The Reliquary:** a shard-priced shop section, hidden until the first
   victory — reroll/option-widening nodes plus **Forge** nodes that
   permanently add a new depth-themed Aspect to the relic drop pool. Deeper
   nodes are hidden until their Depth is cleared: the shop becomes a map of
   the descent. Lives in its own bordered panel on LoadoutScreen, separate
   from the gold branches (split 2026-07-12; see status block).

## The five Depths (first-guess numbers, calibrate by feel)

Numbers are authored per-Depth as absolute values (already compounded), not
stacked deltas — each `.tres` reads standalone. "Rarity +" is seconds added to
the boon-rarity clock (the 8B ramp reaches its late-game weights at 450s).

| Depth | Name | HP | Dmg | Rewards | Rarity + | Identity twist |
|---|---|---|---|---|---|---|
| I | THE FLOOR BELOW | ×1.3 | ×1.2 | ×1.25 | +60s | Elites from 3:00 (base 4:00) |
| II | THE PRESSING DARK | ×1.6 | ×1.4 | ×1.5 | +120s | Swarm counts ×1.25, alive cap +15 |
| III | THE TWIN COURT | ×2.0 | ×1.6 | ×1.8 | +180s | Second Juggernaut at 2:38; 2 elites alive, Aspect cap 3, double boss relics |
| IV | THE QUICKENING | ×2.5 | ×1.85 | ×2.2 | +240s | Telegraph windups ×0.85, spawn interval ×0.85, one pinned Legendary offer |
| V | THE REVENANT'S HOUR | ×3.1 | ×2.1 | ×2.6 | +300s | The Revenant stirs at 6:45 (−45s of build time) |

Notes baked into those choices:

- **Twin Juggernaut is offset by ~8s** (2:38, not 2:30) so the two wall-to-wall
  charges desync — simultaneous crossing charges in a corner would be
  undodgeable, staggered ones are a dance. The multi-boss wave plumbing
  (`RunDirector._alive_bosses`, relic-on-last-death) already handles this.
- **Depth V shortens the run** rather than lengthening it: 45 fewer seconds of
  compounding boons is a bigger handicap than it reads, and it makes the
  deepest Depth *feel* different (the finale hunts you before you're ready)
  instead of just bigger.
- Elite generosity scales down the depths (earlier window, 2 alive at III+,
  Aspect cap 3, double boss relics): Aspects are the tool the player is given
  to answer the HP curve.

## Reward economy

### Lane 1 — in-run juice

- **Rarity clock bonus:** `BoonScreen._roll_rarity_index(elapsed)` already
  lerps rarity weights over `RARITY_RAMP_DURATION` (450s). The Depth's
  `rarity_time_bonus` is added to `elapsed` at that one call site — Depth V
  starts rolling like minute 5. Zero new systems.
- **Pinned Legendary (Depth IV+):** once per run, the first boon screen after
  3:00 pins one card to Legendary (`pin_legendary` on the DepthData; a
  run-scoped flag in BoonScreen consumes it).
- **Double boss relics (Depth III+):** `boss_relic_count = 2` — the wave-clear
  path spawns two Aspect relics (two pick-1-of-2 moments). Spawning stays
  paused until the last relic is claimed; the second relic is skipped when
  `AspectPool.available()` runs dry. Weapon-unlock relics are unaffected
  (still one, still priority).

### Lane 2 — shards & the Reliquary

**Income — must scale with depth, or the easiest Depth becomes the optimal
farm:**

| Event | Shards |
|---|---|
| Boss kill at Depth N | **N** (banked immediately, kept on death/abandon) |
| Clearing Depth N | **+2×N** |

So a full Depth I clear = 5, Depth III = 15, Depth V = 25; a failed Depth IV
attempt that dropped two bosses still banks 8. Deeper is always better
shards-per-hour, and a loss still moves the needle — *"I died but I'm 4 shards
from the Twin Court forge"* is the sentence this system exists to produce.
Implementation: `RunDirector._track_boss` death hooks call
`MetaProgression.add_currency(&"shards", depth.level)`; the clear bonus lands
in `finish_victory`.

**The Reliquary (its own shop section, priced in shards):** nodes are
`UpgradeData` with two new fields — `currency` (default `&"gold"`; the shop
reads/charges that balance) and `requires_depth` (hidden until
`records.best_depth >= N`, same hide-entirely pattern as `requires_ability`).
Branch `&"reliquary"`, universal (`loadout = &""`), hidden until the first
victory.

**Node rule — option-shaped, never stat-shaped.** Raw power lives in the gold
trees; if shards sold +damage the branch would become homework for Surface
players and re-inflate the curves 8B just fixed. Nodes widen choice:

| Node | Effect | Cost | Gate |
|---|---|---|---|
| Second Thoughts | +1 free boon reroll per run | 5 | — (max 2) |
| Deep Cache | start each run with a magnet primed | 6 | — |
| Wider Fate | Aspect relics offer 3 choices | 10 | Depth II |
| Fourth Card | level-ups offer 4 boons | 14 | Depth III |
| Forge nodes | add one Aspect to the drop pool (below) | 12–20 | Depth N |

**Forge nodes — the capstones.** Each is a one-time purchase
(`max_level = 1`) whose `grants_ability` sets a persistent flag (flows through
`MetaProgression.unlocked_abilities` → `player.has_ability()`, exactly like
weapon unlocks); the forged Aspect is a normal `BoonData` in the Aspect
registry gated by `requires_any_ability = [that flag]`. **Forging adds the
Aspect to the relic pool — it never auto-equips.** The pick-1-of-2 draft is
the best moment Aspects have; what you buy is *possibility*, and it refreshes
the ~13-Aspect pool for exactly the veterans who've seen everything.

Pairing rule: the forge for a Depth's themed Aspect requires clearing that
Depth (`requires_depth = N`) — you earn the right to buy the thing in the same
place you earned the money. Ship scope: **one universal forge (Depth I) + two
loadout-themed forges (Depth II–III)**, themes drawn from the Depth names
(Twin Court → a twin/echo mechanic, etc.); the remaining slots are authored
later — the structure is the feature, the pool can grow.

#### Forge wave 2 — shipped 2026-07-12 (jam outcome 2026-07-11)

Brings every loadout to 3 forged Aspects and universals to 5. Design rules the
jam settled on: rewire a verb or add a decision, never a flat stat or an RNG
proc; don't collide with the base pool (burning ground = Scorched Earth, bolt
chaining = Split Shot, mana-on-kill = redundant beside the 8-mana bolt
generator); don't add more *sources* of control (the pool's most saturated
axis) — pay existing control off instead (Cold Blood). Execute thresholds and
windup dampeners were considered and rejected (chaff dies in 1–2 hits; not
rewarding). Prices extend the gate ladder: I=12 II=16 III=20 IV=25 V=30.

| Aspect | Slot | Gate | ◆ | Effect |
|---|---|---|---|---|
| THE PATIENT DARK | sword | II | 16 | ~6s without taking damage primes your next swing as a full riposte (all riposte boons apply; Crescendo can chain off it, Twin Court echoes it) |
| THE VANISHING STAIR | sword | IV | 25 | Riposte kills instantly refund a blink charge |
| THE OPEN GRAVE | hammer | III | 20 | During Crashing Leap's descent, enemies are dragged toward the landing marker — the grave opens before you land |
| HOLLOW EARTH | hammer | IV | 25 | Enemies killed by a Seismic wave erupt a 0.5× shockwave from where they fall (single generation, no cascade) |
| THE DEEP DRAUGHT | staff | I | 12 | Hold the Fireball cast to overcharge: up to 2× mana cost for up-to-2× blast size and damage |
| THE DROWNED VEIL | staff | II | 16 | Damage drains mana before health (~2 mana per 1 damage; remainder spills to HP when dry) |
| THE WAITING COLD | staff | III | 20 | Frost Nova plants a rune at your feet (~0.5s arm) that detonates at 1.5× when trodden on, auto-firing after ~6s; nova boons apply |
| DEAD WEIGHT | universal | I | 12 | Overkill damage carries to the nearest enemy (~4m) and keeps chaining until the surplus is spent |
| THE UNCLOSED WOUND | universal | III | 20 | Hits open wounds: ~30% of damage dealt bleeds over 4s, stacking |
| COLD BLOOD | universal | IV | 25 | Held enemies — staggered, stunned, slowed, or chilled — take 1.5× damage |
| THE REVENANT'S HOUR | universal | V | 30 | Every boss horn restores you fully: health, mana, cooldowns, charges |

Gate spread including the shipped three: I×3 · II×3 · III×4 · IV×3 · V×1 — the
shop stays dense at the foot and V keeps a single crown.

Implementation notes (the non-obvious hooks):

- **Patient Dark:** run-scoped timer in `player.gd` reusing the
  riposte-primed swing path; resets when the player takes damage.
- **Vanishing Stair:** riposte-kill attribution already exists (Crescendo's
  path); refund lands on the 8C dash-charge resource.
- **Open Grave:** Implosion-style pull force toward the landing marker,
  applied only during the crash phase.
- **Hollow Earth:** wave-kill attribution → spawn a 0.5× `GroundShockwave` at
  the corpse; generation flag per the Mass Driver/Shatterflux stance.
- **Deep Draught:** press/release split on the fireball input; cost/blast/
  damage scale with held fraction.
- **Drowned Veil:** intercept in `Player.mitigate_hit` before HP applies;
  flash the mana bar on absorb. Deliberate tension with Blood Pact (both
  spend the same pool) and Arcane Surge (hits starve the ≥80% threshold).
- **Waiting Cold:** placed Area3D + GroundTelegraph decal; enemies already in
  range when it arms trigger it, preserving panic-button use.
- **Dead Weight:** on-kill surplus = damage − remaining HP → nearest enemy;
  the chain is strictly bounded by the original surplus (self-limiting).
- **Unclosed Wound:** needs a small ticking-stack DoT tracker on `EnemyBase`
  (reusable infra — future burn/poison rides it). Bleed ticks count as player
  damage (vampire, Dead Weight) but must not re-open wounds (no recursion).
- **Cold Blood:** status check in the enemy damage path against states that
  already exist. Watch item: a universal 1.5× is the strongest raw multiplier
  in the pool — if it playtests as a must-pick, trim to 1.35× before
  narrowing the status list.
- **Revenant's Hour:** RunDirector's boss-wave start hook, finale included.

One real plumbing gap (verified): `AspectPool.available()`
(`core/aspect_pool.gd:19`) filters by owned-flag and `requires_weapon` but
never checks `requires_any_ability` — the level-up boon screen does
(`boon_screen.gd:152`), the Aspect pool doesn't. Forged Aspects need that
~6-line check mirrored into the pool; without it they'd appear before being
forged.

### Lane 3 — badges, trim, titles (first clears; no gold)

- **Grid badges:** each loadout × Depth cell renders cleared/uncleared from
  `records.depth_wins` — no new save data.
- **Weapon trim:** each weapon scene gains a small emissive trim mesh;
  `weapon.gd` tints it on mount from that loadout's deepest clear (one color
  per Depth, themed to the Depth names). Trim-as-tier is already established
  visual language (the Revenant's teal TrimRing); a missing trim mesh is a
  no-op so untrimmed test scenes stay valid.
- **Titles:** the death-screen loadout banner gains a line — "DUELIST OF THE
  THIRD" — from the same deepest-clear lookup. Display-only.

## Architecture

### New: `core/depth_data.gd` (`class_name DepthData extends Resource`)

```gdscript
@export var level := 1
@export var display_name := ""          # "THE FLOOR BELOW"
@export var hp_mult := 1.0              # on top of WaveTable.hp_mult_at
@export var dmg_mult := 1.0
@export var reward_mult := 1.0          # gold AND xp (see tuning risks)
@export var interval_mult := 1.0        # scales spawn_interval_at output
@export var alive_cap_bonus := 0
@export var swarm_count_mult := 1.0     # repeating events only, not bosses
@export var elite_min_elapsed := -1.0   # -1 = Spawner default (240s)
@export var elite_max_alive := 1
@export var aspect_elite_cap := 2       # RunDirector.ASPECT_ELITE_CAP override
@export var boss_relic_count := 1       # Aspect relics per cleared boss wave
@export var rarity_time_bonus := 0.0    # seconds added to the boon-rarity clock
@export var pin_legendary := false      # one pinned Legendary offer per run
@export var windup_mult := 1.0          # enemy telegraph time scale, ≥0.85
@export var finale_time_shift := 0.0    # seconds; negative = Revenant earlier
@export var extra_events: Array[WaveEvent] = []  # e.g. the twin Juggernaut
@export var ambient_tint := Color.WHITE # arena mood shift, subtle
```

Plus `core/depth_registry.gd` (`depths: Array[DepthData]`, ordered) and
`data/depths/depth_1.tres … depth_5.tres + registry.tres`.

`extra_events` is the affix escape hatch: rather than affix flags with bespoke
code, a Depth schedules additional `WaveEvent`s (the twin Juggernaut is just a
one-shot boss event at 158s). Anything the WaveTable can express, a Depth can
add — future Depths get identity for free.

### Consumption points (no `WaveTable` mutation)

- **`Spawner`** gains `var depth: DepthData` (null = Surface, all code paths
  treat null as 1.0/default — Surface runs are byte-identical to today):
  - `spawn_enemy` (`spawner.gd:81`): multiply `hp_mult_at/dmg_mult_at/
    reward_mult_at` by the Depth's mults. This covers pool spawns, scheduled
    events, *and* death-spawned Broodlings (children inherit the parent's
    mults in `EnemyBase._spawn_death_spawns`).
  - `tick`: `interval_mult` on the spawn timer, `alive_cap_bonus` on the cap.
  - `_should_make_elite`: `elite_min_elapsed` override; `_elite_alive()`
    becomes a count checked against `elite_max_alive`.
- **`RunDirector`**:
  - `_ready`: resolve `MetaProgression.get_selected_depth_data()`, hand it to
    the spawner, emit the announcement.
  - `_fire_due_events` (`run_director.gd:90`): iterate a **local combined
    array** (`table.events + depth.extra_events`) instead of `table.events`;
    apply `swarm_count_mult` to events with `repeat_every > 0`; apply
    `finale_time_shift` when initializing the clock of events whose enemy is
    tagged `&"finale"`.
  - Boss death hooks bank `depth.level` shards; `finish_victory` adds the
    2×N clear bonus before `_final_stats`.
  - `_on_boss_wave_cleared`: spawn `boss_relic_count` Aspect relics (pool
    permitting); spawn-resume waits for the last claim.
  - `ASPECT_ELITE_CAP` reads the Depth's `aspect_elite_cap`.
  - `_final_stats`: add `stats["depth"]`.
- **`BoonScreen`**: `rarity_time_bonus` added to `elapsed` at the
  `_roll_rarity_index` call site; `pin_legendary` consumed by a run-scoped
  once-flag (first boon screen past 3:00).
- **`EnemyBase`**: `windup_mult` lands as a run-scoped static
  (`EnemyBase.depth_time_scale`, the same pattern as `EnemyBase.alive`),
  applied where `data.windup_time` is read. RunDirector sets it in `_ready`
  **and resets it on Surface runs** — statics outlive the run scene.
- **`AspectPool.available()`**: mirror the `requires_any_ability` check from
  `boon_screen._is_offerable` (forged-Aspect gate; see Lane 2).
- **Arena tint**: RunDirector nudges the `WorldEnvironment` ambient toward
  `ambient_tint` on run start. Display-only.

### `MetaProgression`

- `selected_depth: int` persisted beside `selected_weapon` (top-level save
  key, default 0).
- `get_selected_depth_data() -> DepthData`: validates like
  `get_selected_weapon()` — clamps to `[0, min(best_depth + 1, authored max)]`,
  returns null for Surface. An edited save can't select a locked Depth.
- **Shards are just `currencies[&"shards"]`** — the id-keyed hook needs no
  changes; the balance persists with the existing save write.
- `records` gains (additive, String keys):
  - `best_depth` — deepest Depth cleared (int).
  - `depth_wins` — `{ "1": { "fastest": secs, "loadouts": ["sword_and_shield", …] } }`
    — powers the grid, badges, trim, titles, and per-Depth fastest.
- `record_run()`: on `victory` with `stats.depth > 0`, update both; append
  `"best_depth"` / `"depth_fastest_N"` to the returned fresh-records list so
  the death screen's existing NEW BEST badge machinery just works. The global
  `fastest_victory` / `victories` records stay depth-agnostic (a deep win is
  still a win).

### `UpgradeData` (two additive fields)

- `currency: StringName = &"gold"` — the shop charges/reads this balance and
  shows it beside the branch header when it isn't gold.
- `requires_depth: int = 0` — hidden from the shop until
  `records.best_depth >= N` (hide-entirely, same as `requires_ability`).

Reliquary nodes and forge nodes are plain registry entries with these fields
set; the existing tree renderer needs only the currency label and the new
hide check.

### UI

- **`ui/death_screen.gd`** (all code-built, no scene edits — house pattern):
  - Depth picker row below the loadout picker, hidden until
    `records.victories ≥ 1`. Buttons `SURFACE, I … deepest+1`; locked Depths
    beyond that are not shown (no tease-noise).
  - Victory banner variants: first win (*"THE WAY DOWN OPENS…"*), Depth clear
    (*"DEPTH N CLEARED — DEPTH N+1 UNLOCKED"*).
  - Records line gains `Deepest: N`.
  - Loadout × Depth badge grid, tinted with `LOADOUT_THEMES`.
  - Reliquary branch column (shard balance in header) + title line under the
    loadout banner.
- **HUD**: `DEPTH N` chip near the run timer; shard blip on boss kill (reuses
  the pickup-counter pattern; no new banner system).
- **SFX**: one new `SfxFactory` cue — a low descend stinger on depth-run start
  (low fundamental, per the synth-pitch rule; differentiates by timbre from
  the boss horn). Shard pickup reuses an existing low blip at reduced rate.

## Milestones

Each milestone lands runtime-verified headless (house rule), Surface runs
regression-checked at every step.

- **M1 — Core plumbing.** `DepthData`/`DepthRegistry` + 5 authored `.tres`;
  `MetaProgression` selection/validation/records; Spawner + RunDirector consume
  the numeric fields; `stats["depth"]`; unlock-on-victory. `test/DepthSmoke.tscn`.
- **M2 — Surfacing.** Death-screen picker + victory banners + records line +
  HUD chip + announcement + descend stinger. The system is now *felt*.
- **M3 — Identity twists & juice.** `extra_events` (twin Juggernaut),
  `windup_mult` static, `finale_time_shift`, elite overrides, ambient tint,
  **rarity clock bonus, pinned Legendary, double boss relics**. Depths gain
  their signatures and their generosity in the same pass — they must be tuned
  together.
- **M4 — Status lane.** Loadout × Depth badge grid, per-Depth fastest with NEW
  BEST integration, weapon trim, titles.
- **M5 — Shards & the Reliquary.** Shard banking (boss kills + clear bonus),
  `UpgradeData.currency`/`requires_depth`, the Reliquary branch (4 QoL nodes),
  the `AspectPool` gate fix, and 3 forge nodes + their forged `BoonData`
  Aspects (1 universal, 2 loadout-themed).
- **M6 — Balance pass.** Play each Depth per loadout; tune the difficulty
  table *against* the juice lane (they move together — see risks); sweep docs
  + the PLAN.md §5 row.

## Verification

`test/depth_smoke.gd` (pattern of `recap_smoke.gd`): fabricate a save with
`victories = 1`, select Depth 1 → boot Arena headless → assert a spawned
enemy's max HP equals `data.max_health × hp_mult_at(t) × depth.hp_mult` and its
reward mult carries the Depth factor → kill a boss → assert
`currencies.shards` grew by the Depth level → fake the finale kill → assert
`records.best_depth == 1`, `depth_wins["1"]` recorded with the loadout, the
clear bonus banked, and `new_records` carries `"best_depth"` → grant a forge
flag → assert the forged Aspect now appears in `AspectPool.available()` (and
did not before) → assert a `requires_depth = 3` node stays hidden → reload
save, assert `selected_depth` round-trips and a locked selection clamps. Then
a Surface control run asserts today's numbers exactly (null-depth regression).
Existing harnesses (`RecapSmoke`, `EnemySmoke`, `AspectSmoke`) must still pass.
Run: `--headless res://test/DepthSmoke.tscn --quit-after 900`.

## Tuning risks / levers

- **Difficulty and juice must be tuned as one dial.** The rarity bonus, extra
  relics, and XP-side of `reward_mult` all push the player's power *up* at
  depth; the HP/Dmg table assumes that lift. If Depth wins feel free, the
  order of levers is: split `reward_mult` into `gold_mult`/`xp_mult` and hold
  XP flat → trim the rarity bonus → only then raise enemy HP. Never nerf the
  juice lane first — it's the pitch.
- **Shard faucet:** boss-kill income means quit-after-boss farming banks
  shards without finishing runs. That's identical to dying (attempts pay by
  design), but if shard velocity outruns the node prices, raise forge prices
  before touching income — early QoL nodes being reachable fast is what makes
  the branch feel alive.
- **Option-shaped creep:** Fourth Card and Wider Fate widen RNG, which is
  power. If they prove must-buys that trivialize Surface builds, gate them one
  Depth deeper rather than nerfing — scarcity is the lever, not strength.
- **Windup compression vs the Duelist:** faster telegraphs shrink parry setup
  time and hit the parry-riposte loadout hardest. Floor `windup_mult` at 0.85
  and exempt nothing initially; if Depth IV playtests as Duelist-hostile,
  exempt boss signature attacks before raising the floor.
- **Depth V's early finale** is a bigger nerf than it reads (compounding boon
  loss). If it's a wall, bump Depth V's rarity bonus or shard payout before
  moving the time back — the identity is worth protecting.
- **Depth I difficulty jump:** a first-time winner has a proven build; ×1.3 HP
  is deliberately gentle so Depth I converts in the same session. If first-win
  players bounce off Depth I, soften Depth I only — the ladder's foot matters
  more than its head.

## Files touched

| File | Change |
|---|---|
| `core/depth_data.gd`, `core/depth_registry.gd` | **new** — Depth as data |
| `data/depths/*.tres` (6) | **new** — 5 Depths + registry |
| `autoload/meta_progression.gd` | `selected_depth`, validation, records keys, `record_run` depth handling |
| `core/upgrade_data.gd` | `currency` + `requires_depth` fields |
| `core/aspect_pool.gd` | `requires_any_ability` check (forged-Aspect gate) |
| `data/upgrades/*.tres` | **new** — Reliquary QoL + forge nodes |
| `data/boons/aspects/*.tres` | **new** — 3 forged Aspects (flag-gated) |
| `systems/spawner.gd` | `depth` field folded into mults/caps/elite gate |
| `systems/run_director.gd` | combined event array, swarm/finale/aspect-cap overrides, shard banking, relic count, stats, tint, announcement |
| `actors/enemies/enemy_base.gd` | `depth_time_scale` static on windup reads |
| `ui/boon_screen.gd` | rarity clock bonus + pinned Legendary |
| `ui/death_screen.gd` | picker, banners, records line, badge grid, Reliquary branch, titles |
| `ui/HUD` script | depth chip + shard blip |
| `weapons/weapon.gd` + weapon scenes | trim mesh + deepest-clear tint |
| `core/sfx_factory.gd` | descend stinger |
| `test/depth_smoke.gd` + `DepthSmoke.tscn` | **new** — headless harness |
| `docs/DEPTHS.md`, `PLAN.md` | this doc; §5 row at ship time |

## Non-goals (this pass)

- **Endless / infinite Depth scaling** — authored Depths only; if the ladder
  proves out, Depth 6+ is a data add, and a formula-generated tail can come
  later without touching this design.
- **The full forge set** — **done.** The original 3 forged Aspects plus the
  Forge wave 2 roster (11 more, see Lane 2) shipped 2026-07-12, bringing the
  Aspect registry to 26 and the forge tree to 14 capstones (I×3 · II×3 ·
  III×4 · IV×3 · V×1).
- **A prestige reset layer** — shards are a *depth-only earner*, not a reset
  mechanic; a true prestige loop (reset gold/upgrades for global multipliers)
  remains parked, and nothing here blocks it.
- **Run mutators / Omens, feats/achievement unlocks** — complementary systems
  from the loop analysis, not part of this.
