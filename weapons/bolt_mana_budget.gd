class_name BoltManaBudget
extends RefCounted
## Shared mana-refund budget for one Arcane Bolt volley -- the bolts fired by a
## single trigger pull plus any Split Shot children. Caps total mana refunded
## per volley at the base per-bolt amount, so scatter + split can never turn
## into a mana printer.

var _player: Player
var _remaining: float


func _init(player: Player, cap: float) -> void:
	_player = player
	_remaining = cap


## Refund up to `amount`, but never more than the volley's remaining budget.
func grant(amount: float) -> void:
	if _player == null or _remaining <= 0.0:
		return
	var given := minf(amount, _remaining)
	_remaining -= given
	_player.restore_mana(given)
