extends Node
## All of Gemhalla's sound effects, synthesized at startup (see synth.gd) and played
## through a small pool of players. Tweak a sound by editing its recipe below.

const Synth := preload("res://scripts/audio/synth.gd")

const VOICES := 10

# Note frequencies (Hz) used by the recipes: mostly A minor, low down, for a dark
# 80s-synth sound.
const A1 := 55.0
const E2 := 82.41
const G2 := 98.0
const A2 := 110.0
const C3 := 130.81
const E3 := 164.81
const G3 := 196.0
const A3 := 220.0
const B3 := 246.94
const C4 := 261.63
const E4 := 329.63
const G4 := 392.0
const A4 := 440.0
const C5 := 523.25

## Mutes the whole game (master bus).
var muted := false:
	set(value):
		muted = value
		AudioServer.set_bus_mute(0, value)

var _sounds := {}
var _players: Array = []
var _loops := {}  # sound name -> its looping AudioStreamPlayer


## Pitch multiplier for a shift of n semitones.
static func semitones(n: float) -> float:
	return pow(2.0, n / 12.0)


# Minor pentatonic steps (semitones): the rock and blues scale; any of them sound right
# together, with no clashes.
const PENTATONIC := [0, 3, 5, 7, 10]

## Pitch multiplier for the nth step up a minor pentatonic scale (for rising notes),
## held to two octaves so a long run of gems never turns shrill.
static func scale_step(n: int) -> float:
	n = clampi(n, 0, PENTATONIC.size() * 2)
	return semitones(PENTATONIC[n % PENTATONIC.size()] + 12 * (n / PENTATONIC.size()))


## Emitted once every sound has been synthesized.
signal ready_to_play


func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	# Synthesize one sound per frame so the game appears immediately (the web build
	# is slower); any sound requested before it's built is simply skipped.
	var recipes := {
		"reel_stop": _reel_stop, "reel_spin": _reel_spin, "click": _click,
		"gem_land": _gem_land, "vault": _vault, "anticipation": _anticipation,
		"win": _win, "big_win": _big_win, "coin_tick": _coin_tick,
		"fanfare": _fanfare, "whoosh": _whoosh, "jackpot": _jackpot, "firework": _firework,
	}
	for sound: String in recipes:
		await get_tree().process_frame
		_sounds[sound] = recipes[sound].call()
	ready_to_play.emit()


func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _sounds.has(sound):
		return
	var player: AudioStreamPlayer = _players[0]
	for candidate: AudioStreamPlayer in _players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = _sounds[sound]
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func start_loop(sound: String, volume_db: float = 0.0) -> void:
	if _loops.has(sound) or not _sounds.has(sound):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _sounds[sound]
	player.volume_db = volume_db
	add_child(player)
	player.play()
	_loops[sound] = player


func stop_loop(sound: String) -> void:
	if _loops.has(sound):
		_loops[sound].queue_free()
		_loops.erase(sound)


## Every sound as a WAV stream, for previewing or exporting.
func streams() -> Dictionary:
	return _sounds


# --- Recipes ---------------------------------------------------------------

## Looping soft clatter while the reels spin.
func _reel_spin() -> AudioStreamWAV:
	var s := Synth.new(0.48)
	for k in 8:
		s.noise(k * 0.06, 0.025, 0.6, 2600.0, 1200.0, 110.0)
	return s.to_stream(true)


## Heavy thunk as a reel lands.
func _reel_stop() -> AudioStreamWAV:
	var s := Synth.new(0.2)
	s.tone(0.0, 0.18, 150.0, 60.0, 0.7, 22.0, 0.002)
	s.noise(0.0, 0.03, 0.35, 3000.0, 800.0, 80.0)
	return s.to_stream()


## Rising, trembling tone on a reel that could complete a feature.
func _anticipation() -> AudioStreamWAV:
	var s := Synth.new(0.9)
	s.tone(0.0, 0.9, 330.0, 880.0, 0.22, 0.0, 0.05, 14.0, 0.8)
	s.tone(0.0, 0.9, 495.0, 1320.0, 0.1, 0.0, 0.05, 14.0, 0.8)
	return s.to_stream()


## Gritty synth pluck when a Rune Gem lands, with a faint octave above (callers raise the
## pitch up the minor pentatonic as more land).
func _gem_land() -> AudioStreamWAV:
	var s := Synth.new(1.1)
	s.keys(0.0, A3, 0.9, 0.3, 0.003, 4.0, 0.7, 10.0, 0.3, 1.5)
	s.keys(0.0, A4, 0.5, 0.07, 0.003, 7.0, 0.5, 14.0)
	s.reverb(0.3, 0.78)
	return s.to_stream()


## A dark synth pad swelling in when a Vault (free games) lands: A-E-B, open and
## unresolved, over a low boom.
func _vault() -> AudioStreamWAV:
	var s := Synth.new(1.8)
	s.keys(0.0, A2, 1.5, 0.22, 0.08, 1.6, 0.35, 2.5, 0.4, 1.0)
	s.keys(0.03, E3, 1.45, 0.15, 0.08, 1.8, 0.35, 2.5, 0.0, 1.0)
	s.keys(0.06, B3, 1.4, 0.11, 0.08, 2.0, 0.35, 2.5, 0.0, 1.0)
	s.tone(0.0, 1.5, A1, A1, 0.15, 2.5, 0.01)
	s.reverb(0.4, 0.84)
	return s.to_stream()


## A rising A-minor arpeggio of overdriven synth plucks for an ordinary win.
func _win() -> AudioStreamWAV:
	var s := Synth.new(1.5)
	var notes := [A2, E3, A3, C4]
	for k in notes.size():
		s.keys(k * 0.085, notes[k], 1.1, 0.26, 0.004, 3.5, 0.6, 8.0, 0.4 if k < 2 else 0.0, 1.0)
	s.reverb(0.35)
	return s.to_stream()


## A longer arpeggio into a heavy, driven A-minor pad on a kick, for big wins (10x bet and up).
func _big_win() -> AudioStreamWAV:
	var s := Synth.new(2.6)
	var notes := [A2, C3, E3, A3, C4, E4]
	for k in notes.size():
		s.keys(k * 0.075, notes[k], 0.9, 0.22, 0.004, 4.0, 0.6, 8.0, 0.3, 1.0)
	for f: float in [A2, E3, A3, C4, E4]:
		s.keys(0.45, f, 2.0, 0.12, 0.1, 1.2, 0.5, 1.8, 0.35 if f == A2 else 0.0, 1.5)
	_kick(s, 0.45, 0.5)
	s.reverb(0.4, 0.85)
	return s.to_stream()


## Feature trigger (Hold & Spin or free games): industrial power-chord stabs, E, E, G, then
## a held A, each landing on a kick.
func _fanfare() -> AudioStreamWAV:
	var s := Synth.new(2.4)
	for hit: Array in [[0.0, E2, 0.2], [0.22, E2, 0.2], [0.45, G2, 0.4], [0.9, A2, 1.4]]:
		var at: float = hit[0]
		var root: float = hit[1]
		var held: float = hit[2]
		var decay := 6.0 if held < 0.5 else 1.2
		# A power chord: root, fifth and octave, heavily driven.
		for f: float in [root, root * 1.4983, root * 2.0]:
			s.keys(at, f, held, 0.13, 0.003, decay, 0.7, 6.0, 0.5 if f == root else 0.0, 3.0)
		_kick(s, at, 0.4)
	s.reverb(0.3, 0.82)
	return s.to_stream()


## Looping pulse while the win meter counts up: a running bass arpeggio in sixteenths,
## the driving sequencer line of 80s synth scores.
func _coin_tick() -> AudioStreamWAV:
	var s := Synth.new(0.48)
	var figure := [A2, E3, A3, E3, A2, E3, C4, E3]
	for k in figure.size():
		s.keys(k * 0.06, figure[k], 0.12, 0.24, 0.002, 14.0, 0.5, 20.0, 0.0, 0.8)
	s.reverb(0.25, 0.75, true)
	return s.to_stream(true)


## A firework bursting: a distant thump, a bang of noise, then a scatter of crackles as
## the stars burn.
func _firework() -> AudioStreamWAV:
	var s := Synth.new(1.4)
	s.tone(0.0, 0.5, 90.0, 38.0, 0.6, 7.0, 0.003)
	s.noise(0.0, 0.35, 0.8, 2400.0, 500.0, 12.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 22:
		var at := 0.15 + rng.randf() * 0.9
		s.noise(at, 0.012, 0.35 * (1.0 - at / 1.2), 6000.0, 4000.0, 300.0)
	s.reverb(0.35, 0.84)
	return s.to_stream()


## A kick drum: a falling sine thump with a click of noise.
func _kick(s: Synth, at: float, amp: float) -> void:
	s.tone(at, 0.4, 150.0, 42.0, amp, 8.0, 0.002)
	s.noise(at, 0.02, amp * 0.4, 4000.0, 1500.0, 120.0)


## Swell of noise as Hold & Spin's empty cells start a respin.
func _whoosh() -> AudioStreamWAV:
	var s := Synth.new(0.55)
	s.noise(0.0, 0.55, 1.2, 500.0, 4000.0, 4.0, 0.25)
	return s.to_stream()


## A power-chord hit, a synth run up two octaves of A minor, then a huge driven A-minor-7
## pad over a kick and a low boom.
func _jackpot() -> AudioStreamWAV:
	var s := Synth.new(3.4)
	for f: float in [A2, A2 * 1.4983, A3]:
		s.keys(0.0, f, 0.3, 0.16, 0.003, 6.0, 0.7, 6.0, 0.5 if f == A2 else 0.0, 3.0)
	_kick(s, 0.0, 0.45)
	var run := [A2, C3, E3, G3, A3, C4, E4, G4, A4, C5]
	for k in run.size():
		s.keys(0.15 + k * 0.055, run[k], 0.6, 0.17, 0.004, 4.5, 0.6, 8.0, 0.0, 1.0)
	for f: float in [A2, E3, A3, C4, E4, G4]:
		s.keys(0.75, f, 2.6, 0.1, 0.12, 0.9, 0.5, 1.3, 0.35 if f == A2 else 0.0, 2.0)
	_kick(s, 0.75, 0.5)
	s.tone(0.75, 2.6, A1, A1, 0.25, 1.2, 0.01)
	s.reverb(0.45, 0.86)
	return s.to_stream()


## Small tick for buttons.
func _click() -> AudioStreamWAV:
	var s := Synth.new(0.05)
	s.tone(0.0, 0.04, 1800.0, 1200.0, 0.25, 80.0, 0.001)
	s.noise(0.0, 0.01, 0.2, 5000.0, 5000.0, 200.0)
	return s.to_stream()
