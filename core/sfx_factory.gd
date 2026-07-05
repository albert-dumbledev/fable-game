class_name SfxFactory
extends RefCounted
## Procedural SFX: every sound in the game is synthesized at startup from a
## few primitives (tone sweeps, filtered noise, envelopes, overlays), so no
## audio assets ship and web export stays asset-free. Each sound is a short
## mono 16-bit AudioStreamWAV; AudioManager owns playback.

const RATE := 22050

## Tone shapes for _tone().
const SINE := 0
const SQUARE := 1
const SAW := 2


static func build_all() -> Dictionary[StringName, AudioStreamWAV]:
	var sounds: Dictionary[StringName, AudioStreamWAV] = {}
	sounds[&"swing"] = _swing()
	sounds[&"hammer_swing"] = _hammer_swing()
	sounds[&"hit"] = _hit()
	sounds[&"melee_hit"] = _melee_hit()
	sounds[&"hammer_slam"] = _hammer_slam()
	sounds[&"block"] = _block()
	sounds[&"parry"] = _parry()
	sounds[&"guard_break"] = _guard_break()
	sounds[&"hurt"] = _hurt()
	sounds[&"enemy_die"] = _enemy_die()
	sounds[&"coin"] = _coin()
	sounds[&"xp"] = _xp()
	sounds[&"magnet_collect"] = _magnet_collect()
	sounds[&"health_pickup"] = _health_pickup()
	sounds[&"loot_shimmer"] = _loot_shimmer()
	sounds[&"level_up"] = _level_up()
	sounds[&"unlock_claim"] = _unlock_claim()
	sounds[&"boon"] = _boon()
	sounds[&"arcane_bolt"] = _arcane_bolt()
	sounds[&"fireball_shoot"] = _fireball_shoot()
	sounds[&"explosion"] = _explosion()
	sounds[&"frost_nova"] = _frost_nova()
	sounds[&"dash"] = _dash()
	sounds[&"boss_horn"] = _boss_horn()
	sounds[&"boss_death"] = _boss_death()
	sounds[&"boulder_impact"] = _boulder_impact()
	sounds[&"brood_burst"] = _brood_burst()
	sounds[&"stalker_disengage"] = _stalker_disengage()
	sounds[&"repulse"] = _repulse()
	sounds[&"eruption"] = _eruption()
	sounds[&"gilded_glimmer"] = _gilded_glimmer()
	sounds[&"gilded_jackpot"] = _gilded_jackpot()
	sounds[&"scavenger_gulp"] = _scavenger_gulp()
	sounds[&"scavenger_burrow"] = _scavenger_burrow()
	sounds[&"alarm"] = _alarm()
	sounds[&"click"] = _click()
	sounds[&"player_death"] = _player_death()
	return sounds


# --- Individual sounds ------------------------------------------------------


## Sword slash: broad air whoosh swelling through the arc with a thin high
## hiss riding the blade edge — a smooth sweep rather than an abrupt chop.
static func _swing() -> AudioStreamWAV:
	var arc := _env(_noise(0.24, 250.0, 2400.0, 1.0), 0.09, 1.1)
	var edge := _env(_noise(0.18, 1200.0, 4200.0, 0.35), 0.07, 1.3)
	return _to_wav(_overlay(arc, edge, 0.04), 0.32)


## Heavier, slower whoosh for the hammer haul.
static func _hammer_swing() -> AudioStreamWAV:
	return _to_wav(_env(_noise(0.28, 150.0, 850.0, 1.0), 0.06, 1.2), 0.38)


## Melee connect: punchy low thud with a snap of noise on top.
static func _hit() -> AudioStreamWAV:
	var body := _env(_tone(0.14, 170.0, 55.0, 1.0, SINE), 0.004, 2.2)
	var snap := _env(_noise(0.05, 3200.0, 500.0, 0.5), 0.002, 2.0)
	return _to_wav(_overlay(body, snap, 0.0), 0.75)


## Direct weapon contact: meaty wet smack — a sharp crack of noise over a
## pitch-dropping body, with a short low saw for gristle.
static func _melee_hit() -> AudioStreamWAV:
	var crack := _env(_noise(0.05, 2400.0, 300.0, 0.55), 0.002, 2.2)
	var body := _env(_tone(0.18, 140.0, 58.0, 1.0, SINE), 0.004, 2.0)
	var gristle := _env(_tone(0.07, 90.0, 50.0, 0.35, SAW), 0.003, 1.8)
	var out := _overlay(body, crack, 0.0)
	return _to_wav(_overlay(out, gristle, 0.01), 0.8)


## Ground slam: deep boom sagging into a long low rumble tail, with only a
## short dark crack on the impact itself.
static func _hammer_slam() -> AudioStreamWAV:
	var boom := _env(_tone(0.7, 100.0, 26.0, 1.0, SINE), 0.005, 1.1)
	var rumble := _env(_noise(0.65, 160.0, 45.0, 0.7), 0.01, 1.0)
	var crack := _env(_noise(0.08, 1200.0, 200.0, 0.4), 0.003, 2.0)
	var out := _overlay(boom, rumble, 0.0)
	return _to_wav(_overlay(out, crack, 0.0), 0.95)


## Shield block: inharmonic metallic partials with a hard attack.
static func _block() -> AudioStreamWAV:
	var out := _env(_tone(0.14, 620.0, 615.0, 0.6, SINE), 0.002, 3.0)
	out = _overlay(out, _env(_tone(0.11, 1180.0, 1174.0, 0.45, SINE), 0.002, 3.0), 0.0)
	out = _overlay(out, _env(_tone(0.08, 1660.0, 1660.0, 0.25, SINE), 0.002, 3.0), 0.0)
	out = _overlay(out, _env(_noise(0.03, 3500.0, 1500.0, 0.5), 0.001, 2.0), 0.0)
	return _to_wav(out, 0.65)


## Perfect block: a metallic "shing" — low bell chord under a rising noise
## sweep. Deliberately unlike the coin's discrete high blips.
static func _parry() -> AudioStreamWAV:
	var out := _env(_tone(0.35, 880.0, 884.0, 0.5, SINE), 0.004, 1.4)
	out = _overlay(out, _env(_tone(0.3, 1319.0, 1325.0, 0.35, SINE), 0.004, 1.5), 0.0)
	out = _overlay(out, _env(_noise(0.22, 1200.0, 2600.0, 0.4), 0.01, 1.6), 0.0)
	return _to_wav(out, 0.6)


## Guard meter breaking: a crack of noise over a low sagging thud.
static func _guard_break() -> AudioStreamWAV:
	var crack := _env(_noise(0.26, 3000.0, 300.0, 1.0), 0.002, 1.8)
	var sag := _env(_tone(0.32, 95.0, 42.0, 0.8, SINE), 0.01, 1.4)
	return _to_wav(_overlay(crack, sag, 0.02), 0.75)


## Player taking a hit: dull low thump, noticeably darker than enemy hits.
static func _hurt() -> AudioStreamWAV:
	var thump := _env(_tone(0.18, 130.0, 68.0, 1.0, SINE), 0.004, 1.8)
	var grit := _env(_noise(0.1, 900.0, 200.0, 0.45), 0.003, 2.0)
	return _to_wav(_overlay(thump, grit, 0.0), 0.8)


## Enemy death: a short squelchy descending blip.
static func _enemy_die() -> AudioStreamWAV:
	var blip := _env(_tone(0.22, 260.0, 70.0, 0.6, SQUARE), 0.006, 1.5)
	var splat := _env(_noise(0.08, 1600.0, 300.0, 0.4), 0.003, 2.0)
	return _to_wav(_overlay(blip, splat, 0.0), 0.45)


## Gold pickup: coin-purse thock — a woody low knock with a soft chime on
## top; tactile rather than musical.
static func _coin() -> AudioStreamWAV:
	var thock := _env(_tone(0.07, 320.0, 190.0, 1.0, SINE), 0.002, 2.2)
	var chime := _env(_tone(0.14, 660.0, 662.0, 0.5, SINE), 0.003, 1.8)
	return _to_wav(_overlay(thock, chime, 0.03), 0.55)


## XP pickup: warm two-note chime with a soft low thump for body.
static func _xp() -> AudioStreamWAV:
	var thump := _env(_tone(0.08, 220.0, 160.0, 0.4, SINE), 0.003, 2.0)
	var n1 := _env(_tone(0.16, 523.25, 524.0, 0.8, SINE), 0.003, 1.8)
	var n2 := _env(_tone(0.22, 784.0, 786.0, 0.8, SINE), 0.003, 1.6)
	var out := _overlay(thump, n1, 0.0)
	return _to_wav(_overlay(out, n2, 0.07), 0.45)


## Magnet pickup: a big, low whoomp as the field kicks in, with a rising
## filtered-noise swell and a soft mid chord shimmer riding in behind it as
## the loot arrives. Everything low per the audio direction — it reads as
## weight, not a chime.
static func _magnet_collect() -> AudioStreamWAV:
	var whoomp := _env(_tone(0.5, 90.0, 28.0, 1.0, SINE), 0.01, 1.1)
	var swell := _env(_noise(0.4, 220.0, 1400.0, 0.55), 0.08, 1.3)
	var out := _overlay(whoomp, swell, 0.05)
	var chord := _env(_tone(0.4, 220.0, 221.0, 0.3, SINE), 0.06, 1.4)
	chord = _overlay(chord, _env(_tone(0.4, 277.18, 278.0, 0.25, SINE), 0.06, 1.4), 0.0)
	return _to_wav(_overlay(out, chord, 0.12), 0.7)


## Health pickup: a short warm blip — gentle attack, low soft body, clearly
## rounder than the coin/xp cues.
static func _health_pickup() -> AudioStreamWAV:
	var body := _env(_tone(0.1, 170.0, 150.0, 0.5, SINE), 0.015, 1.6)
	var blip := _env(_tone(0.2, 220.0, 330.0, 0.7, SINE), 0.02, 1.5)
	return _to_wav(_overlay(body, blip, 0.02), 0.5)


## Mass pickup vacuum: one warm rolled chord instead of twenty coin blips.
## Soft attack and mid-register fundamentals so it shimmers rather than
## stabs; distinct from the level-up arpeggio by being simultaneous-ish.
static func _loot_shimmer() -> AudioStreamWAV:
	var freqs: PackedFloat32Array = [261.63, 329.63, 392.0, 523.25]
	var out := PackedFloat32Array()
	for i: int in freqs.size():
		var note := _env(_tone(0.5, freqs[i], freqs[i] * 1.004, 0.4, SINE), 0.04, 1.3)
		out = _overlay(out, note, 0.04 * i)
	var sparkle := _env(_noise(0.3, 1500.0, 400.0, 0.25), 0.03, 1.5)
	return _to_wav(_overlay(out, sparkle, 0.05), 0.5)


## Level up: rising major arpeggio.
static func _level_up() -> AudioStreamWAV:
	var notes: PackedFloat32Array = [261.63, 329.63, 392.0, 523.25]
	var out := PackedFloat32Array()
	for i: int in notes.size():
		var note := _env(_tone(0.32, notes[i], notes[i] * 1.005, 0.5, SINE), 0.005, 1.5)
		out = _overlay(out, note, 0.09 * i)
	return _to_wav(out, 0.6)


## Weapon unlock claimed: a short low fanfare — a rising two-note power chord
## (root + fifth) on a warm saw with a bright but brief metallic shimmer over
## the top, so it reads as an earned reward without climbing into chime pitch.
static func _unlock_claim() -> AudioStreamWAV:
	var root := _env(_tone(0.4, 110.0, 130.0, 0.6, SAW), 0.01, 1.2)
	var fifth := _env(_tone(0.4, 165.0, 195.0, 0.45, SAW), 0.015, 1.2)
	var out := _overlay(root, fifth, 0.03)
	var shimmer := _env(_noise(0.15, 3000.0, 1200.0, 0.35), 0.004, 1.8)
	return _to_wav(_overlay(out, shimmer, 0.05), 0.7)


## Boon picked: two-note confirmation chime.
static func _boon() -> AudioStreamWAV:
	var out := _env(_tone(0.2, 523.25, 525.0, 0.5, SINE), 0.004, 1.5)
	out = _overlay(out, _env(_tone(0.28, 784.0, 786.0, 0.5, SINE), 0.004, 1.5), 0.08)
	return _to_wav(out, 0.55)


## Arcane bolt: a quick descending zap over a soft low body-tick — bright
## transient but the fundamentals stay low, so it reads as distinct from the
## heavier _fireball_shoot rather than competing with it up in pitch.
static func _arcane_bolt() -> AudioStreamWAV:
	var zap := _env(_tone(0.09, 950.0, 220.0, 0.5, SAW), 0.002, 1.8)
	var tick := _env(_noise(0.03, 2200.0, 500.0, 0.4), 0.001, 2.0)
	return _to_wav(_overlay(zap, tick, 0.0), 0.5)


## Fireball release: ignition puff and a low saw roar with fiery crackle
## pops scattered through the tail.
static func _fireball_shoot() -> AudioStreamWAV:
	var puff := _env(_noise(0.3, 2200.0, 200.0, 1.0), 0.008, 1.6)
	var roar := _env(_tone(0.3, 150.0, 70.0, 0.55, SAW), 0.02, 1.3)
	var out := _overlay(puff, roar, 0.0)
	for i: int in 9:
		var pop := _env(_noise(randf_range(0.015, 0.035), 2800.0, 600.0,
				randf_range(0.2, 0.4)), 0.002, 2.0)
		out = _overlay(out, pop, randf_range(0.03, 0.26))
	return _to_wav(out, 0.6)


## Explosion: hard blast front collapsing into a sub drop, with burning
## ember crackle in the tail.
static func _explosion() -> AudioStreamWAV:
	var blast := _env(_noise(0.55, 3000.0, 45.0, 1.0), 0.003, 1.3)
	var sub := _env(_tone(0.6, 80.0, 24.0, 1.0, SINE), 0.006, 1.2)
	var out := _overlay(blast, sub, 0.0)
	for i: int in 7:
		var ember := _env(_noise(randf_range(0.02, 0.04), 2200.0, 500.0,
				randf_range(0.15, 0.3)), 0.002, 2.0)
		out = _overlay(out, ember, randf_range(0.12, 0.45))
	return _to_wav(out, 0.9)


## Frost nova: cold air rush with two detuned glass tones falling away and
## tiny crystalline ticks like frost snapping into place.
static func _frost_nova() -> AudioStreamWAV:
	var rush := _env(_noise(0.5, 6000.0, 700.0, 0.7), 0.008, 1.3)
	var glass_hi := _env(_tone(0.45, 1319.0, 988.0, 0.35, SINE), 0.01, 1.2)
	var glass_lo := _env(_tone(0.5, 660.0, 440.0, 0.3, SINE), 0.015, 1.1)
	var out := _overlay(rush, glass_hi, 0.01)
	out = _overlay(out, glass_lo, 0.03)
	for i: int in 8:
		var tick := _env(_noise(randf_range(0.008, 0.02), 5000.0, 2500.0,
				randf_range(0.25, 0.45)), 0.001, 1.8)
		out = _overlay(out, tick, randf_range(0.05, 0.4))
	return _to_wav(out, 0.55)


## Dash blink: the original bright zip riding on a low falling air rush —
## the low layer is what makes it read as *speed* rather than a UI tick.
static func _dash() -> AudioStreamWAV:
	var zip := _env(_noise(0.12, 600.0, 2200.0, 1.0), 0.015, 1.6)
	var rush := _env(_noise(0.3, 900.0, 160.0, 0.9), 0.02, 1.2)
	var drop := _env(_tone(0.22, 220.0, 85.0, 0.35, SINE), 0.01, 1.4)
	var out := _overlay(zip, rush, 0.0)
	return _to_wav(_overlay(out, drop, 0.02), 0.55)


## Boss spawn: low detuned horn blast, slow attack.
static func _boss_horn() -> AudioStreamWAV:
	var out := _env(_tone(0.9, 65.0, 66.0, 0.6, SAW), 0.2, 1.1)
	out = _overlay(out, _env(_tone(0.9, 65.7, 66.8, 0.5, SAW), 0.2, 1.1), 0.0)
	out = _overlay(out, _env(_tone(0.85, 97.5, 98.5, 0.4, SAW), 0.22, 1.1), 0.02)
	return _to_wav(out, 0.7)


## Boss death: a huge slow detonation — blast front into a deep sub drop,
## a long rumble tail, and a sagging low horn so it reads as a creature
## dying, not just a bomb. Everything lives well under the pitch ceiling;
## it's the longest, darkest sound in the game by design.
static func _boss_death() -> AudioStreamWAV:
	var blast := _env(_noise(0.5, 2500.0, 60.0, 1.0), 0.004, 1.4)
	var sub := _env(_tone(1.1, 70.0, 22.0, 1.0, SINE), 0.008, 1.1)
	var rumble := _env(_noise(1.3, 140.0, 35.0, 0.7), 0.02, 1.0)
	var horn := _env(_tone(0.9, 98.0, 49.0, 0.45, SAW), 0.05, 1.2)
	var out := _overlay(blast, sub, 0.0)
	out = _overlay(out, rumble, 0.05)
	return _to_wav(_overlay(out, horn, 0.1), 0.95)


## Juggernaut boulder impact: a heavy stone thud — deep boom collapsing into a
## short gritty debris rumble with a dry rock crack on the front. Rockier and
## shorter than the hammer slam so the two heavy impacts read apart. Low.
static func _boulder_impact() -> AudioStreamWAV:
	var boom := _env(_tone(0.5, 95.0, 30.0, 1.0, SINE), 0.004, 1.2)
	var debris := _env(_noise(0.4, 500.0, 80.0, 0.8), 0.006, 1.1)
	var crack := _env(_noise(0.07, 1400.0, 300.0, 0.5), 0.002, 2.0)
	var out := _overlay(boom, debris, 0.0)
	return _to_wav(_overlay(out, crack, 0.0), 0.9)


## Broodmother burst: a wet low squelch (fast-falling filtered noise over a
## short pitch-dropping body) with a scatter of short high-ish chitters riding
## the tail as the brood hatches. Fundamentals stay low; the chitters are brief.
static func _brood_burst() -> AudioStreamWAV:
	var squelch := _env(_noise(0.22, 900.0, 90.0, 1.0), 0.004, 1.5)
	var body := _env(_tone(0.2, 150.0, 55.0, 0.7, SINE), 0.005, 1.6)
	var out := _overlay(squelch, body, 0.0)
	for i: int in 6:
		var chitter := _env(_tone(randf_range(0.03, 0.05), randf_range(600.0, 900.0),
				randf_range(300.0, 450.0), randf_range(0.15, 0.28), SQUARE), 0.002, 2.0)
		out = _overlay(out, chitter, randf_range(0.06, 0.28))
	return _to_wav(out, 0.7)


## Stalker disengage: a short reverse-whoosh — filtered noise whose cutoff RISES
## (air rushing as it bolts back) with a long swell-in attack and an abrupt tail,
## the inverse of the swing whoosh. Low-mid and brief.
static func _stalker_disengage() -> AudioStreamWAV:
	var rush := _env(_noise(0.22, 200.0, 1500.0, 1.0), 0.14, 0.5)
	var body := _env(_tone(0.18, 90.0, 165.0, 0.35, SINE), 0.1, 0.6)
	return _to_wav(_overlay(rush, body, 0.0), 0.4)


## Caster repulse: a low outward whoomp — a soft sine body dropping in pitch
## under a filtered-noise swell whose cutoff RISES (air shoved outward), with a
## sub thump under it. A push, not an impact; all low per the audio direction.
static func _repulse() -> AudioStreamWAV:
	var whoomp := _env(_tone(0.4, 120.0, 40.0, 1.0, SINE), 0.008, 1.2)
	var swell := _env(_noise(0.34, 200.0, 1100.0, 0.6), 0.05, 1.3)
	var sub := _env(_tone(0.45, 70.0, 24.0, 0.7, SINE), 0.006, 1.1)
	var out := _overlay(whoomp, swell, 0.02)
	return _to_wav(_overlay(out, sub, 0.0), 0.7)


## Arcane eruption: a ground crack/geyser — a sharp filtered-noise crack over a
## low sub thump and a brief rumble, with a faint rising tone for the upward
## burst. Sharper and thinner than the boulder thud; fundamentals stay low.
static func _eruption() -> AudioStreamWAV:
	var crack := _env(_noise(0.12, 1500.0, 220.0, 1.0), 0.002, 1.7)
	var thump := _env(_tone(0.45, 85.0, 28.0, 0.9, SINE), 0.005, 1.2)
	var rumble := _env(_noise(0.4, 240.0, 55.0, 0.55), 0.02, 1.0)
	var rise := _env(_tone(0.22, 180.0, 320.0, 0.3, SINE), 0.02, 1.3)
	var out := _overlay(crack, thump, 0.0)
	out = _overlay(out, rumble, 0.03)
	return _to_wav(_overlay(out, rise, 0.02), 0.85)


## Gilded One spawn/despawn glimmer: two detuned low-mid tones under a slow
## tremolo — an audible "something rare is here" cue. Low per the audio direction.
static func _gilded_glimmer() -> AudioStreamWAV:
	var a := _tone(0.6, 330.0, 333.0, 0.5, SINE)
	var b := _tone(0.6, 495.0, 499.0, 0.4, SINE)
	var out := _overlay(a, b, 0.0)
	for i: int in out.size():
		var t := float(i) / float(RATE)
		out[i] *= 0.65 + 0.35 * sin(TAU * 6.0 * t)
	return _to_wav(_env(out, 0.03, 1.2), 0.5)


## Gilded jackpot: a deep celebratory thunk to sit UNDER the coin-blip fountain
## when the Gilded One is finally cracked open. Low sine body + soft noise puff.
static func _gilded_jackpot() -> AudioStreamWAV:
	var thunk := _env(_tone(0.4, 140.0, 60.0, 1.0, SINE), 0.005, 1.3)
	var puff := _env(_noise(0.25, 400.0, 1200.0, 0.4), 0.02, 1.2)
	var shimmer := _env(_tone(0.5, 330.0, 331.0, 0.25, SINE), 0.05, 1.3)
	var out := _overlay(thunk, puff, 0.0)
	return _to_wav(_overlay(out, shimmer, 0.03), 0.7)


## Scavenger gulp: a short comedic downward sweep — a quick gulp as it swallows a
## piece of loot. Low and brief.
static func _scavenger_gulp() -> AudioStreamWAV:
	var gulp := _env(_tone(0.12, 300.0, 90.0, 1.0, SINE), 0.004, 1.6)
	var slurp := _env(_noise(0.06, 800.0, 200.0, 0.3), 0.003, 1.8)
	return _to_wav(_overlay(gulp, slurp, 0.0), 0.5)


## Scavenger burrow: a low filtered-noise rumble swell as it digs out with the
## loot — earthy, rising then cut. All low.
static func _scavenger_burrow() -> AudioStreamWAV:
	var rumble := _env(_noise(0.6, 90.0, 260.0, 1.0), 0.15, 0.9)
	var grit := _env(_noise(0.5, 300.0, 120.0, 0.5), 0.05, 1.0)
	var sub := _env(_tone(0.5, 70.0, 45.0, 0.5, SINE), 0.02, 1.0)
	var out := _overlay(rumble, grit, 0.0)
	return _to_wav(_overlay(out, sub, 0.0), 0.6)


## Wave/swarm announcement: two alternating alarm tones.
static func _alarm() -> AudioStreamWAV:
	var out := _env(_tone(0.14, 440.0, 440.0, 0.4, SQUARE), 0.01, 1.0)
	out = _overlay(out, _env(_tone(0.14, 587.0, 587.0, 0.4, SQUARE), 0.01, 1.0), 0.16)
	out = _overlay(out, _env(_tone(0.14, 440.0, 440.0, 0.4, SQUARE), 0.01, 1.0), 0.32)
	out = _overlay(out, _env(_tone(0.18, 587.0, 587.0, 0.4, SQUARE), 0.01, 1.4), 0.48)
	return _to_wav(out, 0.4)


## UI tick.
static func _click() -> AudioStreamWAV:
	return _to_wav(_env(_noise(0.025, 1700.0, 900.0, 1.0), 0.001, 1.5), 0.4)


## Player death: long falling tone with a rough noise tail.
static func _player_death() -> AudioStreamWAV:
	var fall := _env(_tone(0.9, 220.0, 55.0, 0.8, SINE), 0.01, 1.1)
	var tail := _env(_noise(0.7, 500.0, 80.0, 0.5), 0.05, 1.2)
	return _to_wav(_overlay(fall, tail, 0.05), 0.75)


# --- Synthesis primitives ---------------------------------------------------


## A pitch-swept tone. Phase-accumulated so sweeps stay click-free.
static func _tone(duration: float, freq_start: float, freq_end: float,
		amp: float, shape: int) -> PackedFloat32Array:
	var count := maxi(1, int(duration * RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i: int in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(freq_start, freq_end, t) / float(RATE)
		var value := 0.0
		match shape:
			SQUARE:
				value = signf(sin(phase))
			SAW:
				value = 2.0 * fposmod(phase / TAU, 1.0) - 1.0
			_:
				value = sin(phase)
		samples[i] = value * amp
	return samples


## White noise through a one-pole lowpass whose cutoff sweeps over the
## duration — cutoff falling = boom/debris, rising = whoosh.
static func _noise(duration: float, cutoff_start: float, cutoff_end: float,
		amp: float) -> PackedFloat32Array:
	var count := maxi(1, int(duration * RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var last := 0.0
	for i: int in count:
		var t := float(i) / float(count)
		var alpha := clampf(TAU * lerpf(cutoff_start, cutoff_end, t) / float(RATE), 0.0, 1.0)
		last += alpha * (randf_range(-1.0, 1.0) - last)
		samples[i] = last * amp
	return samples


## Linear attack, then a power-curve decay that reaches zero exactly at the
## end (higher curve = punchier).
static func _env(samples: PackedFloat32Array, attack: float,
		curve: float) -> PackedFloat32Array:
	var count := samples.size()
	var attack_samples := maxi(1, int(attack * RATE))
	for i: int in count:
		var gain := minf(1.0, float(i) / float(attack_samples))
		var remaining := 1.0 - float(i) / float(count)
		samples[i] *= gain * pow(remaining, curve)
	return samples


## Mixes `layer` into `base` starting at `offset` seconds, growing the
## buffer as needed. Returns the combined buffer.
static func _overlay(base: PackedFloat32Array, layer: PackedFloat32Array,
		offset: float) -> PackedFloat32Array:
	var start := int(offset * RATE)
	var needed := start + layer.size()
	if needed > base.size():
		base.resize(needed)
	for i: int in layer.size():
		base[start + i] += layer[i]
	return base


## Peak-normalizes to `peak` (per-sound loudness lives here, playback
## volume_db is for situational ducking) and packs into a 16-bit mono WAV.
static func _to_wav(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var max_sample := 0.0001
	for i: int in samples.size():
		max_sample = maxf(max_sample, absf(samples[i]))
	var scale := peak / max_sample
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * scale, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream
