# Gameplay Telemetry System (Phase 10)

## Context

We want data to drive rebalancing: how far runs get, run stats (kills/gold/level), loadout upgrade state, what kills players, boon popularity (by loadout + aggregate), and which boons correlate with deeper/more successful runs. Nothing is instrumented today — no networking code, no install ID, no run history. The game ships as a web export (COOP/COEP cross-origin-isolated page), so the collector must speak CORS and handle tab-close data loss.

**Decisions made with user:** Node (Fastify) + SQLite (better-sqlite3) collector on a user-hosted VPS behind Caddy, living in this repo under `server/`; canned SQL queries + a tiny basic-auth stats page served by the same service; telemetry ON by default with a "Share anonymous gameplay data" toggle in Settings and a one-time first-launch notice. Anonymous random install ID, no PII.

## Design at a glance

One workhorse event — **`run_summary`**, sent once per run at `GameManager.end_run()` time — carries everything (runs are ≤7:30, so nothing needs mid-run streaming). Boon *offers* are folded into the summary so pick-rate is computable. A JS `sendBeacon` mirror rescues tab-closed runs as `outcome: "disconnect"`; an offline queue in `user://` retries failed uploads next session. Server dedups by `run_id` and keeps raw JSON for schema evolution.

Key existing seams (verified):
- `GameManager.end_run(stats)` ([autoload/game_manager.gd](autoload/game_manager.gd)) — single choke point for death/victory/abandon; stats dict has `time`, `kills`, `gold`, optional `victory`/`abandoned`.
- EventBus signals already sufficient for most of the record: `run_started`, `run_ended(stats)`, `enemy_killed(enemy_data, position)`, `boss_spawned(boss)`, `level_up(new_level)`, `pickup_collected(kind, value)`.
- Damage attribution: `AttackInfo.source` is always the attacking `EnemyBase` (even for projectiles — verified across spitter/caster/bosses), but `player_damaged` drops it. One new signal fixes this.
- Enemy IDs: `EnemyData` has no `id` field — derive from `data.resource_path.get_file().get_basename()` (`chaser`, `spitter`, `juggernaut`, `revenant`, …). Zero `.tres` edits.
- `game_version`: add `config/version` to `project.godot`; bump per web deploy.

## 1. Event schema (v1)

Envelope: `POST /v1/ingest` with `{"token": "<non-secret>", "events": [...]}`. Token also in body because sendBeacon can't set headers.

`run_summary` fields:

```json
{
  "type": "run_summary", "schema_version": 1,
  "run_id": "uuid", "install_id": "uuid", "session_id": "uuid",
  "client_ts": 1783102934123, "game_version": "0.10.0", "platform": "web",

  "outcome": "death | victory | abandon | disconnect",
  "duration_s": 312.4, "level": 14, "levelups": 14,
  "kills": 233, "gold": 410, "xp_collected": 1290,

  "loadout": "warhammer",
  "meta": { "upgrade_levels": {"damage": 4}, "total_spent_gold": 830,
            "unlocked_abilities": ["..."] },

  "boons":  [ {"id": "wide_tremor", "rarity": "RARE", "mult": 1.4, "level": 3, "t": 83.2} ],
  "offers": [ {"level": 3, "t": 81.0, "action": "pick|skip|reroll", "picked": "wide_tremor",
               "offered": [{"id": "...", "rarity": "..."}]} ],

  "kills_by_enemy": { "chaser": 120 },
  "damage_taken":   { "chaser": {"dmg": 84.0, "hits": 7} },
  "killer_enemy": "caster",
  "boss_events": [ {"enemy": "juggernaut", "spawned_t": 150.1, "killed_t": 171.2} ],

  "aspects": [],
  "perf": { "fps_avg": 52.1, "fps_p5": 31.0, "render_scale": 0.85, "preset": "medium" }
}
```

- Boss-stage funnel + time-to-boss-kill derive from `boss_events` (2:30/5:00/7:30 clock). All `t` values are RunDirector `elapsed` (game time, pause-frozen).
- `aspects: []` reserved for Phase 9 relics — additive, no schema change later.
- `perf` optional; sampled FPS every 5s (avg + p5) plus render_scale/preset.
- Evolution rule: additive fields only, bump `schema_version`, server keeps `raw`.

## 2. Godot client

### New autoload `autoload/telemetry.gd` (`Telemetry`)
Registered after `Settings` in project.godot; `PROCESS_MODE_ALWAYS`. Contains:
- `install_id` (UUIDv4 via `Crypto.generate_random_bytes(16)`, stored once in `user://telemetry.json` alongside `notice_shown`), `session_id` per boot, `run_id` per run.
- Inner `class RunRecord extends RefCounted` — accumulator with `to_payload(outcome, stats)`; snapshots `MetaProgression.selected_weapon`, `upgrade_levels`, computes `total_spent_gold` from the upgrade registry's cost curve.
- `HTTPRequest` child (one in-flight POST, 10s timeout), retry `Timer` (backoff 30s×2ⁿ, cap 15min), perf-sample `Timer` (5s).
- Endpoint: `DEFAULT_ENDPOINT` const, overridable via `OS.get_environment("FABLE_TELEMETRY_URL")` for local dev/tests.
- Offline queue `user://telemetry_queue.json` (`{"v":1, "events":[...]}`), capped at 40 (drop oldest); flush on startup+3s, on `run_ended`, on retry timer; ≤10 events/POST; remove from queue only on HTTP 2xx.
- Signal wiring (all EventBus, no scene coupling): `run_started` → new record; `run_ended(stats)` → finalize+enqueue+flush; `enemy_killed` → kills_by_enemy, match pending boss_events `killed_t`; `boss_spawned` → append boss_events; `level_up` → level/levelups; `pickup_collected` → xp_collected; plus the two new signals below.
- Helper `enemy_id(data)` = resource-path basename, `"unknown"` fallback; `_elapsed()` reads the `&"run_director"` group node.

### Web tab-close rescue
On web only, `JavaScriptBridge.eval()` installs a `pagehide` listener that `navigator.sendBeacon`s `window.__fableTel.body` (token in body; string beacon posts `text/plain` = CORS-simple, no preflight at pagehide). Telemetry refreshes the snapshot (`outcome: "disconnect"`, current elapsed) on run start, each boss event/boon pick, and the 5s perf tick; clears it on `run_ended`. Server upsert rule resolves the beacon/real-summary race.

### Opt-out & consent
- `Settings.share_telemetry := true` + save/load lines in [autoload/settings.gd](autoload/settings.gd); `CheckButton` "Share anonymous gameplay data" in [ui/settings_panel.gd](ui/settings_panel.gd).
- First-launch notice: small code-built `CanvasLayer` (OK / Turn off) shown once in menu; records `notice_shown`.
- Gating at enqueue+send time; toggling off deletes the queue file and disables the JS beacon.

### Edits to existing files (complete list)
1. [autoload/event_bus.gd](autoload/event_bus.gd) — two new signals:
   - `signal player_hit(info: AttackInfo)` (full attribution; `player_damaged`/`player_died` untouched)
   - `signal boon_offer_resolved(ctx: Dictionary)` — `{level, t, action, picked, offered:[{id, rarity}]}`
2. [player.gd](actors/player/player.gd) `_on_damaged()` (~line 972) — one line: `EventBus.player_hit.emit(info)`.
3. [ui/boon_screen.gd](ui/boon_screen.gd) — store rolled offers in a field (`_populate()` currently inlines `_roll_offers()` in its for loop; capture to `_current_offers` first), then emit `boon_offer_resolved` in `_on_pick` (action "pick"), `_on_skip`, and `_on_reroll` after `try_spend` succeeds / before `_populate()` re-rolls. Rarity comes from `Offer.tag` (includes "UNIQUE"). ~15 lines.
4. [autoload/settings.gd](autoload/settings.gd) — `share_telemetry` var + persistence.
5. [ui/settings_panel.gd](ui/settings_panel.gd) — the toggle row.
6. `project.godot` — `config/version="0.10.0"`; `Telemetry` autoload after Settings.

Nothing changes in run_director.gd, game_manager.gd, health_component.gd, or death_screen.gd.

## 3. Server (`server/`)

```
server/
├─ package.json            # fastify, better-sqlite3, @fastify/{cors,rate-limit,basic-auth}, dotenv
├─ .env.example            # PORT, DB_PATH, INGEST_TOKEN, STATS_USER/PASS, ALLOWED_ORIGINS
├─ schema.sql              # idempotent DDL
├─ src/index.js            # bootstrap + --prune maintenance flag
├─ src/db.js               # WAL, schema, prepared statements
├─ src/ingest.js           # POST /v1/ingest
├─ src/stats_api.js        # GET /stats/api/:name (canned queries)
├─ queries/analysis.sql    # commented, sqlite3-CLI runnable
├─ public/stats.html       # single-file dashboard, no CDN deps
├─ Caddyfile.example
└─ README.md               # deploy runbook: systemd unit, nightly .backup cron
```

**Routes:** `POST /v1/ingest` (token header *or* body; accepts `application/json` and `text/plain` for beacons; ≤20 events, ≤128KB; rate-limit 30/min/IP) · `GET /healthz` · `GET /stats` + `GET /stats/api/:name?days=&version=&loadout=` behind basic auth.

**Validation:** JSON-schema envelope + per-event checks (outcome enum, duration 0–7200, strings ≤64 chars, dicts ≤40 keys, arrays ≤80 rows); unknown types dropped+counted, never 500.

**Schema:** `runs` table (one row per run: identity, outcome, duration, loadout, killer_enemy, derived `boss1/boss2/finale_killed_at`, `meta_upgrades`/`boons` as JSON columns, perf columns, `raw` JSON) + normalized child tables `run_kills(run_id, enemy, kills)`, `run_damage(run_id, enemy, damage, hits)`, `run_boon_offers(run_id, seq, slot, level, t, action, boon, rarity, picked)` for group-by queries. Indexes on game_version+received_at, loadout, enemy, boon.

**Dedup/upsert rule:** upsert by `run_id`; a `disconnect` row never overwrites a real outcome, a real outcome upgrades a `disconnect` row (child tables reinserted in the same transaction). Makes client retries and the beacon race harmless.

**CORS:** handled in Fastify (`@fastify/cors`, origin from `ALLOWED_ORIGINS`, default `*` — endpoint is anonymous by design), so dev and prod behave identically; Caddy just does TLS + reverse_proxy. Note: the game page's COOP/COEP isolation constrains embedded subresources, not fetch — Godot web `HTTPRequest` rides fetch and works with normal CORS.

**Retention:** ~2–4 KB/run. `--prune` clears `raw` older than 90 days + VACUUM; README documents nightly sqlite `.backup` cron.

## 4. Canned queries (`server/queries/analysis.sql`)

All version-taggable so rebalance patches are comparable:
1. **Boss-stage funnel** per version — % reaching/killing 2:30 boss, 5:00 boss, finale; victory %; quit %.
2. **Survival-time histogram** (30s buckets, deaths).
3. **What kills players** — killer_enemy share of deaths, partitioned by loadout.
4. **Damage pressure by enemy** — avg dmg/hits per run from `run_damage`.
5. **Boon pick rate** — `SUM(picked)/COUNT(*)` from `run_boon_offers`, by loadout and aggregate, `HAVING times_offered >= 20`.
6. **Boon lift** — avg duration / victory % with vs. without each boon, within loadout+version. *Written caveat in the file:* correlational; survivorship bias is structural (late boons imply long runs); mitigate with early-pick cohorts.
7. **Meta spend deciles vs outcome** (NTILE).
8–11. Kills/gold/level distributions per loadout; time-to-first-boss-kill trend; rarity mix early vs late; fps_p5 by graphics preset (web perf guardrail).

## 5. Stats page

`public/stats.html`: single file, vanilla JS + inline SVG bars (no CDN — works on a locked-down VPS), behind basic auth. Fetches `/stats/api/*` for: funnel, survival histogram, death causes, boon pick rates with loadout filter, boon lift (caveat printed above the table), spend deciles. Global days-back + version selectors.

## 6. Milestones

| M | Scope | Verify |
|---|---|---|
| **M1 — Client core** | telemetry.gd (ids, RunRecord from existing signals, queue, HTTP flush, env override), Settings toggle + panel row + first-launch notice, project.godot version/autoload, docs/TELEMETRY.md | New `test/telemetry_smoke.gd` + TscN (pattern of enemy_smoke.gd): boot Arena, kill an enemy, `abandon_run()`, assert queue file has one `run_summary` with `outcome=="abandon"`, kill/gold fields, UUID run_id. Headless: `--headless res://test/TelemetrySmoke.tscn --quit-after 900` |
| **M2 — Attribution & boons** | `player_hit` + emit; `boon_offer_resolved` + boon_screen instrumentation; RunRecord gains damage_taken/killer_enemy/kills_by_enemy/boss_events/offers | Extend smoke test: route an `AttackInfo` through the player hurtbox → assert damage_taken/killer_enemy; synthesize an offer ctx → assert round-trip |
| **M3 — Server** | Everything in §3 + queries/analysis.sql + Caddyfile + README | `cd server && npm i && npm test` (fixture batches incl. dedup + disconnect-upgrade). E2E: run server locally, `FABLE_TELEMETRY_URL=http://127.0.0.1:8787/v1/ingest`, run smoke test → assert queue drained; inspect rows via sqlite3 |
| **M4 — Web hardening** | pagehide beacon mirror, text/plain ingest, backoff polish, queue cap, opt-out purge | Local web export vs local server: close tab mid-run → `disconnect` row; finish run → row upgrades; toggle off → no traffic + queue deleted |
| **M5 — Stats page** | stats.html + /stats routes | Browse against M3-seeded DB; wrong password → 401 |
| **M6 — Polish & deploy** | perf sampling, `aspects` plumbing (Phase 9-ready), PLAN.md rows, deploy checklist, real `DEFAULT_ENDPOINT` | Smoke asserts perf present; deploy to VPS, confirm one real web run lands |

M1–M2 accumulate locally before any server exists; M3 is testable without the game. Server deployment (VPS, domain, Caddy) is the user's part — README.md is the handoff artifact.

## 7. Docs

- **docs/TELEMETRY.md** (new): goals, privacy stance (exactly what's collected, anonymous ID, toggle), schema v1 field-by-field, client architecture, server endpoints/deploy pointer, analysis guide (which query answers which balance question), schema-evolution rules, M1–M6.
- **PLAN.md**: §3.1 autoload row for `Telemetry`; §5 row "10. Telemetry & rebalance data → docs/TELEMETRY.md"; §6 risk bullets: privacy, beacon best-effort (treat abandon+disconnect as one funnel bucket), CORS misconfig silently zeroes web data (watch ingest volume post-deploy), additive-only schema.

## Open items (resolved during implementation, not blockers)

- Production endpoint URL / domain — placeholder const until the VPS exists (M6).
- Final web-hosting origin — determines whether to tighten `ALLOWED_ORIGINS` from `*` (fine either way given the anonymous token-deterred endpoint).