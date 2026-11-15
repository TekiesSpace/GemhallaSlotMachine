extends SceneTree
## Builds assets/gems/tiara_256.png, the Wild symbol, by rendering a 3D platinum tiara:
## a band that curves around the head, a row of pointed double-line arches (tallest in
## the middle) with diamonds pavé set along them, a claw-set brilliant hanging in each
## arch, pearls on the tips and a pearl drop under the center diamond. The studio,
## materials and builders are in tools/render_kit.gd.
##
## Needs a window (not --headless), from the project folder:
##   <Godot>_console.exe --path . --rendering-method forward_plus --script res://tools/build_tiara.gd

const RenderKit := preload("res://tools/render_kit.gd")

const OUT := "res://assets/gems/tiara_256.png"
const FILL := 0.96  # the tiara's width as a share of the picture

# The tiara sits on an oval (front-to-back DEPTH of side-to-side) and leans in toward the top.
const DEPTH := 0.85
const LEAN := 0.1
const BAND_SPAN := 74.0  # degrees either side of the front

# Arches: [center angle, half-width (degrees), height, bulge (degrees), stone radius,
# pearl radius]. Mirrored for angles != 0.
const ARCHES := [
	[0.0, 16.0, 0.95, 7.0, 0.09, 0.046],
	[31.0, 13.0, 0.66, 5.0, 0.062, 0.038],
	[56.0, 11.0, 0.42, 4.0, 0.045, 0.031],
]
# Scroll rings with pearl spikes where the arches meet: [angle, spike top].
const SCROLLS := [[17.0, 0.27], [44.5, 0.21], [68.5, 0.15]]

var kit: RenderKit


func _initialize() -> void:
	kit = RenderKit.new(self, 1400, Vector3(0, 1.75, 7.2), Vector3(0, 0.36, 0), 22.0, 7)
	_build_tiara()
	var picture: Image = await kit.capture(FILL)
	var err := picture.save_png(ProjectSettings.globalize_path(OUT))
	print("tiara_256.png: ", error_string(err))
	quit()


## A point on the tiara's surface: angle from the front (degrees) and height.
func _p(angle: float, h: float) -> Vector3:
	var t := deg_to_rad(angle)
	var r := 1.0 - LEAN * h
	return Vector3(r * sin(t), h, DEPTH * r * cos(t))


## Which way the tiara's surface faces there.
func _out(angle: float) -> Vector3:
	var t := deg_to_rad(angle)
	return Vector3(sin(t), LEAN, cos(t) / DEPTH).normalized()


func _build_tiara() -> void:
	# The band, with a row of pavé diamonds across its front.
	var band := PackedVector3Array()
	for i in 93:
		band.append(_p(-BAND_SPAN + i * BAND_SPAN * 2.0 / 92.0, 0.0))
	kit.tube(band, 0.05, 0.04)
	var a := -BAND_SPAN + 3.0
	while a <= BAND_SPAN - 3.0:
		kit.stone(_p(a, 0.0) + _out(a) * 0.036, _out(a), 0.036)
		a += 4.6
	for arch: Array in ARCHES:
		for side in ([1.0] if arch[0] == 0.0 else [-1.0, 1.0]):
			_arch(arch[0] * side, arch[1], arch[2], arch[3], arch[4], arch[5])
	for scroll: Array in SCROLLS:
		for side in [-1.0, 1.0]:
			var at: float = scroll[0] * side
			kit.ring(_p(at, 0.085), _out(at), 0.036, 0.011)
			kit.tube(PackedVector3Array([_p(at, 0.12), _p(at, scroll[1])]), 0.011, 0.008)
			kit.sphere(_p(at, scroll[1] + 0.024), 0.027, kit.pearl)


## One pointed arch: a pavé-set outer line, a finer pavé-set inner line, a claw-set stone
## hanging from the inner tip, a pearl on the outer tip (and a pearl drop under the
## tallest arch's stone).
func _arch(center: float, half: float, height: float, bulge: float, stone_r: float, pearl_r: float) -> void:
	for side in [-1.0, 1.0]:
		var outer := _curve(center + side * half, center + side * (half + bulge), center, 0.03, height)
		kit.tube(outer, 0.03, 0.022)
		_pave(outer, 0.024, 0.062)
		var inner := _curve(center + side * half * 0.6, center + side * (half * 0.6 + bulge * 0.6), center, 0.03, height * 0.78)
		kit.tube(inner, 0.019, 0.015)
		_pave(inner, 0.016, 0.044)
	kit.sphere(_p(center, height + 0.03), pearl_r, kit.pearl)
	# The stone hangs like a pendant from the inner arch's tip.
	var tip := height * 0.78
	var stone_h := tip - 0.05 - stone_r * 1.2
	var facing := _out(center)
	kit.collet(_p(center, stone_h) + facing * 0.012, facing, stone_r)
	kit.tube(PackedVector3Array([_p(center, tip), _p(center, stone_h + stone_r * 1.1)]), 0.006, 0.006)
	if height > 0.9:
		# Under the tallest arch's diamond, a pearl drop.
		var below := stone_h - stone_r * 1.15
		kit.tube(PackedVector3Array([_p(center, below), _p(center, below - 0.035)]), 0.005, 0.005)
		var drop := kit.sphere(_p(center, below - 0.035 - 0.044), 0.034, kit.pearl)
		drop.scale = Vector3(1.0, 1.3, 1.0)


## Pavé: little diamonds of `radius` every `gap` along the front of a line, clear of its
## foot and tip.
func _pave(line: PackedVector3Array, radius: float, gap: float) -> void:
	var travelled := 0.0
	for i in range(4, line.size() - 4):
		travelled += line[i].distance_to(line[i - 1])
		if travelled >= gap:
			travelled = 0.0
			var facing := _out(_angle_of(line[i]))
			kit.stone(line[i] + facing * radius * 0.95, facing, radius)


## A curve on the tiara's surface from a foot up to the apex, bowing out through `control`.
func _curve(foot: float, control: float, apex: float, h0: float, height: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var p0 := Vector2(foot, h0)
	var p1 := Vector2(control, lerpf(h0, height, 0.45))
	var p2 := Vector2(apex, height)
	for i in 41:
		var t := i / 40.0
		var q := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		points.append(_p(q.x, q.y))
	return points


func _angle_of(p: Vector3) -> float:
	return rad_to_deg(atan2(p.x, p.z / DEPTH))
