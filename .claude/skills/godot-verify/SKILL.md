---
name: godot-verify
description: Verify fable-game changes headlessly with Godot 4.7 — import, scene smoke-loads, and behavioral test harnesses. Use this whenever a GDScript, scene, or .tres change needs checking, before committing, when asked to run tests or smoke tests, or when a confusing "Identifier not declared" error appears after adding files. Do not guess at Godot CLI invocations for this repo — this skill has the exact working commands and the known false-positives.
---

# Verifying fable-game changes headlessly

## The engine binary

Always use the 4.7 console build, by full path:

```
& "C:\Program Files\Godot\Godot_v4.7-stable_win64_console.exe" <args>
```

Never glob `C:\Program Files\Godot\` for an exe — 4.3 sorts first and cannot
parse this project's typed dictionaries (`Dictionary[K, V]` is 4.4+), so it
reports fake syntax errors.

## The verification ladder

Run the cheapest step that answers the question; escalate only if needed.

**1. Import (always run first after adding files).** New scripts — especially
new `class_name` scripts — and new `.tres`/`.tscn` files are invisible until
the global class cache and import DB update. Skipping this makes every
referencing script fail with "Identifier not declared", which looks like a
real bug but is not.

```
& "C:\Program Files\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --import
```

**2. Scene smoke-load (parse + _ready check).** Loads a scene with autoloads
active. Exit code 0 and no `SCRIPT ERROR` on output means every script in the
dependency graph compiled and `_ready` ran.

```
& "C:\Program Files\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --quit-after 10 "res://levels/Arena.tscn"
```

**3. Behavioral harness (runtime logic check).** The `test/` scenes run as a
real main loop with autoloads live — they instantiate actors, tick physics
across frames, and assert on actual damage/state. This is what catches runtime
nil-derefs and logic bugs that a parse check cannot.

```
& "C:\Program Files\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --quit-after 900 "res://test/DepthSmoke.tscn"
```

Pass/fail convention: harnesses print `SMOKE OK ...` on success and
`SMOKE: FAIL — <reason>` per failed assert. Read the output for the OK line —
don't rely on exit code alone (a harness that crashes early can still exit 0).
A trailing "ObjectDB instances were leaked" warning is normal for these
throwaway scenes, not a failure.

| Harness | Covers |
|---|---|
| `test/AspectSmoke.tscn` | Aspect registry count + elite→relic→pick chain (has `EXPECTED_ASPECT_COUNT`) |
| `test/DepthSmoke.tscn` | Depth tiers, shards, Reliquary, Surface byte-identical control (~60 asserts) |
| `test/EnemySmoke.tscn` | Force-spawns new enemies via live spawner, Broodmother death-burst |
| `test/MobilitySmoke.tscn` | Per-loadout Shift verbs (charges / leap / levitate) |
| `test/RecapSmoke.tscn` | Death-screen recap + personal bests |

After a content or system change, run the harness that owns that system, plus
any harness whose asserted counts changed (see the add-content skill).

## Known false-positives — do not chase these

- **`--check-only -s <script>` lies.** It compiles without autoload singletons
  registered, so any reference to EventBus/GameManager/MetaProgression fails
  with "Identifier not found". Not a real error. Use a scene smoke-load instead.
- **`EnemyBase.PICKUP_SCENE` in bare harness runs.** A `preload` inside a
  globally-registered `class_name` returns a node-count-0 PackedScene when the
  scene isn't run as the main game — harness artifact, works in the real game.
  Loot-spawn paths can't be validated headlessly; don't assert on them.

## Writing a new throwaway harness

Model it on an existing `test/*_smoke.gd`. Gotchas that cost time before:

- A stand-in player hurtbox must set `collision_layer = 8` (the real player's
  layer; projectiles use `collision_mask = 9`) or Area3D projectile hits
  silently miss. Direct `hurtbox.receive_hit()` calls don't care about layers,
  but anything that actually flies does.
- `untyped_declaration` is an error project-wide, including test scripts: type
  every `for x: T in ...` and `var x: T = load(...).instantiate()`.
- Defer the body out of `_ready` (`_run.call_deferred()`) so the tree is fully
  inside the main loop before you start ticking.
