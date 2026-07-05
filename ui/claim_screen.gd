extends CanvasLayer
## Weapon-unlock claim overlay: when the player collects a boss relic, pause the
## run and show what was claimed until they acknowledge, then resume. Mirrors
## the boon screen's pause handling (runs with PROCESS_MODE_ALWAYS).

@onready var title: Label = $Center/Box/Title
@onready var item_label: Label = $Center/Box/ItemLabel
@onready var subtitle: Label = $Center/Box/Subtitle
@onready var continue_button: Button = $Center/Box/ContinueButton


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	EventBus.unlock_claimed.connect(_on_unlock_claimed)


func _on_unlock_claimed(ability: StringName) -> void:
	# unlock_claimed fires mid-physics (pickup collection); defer the pause so we
	# don't pause the tree inside that callback stack.
	_show.call_deferred(ability)


func _show(ability: StringName) -> void:
	item_label.text = _weapon_name(ability)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	AudioManager.play(&"unlock_claim")


func _on_continue() -> void:
	AudioManager.play(&"click")
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The claimed weapon's display name (upper-cased), resolved from the registry.
func _weapon_name(ability: StringName) -> String:
	var registry := MetaProgression.weapon_registry
	if registry != null:
		for weapon: WeaponData in registry.weapons:
			if weapon.unlock_ability == ability:
				return weapon.display_name.to_upper()
	return String(ability).to_upper()
