extends Node
## Global signal hub. Signals only — no logic, no state.
##
## Systems emit and connect through this bus so HUD, spawner, and progression
## never reference each other directly.

## Emitted when a run begins (player spawned, timer at zero).
signal run_started

## Emitted when the player dies and the run is over.
## `stats` is a Dictionary until RunStats exists (Phase 1).
signal run_ended(stats: Dictionary)

## Emitted whenever any enemy dies. `enemy_data` is the enemy's EnemyData resource.
@warning_ignore("unused_signal")
signal enemy_killed(enemy_data: Resource, position: Vector3)

## Emitted when the player takes damage (post-mitigation).
@warning_ignore("unused_signal")
signal player_damaged(amount: float)

## Emitted when the player's shield successfully blocks a hit.
@warning_ignore("unused_signal")
signal attack_blocked

## Emitted on a perfectly timed block (attacker stunned).
@warning_ignore("unused_signal")
signal perfect_block

## Emitted the moment the player's health reaches zero.
@warning_ignore("unused_signal")
signal player_died

## Emitted whenever a currency balance changes (kill rewards, shop purchases).
signal currency_changed(id: StringName, amount: int)

## Emitted whenever run XP changes. `required` is the threshold for the next level.
@warning_ignore("unused_signal")
signal xp_changed(current: int, required: int, level: int)

## Emitted each time the player levels up mid-run (triggers the boon choice).
@warning_ignore("unused_signal")
signal level_up(new_level: int)

## Emitted when the player collects a dropped pickup (&"gold", &"xp", ...).
@warning_ignore("unused_signal")
signal pickup_collected(kind: StringName, value: int)

## Emitted when a scheduled wave event with an announcement fires.
@warning_ignore("unused_signal")
signal wave_announcement(text: String)

## Emitted when a boss-tagged enemy spawns. `boss` is the EnemyBase node.
@warning_ignore("unused_signal")
signal boss_spawned(boss: Node)

## Emitted when the player collects a weapon-unlock relic. `ability` is the
## granted flag. Drives the claim screen and resumes boss-cleared spawning.
@warning_ignore("unused_signal")
signal unlock_claimed(ability: StringName)

## Emitted the moment the player's dash begins (drives screen feedback).
@warning_ignore("unused_signal")
signal player_dashed

## Emitted when the player triggers a spell they can't afford (mana too low),
## so the HUD can flash the mana bar.
@warning_ignore("unused_signal")
signal mana_cast_denied

## Emitted when the player walks onto an Aspect relic. No args — the AspectScreen
## does the pick-1-of-2 roll itself. Opening the screen is the whole payload.
@warning_ignore("unused_signal")
signal aspect_relic_claimed

## Emitted when an elite enemy dies. `position` is where it fell; RunDirector
## decides the drop (Aspect relic for the first elites, bounty fallback after).
@warning_ignore("unused_signal")
signal elite_died(position: Vector3)
