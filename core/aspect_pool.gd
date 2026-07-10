class_name AspectPool
extends RefCounted
## Shared candidate source for Aspect drops (Phase 9 M2). Both RunDirector (the
## spawn decision — does an elite/boss relic have anything to offer?) and
## AspectScreen (the pick-1-of-2 roll) read the pool through here, so the "which
## Aspects are still available" logic lives in exactly one place.
##
## Aspects are plain BoonData resources in their own registry — the level-up boon
## screen never loads this, keeping the two tiers fully separate.

## The Aspect registry (empty until M3+ append the loadout/universal trios).
const ASPECT_REGISTRY := preload("res://data/boons/aspects/registry.tres")


## Every Aspect the player can still be offered: not already owned (the granted
## ability flag doubles as the taken-this-run tracker) and either universal or
## gated to the mounted weapon. Nulls are guarded exactly like
## boon_screen._is_offerable.
static func available(player: Player) -> Array[BoonData]:
	var pool: Array[BoonData] = []
	if ASPECT_REGISTRY == null:
		return pool
	for aspect: BoonData in ASPECT_REGISTRY.boons:
		if aspect == null:
			continue
		if player != null and player.has_ability(aspect.grants_ability):
			continue
		if aspect.requires_weapon != &"":
			if player == null or player.weapon == null \
					or player.weapon.weapon_data == null \
					or player.weapon.weapon_data.id != aspect.requires_weapon:
				continue
		pool.append(aspect)
	return pool


## Up to `count` distinct Aspects sampled by weight from available() — the same
## weighted-pick-and-remove approach the boon screen uses for its offers.
static func roll(player: Player, count: int) -> Array[BoonData]:
	var pool := available(player)
	var picks: Array[BoonData] = []
	while picks.size() < count and not pool.is_empty():
		var total := 0.0
		for aspect: BoonData in pool:
			total += aspect.weight
		var roll_value := randf() * total
		var picked := pool.size() - 1
		for i: int in pool.size():
			roll_value -= pool[i].weight
			if roll_value <= 0.0:
				picked = i
				break
		picks.append(pool[picked])
		pool.remove_at(picked)
	return picks
