extends Control
## Overlay that draws winning paylines through the centers of the reel cells, as
## crackling lightning bolts: a glow in the line's own color around a white-hot core,
## re-forked and flickering many times a second.

const Config := preload("res://scripts/math/slot_config.gd")

# Each payline keeps its own color, cycling through this gem palette.
const LINE_COLORS := [
	Color("ff4d6d"), Color("4dd0e1"), Color("f3c969"), Color("9ccc3c"), Color("b388ff"),
	Color("ff9e40"), Color("40c4ff"), Color("f06292"),
]
const STRIKE_INTERVAL := 0.06  # seconds between new bolt shapes
const JAG := 11.0  # how far (px) the first split of each stretch may wander off the line
const DETAIL := 4  # midpoint splits per stretch between cell centers (2^4 = 16 kinks)
const BRANCH_CHANCE := 0.12  # chance of a short fork at each kink
const CORE := Color(0.92, 0.97, 1.0)  # white with a touch of electric blue
const STORM_COLOR := Color("22cfc0")  # the Rune Gem's teal
const STORM_JAG := 44.0
const STORM_BOLT_LIFE := 0.3  # seconds

var _storm_bolts: Array = []  # Rune Storm strikes: {points, branches, age}
var _cell_size := Vector2.ZERO
var _gap := 0.0
var _line_wins: Array = []
var _rng := RandomNumberGenerator.new()
var _bolts: Array = []  # per line: {points, branches: [PackedVector2Array], flicker}
var _since_strike := 0.0


func setup(cell_size: Vector2, gap: float) -> void:
	_cell_size = cell_size
	_gap = gap
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	set_process(false)


## Draws the given line wins (entries from SlotEngine.evaluate's line_wins).
func show_lines(line_wins: Array) -> void:
	_line_wins = line_wins
	_strike()
	set_process(not line_wins.is_empty() or not _storm_bolts.is_empty())


func clear() -> void:
	show_lines([])


## Rune Storm: a bolt from above the reels down into a cell, gone in a moment.
func strike_cell(reel: int, row: int) -> void:
	var to := cell_center(reel, row)
	var from := Vector2(to.x + _rng.randf_range(-70.0, 70.0), -_cell_size.y * 0.4)
	var points := _jagged(from, to, STORM_JAG)
	var branches: Array = []
	for k in range(1, points.size() - 1):
		if _rng.randf() < BRANCH_CHANCE:
			branches.append(_branch(points[k], points[k] - points[k - 1]))
	_storm_bolts.append({"points": points, "branches": branches, "age": 0.0})
	set_process(true)
	queue_redraw()


func cell_center(reel: int, row: int) -> Vector2:
	return Vector2(reel, row) * (_cell_size + Vector2(_gap, _gap)) + _cell_size / 2


func _process(delta: float) -> void:
	_since_strike += delta
	if _since_strike >= STRIKE_INTERVAL:
		_strike()
	if _storm_bolts.is_empty():
		return
	for bolt: Dictionary in _storm_bolts:
		bolt.age += delta
	_storm_bolts = _storm_bolts.filter(func(b): return b.age < STORM_BOLT_LIFE)
	if _storm_bolts.is_empty() and _line_wins.is_empty():
		set_process(false)
	queue_redraw()


## New jagged shapes and flicker for every shown line.
func _strike() -> void:
	_since_strike = 0.0
	_bolts.clear()
	for line_win: Dictionary in _line_wins:
		var path := _line_path(line_win.line)
		var points := PackedVector2Array([path[0]])
		var branches: Array = []
		for i in path.size() - 1:
			var stretch := _jagged(path[i], path[i + 1])
			for k in range(1, stretch.size()):
				points.append(stretch[k])
				if k < stretch.size() - 1 and _rng.randf() < BRANCH_CHANCE:
					branches.append(_branch(stretch[k], stretch[k] - stretch[k - 1]))
		_bolts.append({"points": points, "branches": branches, "flicker": _rng.randf_range(0.7, 1.0)})
	queue_redraw()


## The line through its cells, run off both edges of the reels so it reads as a payline.
func _line_path(line: int) -> PackedVector2Array:
	var rows: Array = Config.PAYLINES[line]
	var path := PackedVector2Array()
	for reel in Config.REELS:
		path.append(cell_center(reel, rows[reel]))
	path.insert(0, path[0] - Vector2(_cell_size.x / 2, 0))
	path.append(path[path.size() - 1] + Vector2(_cell_size.x / 2, 0))
	return path


## Midpoint displacement: split the stretch, nudge each midpoint sideways by a random
## amount that halves at every level, so it zigzags like real lightning but always
## passes through the cell centers.
func _jagged(from: Vector2, to: Vector2, amount: float = JAG) -> PackedVector2Array:
	var points := PackedVector2Array([from, to])
	for level in DETAIL:
		var next := PackedVector2Array([points[0]])
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var normal := (b - a).orthogonal().normalized()
			next.append((a + b) / 2 + normal * _rng.randf_range(-amount, amount))
			next.append(b)
		points = next
		amount *= 0.5
	return points


## A short fork off the bolt, heading roughly the same way and bending away.
func _branch(start: Vector2, heading: Vector2) -> PackedVector2Array:
	var direction := heading.normalized().rotated(_rng.randf_range(-1.0, 1.0))
	var points := PackedVector2Array([start])
	var at := start
	for i in _rng.randi_range(2, 4):
		direction = direction.rotated(_rng.randf_range(-0.6, 0.6))
		at += direction * _rng.randf_range(8.0, 16.0)
		points.append(at)
	return points


func _draw() -> void:
	var font := get_theme_default_font()
	for bolt: Dictionary in _storm_bolts:
		var fade: float = 1.0 - bolt.age / STORM_BOLT_LIFE
		draw_polyline(bolt.points, Color(STORM_COLOR, 0.3 * fade), 24.0, true)
		draw_polyline(bolt.points, Color(STORM_COLOR.lerp(Color.WHITE, 0.4), 0.85 * fade), 7.0, true)
		draw_polyline(bolt.points, Color(CORE, fade), 3.0, true)
		for branch: PackedVector2Array in bolt.branches:
			draw_polyline(branch, Color(STORM_COLOR, 0.6 * fade), 4.0, true)
			draw_polyline(branch, Color(CORE, 0.8 * fade), 1.4, true)
	for i in _bolts.size():
		var line: int = _line_wins[i].line
		var color: Color = LINE_COLORS[line % LINE_COLORS.size()]
		var bolt: Dictionary = _bolts[i]
		var f: float = bolt.flicker
		# Wide soft glow in the line's color, a brighter band, then the white-hot core.
		draw_polyline(bolt.points, Color(color, 0.22 * f), 18.0, true)
		draw_polyline(bolt.points, Color(color.lerp(Color.WHITE, 0.35), 0.75 * f), 6.0, true)
		draw_polyline(bolt.points, Color(CORE, f), 2.4, true)
		for branch: PackedVector2Array in bolt.branches:
			draw_polyline(branch, Color(color, 0.5 * f), 4.0, true)
			draw_polyline(branch, Color(CORE, 0.8 * f), 1.4, true)
		# Badge with the line number on the left edge (steady, so it stays readable).
		var badge: Vector2 = bolt.points[0]
		draw_circle(badge, 17, Color(color, 0.35))
		draw_circle(badge, 15, color)
		draw_string(font, badge + Vector2(-15, 6), str(line + 1), HORIZONTAL_ALIGNMENT_CENTER, 30, 16, Color.BLACK)
