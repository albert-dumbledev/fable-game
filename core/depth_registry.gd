class_name DepthRegistry
extends Resource
## The authored Depth ladder, ordered by level (docs/DEPTHS.md). Loaded once by
## MetaProgression; selection/validation reads it. Adding a Depth is authoring a
## .tres and appending it here — no systems change.

@export var depths: Array[DepthData] = []


## The Depth at `level`, or null if none is authored for it (Surface, or out of
## range). Level lookup, not array index — the list stays authoring-ordered.
func get_depth(level: int) -> DepthData:
	for depth: DepthData in depths:
		if depth != null and depth.level == level:
			return depth
	return null


## The deepest authored level (0 if the registry is empty). Caps how far the
## picker can ever unlock.
func max_level() -> int:
	var top := 0
	for depth: DepthData in depths:
		if depth != null and depth.level > top:
			top = depth.level
	return top
