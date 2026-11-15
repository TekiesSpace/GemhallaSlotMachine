extends SceneTree
## Rebuilds assets/gems/gems_256.png from KillGorack's "Rotating Jewels" sheet (CC0).
## Rows: H1 diamond, H2 ruby, H3 emerald, H4 sapphire, ORB rune gem (the topaz pear
## recolored to teal), SCAT vault amethyst (the yellow round brilliant recolored to
## purple). 16 rotation frames of 256 px per row.
##
## Usage (from the project folder):
##   <Godot>_console.exe --headless --path . --script res://tools/build_gem_sheet.gd -- <path to gemstones_256.png>

const FRAME := 256
const FRAMES := 16
# Source sheet rows: 0 diamond, 1 emerald, 2 ruby, 3 sapphire, 4 topaz pear, 5 yellow.
const ROWS := [0, 2, 1, 3, 4, 5]
# Output row -> [new hue, minimum saturation]: the teal Rune Gem and the purple amethyst
# Vault. The yellow source is pale, so the amethyst gets a saturation floor to read purple.
const RECOLOR := {4: [0.47, 0.0], 5: [0.77, 0.55]}
# Tone per output row, to remove the near-black facets of the source renders (they
# read as harsh dark spots on the reels): [curve, floor, saturation].
# - curve < 1 lifts dark tones more than light ones,
# - floor is the darkest any facet may get (0..1); brightness is remapped into
#   floor..1, so facets keep their order (and the cut still reads) but none go black,
# - saturation scales color; the diamond keeps a little, so it reads icy blue-white.
# The renders are partly see-through (about half of each stone), which lets the dark
# tile show through as grey/black patches. Opacity is raised along this curve so the
# stones read as solid while their anti-aliased edges stay smooth.
const ALPHA_CURVE := 0.3
const TONE := [
	[0.85, 0.35, 0.65], # H1 diamond (lower floor than the rest so its facets still show)
	[0.55, 0.45, 1.0],  # H2 ruby
	[0.6, 0.42, 1.0],   # H3 emerald
	[0.5, 0.48, 1.0],   # H4 sapphire
	[0.6, 0.45, 1.0],   # ORB rune gem
	[0.9, 0.22, 0.85],  # SCAT amethyst: more contrast so its crown facets show
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_path: String = args[0] if args.size() > 0 else "C:/Workspace/Resources/Godot/Art/gemstones/gemstones_256.png"
	var sheet := Image.load_from_file(source_path)
	if sheet == null:
		push_error("Could not read %s" % source_path)
		quit(1)
		return
	var out := Image.create(FRAME * FRAMES, FRAME * ROWS.size(), false, Image.FORMAT_RGBA8)
	for i in ROWS.size():
		var row := sheet.get_region(Rect2i(0, ROWS[i] * FRAME, FRAME * FRAMES, FRAME))
		row.convert(Image.FORMAT_RGBA8)
		if RECOLOR.has(i):
			_recolor(row, RECOLOR[i][0], RECOLOR[i][1])
		_tone(row, TONE[i][0], TONE[i][1], TONE[i][2])
		out.blit_rect(row, Rect2i(0, 0, row.get_width(), FRAME), Vector2i(0, i * FRAME))
	var err := out.save_png("res://assets/gems/gems_256.png")
	print("gems_256.png: ", error_string(err))
	quit()


## Remaps brightness into floor..1 along a curve, scales saturation (see TONE), and
## makes the stone solid (see ALPHA_CURVE).
func _tone(img: Image, curve: float, floor_value: float, saturation: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a >= 0.01:
				var v := floor_value + (1.0 - floor_value) * pow(c.v, curve)
				img.set_pixel(x, y, Color.from_hsv(c.h, clampf(c.s * saturation, 0.0, 1.0), v, pow(c.a, ALPHA_CURVE)))


## Shifts every visible pixel to `hue`, keeping its saturation (at least min_saturation)
## and brightness, and lifts brightness slightly so the stone reads well on the dark tiles.
func _recolor(img: Image, hue: float, min_saturation: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a >= 0.01:
				img.set_pixel(x, y, Color.from_hsv(hue, maxf(c.s, min_saturation), clampf(c.v * 1.1, 0.0, 1.0), c.a))
