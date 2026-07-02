extends Node
## Top-level game state machine: Menu -> InRun -> DeathScreen -> (shop) -> InRun.
## Owns scene transitions. No gameplay logic lives here.

enum State { MENU, IN_RUN, DEATH_SCREEN }

const ARENA_SCENE: String = "res://levels/Arena.tscn"

var state: State = State.MENU


func start_run() -> void:
	state = State.IN_RUN
	get_tree().change_scene_to_file(ARENA_SCENE)
	EventBus.run_started.emit()


func end_run(stats: Dictionary) -> void:
	state = State.DEATH_SCREEN
	EventBus.run_ended.emit(stats)
	# Phase 1: transition to the death screen / upgrade shop here.
