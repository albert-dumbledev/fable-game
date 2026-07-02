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

## Emitted the moment the player's health reaches zero.
@warning_ignore("unused_signal")
signal player_died

## Emitted whenever a currency balance changes (kill rewards, shop purchases).
signal currency_changed(id: StringName, amount: int)
