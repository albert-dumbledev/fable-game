extends Node
## Top-level game state machine:
##   Menu -> Loadout -> InRun -> DeathScreen (recap) -> Loadout -> InRun.
## The Loadout screen is the pre-run hub (pick weapon/Depth, spend at the
## shops); the DeathScreen is now recap-only and hands back to Loadout.
## Owns scene transitions. No gameplay logic lives here.

enum State { MENU, LOADOUT, IN_RUN, DEATH_SCREEN }

const ARENA_SCENE: String = "res://levels/Arena.tscn"
const DEATH_SCREEN_SCENE: String = "res://ui/DeathScreen.tscn"
const LOADOUT_SCREEN_SCENE: String = "res://ui/LoadoutScreen.tscn"
const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

var state: State = State.MENU
var last_run_stats: Dictionary = {}


func go_to_menu() -> void:
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func go_to_loadout() -> void:
	state = State.LOADOUT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(LOADOUT_SCREEN_SCENE)


func start_run() -> void:
	state = State.IN_RUN
	get_tree().change_scene_to_file(ARENA_SCENE)
	# EventBus.run_started is emitted by RunDirector once the arena is live.


func end_run(stats: Dictionary) -> void:
	state = State.DEATH_SCREEN
	last_run_stats = stats
	EventBus.run_ended.emit(stats)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(DEATH_SCREEN_SCENE)
