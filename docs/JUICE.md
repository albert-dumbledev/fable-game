# Juice & Theme Pass — Plan

Goal: make the game *feel* great without changing its balance. Everything here is
presentation — where a change touches numbers (boss loot), the guardrail is stated
inline. Constraints that shape every choice below:

- **GL Compatibility renderer** (web is the target): no volumetric fog, no SSR/SSAO.
  Glow **is** supported (since 4.2) and is the single highest-leverage switch we're
  not using. Prefer `CPUParticles3D` over GPU particles for web reliability.
- **Zero audio assets** stays true — new cues come from `SfxFactory`, low-pitched
  fundamentals, differentiated by timbre per the existing sound design rules.
- **Perf budget**: 90 alive cap + hundreds of pickups already; all VFX must be
  pooled or fire-and-forget meshes/CPU particles, nothing per-enemy-per-frame.

Theme direction: **"dusk colosseum"** — a fighting pit at twilight. Dark blue-purple
sky, warm gold torchlight, emissive accents that pop once glow is on. Gold = reward,
orange = danger/fire, ice-blue = frost/stun. The UI adopts the same palette: dark
translucent panels, gold accents, warm parchment text.

---

## P1 — The big four (do these first)

### 1. Dash must *feel* fast — ✅ shipped 2026-07-04

Today: 0.12s velocity blink + 9° FOV punch + one synth cue (`player.gd::_begin_dash`).
It teleports competently but doesn't *rush*. Changes:

- **Speed readability comes from the floor, not the dash** — a flat untextured
  plane gives the eye nothing to track motion against. The floor pattern in §3 is
  half of this fix; do them together.
- **Radial speed-line overlay**: full-screen `ColorRect` + canvas shader on the HUD
  layer — anamorphic streaks from screen center, alpha driven by a `dash_intensity`
  uniform the player sets. In: 0.05s, out: 0.25s. (A `SCREEN_TEXTURE` radial blur is
  the deluxe version; streaks alone read 90% as fast and cost nothing.)
- **Stronger FOV punch** (+9 → +14) with a snappier curve: overshoot in the first
  40% of the dash, settle during the tail.
- **Departure/arrival marks**: small flattened `BlastVfx` ring at the start point,
  dust-puff ring at the end point, plus a ~0.1 trauma shake on arrival so the stop
  lands with weight.
- **Layered whoosh**: keep `dash` cue, add a low filtered-noise sweep under it
  (falling pitch, fundamentals well under 1.5 kHz).
- **Viewmodel kick**: tilt the weapon mount ~4° into the dash direction and recover
  with an ease-back — sells body movement without touching aim.

No mechanical changes: distance, duration, cooldown, i-frames all stay.

### 2. Boss deaths explode with waves of loot — ✅ shipped 2026-07-04

Today: the Juggernaut dies exactly like a chaser — shrink to 5% in 0.22s, ≤8 gold
+ ≤8 XP pieces (`enemy_base.gd::_on_died`, `MAX_PICKUP_PIECES`). 100 gold in 8
lumps is a payout, not a spectacle. Changes:

- **Boss death sequence** (trigger: `data.tags.has(&"boss")` — override `_on_died`
  in `BossEnemy` or branch in `EnemyBase`):
  1. ~0.5s of real-time slow-mo (`Engine.time_scale` ≈ 0.3, restored by an
     `ignore_time_scale` timer) while the boss flashes white and swells.
  2. Death burst: large gold `BlastVfx` ring + CPU-particle shards in the boss's
     color + heavy shake + a long low death-rumble cue (new `SfxFactory` sound).
  3. **Three radial loot waves** over ~1.2s: rings of pickups ejected outward at
     staggered delays (e.g. 12 + 12 + 12 pieces), higher burst velocity than normal
     drops so they fountain visibly. A `boss_pickup_pieces` cap of ~36 replaces the
     8-piece cap for boss-tagged enemies only.
- **Balance guardrail**: total reward value is unchanged — same `gold_reward` /
  `xp_reward`, split into more, smaller pieces. If we want a celebration bonus,
  cap it at +20% and put it in `juggernaut.tres` where it's visible, not in code.
- **Don't lose the payout**: boss pickups get a longer `LIFETIME` (30s → 60s) and a
  slightly larger magnet radius so the reward isn't stranded mid-swarm.

### 3. Arena spruce-up (keep the fight space flat) — ✅ shipped 2026-07-03, tuning pending playtest

Hard constraint: enemies steer straight-line (no navmesh) and the boss charge needs
wall-to-wall clearance — **nothing solid inside the 40×40 play area**. All
decoration is visual, at the perimeter, or outside the walls.

- **Floor**: replace the flat albedo with a simple shader or mesh pattern — large
  stone tiles with darker grout lines and a subtle emissive rune circle at arena
  center. Contrast lines on the ground are what make movement and dashing *read*
  fast; this doubles as the dash fix.
- **Walls**: keep the colliders, dress the meshes — pillar segments every ~8 m,
  torch sconces at the corners and midpoints: emissive cube flame + flickering
  low-energy `OmniLight3D` (8 lights total, cheap in Compatibility).
- **Beyond the walls**: silhouette geometry outside the play space — tiered
  colosseum ring or jagged rock spires against the sky, unlit dark material. Pure
  backdrop, no collision.
- **Sky & light**: `ProceduralSkyMaterial` tuned to twilight (deep blue top, ember
  horizon), sun lowered to a long warm angle, fog (depth fog, Compatibility-safe —
  verify on the web export) for depth, and a large emissive moon disc billboard.
- **WorldEnvironment**: enable **glow** (the single biggest visual upgrade —
  pickups, fireballs, telegraph flashes, and torches all start popping), mild
  contrast/saturation adjustment, slightly cool ambient with warm key light.

### 4. Hit-pause (the missing combat feel lever) — ✅ shipped 2026-07-04

Already named in PLAN.md §6 as the remaining melee-feel lever. One tiny system:
`FreezeFrame.hit_pause(duration)` (autoload or static) sets `Engine.time_scale`
≈ 0.05 and restores it via an `ignore_time_scale` timer; calls coalesce (never
stack pauses).

- Sword hit: 40 ms. Hammer slam connect: 70 ms. Perfect block: 90 ms + the existing
  flash. Boss death: handled by the slow-mo in §2.
- Guard: skip when a pause is already active so swarm cleaves don't stutter-lock.

---

## P2 — Theme & UI pass

### 5. One Theme resource for the whole UI — ✅ shipped 2026-07-04

There is currently **no theme** — every screen is default Godot gray. Create
`ui/theme.tres` (dark translucent panels, gold accent `#d4a942`-ish, parchment
text) plus one bundled open-license display font (single small `.ttf` — the
asset-free rule was about audio; one font is worth it). Apply at the project level
so the main menu, pause, settings, death screen, boon screen, and shop all restyle
at once.

### 6. HUD juice — ✅ shipped 2026-07-04

- **Health bar**: color lerps green→amber→red with missing health; **ghost-damage
  segment** (white chunk that lingers ~0.4s then drains) so hits read at a glance;
  pulsing red edge vignette under 25% HP (heartbeat cue, replaces nothing).
- **Gold/kill counters**: icon + animated count-up ticker instead of instant text
  swap; gold label does a small scale-pop on pickup (rate-limited like the SFX).
- **XP bar**: emissive-looking fill, flash + fill-drain animation on level-up.
- **Boss bar**: name plate styling, thicker bar, brief white flash on boss damage.
- **Announcements** (`SWARM`, boss banners): scale-in punch + chromatic gold
  outline instead of the current fade-only label.
- **Skill slots**: radial or vertical cooldown sweep is already there — add a
  "ready" ping (flash + tick cue) the frame a cooldown completes.

### 7. Kill & combat readability polish — ✅ shipped 2026-07-04

- **Enemy deaths**: keep the shrink, add a matching-color CPU-particle shard burst
  and a brief floor decal-style ring. Bosses excepted (§2).
- **Damage numbers**: scale font with damage tiers, gold color for kill-blows.
- **Projectiles & spells**: fireball gets an emissive trail (CPU particles);
  frost nova leaves a fading frost ring on the ground; Scorched Earth patches get
  ember particles. All glow-lit for free once §3 lands.
- **Enemy telegraphs**: windup color shift stays, plus a thin emissive eye-flash —
  reads through a crowd better than body tint alone.

---

## P3 — Nice-to-haves — ◐ shipped 2026-07-04 except audio ducking

Shipped: menu backdrop, kill-streak ticker, pickup vacuum chord, reduced-flash
toggle. Remaining: low-HP audio ducking (needs a player-health relay signal
into AudioManager; do it alongside the next audio pass).

- **Main menu backdrop**: slow orbiting camera over the dressed arena instead of a
  flat panel — the theme sells itself before the first run.
- **Kill-streak ticker**: small combo counter that decays in ~3s; purely cosmetic,
  feeds a rising-pitch-capped (≤1.5 kHz) blip family.
- **Low-HP audio ducking**: below 25% HP, duck SFX slightly and add a muffled
  heartbeat loop.
- **Pickup vacuum moment**: when 20+ pickups magnet simultaneously, one shimmer
  chord instead of 20 blips (extends the existing per-id rate limiting).
- **Settings**: add a "reduced flash" toggle next to screen shake (slow-mo, speed
  lines, and freeze frames all respect it).

---

## Explicitly not doing

- No new mechanics disguised as juice (no dash buffs, no loot value inflation
  beyond the capped, data-visible boss bonus).
- No obstacles inside the arena (AI has no navmesh; boss charge assumes clear
  lanes).
- No GPU particles, volumetric fog, or SSR (Compatibility/web).
- No recorded audio assets.

## Acceptance criteria

1. Dashing produces an audible+visible whoosh, speed lines, and ground marks; a
   blindfold test ("did I dash or teleport?") answers *dash*.
2. Boss kill is a 2-second event: slow-mo, burst, three loot waves — and the
   collected total matches the old payout within the stated bonus cap.
3. The arena screenshot no longer reads as graybox: lit torches, patterned floor,
   silhouetted backdrop, glow on emissives.
4. Every UI screen shares the palette; no default-gray Godot controls remain.
5. Web export holds 60 fps during a swarm event with a boss alive and a boss-death
   loot fountain on screen.

## Suggested order

1. §3 WorldEnvironment + glow + floor pattern (unlocks visual payoff for everything else)
2. §1 dash feel → §4 hit-pause (small, immediate feel wins)
3. §2 boss death sequence
4. §5 theme resource → §6 HUD juice
5. §7 polish, then P3 as appetite allows

Each step is independently shippable and testable via the headless smoke-load.

---

## Web performance (2026-07)

The graphics settings (Settings autoload → Graphics section of the settings
panel) exist primarily for the web export: render scale, shadows, glow,
torch lights, effect density, damage numbers. Web first-run defaults to the
**medium** preset; desktop defaults to high. Combat VFX are pooled in
`core/vfx_pool.gd` — add new fire-and-forget effects there, not as
per-spawn mesh+material allocations.

Export checklist for the web build:

- **Export with the release template.** A debug-template WASM runs
  dramatically slower and is the most common cause of "web is laggy".
  (`index.wasm` size only affects load time, not runtime.)
- `project.godot` already caps the directional shadow map at 2048 with
  cheaper filtering via `.web` feature overrides.
