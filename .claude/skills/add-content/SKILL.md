---
name: add-content
description: Author new fable-game content — Aspects (relic boons), Reliquary forge nodes, level-up boons, and enemies. Use this whenever adding or retuning .tres content under data/, even for casual asks like "add a sword aspect", "next forge wave", or "new enemy type". It has the exact resource wiring, registry/harness-count bookkeeping, and the design rules settled in past jams, so read it before touching any content resource.
---

# Authoring fable-game content

All content is data-driven Resources under `data/`. Every content type follows
the same shape: author a `.tres`, append it to that type's `registry.tres`,
bump any harness count that asserts on pool size, then verify (see the
godot-verify skill). The bookkeeping is easy to half-do — a `.tres` that isn't
in its registry silently never appears in game, and a stale harness count
fails the next unrelated run.

Hand-editing `.tres` gotcha: `load_steps` in the header must equal the number
of `ext_resource` + `sub_resource` entries **plus one**, or the resource fails
to load.

## Design rules (jam-settled — apply to any new Aspect or boon)

- **Rewire a verb or add a decision.** Never a flat stat bump and never an RNG
  proc — those live in the base boon pool and in upgrades.
- **Check the base pool for collisions first** (`data/boons/*.tres`). Past
  catches: burning ground = Scorched Earth, bolt chaining = Split Shot,
  mana-on-kill is redundant beside the 8-mana bolt generator.
- **Don't add new sources of control** (stun/slow/chill/stagger — the pool's
  most saturated axis). Pay existing control off instead, the way Cold Blood
  does (1.5× damage vs held enemies).
- **Rejected patterns, don't re-propose:** execute thresholds (chaff already
  dies in 1–2 hits) and windup dampeners (not rewarding to feel).
- Unique boons use their `description` verbatim — write real flavor text.
  Regular boons auto-generate descriptions from modifiers; leave numbers out.

## Aspect (relic boon)

An Aspect is a plain `BoonData` in its own registry — the level-up boon screen
never sees it.

1. Author `data/boons/aspects/<id>.tres` (`BoonData`): `unique = true`,
   `grants_ability = &"<id>"` (the flag doubles as the taken-this-run
   tracker), `requires_weapon` for loadout-slotted aspects (empty =
   universal). A **forged** aspect additionally gates on its forge node:
   `requires_any_ability = [&"forge_<id>"]`.
2. Append it to `data/boons/aspects/registry.tres` (ext_resource + entry in
   the `boons` array; fix `load_steps`).
3. Implement the mechanic. House patterns: `AttackInfo.no_proc` marks derived
   hits that must not re-trigger on-hit effects; secondary shockwaves/echoes
   carry a single-generation flag (Mass Driver/Shatterflux stance) so nothing
   cascades.
4. Bump `EXPECTED_ASPECT_COUNT` in `test/aspect_smoke.gd`, then run
   AspectSmoke — and DepthSmoke if the aspect is forged.

## Reliquary forge node

A forge node is an `UpgradeData` whose only job is granting the
`forge_<aspect_id>` flag that unlocks its Aspect in the drop pool.

1. Author `data/upgrades/forge_<aspect_id>.tres` (`UpgradeData`):
   `max_level = 1`, `branch = &"reliquary"`, `currency = &"shards"`,
   `grants_ability = &"forge_<aspect_id>"`, `requires_depth = <gate>`.
2. Price follows the gate ladder — Depth I=12, II=16, III=20, IV=25, V=30
   shards. Keep the shop dense at the foot: Depth V holds a single crown, so
   justify any second V-gate node explicitly.
3. Description convention: "Add the <slot> Aspect NAME to the relic drop pool —
   <effect in prose>. Forged, never auto-equipped."
4. Append to `data/upgrades/registry.tres`; run DepthSmoke.

## Enemy

1. Author the scene in `actors/enemies/<Name>Enemy.tscn` (extend an existing
   enemy scene/script as the template) and `data/enemies/<id>.tres`
   (`EnemyData`) pointing at it.
2. Spawn integration is weight-driven, not code: add the EnemyData to the
   `enemies` array of `data/waves/default.tres`. Time-gate with
   `min_elapsed` + `weight_ramp_duration`; Depth tiers overlay these numbers
   at consumption points, so author Surface values only.
3. Death-burst spawners (Broodmother-style) use the `death_spawns` /
   `death_spawn_count` / frenzy fields — no custom code needed.
4. Add the new `.tres` path to `CANDIDATES` in `test/enemy_smoke.gd` and run
   EnemySmoke (it force-spawns regardless of time gates).

## After any content wave

- Run `--import` before any harness (new class_name scripts and .tres files
  are invisible until the caches update — see godot-verify).
- Update the owning doc's top status block in `docs/` (DEPTHS.md for
  aspects/forge, ENEMIES.md for enemies) with implementation deviations —
  that block is the project's changelog of record.
