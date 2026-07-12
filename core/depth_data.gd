class_name DepthData
extends Resource
## One Depth: a harder overlay on the same 7:30 run (docs/DEPTHS.md). Authored
## per-Depth as absolute, already-compounded values (each deeper Depth is a
## superset of the shallower ones' twists), so every .tres reads standalone.
## Consumed at the Spawner/RunDirector/BoonScreen call sites — the shared
## WaveTable is never mutated. A null DepthData is Surface (today's numbers).

## Depth ordinal (1 = shallowest). Surface is the absence of a DepthData, not
## level 0; the registry is keyed by this.
@export var level := 1
## The all-caps house-voice name shown in the announcement and picker.
@export var display_name := ""              # "THE FLOOR BELOW"
@export var hp_mult := 1.0                  # on top of WaveTable.hp_mult_at
@export var dmg_mult := 1.0                 # on top of WaveTable.dmg_mult_at
@export var reward_mult := 1.0              # gold AND xp, on top of reward_mult_at
@export var interval_mult := 1.0            # scales spawn_interval_at output
@export var alive_cap_bonus := 0            # added to max_alive_at
@export var swarm_count_mult := 1.0         # repeating events only, not bosses
@export var elite_min_elapsed := -1.0       # -1 = Spawner default (240s)
@export var elite_max_alive := 1            # concurrent pool elites allowed
@export var aspect_elite_cap := 2           # RunDirector.ASPECT_ELITE_CAP override
@export var boss_relic_count := 1           # Aspect relics per cleared boss wave
@export var rarity_time_bonus := 0.0        # seconds added to the boon-rarity clock
@export var pin_legendary := false          # one pinned Legendary offer per run
@export var windup_mult := 1.0              # enemy telegraph time scale, >= 0.85
@export var finale_time_shift := 0.0        # seconds; negative = Revenant earlier
## The affix escape hatch: extra WaveEvents this Depth schedules on top of the
## table (e.g. the Twin Court's second Juggernaut). Anything the WaveTable can
## express, a Depth can add without bespoke code.
@export var extra_events: Array[WaveEvent] = []
## Subtle arena mood shift, kept close to white — a nudge, not a filter.
@export var ambient_tint := Color.WHITE
## Saturated identity color for this Depth (docs/DEPTHS.md Lane 3) — unlike
## ambient_tint (kept near-white, a mood nudge), this is a bold, unmistakable
## hue. Badges (death-screen grid) and weapon trim both tint from this one
## field, so a Depth's color is defined exactly once.
@export var theme_color := Color.WHITE

## Roman numeral for a Depth level (1-based), shared by the picker, victory
## banners, the records line, and the HUD chip so the numeral never drifts
## between call sites. A general conversion rather than a lookup table, so it
## extends past the currently authored ladder (V) for free.
static func numeral(level: int) -> String:
	if level <= 0:
		return str(level)
	const VALUES: Array[int] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	const SYMBOLS: Array[String] = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var remaining := level
	var result := ""
	for i: int in VALUES.size():
		while remaining >= VALUES[i]:
			remaining -= VALUES[i]
			result += SYMBOLS[i]
	return result


## English ordinal word for a Depth level ("FIRST".."FIFTH", …), the house-voice
## title line's "OF THE <ORDINAL>" (death screen). Plain words rather than
## "1ST" to match numeral()'s all-caps voice. A lookup table over English's
## irregular ordinals; past the authored words it falls back to "<numeral>TH"
## rather than guessing the rest of the ladder's suffixes — fine since this
## only degrades gracefully once the ladder outgrows the list.
static func ordinal_word(level: int) -> String:
	const WORDS: Array[String] = [
		"FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH",
		"SIXTH", "SEVENTH", "EIGHTH", "NINTH", "TENTH",
	]
	if level >= 1 and level <= WORDS.size():
		return WORDS[level - 1]
	return "%sTH" % numeral(level)
