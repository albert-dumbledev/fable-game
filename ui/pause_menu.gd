extends CanvasLayer
## In-run pause menu on Esc. Runs with PROCESS_MODE_ALWAYS so it works while
## the tree is paused — but never opens over the boon screen (which owns the
## pause during a level-up choice).

@onready var resume_button: Button = $Root/Center/Box/ResumeButton
@onready var settings_button: Button = $Root/Center/Box/SettingsButton
@onready var abandon_button: Button = $Root/Center/Box/AbandonButton
@onready var settings_panel: SettingsPanel = $Root/SettingsPanel

var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(_close)
	settings_button.pressed.connect(_on_settings)
	abandon_button.pressed.connect(_on_abandon)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		if settings_panel.visible:
			settings_panel.visible = false
		else:
			_close()
		get_viewport().set_input_as_handled()
	elif GameManager.state == GameManager.State.IN_RUN and not get_tree().paused:
		_show_menu()
		get_viewport().set_input_as_handled()


func _show_menu() -> void:
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.play(&"click")


func _close() -> void:
	_open = false
	visible = false
	settings_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play(&"click")


func _on_settings() -> void:
	AudioManager.play(&"click")
	settings_panel.visible = true


func _on_abandon() -> void:
	AudioManager.play(&"click")
	_open = false
	visible = false
	get_tree().paused = false
	var director := get_tree().get_first_node_in_group(&"run_director") as RunDirector
	if director != null:
		director.abandon_run()
	else:
		GameManager.go_to_menu()
