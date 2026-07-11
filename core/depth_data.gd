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
