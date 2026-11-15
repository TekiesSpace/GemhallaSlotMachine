extends Control
## A fireworks show drawn in code: rockets climb from the bottom of the screen trailing
## sparks, then burst into a ball of colored stars that drift down under gravity, twinkle
## and fade. Glows add up (additive blending), like light in a night sky.
## start() / stop(); a stopped show lets the last bursts finish.

const COLORS := [
	Color("f3c969"), Color("ff5e7e"), Color("8e6bff"), Color("2fe0c8"),
	Color("6fb8ff"), Color("ffffff"), Color("ff9a3c"), Color("7dff8a"),
]
const GRAVITY := 160.0  # px/s^2 on the stars
const DRAG := 1.15  # how quickly stars lose their burst speed
const LAUNCH_EVERY := Vector2(0.22, 0.5)  # seconds between rockets, random in this range
const STARS := Vector2i(80, 140)  # stars per burst
const STAR_LIFE := Vector2(1.4, 2.3)  # seconds
const CLEAR_MIDDLE := 0.25  # half-width (share of the screen) kept clear for the winner card

## Called with each burst (for its sound).
signal burst

var _rockets: Array = []  # each: {pos, vel, color, fuse}
var _stars: Array = []  # each: {pos, vel, color, life, age, size, twinkle}
var _running := false
var _next_launch := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow
	_rng.randomize()
	set_process(false)


func start() -> void:
	_running = true
	_next_launch = 0.0
	set_process(true)


func stop() -> void:
	_running = false


func _process(delta: float) -> void:
	if _running:
		_next_launch -= delta
		if _next_launch <= 0.0:
			_next_launch = _rng.randf_range(LAUNCH_EVERY.x, LAUNCH_EVERY.y)
			_launch()
	for rocket: Dictionary in _rockets:
		rocket.vel.y += GRAVITY * 0.35 * delta
		rocket.pos += rocket.vel * delta
		rocket.fuse -= delta
		# A short trail of sparks behind the climbing rocket.
		if _rng.randf() < 0.7:
			_add_star(rocket.pos, Vector2(_rng.randf_range(-20, 20), _rng.randf_range(10, 50)),
				Color(1.0, 0.85, 0.55), 0.45, 1.6)
	for rocket: Dictionary in _rockets.filter(func(r): return r.fuse <= 0.0):
		_explode(rocket)
	_rockets = _rockets.filter(func(r): return r.fuse > 0.0)
	var drag := exp(-DRAG * delta)
	for star: Dictionary in _stars:
		star.vel *= drag
		star.vel.y += GRAVITY * delta
		star.pos += star.vel * delta
		star.age += delta
	_stars = _stars.filter(func(s): return s.age < s.life)
	if not _running and _rockets.is_empty() and _stars.is_empty():
		set_process(false)
	queue_redraw()


func _launch() -> void:
	# Mostly beside the card, where they can be seen; now and then right over its top.
	var x: float
	if _rng.randf() < 0.2:
		x = _rng.randf_range(size.x * (0.5 - CLEAR_MIDDLE), size.x * (0.5 + CLEAR_MIDDLE))
	else:
		x = _rng.randf_range(0.06, 0.5 - CLEAR_MIDDLE) * size.x
		if _rng.randf() < 0.5:
			x = size.x - x
	var from := Vector2(x, size.y + 10)
	var peak := _rng.randf_range(size.y * 0.1, size.y * 0.45)
	if absf(x - size.x * 0.5) < size.x * CLEAR_MIDDLE:
		peak = _rng.randf_range(size.y * 0.06, size.y * 0.14)  # above the card
	var climb := from.y - peak
	var time := _rng.randf_range(0.9, 1.3)
	_rockets.append({
		"pos": from, "vel": Vector2(_rng.randf_range(-60, 60), -climb / time - GRAVITY * 0.175 * time),
		"color": COLORS[_rng.randi() % COLORS.size()], "fuse": time,
	})


func _explode(rocket: Dictionary) -> void:
	burst.emit()
	var color: Color = rocket.color
	# Some bursts carry a second color on alternate stars.
	var second: Color = COLORS[_rng.randi() % COLORS.size()] if _rng.randf() < 0.4 else color
	var count := _rng.randi_range(STARS.x, STARS.y)
	var speed := _rng.randf_range(300.0, 470.0)
	var life := _rng.randf_range(STAR_LIFE.x, STAR_LIFE.y)
	for i in count:
		# Evenly round the circle with a little jitter, so it reads as a ball, not a smear.
		var angle := TAU * i / count + _rng.randf_range(-0.05, 0.05)
		var v := Vector2.from_angle(angle) * speed * _rng.randf_range(0.85, 1.05)
		_add_star(rocket.pos, v, color if i % 2 == 0 else second, life * _rng.randf_range(0.8, 1.1), 3.0)
	# A quick, soft flash at the center.
	_add_star(rocket.pos, Vector2.ZERO, color.lerp(Color.WHITE, 0.6), 0.15, 12.0)


func _add_star(pos: Vector2, vel: Vector2, color: Color, life: float, star_size: float) -> void:
	_stars.append({"pos": pos, "vel": vel, "color": color, "life": life, "age": 0.0,
		"size": star_size, "twinkle": _rng.randf() * TAU})


func _draw() -> void:
	for rocket: Dictionary in _rockets:
		draw_circle(rocket.pos, 3.0, Color(1.0, 0.9, 0.7))
	for star: Dictionary in _stars:
		var fade: float = 1.0 - star.age / star.life
		# Stars twinkle as they fade out.
		var twinkle := 0.75 + 0.25 * sin(star.age * 22.0 + star.twinkle)
		var color: Color = star.color
		var a := fade * fade * twinkle
		draw_circle(star.pos, star.size * 2.6, Color(color, a * 0.18))  # soft glow
		draw_circle(star.pos, star.size, Color(color.lerp(Color.WHITE, 0.35), a))
