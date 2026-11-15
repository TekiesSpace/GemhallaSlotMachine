extends Control
## One reel cell. Draws its symbol as faceted vector art, so the prototype looks like
## gems without any image files. To use real PNG art later, swap _draw for a texture.

const GOLD := Color("f3c969")
const PANEL_COLOR := Color("1d1730")
const EMPTY_COLOR := Color("140f22")
const GEM_COLORS := {
	"H1": Color("cfefff"), "H2": Color("d4143a"), "H3": Color("16a05a"), "H4": Color("2452d6"),
	"ORB": Color("22cfc0"), "SCAT": Color("8e44d9"),
}
# Low symbols are card ranks tinted like lesser gems: [text, color].
const LETTERS := {
	"A": ["A", Color("a66be0")], "K": ["K", Color("f0902e")], "Q": ["Q", Color("f06292")],
	"J": ["J", Color("e8c547")], "T": ["10", Color("4dd0e1")], "N": ["9", Color("9ccc3c")],
}
const DEFAULT_CAPTIONS := {"WILD": "WILD", "SCAT": "FREE GAMES"}
# Facets facing this direction are lit; the far side is shaded.
const LIGHT_DIR := Vector2(-0.6, -0.8)

enum WinState { NORMAL, WIN, DIM }

## Pseudo-symbol for an empty Hold & Spin cell that is mid-respin (animated streaks).
const SPINNING := "~"

const DIM_MODULATE := Color(0.42, 0.42, 0.5)

# Symbols whose sparkle twinkles (they redraw every frame).
const TWINKLE := ["H1", "H2", "H3", "H4", "ORB", "WILD"]

## Optional image art, shared by all tiles: symbol id -> {texture: Texture2D,
## glow: Color, modulate: Color, frames: Array[Texture2D], rest: int}. A symbol
## listed here is drawn from its image instead of the vector gem; anything not
## listed keeps the drawn version. With `frames`, a winning tile spins through them.
static var art := {}

const SPIN_FPS := 14.0  # rotation speed of a winning gem, in frames per second

# How image gems lean back toward the viewer (see _tilt).
const TILT_ROTATION := -0.12  # radians, about 7 degrees
const TILT_SKEW := 0.12
const TILT_SCALE := Vector2(1.02, 0.93)

var symbol := ""
var caption := ""
var _panel := StyleBoxFlat.new()
var _win_state := WinState.NORMAL
var _phase := randf() * TAU  # so neighbouring gems don't twinkle in sync
var _win_since_ms := 0  # when this tile started winning, so its spin starts at rest


func _init() -> void:
	# Image gems are drawn at about half their source size; mipmaps keep facets smooth.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_panel.set_corner_radius_all(10)
	_panel.set_border_width_all(2)
	_panel.border_color = GOLD.darkened(0.45)


## Shows a symbol id from slot_config ("" = empty cell). caption overrides the default label.
func show_symbol(new_symbol: String, new_caption: String = "") -> void:
	symbol = new_symbol
	caption = new_caption
	set_process(_animates())
	queue_redraw()


func _ready() -> void:
	# Godot turns processing on for any script with _process; only animated tiles need it.
	set_process(_animates())


func _process(_delta: float) -> void:
	queue_redraw()  # animates spin streaks and sparkle twinkles


func _animates() -> bool:
	return symbol == SPINNING or TWINKLE.has(symbol) or art.has(symbol)


## WIN gives the tile a bright gold frame; DIM darkens it so the winners stand out.
func set_win_state(state: WinState) -> void:
	if state == WinState.WIN and _win_state != WinState.WIN:
		_win_since_ms = Time.get_ticks_msec()
	_win_state = state
	modulate = DIM_MODULATE if state == WinState.DIM else Color.WHITE
	queue_redraw()


func _draw() -> void:
	var winning := _win_state == WinState.WIN
	_panel.bg_color = EMPTY_COLOR if symbol.is_empty() or symbol == SPINNING else PANEL_COLOR
	_panel.border_color = GOLD if winning else GOLD.darkened(0.45)
	_panel.set_border_width_all(4 if winning else 2)
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	if symbol.is_empty():
		return
	if symbol == SPINNING:
		_draw_spin_streaks()
		return
	_draw_recess()

	var label: String = caption if not caption.is_empty() else DEFAULT_CAPTIONS.get(symbol, "")
	var area := Rect2(Vector2.ZERO, size).grow(-12)
	if not label.is_empty():
		area.size.y -= 22
	var c := area.get_center()
	var r := minf(area.size.x, area.size.y) * 0.5

	if art.has(symbol):
		_draw_art(art[symbol], c, r)
	else:
		_draw_vector_symbol(c, r, area)

	if not label.is_empty():
		var font := get_theme_default_font()
		var pos := Vector2(0, size.y - 13)
		var color := Color.WHITE if label.is_valid_int() else GOLD
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, 6, Color.BLACK)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, color)


## An image symbol: glow halo, the picture fitted to the cell, and a twinkle.
## Makes the tile read as a recessed pocket: the rim casts a shadow down from the top
## edge, a soft spotlight pools behind the symbol, and the bottom lip catches light.
func _draw_recess() -> void:
	var inset := 10.0  # stay inside the rounded corners
	var shade := Color(0, 0, 0, 0.5)
	draw_polygon(
		PackedVector2Array([Vector2(inset, 4), Vector2(size.x - inset, 4), Vector2(size.x - inset, 26), Vector2(inset, 26)]),
		PackedColorArray([shade, shade, Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	var spot := size / 2 + Vector2(0, 6)
	for i in 10:
		draw_circle(spot, minf(size.x, size.y) * (0.5 - i * 0.04), Color(0.75, 0.62, 1.0, 0.016))
	draw_line(Vector2(inset + 4, size.y - 5), Vector2(size.x - inset - 4, size.y - 5), Color(1, 1, 1, 0.12), 2.0)


## An image symbol, layered for depth: glow, a contact shadow on the "floor", a soft
## drop shadow of the stone itself, the stone, then top-lit volume shading.
func _draw_art(entry: Dictionary, c: Vector2, r: float) -> void:
	# Slightly smaller than the cell and lifted, so the floor shadow shows beneath it.
	# (Source images carry some transparent margin, hence > 2r.)
	var side := r * 2.05 * float(entry.get("size", 1.0))
	var lifted := c - Vector2(0, r * 0.1)
	# Drawn centered on the origin; _tilt() places and leans it, plus any extra turn
	# the art needs to stand upright (pose_angle).
	var pose: float = entry.get("pose_angle", 0.0)
	var rect := Rect2(-Vector2(side, side) / 2, Vector2(side, side))
	var texture: Texture2D = entry.texture
	if _win_state == WinState.WIN and entry.has("frames"):
		var frames: Array = entry.frames
		var turned := int((Time.get_ticks_msec() - _win_since_ms) / 1000.0 * SPIN_FPS)
		texture = frames[(entry.get("rest", 0) + turned) % frames.size()]
	var tint: Color = entry.get("modulate", Color.WHITE)

	_draw_halo(c, r, entry.get("glow", GOLD))
	# Contact shadow: a squashed, soft dark ellipse where the stone meets the floor.
	draw_set_transform(Vector2(c.x + r * 0.08, c.y + r * 0.95), 0.0, Vector2(1.0, 0.24))
	for i in 16:
		draw_circle(Vector2.ZERO, r * (0.9 - i * 0.05), Color(0, 0, 0, 0.075))
	draw_set_transform(Vector2.ZERO)
	# Drop shadow: the stone's own silhouette pushed down-right, stacked to soften it.
	for k in 5:
		draw_set_transform_matrix(_tilt(lifted + Vector2(3 + k * 2.0, 6 + k * 2.5), pose))
		draw_texture_rect(texture, rect, false, Color(0, 0, 0, 0.2))
	draw_set_transform_matrix(_tilt(lifted, pose))
	# The renders are about half translucent, so back the stone with its own silhouette
	# in its body color; otherwise the drop shadow shows through as dark blotches.
	var glow: Color = entry.get("glow", GOLD)
	var body: Color = entry.get("backing", glow.darkened(0.2))
	for k in 3:
		draw_texture_rect(texture, rect, false, Color(body, 1.0))
	draw_texture_rect(texture, rect, false, tint)
	_draw_volume(texture, rect, tint)
	if entry.get("rune", false):
		_draw_rune_glyph(side)
	draw_set_transform(Vector2.ZERO)
	_draw_sparkle(c + entry.get("sparkle", Vector2(-0.5, -0.55)) * r, r * 0.24)


## Leans a stone back toward the viewer: a small turn plus a skew and a slight vertical
## squash, which reads as the top tipping away in perspective.
func _tilt(at: Vector2, pose: float = 0.0) -> Transform2D:
	return Transform2D(TILT_ROTATION + pose, TILT_SCALE, TILT_SKEW, at)


## The Fehu (wealth) rune set into the Rune Gem: a soft glow under a bright stroke.
## Drawn in the stone's own (tilted) space, centred on the wide part of the pear.
func _draw_rune_glyph(side: float) -> void:
	var s := side * 0.36
	var o := Vector2(side * 0.04, -side * 0.05)
	var strokes := [
		[Vector2(-0.12, -0.32), Vector2(-0.12, 0.32)],
		[Vector2(-0.12, -0.08), Vector2(0.18, -0.3)],
		[Vector2(-0.12, 0.08), Vector2(0.18, -0.14)],
	]
	for stroke: Array in strokes:
		draw_line(o + stroke[0] * s, o + stroke[1] * s, Color(0.7, 1.0, 0.95, 0.35), 8.0, true)
	for stroke: Array in strokes:
		draw_line(o + stroke[0] * s, o + stroke[1] * s, Color(1, 1, 1, 0.95), 3.0, true)


## Lights the stone from above: thin horizontal slices of the upper half are redrawn
## brighter toward the top, giving it a rounded volume. (The lower half is left as
## is; darkening it made harsh dark spots.)
func _draw_volume(texture: Texture2D, rect: Rect2, tint: Color) -> void:
	const SLICES := 20  # across the top half; fine enough that steps don't band
	var source := texture.get_size()
	for k in SLICES:
		var t := float(k) / SLICES * 0.5
		var src := Rect2(0, t * source.y, source.x, source.y * 0.5 / SLICES)
		var dst := Rect2(rect.position.x, rect.position.y + t * rect.size.y, rect.size.x, rect.size.y * 0.5 / SLICES)
		var light := 1.0 - t * 2.0  # 1 at the top, fading to 0 at the middle
		draw_texture_rect_region(texture, dst, src, Color(tint.r * 2.2, tint.g * 2.2, tint.b * 2.2, 0.45 * light))


func _draw_vector_symbol(c: Vector2, r: float, area: Rect2) -> void:
	match symbol:
		"H1":
			_draw_halo(c, r, GEM_COLORS.H1)
			_draw_facets(_diamond(), c, r, GEM_COLORS.H1)
			_draw_glint(c, r)
			_draw_sparkle(c + Vector2(-0.55, -0.6) * r, r * 0.28)
			_draw_sparkle(c + Vector2(0.62, -0.25) * r, r * 0.16, 2.1)
		"H2":
			_draw_halo(c, r, GEM_COLORS.H2)
			_draw_facets(_crown_cut(8, 0.8, 1.0, 0.55, PI / 8), c, r, GEM_COLORS.H2)
			_draw_glint(c, r)
			_draw_sparkle(c + Vector2(-0.4, -0.6) * r, r * 0.24)
		"H3":
			_draw_halo(c, r, GEM_COLORS.H3)
			_draw_facets(_step_cut(), c, r, GEM_COLORS.H3)
			_draw_glint(c, r)
			_draw_sparkle(c + Vector2(-0.6, -0.5) * r, r * 0.24)
		"H4":
			_draw_halo(c, r, GEM_COLORS.H4)
			_draw_facets(_brilliant(), c, r, GEM_COLORS.H4)
			_draw_glint(c, r)
			_draw_sparkle(c + Vector2(-0.5, -0.6) * r, r * 0.24)
		"WILD":
			_draw_halo(c, r, GOLD)
			_draw_crown(c, r)
			_draw_sparkle(c + Vector2(0, -0.75) * r, r * 0.3)
		"SCAT":
			_draw_vault(c, r)
		"ORB":
			_draw_rune_gem(c, r)
		_:
			if LETTERS.has(symbol):
				_draw_letter(LETTERS[symbol][0], LETTERS[symbol][1], c, area.size.y)


# --- Gem shapes (unit coordinates, y down; each facet is [points, shade]) ------

## Side view of a brilliant-cut diamond: crown facets over a pointed pavilion.
func _diamond() -> Array:
	var g := [Vector2(-1, -0.2), Vector2(-0.5, -0.2), Vector2(0, -0.2), Vector2(0.5, -0.2), Vector2(1, -0.2)]
	var t := [Vector2(-0.5, -0.65), Vector2(0, -0.65), Vector2(0.5, -0.65)]
	var culet := Vector2(0, 0.9)
	return [
		[[g[0], t[0], g[1]], 0.35],
		[[t[0], t[1], g[2], g[1]], 0.55],
		[[t[1], t[2], g[3], g[2]], 0.2],
		[[t[2], g[4], g[3]], -0.15],
		[[g[0], g[1], culet], 0.1],
		[[g[1], g[2], culet], 0.3],
		[[g[2], g[3], culet], -0.25],
		[[g[3], g[4], culet], -0.45],
	]


## Top view of an n-sided cut: a ring of bevel facets around a flat table.
func _crown_cut(n: int, rx: float, ry: float, table: float, start_angle: float) -> Array:
	var outer := _ring(n, rx, ry, start_angle)
	var inner := _ring(n, rx * table, ry * table, start_angle)
	var facets: Array = []
	for i in n:
		var j := (i + 1) % n
		var quad := [outer[i], outer[j], inner[j], inner[i]]
		facets.append([quad, _shade(quad)])
	facets.append([inner, 0.15])
	return facets


## Emerald (step) cut: nested cut-corner rectangles stepping down to the table.
func _step_cut() -> Array:
	var rings: Array = []
	for s: float in [1.0, 0.78, 0.56]:
		rings.append(_octagon_rect(1.0 * s, 0.72 * s, 0.26 * s))
	var facets: Array = []
	for k in 2:
		for i in 8:
			var j := (i + 1) % 8
			var quad := [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
			facets.append([quad, _shade(quad) * (1.0 - 0.3 * k)])
	facets.append([rings[2], 0.25])
	return facets


## Top view of a round brilliant: octagonal table, star facets, 16-point girdle.
func _brilliant() -> Array:
	var outer := _ring(16, 1.0, 1.0, -PI / 2)
	var table := _ring(8, 0.55, 0.55, -PI / 2)
	var facets: Array = []
	for j in 8:
		var t0: Vector2 = table[j]
		var t1: Vector2 = table[(j + 1) % 8]
		var o0: Vector2 = outer[2 * j]
		var o1: Vector2 = outer[2 * j + 1]
		var o2: Vector2 = outer[(2 * j + 2) % 16]
		var left := [t0, o0, o1]
		var star := [t0, o1, t1]
		var right := [t1, o1, o2]
		facets.append([left, _shade(left) + 0.1])
		facets.append([star, _shade(star) * 0.6 + 0.2])
		facets.append([right, _shade(right) - 0.1])
	facets.append([table, 0.25])
	return facets


func _ring(n: int, rx: float, ry: float, start_angle: float) -> Array:
	var points: Array = []
	for i in n:
		var a := start_angle + TAU * i / n
		points.append(Vector2(cos(a) * rx, sin(a) * ry))
	return points


func _octagon_rect(hx: float, hy: float, cut: float) -> Array:
	return [
		Vector2(-hx + cut, -hy), Vector2(hx - cut, -hy), Vector2(hx, -hy + cut), Vector2(hx, hy - cut),
		Vector2(hx - cut, hy), Vector2(-hx + cut, hy), Vector2(-hx, hy - cut), Vector2(-hx, -hy + cut),
	]


func _shade(points: Array, strength: float = 0.45) -> float:
	var mid := Vector2.ZERO
	for p: Vector2 in points:
		mid += p
	mid /= points.size()
	return mid.normalized().dot(LIGHT_DIR) * strength


# --- Drawing ----------------------------------------------------------------

func _draw_facets(facets: Array, c: Vector2, r: float, base: Color) -> void:
	for facet: Array in facets:
		var shade: float = facet[1]
		var color := base.lightened(shade) if shade >= 0.0 else base.darkened(-shade)
		# Per-vertex colors: each facet brightens toward the top of the gem and darkens
		# toward the bottom, which reads as depth inside the stone.
		var colors := PackedColorArray()
		for p: Vector2 in facet[0]:
			colors.append(color.lightened(minf(-p.y * 0.25, 0.4)) if p.y < 0.0 else color.darkened(minf(p.y * 0.3, 0.45)))
		draw_polygon(_to_screen(facet[0], c, r), colors)
	var edge := base.lightened(0.6)
	edge.a = 0.8
	for facet: Array in facets:
		draw_polyline(_closed(_to_screen(facet[0], c, r)), edge, 1.0, true)


## Rune-colored streaks racing downward, so an empty cell reads as a spinning mini reel.
func _draw_spin_streaks() -> void:
	var glow := GEM_COLORS.ORB as Color
	var t := Time.get_ticks_msec() / 1000.0
	draw_circle(size / 2, minf(size.x, size.y) * 0.32, Color(glow, 0.07))
	for i in 5:
		var y := fposmod(t * 600.0 + i * size.y / 5.0, size.y - 16) + 8
		var fade := 0.15 + 0.35 * (y / size.y)
		draw_line(Vector2(18, y), Vector2(size.x - 18, y), Color(glow, fade), 3.0, true)


## Soft colored glow behind a gem.
func _draw_halo(c: Vector2, r: float, color: Color) -> void:
	for i in 12:
		draw_circle(c, r * (1.3 - i * 0.05), Color(color, 0.022))


## Slim specular streak across the upper-left of a gem.
func _draw_glint(c: Vector2, r: float) -> void:
	var streak := _to_screen([Vector2(-0.5, -0.4), Vector2(-0.2, -0.55), Vector2(-0.1, -0.47), Vector2(-0.42, -0.32)], c, r)
	draw_colored_polygon(streak, Color(1, 1, 1, 0.3))


## Four-point star that pulses in size and brightness (speed lets sparkles drift apart).
func _draw_sparkle(pos: Vector2, s: float, speed: float = 2.4) -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * speed + _phase)
	s *= pulse
	var k := s * 0.18
	var star := PackedVector2Array([
		pos + Vector2(0, -s), pos + Vector2(k, -k), pos + Vector2(s, 0), pos + Vector2(k, k),
		pos + Vector2(0, s), pos + Vector2(-k, k), pos + Vector2(-s, 0), pos + Vector2(-k, -k),
	])
	draw_colored_polygon(star, Color(1, 1, 1, 0.45 + 0.5 * pulse))


func _draw_crown(c: Vector2, r: float) -> void:
	var body := _to_screen([
		Vector2(-0.95, 0.45), Vector2(-0.95, -0.35), Vector2(-0.5, 0.05), Vector2(0, -0.75),
		Vector2(0.5, 0.05), Vector2(0.95, -0.35), Vector2(0.95, 0.45),
	], c, r)
	draw_colored_polygon(body, GOLD)
	draw_polyline(_closed(body), GOLD.darkened(0.5), 2.0, true)
	var band := _to_screen([Vector2(-0.95, 0.45), Vector2(0.95, 0.45), Vector2(0.95, 0.75), Vector2(-0.95, 0.75)], c, r)
	draw_colored_polygon(band, GOLD.darkened(0.25))
	draw_polyline(_closed(band), GOLD.darkened(0.5), 2.0, true)
	for tip: Vector2 in [Vector2(-0.95, -0.35), Vector2(0, -0.75), Vector2(0.95, -0.35)]:
		draw_circle(c + tip * r, r * 0.13, GEM_COLORS.H2)
	draw_circle(c + Vector2(-0.5, 0.6) * r, r * 0.1, GEM_COLORS.H4)
	draw_circle(c + Vector2(0, 0.6) * r, r * 0.1, GEM_COLORS.H3)
	draw_circle(c + Vector2(0.5, 0.6) * r, r * 0.1, GEM_COLORS.H4)


func _draw_vault(c: Vector2, r: float) -> void:
	draw_circle(c, r * 0.95, Color("2a1840"))
	draw_arc(c, r * 0.95, 0, TAU, 48, GOLD.darkened(0.2), 3.0, true)
	draw_arc(c, r * 0.7, 0, TAU, 40, GOLD.darkened(0.45), 2.0, true)
	for i in 8:
		var dir := Vector2.from_angle(TAU * i / 8)
		draw_line(c + dir * r * 0.42, c + dir * r * 0.7, GOLD.darkened(0.3), 3.0, true)
		draw_circle(c + dir * r * 0.83, r * 0.05, GOLD)
	_draw_facets(_brilliant(), c, r * 0.42, GEM_COLORS.SCAT)


func _draw_rune_gem(c: Vector2, r: float) -> void:
	var glow := GEM_COLORS.ORB as Color
	draw_circle(c, r * 1.05, Color(glow, 0.12))
	draw_circle(c, r * 0.9, Color(glow, 0.2))
	_draw_facets(_crown_cut(6, 1.0, 1.0, 0.55, 0.0), c, r * 0.8, glow)
	# A Fehu-style rune (wealth) carved into the table.
	var rune := Color(1, 1, 1, 0.9)
	var s := r * 0.8
	draw_line(c + Vector2(-0.12, -0.32) * s, c + Vector2(-0.12, 0.32) * s, rune, 2.5, true)
	draw_line(c + Vector2(-0.12, -0.08) * s, c + Vector2(0.18, -0.3) * s, rune, 2.5, true)
	draw_line(c + Vector2(-0.12, 0.08) * s, c + Vector2(0.18, -0.14) * s, rune, 2.5, true)
	_draw_sparkle(c + Vector2(-0.55, -0.55) * r, r * 0.22, 3.0)


func _draw_letter(text: String, color: Color, c: Vector2, height: float) -> void:
	var font := get_theme_default_font()
	var font_size := int(height * 0.8)
	# Baseline sits about a third of the font size below center, so capitals look centered.
	var pos := Vector2(0, c.y + font_size * 0.36)
	# Drop shadow, dark rim, then a pale outlined layer under the fill so the edges
	# (strongest top-left) catch light like a beveled stone.
	var pale := color.lightened(0.7)
	draw_string_outline(font, pos + Vector2(3, 4), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 14, Color(0, 0, 0, 0.45))
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 14, color.darkened(0.7))
	draw_string_outline(font, pos + Vector2(-2, -2), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 5, pale)
	draw_string(font, pos + Vector2(-2, -2), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, pale)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


func _to_screen(points: Array, c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(c + p * r)
	return out


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out
