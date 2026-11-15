extends RefCounted
## Tiny offline synthesizer: mixes tones, synth notes and noise into a float buffer, then
## converts it to an AudioStreamWAV. Lets the game ship every effect without audio files.

const RATE := 22050

# Reverb: four parallel comb filters (seconds) into two allpass diffusers, Schroeder style.
const COMBS := [0.0297, 0.0371, 0.0411, 0.0437]
const ALLPASSES := [0.005, 0.0017]

var buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _init(seconds: float) -> void:
	buf.resize(int(seconds * RATE))
	buf.fill(0.0)
	_rng.seed = 7  # same noise every launch


## Keyboard-synthesizer note, the classic analog sound: two sawtooth oscillators a little
## out of tune with each other (a thick, chorused tone) through a resonant low-pass filter
## that opens bright at the strike and closes as the note rings. `bright` is how far the
## filter opens (0..1), `filter_decay` how quickly it closes. A short attack and quick
## filter make a pluck; a slow attack and slow filter make a pad.
## `sub` mixes in a square wave an octave below, for weight; `drive` pushes the result
## into soft saturation, the gritty overdriven edge of 80s rock synths.
func keys(at: float, freq: float, length: float, amp: float, attack: float = 0.004,
		decay: float = 3.0, bright: float = 1.0, filter_decay: float = 9.0,
		sub: float = 0.0, drive: float = 0.0) -> void:
	const OVERSAMPLE := 2  # the filter runs twice per sample, so it stays stable when bright
	const DETUNE := 0.007
	const RESONANCE := 0.4
	var start := int(at * RATE)
	var n := mini(int(length * RATE), buf.size() - start)
	var phases := [0.0, 0.37]
	var steps := [freq * (1.0 - DETUNE) / RATE, freq * (1.0 + DETUNE) / RATE]
	var sub_phase := 0.0
	var sub_step := freq * 0.5 / RATE
	var low := 0.0
	var band := 0.0
	var level := 1.0
	var level_step := exp(-decay / RATE)
	var sweep := 1.0
	var sweep_step := exp(-filter_decay / RATE)
	var damping := 2.0 * (1.0 - RESONANCE)
	var gain := 1.0 + drive
	var makeup := 1.0 / tanh(gain * 0.5)  # keeps a driven note about as loud as a clean one
	for i in n:
		var t := float(i) / RATE
		var x := 0.0
		for k in 2:
			var p: float = phases[k]
			var dt: float = steps[k]
			x += 2.0 * p - 1.0 - _blep(p, dt)
			p += dt
			phases[k] = p - floorf(p)
		if sub > 0.0:
			var square := (1.0 if sub_phase < 0.5 else -1.0) + _blep(sub_phase, sub_step) \
					- _blep(fmod(sub_phase + 0.5, 1.0), sub_step)
			x += square * sub
			sub_phase += sub_step
			sub_phase -= floorf(sub_phase)
		x *= 0.7  # about as loud as a chime at the same amp once filtered
		# The cutoff follows the note (higher notes stay as bright) and sweeps down.
		var cutoff := minf(freq * 1.2 + bright * 5000.0 * sweep, RATE * OVERSAMPLE * 0.16)
		var f := 2.0 * sin(PI * cutoff / (RATE * OVERSAMPLE))
		for o in OVERSAMPLE:
			low += f * band
			var high := x - low - damping * band
			band += f * high
		var y := low * minf(t / attack, 1.0) * level
		if drive > 0.0:
			y = tanh(y * gain) * makeup * 0.5
		buf[start + i] += y * amp * _end_fade(t, length)
		level *= level_step
		sweep *= sweep_step


## PolyBLEP: smooths a sawtooth's jump so it doesn't alias into a harsh fizz.
func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


## Adds a hall's echo tail: `wet` of the reverberated sound mixed in, `room` from small
## (0.7) to large (0.88). For a looping sound, the tail wraps round to the start, so the
## loop stays seamless.
func reverb(wet: float, room: float = 0.82, loop: bool = false) -> void:
	var dry := buf.duplicate()
	var passes := 2 if loop else 1
	var source := PackedFloat32Array()
	for p in passes:
		source.append_array(dry)
	var out := PackedFloat32Array()
	out.resize(source.size())
	out.fill(0.0)
	for delay_s: float in COMBS:
		var d := int(delay_s * RATE)
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		var damp := 0.0
		for i in source.size():
			var y := line[i % d]
			# Damping in the feedback: highs die away first, as in a real room.
			damp = y * 0.6 + damp * 0.4
			line[i % d] = source[i] + damp * room
			out[i] += y * 0.25
	for delay_s: float in ALLPASSES:
		var d := int(delay_s * RATE)
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		for i in source.size():
			var held := line[i % d]
			var x := out[i]
			line[i % d] = x + held * 0.5
			out[i] = held - x * 0.5
	var offset := source.size() - dry.size()  # the second pass, for loops
	for i in buf.size():
		buf[i] = dry[i] + out[offset + i] * wet


## Sine that glides from f0 to f1, with optional exponential decay and tremolo.
func tone(at: float, length: float, f0: float, f1: float, amp: float, decay: float = 0.0,
		attack: float = 0.005, tremolo_hz: float = 0.0, tremolo_depth: float = 0.0) -> void:
	var start := int(at * RATE)
	var n := mini(int(length * RATE), buf.size() - start)
	var phase := 0.0
	var level := 1.0
	var step := exp(-decay / RATE)
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / length) / RATE
		var env := minf(t / attack, 1.0) * level * _end_fade(t, length)
		level *= step
		var trem := 1.0 if tremolo_depth == 0.0 else 1.0 - tremolo_depth * 0.5 * (1.0 - sin(TAU * tremolo_hz * t))
		buf[start + i] += sin(phase) * amp * env * trem


## Low-passed noise; the cutoff sweeps from cutoff0 to cutoff1 (Hz) over the sound.
func noise(at: float, length: float, amp: float, cutoff0: float, cutoff1: float,
		decay: float = 0.0, attack: float = 0.002) -> void:
	var start := int(at * RATE)
	var n := mini(int(length * RATE), buf.size() - start)
	var y := 0.0
	var level := 1.0
	var step := exp(-decay / RATE)
	for i in n:
		var t := float(i) / RATE
		# One-pole low-pass; the linear coefficient is close enough below ~5 kHz.
		var a := minf(TAU * lerpf(cutoff0, cutoff1, t / length) / RATE, 1.0)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		buf[start + i] += y * amp * minf(t / attack, 1.0) * level * _end_fade(t, length)
		level *= step


## Converts to 16-bit mono WAV, scaling down first if the mix would clip.
func to_stream(loop: bool = false) -> AudioStreamWAV:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(buf[i] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream


# 10 ms fade at the end of every voice so nothing clicks when it's cut off.
func _end_fade(t: float, length: float) -> float:
	return clampf((length - t) / 0.01, 0.0, 1.0)
