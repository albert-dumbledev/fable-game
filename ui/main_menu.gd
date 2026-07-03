extends Control
## Main menu: the boot scene. Start a run, open settings, or quit.

@onready var gold_label: Label = $Center/Box/GoldLabel
@onready var play_button: Button = $Center/Box/PlayButton
@onready var settings_button: Button = $Center/Box/SettingsButton
@onready var quit_button: Button = $Center/Box/QuitButton
@onready var settings_panel: SettingsPanel = $SettingsPanel


func _ready() -> void:
	GameManager.state = GameManager.State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var gold := MetaProgression.get_currency(&"gold")
	gold_label.text = "Gold: %d" % gold
	gold_label.visible = gold > 0
	play_button.pressed.connect(_on_play)
	settings_button.pressed.connect(_on_settings)
	quit_button.pressed.connect(_on_quit)
	# Closing the tab is the quit button on web.
	quit_button.visible = not OS.has_feature("web")
	settings_panel.visible = false
	play_button.grab_focus()


func _on_play() -> void:
	AudioManager.play(&"click")
	GameManager.start_run()


func _on_settings() -> void:
	AudioManager.play(&"click")
	settings_panel.visible = true


func _on_quit() -> void:
	get_tree().quit()
