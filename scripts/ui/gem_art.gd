extends RefCounted
## Installs the rendered gem art into SymbolTile.art. The sheet (from KillGorack's
## "Rotating Jewels", CC0; see CREDITS.md; rebuilt by tools/build_gem_sheet.gd) has
## one row per gem and 16 rotation frames per row. Winning gems spin through the
## frames; at rest each shows a slightly turned angle so its side and depth show.

const SymbolTile := preload("res://scripts/ui/symbol_tile.gd")

const SHEET_PATH := "res://assets/gems/gems_256.png"
# The Wild's tiara, built from the same gems by tools/build_tiara.gd.
const TIARA_PATH := "res://assets/gems/tiara_256.png"
const TIARA_GLOW := Color("e4ecf7")
# The Vault's (free games) amethyst necklace, rendered in 3D by tools/build_necklace.gd.
const NECKLACE_PATH := "res://assets/gems/necklace_256.png"
const FRAME_SIZE := 256
const FRAME_COUNT := 16
# symbol -> [sheet row, resting frame]. Turned frames show the stone's thickness.
# The diamond rests at frame 4, its side-on profile, which the source shows tipped
# diagonally; DIAMOND_POSE turns it upright (flat table on top, point at the bottom).
# ORB is the teal pear-cut Rune Gem; SymbolTile sets its rune into the stone.
# SCAT (the Vault, free games) and WILD are single 3D renders, installed below.
const GEMS := {"H1": [0, 4], "H2": [1, 1], "H3": [2, 1], "H4": [3, 1], "ORB": [4, 1]}
const DIAMOND_POSE := -PI / 4


## Call once at startup. If the sheet is missing, the drawn gems are used instead.
static func install() -> void:
	if not ResourceLoader.exists(SHEET_PATH):
		push_warning("Gem art not found at %s; using drawn gems." % SHEET_PATH)
		return
	var shared: Texture2D = load(SHEET_PATH)
	for symbol: String in GEMS:
		var row: int = GEMS[symbol][0]
		var rest: int = GEMS[symbol][1]
		var frames: Array[Texture2D] = []
		for f in FRAME_COUNT:
			var frame := AtlasTexture.new()
			frame.atlas = shared
			frame.region = Rect2(f * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
			frames.append(frame)
		var entry := {
			"texture": frames[rest], "frames": frames, "rest": rest,
			"glow": SymbolTile.GEM_COLORS[symbol],
		}
		if symbol == "H1":
			# Icy backing: pure white washed the diamond out; this keeps its facets visible.
			entry.backing = Color(0.74, 0.81, 0.93)
			# Classic upright profile at rest; on a win the same turn makes it tumble
			# toward the viewer and back.
			entry.pose_angle = DIAMOND_POSE
			entry.size = 1.2  # the profile fills less of its frame than the other stones
			entry.sparkle = Vector2(-0.5, -0.32)  # on the table's corner
		if symbol == "ORB":
			# The rune is set into the stone, so Rune Gems stay still instead of spinning.
			entry.rune = true
			entry.erase("frames")
		SymbolTile.art[symbol] = entry
	if ResourceLoader.exists(TIARA_PATH):
		# A single picture (no spin frames); it keeps the tilt, shadow and twinkle.
		SymbolTile.art["WILD"] = {
			# Platinum and diamonds: a cool white glow, and a slate backing behind the openwork.
			"texture": load(TIARA_PATH), "rest": 0, "glow": TIARA_GLOW,
			# The tiara is wide and low, so it's drawn larger to fill the tile like the stones.
			"backing": Color(0.24, 0.26, 0.32), "size": 1.62, "sparkle": Vector2(0.0, -0.5),
		}
	if ResourceLoader.exists(NECKLACE_PATH):
		SymbolTile.art["SCAT"] = {
			"texture": load(NECKLACE_PATH), "rest": 0, "glow": SymbolTile.GEM_COLORS.SCAT,
			# Deep violet behind the openwork; drawn a little larger, as the chain leaves
			# empty space around the pendant.
			"backing": Color(0.2, 0.1, 0.3), "size": 1.2, "sparkle": Vector2(-0.15, 0.2),
		}
