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
	sounds[&"hammer_slam"] = _hammer_slam()
	sounds[&"block"] = _block()
	sounds[&"parry"] = _parry()
	sounds[&"guard_break"] = _guard_break()
	sounds[&"hurt"] = _hurt()
	sounds[&"enemy_die"] = _enemy_die()
	sounds[&"coin"] = _coin()
	sounds[&"xp"] = _xp()
	sounds[&"level_up"] = _level_up()
	sounds[&"boon"] = _boon()
	sounds[&"fireball_shoot"] = _fireball_shoot()
	sounds[&"explosion"] = _explosion()
	sounds[&"frost_nova"] = _frost_nova()
	sounds[&"dash"] = _dash()
	sounds[&"boss_horn"] = _boss_horn()
	sounds[&"alarm"] = _alarm()
	sounds[&"click"] = _click()
	sounds[&"player_death"] = _player_death()
	return sounds


# --- Individual sounds ------------------------------------------------------


## Sword whoosh: airy noise sweeping up through the swing arc.
static func _swing() -> AudioStreamWAV:
	return _to_wav(_env(_noise(0.16, 350.0, 1800.0, 1.0), 0.03, 1.4), 0.55)


## Heavier, slower whoosh for the hammer haul.
static func _hammer_swing() -> AudioStreamWAV:
	return _to_wav(_env(_noise(0.28, 150.0, 850.0, 1.0), 0.06, 1.2), 0.6)


## Melee connect: punchy low thud with a snap of noise on top.
static func _hit() -> AudioStreamWAV:
	var body := _env(_tone(0.14, 170.0, 55.0, 1.0, SINE), 0.004, 2.2)
	var snap := _env(_noise(0.05, 3200.0, 500.0, 0.5), 0.002, 2.0)
	return _to_wav(_overlay(body, snap, 0.0), 0.75)


## Ground slam: deep boom plus debris noise.
static func _hammer_slam() -> AudioStreamWAV:
	var boom := _env(_tone(0.42, 110.0, 34.0, 1.0, SINE), 0.005, 1.6)
	var debris := _env(_noise(0.3, 1400.0, 100.0, 0.6), 0.004, 1.8)
	return _to_wav(_overlay(boom, debris, 0.0), 0.85)


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


## Gold pickup: classic two-note coin chirp.
static func _coin() -> AudioStreamWAV:
	var out := _env(_tone(0.05, 1400.0, 1400.0, 0.6, SINE), 0.002, 1.2)
	out = _overlay(out, _env(_tone(0.09, 1870.0, 1880.0, 0.6, SINE), 0.002, 1.4), 0.045)
	return _to_wav(out, 0.5)


## XP pickup: single soft blip, quieter sibling of the coin.
static func _xp() -> AudioStreamWAV:
	return _to_wav(_env(_tone(0.07, 820.0, 980.0, 0.5, SINE), 0.004, 1.4), 0.35)


## Level up: rising major arpeggio.
static func _level_up() -> AudioStreamWAV:
	var notes: PackedFloat32Array = [261.63, 329.63, 392.0, 523.25]
	var out := PackedFloat32Array()
	for i: int in notes.size():
		var note := _env(_tone(0.32, notes[i], notes[i] * 1.005, 0.5, SINE), 0.005, 1.5)
		out = _overlay(out, note, 0.09 * i)
	return _to_wav(out, 0.6)


## Boon picked: two-note confirmation chime.
static func _boon() -> AudioStreamWAV:
	var out := _env(_tone(0.2, 523.25, 525.0, 0.5, SINE), 0.004, 1.5)
	out = _overlay(out, _env(_tone(0.28, 784.0, 786.0, 0.5, SINE), 0.004, 1.5), 0.08)
	return _to_wav(out, 0.55)


## Fireball release: whoosh with a fiery crackle bed.
static func _fireball_shoot() -> AudioStreamWAV:
	var whoosh := _env(_noise(0.28, 400.0, 1500.0, 1.0), 0.02, 1.4)
	var body := _env(_tone(0.2, 240.0, 110.0, 0.5, SAW), 0.01, 1.6)
	return _to_wav(_overlay(whoosh, body, 0.0), 0.6)


## Explosion: big noise boom collapsing into a sub tail.
static func _explosion() -> AudioStreamWAV:
	var blast := _env(_noise(0.5, 2500.0, 60.0, 1.0), 0.005, 1.5)
	var sub := _env(_tone(0.45, 90.0, 30.0, 0.9, SINE), 0.008, 1.4)
	return _to_wav(_overlay(blast, sub, 0.0), 0.85)


## Frost nova: icy shimmer — high noise and a long descending glassy tone.
static func _frost_nova() -> AudioStreamWAV:
	var shimmer := _env(_noise(0.4, 4500.0, 1200.0, 0.8), 0.01, 1.3)
	var glass := _env(_tone(0.38, 1319.0, 392.0, 0.4, SINE), 0.01, 1.2)
	return _to_wav(_overlay(shimmer, glass, 0.02), 0.55)


## Dash blink: very short bright whoosh.
static func _dash() -> AudioStreamWAV:
	return _to_wav(_env(_noise(0.12, 600.0, 2200.0, 1.0), 0.015, 1.6), 0.5)


## Boss spawn: low detuned horn blast, slow attack.
static func _boss_horn() -> AudioStreamWAV:
	var out := _env(_tone(0.9, 65.0, 66.0, 0.6, SAW), 0.2, 1.1)
	out = _overlay(out, _env(_tone(0.9, 65.7, 66.8, 0.5, SAW), 0.2, 1.1), 0.0)
	out = _overlay(out, _env(_tone(0.85, 97.5, 98.5, 0.4, SAW), 0.22, 1.1), 0.02)
	return _to_wav(out, 0.7)


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
