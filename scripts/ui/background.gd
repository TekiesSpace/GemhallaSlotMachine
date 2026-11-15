extends Control
## Backdrop: a deep violet night-sky gradient, a soft glow behind the reels, and gem
## dust that twinkles in the gem colors.

const TOP := Color("2a1544")
const BOTTOM := Color("07040d")
const GLOW := Color(0.55, 0.3, 0.95)
const DUST_COLORS := [Color("cfefff"), Color("ff6b8a"), Color("4fe39a"), Color("6f9bff"), Color("f3c969"), Color("b388ff")]
const DUST_COUNT := 80

var _dust: Array = []  # [normalized position, radius, phase, color]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in DUST_COUNT:
		_dust.append([
			Vector2(rng.randf(), rng.randf()), rng.randf_range(0.8, 2.4),
			rng.randf() * TAU, DUST_COLORS[rng.randi() % DUST_COLORS.size()],
		])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([TOP, TOP, BOTTOM, BOTTOM]))
	# Stacked translucent circles make a soft radial glow behind the reels.
	var center := Vector2(size.x / 2, size.y * 0.52)
	for i in 32:
		draw_circle(center, lerpf(580.0, 90.0, i / 31.0), Color(GLOW, 0.009))
	var t := Time.get_ticks_msec() / 1000.0
	for dust: Array in _dust:
		var pos: Vector2 = dust[0] * size
		var radius: float = dust[1]
		var twinkle := maxf(0.0, sin(t * 1.3 + dust[2]))
		var color: Color = dust[3]
		draw_circle(pos, radius, Color(color, 0.15 + 0.6 * twinkle))
		if radius > 1.8 and twinkle > 0.7:
			# The brightest specks flare into a tiny cross.
			var arm := radius * 3.0 * twinkle
			draw_line(pos - Vector2(arm, 0), pos + Vector2(arm, 0), Color(color, 0.5 * twinkle), 1.0, true)
			draw_line(pos - Vector2(0, arm), pos + Vector2(0, arm), Color(color, 0.5 * twinkle), 1.0, true)
