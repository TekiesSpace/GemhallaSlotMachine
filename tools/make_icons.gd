extends SceneTree
# Builds the Gemhalla icons from the gem sheet: a gem on a dark purple tile with a gold rim.
#   assets/icons/gemhalla.png/.ico  (Rune Gem) game: project icon, so the web export's favicon
#   assets/icons/admin.png/.ico     (sapphire) admin page favicon (copied to server/wwwroot/admin)
# The .ico files hold 16-256 px images, for Windows desktop shortcuts (tools/make_shortcuts.ps1).
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tools/make_icons.gd

const SHEET := "res://assets/gems/gems_256.png"
const FRAME := 256
const SIZE := 256
const ICO_SIZES := [16, 24, 32, 48, 64, 128, 256]
const TILE := Color(0.114, 0.082, 0.188)  # admin page --panel
const TILE_EDGE := Color(0.20, 0.14, 0.32)
const GOLD := Color(0.953, 0.788, 0.412)  # --gold
const ICONS := {
	"gemhalla": {"row": 4, "frame": 8, "admin_copy": false, "rune": true},
	"admin": {"row": 3, "frame": 8, "admin_copy": true, "rune": false},
}
## The Fehu rune strokes, as in SymbolTile._draw_rune_glyph (units of the glyph size).
const RUNE_STROKES := [
	[Vector2(-0.12, -0.32), Vector2(-0.12, 0.32)],
	[Vector2(-0.12, -0.08), Vector2(0.18, -0.3)],
	[Vector2(-0.12, 0.08), Vector2(0.18, -0.14)],
]


func _initialize() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	sheet.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons"))
	for icon_name: String in ICONS:
		var spec: Dictionary = ICONS[icon_name]
		var gem := sheet.get_region(Rect2i(spec.frame * FRAME, spec.row * FRAME, FRAME, FRAME))
		var icon := _compose(gem)
		if spec.rune:
			_draw_rune(icon)
		var base := ProjectSettings.globalize_path("res://assets/icons/" + icon_name)
		icon.save_png(base + ".png")
		_save_ico(icon, base + ".ico")
		if spec.admin_copy:
			icon.save_png(ProjectSettings.globalize_path("res://server/wwwroot/admin/favicon.png"))
		print("wrote ", base, ".png/.ico")
	quit()


## Rounded tile, gold rim, then the gem scaled to fill most of it.
func _compose(gem: Image) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var radius := 46.0
	var rim := 9.0
	for y in SIZE:
		for x in SIZE:
			var d := _rounded_distance(Vector2(x + 0.5, y + 0.5), radius)
			if d > 0.5:
				continue
			var alpha := clampf(0.5 - d, 0.0, 1.0)  # anti-aliased outer edge
			var color: Color
			if d > -rim:
				color = GOLD.lerp(GOLD.darkened(0.35), clampf((y as float) / SIZE, 0.0, 1.0))
			else:
				# Slight vertical glow so the tile isn't flat.
				color = TILE_EDGE.lerp(TILE, clampf((y as float) / SIZE * 1.2, 0.0, 1.0))
			color.a = alpha
			img.set_pixel(x, y, color)
	var used := gem.get_used_rect()
	var cropped := gem.get_region(used)
	var target := 196.0
	var scale := target / maxf(used.size.x, used.size.y)
	cropped.resize(maxi(1, roundi(used.size.x * scale)), maxi(1, roundi(used.size.y * scale)), Image.INTERPOLATE_LANCZOS)
	var at := Vector2i((SIZE - cropped.get_width()) / 2, (SIZE - cropped.get_height()) / 2)
	img.blend_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), at)
	return img


## The Rune Gem's Fehu rune: a soft glow under a bright stroke, on the wide part of the
## pear. Bolder than in the game so it still reads at 16-32 px.
func _draw_rune(img: Image) -> void:
	var size := 120.0
	var center := Vector2(SIZE / 2.0 + 8.0, SIZE / 2.0 - 8.0)
	var layers := [[13.0, Color(0.7, 1.0, 0.95, 0.4)], [5.5, Color(1, 1, 1, 0.97)]]
	for layer: Array in layers:
		var half_width: float = layer[0]
		var color: Color = layer[1]
		for y in SIZE:
			for x in SIZE:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := INF
				for stroke: Array in RUNE_STROKES:
					d = minf(d, _segment_distance(p, center + stroke[0] * size, center + stroke[1] * size))
				var cover := clampf(half_width + 0.5 - d, 0.0, 1.0)  # anti-aliased edge
				if cover > 0.0:
					img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(color, color.a * cover)))


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Signed distance to the tile's rounded-square edge (negative inside).
func _rounded_distance(p: Vector2, radius: float) -> float:
	var half := SIZE / 2.0
	var q := (p - Vector2(half, half)).abs() - Vector2(half - radius, half - radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## ICO with classic 32-bit bitmap entries, plus a PNG one at 256 px (as Windows' own icons
## do). Some Windows code can't read PNG entries at the small sizes, so they're bitmaps.
func _save_ico(source: Image, path: String) -> void:
	var pngs: Array[PackedByteArray] = []
	for size: int in ICO_SIZES:
		var img := source.duplicate() as Image
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pngs.append(img.save_png_to_buffer() if size >= 256 else _ico_bitmap(img))
	var out := StreamPeerBuffer.new()
	out.put_u16(0)  # reserved
	out.put_u16(1)  # type: icon
	out.put_u16(ICO_SIZES.size())
	var offset := 6 + 16 * ICO_SIZES.size()
	for i in ICO_SIZES.size():
		var size: int = ICO_SIZES[i]
		out.put_u8(0 if size >= 256 else size)  # width (0 means 256)
		out.put_u8(0 if size >= 256 else size)  # height
		out.put_u8(0)  # palette colors
		out.put_u8(0)  # reserved
		out.put_u16(1)  # color planes
		out.put_u16(32)  # bits per pixel
		out.put_u32(pngs[i].size())
		out.put_u32(offset)
		offset += pngs[i].size()
	for png in pngs:
		out.put_data(png)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(out.data_array)
	file.close()


## One icon image as a BITMAPINFOHEADER + bottom-up BGRA pixels + an empty AND mask
## (the alpha channel does the masking).
func _ico_bitmap(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var mask_row := ((w + 31) / 32) * 4  # 1 bit per pixel, rows padded to 4 bytes
	var out := StreamPeerBuffer.new()
	out.put_u32(40)  # header size
	out.put_32(w)
	out.put_32(h * 2)  # colour rows + mask rows
	out.put_u16(1)  # planes
	out.put_u16(32)  # bits per pixel
	out.put_u32(0)  # no compression
	out.put_u32(w * h * 4 + mask_row * h)
	out.put_32(0)
	out.put_32(0)
	out.put_u32(0)
	out.put_u32(0)
	for y in range(h - 1, -1, -1):
		for x in w:
			var c := img.get_pixel(x, y)
			out.put_u8(c.b8)
			out.put_u8(c.g8)
			out.put_u8(c.r8)
			out.put_u8(c.a8)
	for i in mask_row * h:
		out.put_u8(0)
	return out.data_array
