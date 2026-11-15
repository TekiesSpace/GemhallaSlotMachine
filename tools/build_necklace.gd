extends SceneTree
## Builds assets/gems/necklace_256.png, the free-games (Vault) symbol, by rendering a 3D
## amethyst and diamond necklace: a graduated line of claw-set diamonds with an amethyst
## every third stone, draped around the neck and dipping at the front, and from it a large
## oval amethyst in a halo of diamonds, hung on a bail under a round diamond. The studio,
## materials and builders are in tools/render_kit.gd.
##
## Needs a window (not --headless), from the project folder:
##   <Godot>_console.exe --path . --rendering-method forward_plus --script res://tools/build_necklace.gd

const RenderKit := preload("res://tools/render_kit.gd")

const OUT := "res://assets/gems/necklace_256.png"
const FILL := 0.94  # the necklace's longer side as a share of the picture

const SPAN := 74.0  # degrees either side of the front the necklace shows
const STONE_GAP := 0.088  # along the line, between stone centers

# The pendant: an oval amethyst (radius, and its width as a share of its height) in a
# halo of small diamonds.
const PENDANT_R := 0.22
const PENDANT_WIDTH := 0.78
const HALO_GAP := 0.05
const HALO_STONE := 0.026

var kit: RenderKit


func _initialize() -> void:
	kit = RenderKit.new(self, 1400, Vector3(0, 0.9, 6.4), Vector3(0, -0.72, 0), 26.0, 11)
	_build_chain()
	_build_pendant()
	var picture: Image = await kit.capture(FILL)
	var err := picture.save_png(ProjectSettings.globalize_path(OUT))
	print("necklace_256.png: ", error_string(err))
	quit()


## A point on the necklace line, `angle` degrees round from the front: it circles the
## neck, rising toward the back, and dips into a soft V at the front where the pendant pulls.
func _line(angle: float) -> Vector3:
	var t := deg_to_rad(angle)
	var y := -0.5 * cos(t) - 0.14 * exp(-pow(angle / 38.0, 2))
	return Vector3(0.88 * sin(t), y, 0.72 * cos(t))


## Which way a stone on the line faces: out from the neck and tipped up, as it lies on the
## collarbone.
func _facing(angle: float) -> Vector3:
	var t := deg_to_rad(angle)
	return Vector3(sin(t), 0.55, cos(t)).normalized()


func _build_chain() -> void:
	var points := PackedVector3Array()
	var angles := PackedFloat32Array()
	for i in 401:
		var a := -SPAN + i * SPAN * 2.0 / 400.0
		points.append(_line(a))
		angles.append(a)
	# The settings are linked by a fine wire running behind the stones.
	kit.tube(points, 0.012, 0.012)
	# Stones outward from the front each way, graduated smaller toward the back.
	for side in [-1.0, 1.0]:
		var travelled := 0.0
		var count := 0
		var i := 200
		while i > 0 and i < 400:
			var next := i + int(side)
			travelled += points[next].distance_to(points[i])
			i = next
			if travelled < STONE_GAP * (0.75 if count == 0 else 1.0):
				continue
			travelled = 0.0
			count += 1
			var a := angles[i]
			var size := lerpf(1.0, 0.72, absf(a) / SPAN)
			var facing := _facing(a)
			var at := points[i] + facing * 0.02
			if count % 3 == 0:
				kit.collet(at, facing, 0.042 * size, kit.amethyst, Vector2.ONE, 4)
			else:
				kit.collet(at, facing, 0.034 * size, kit.diamond, Vector2.ONE, 4)


func _build_pendant() -> void:
	var top := _line(0.0)
	var facing := Vector3(0, 0.22, 1).normalized()
	var basis := kit.facing_basis(facing, 1.0)
	# The bail: a loop seen edge-on from the front, through the line.
	kit.ring(top + Vector3(0, -0.035, 0.0), Vector3.RIGHT, 0.04, 0.011)
	# A round diamond under the bail, then the oval amethyst in its halo.
	var accent := top + Vector3(0, -0.13, 0.02)
	kit.collet(accent, facing, 0.05, kit.diamond, Vector2.ONE, 4)
	var halo_ry := PENDANT_R + HALO_GAP
	var halo_rx := PENDANT_R * PENDANT_WIDTH + HALO_GAP
	var center := accent - basis.y * (0.05 * 1.25 + 0.03 + halo_ry + HALO_STONE)
	kit.tube(PackedVector3Array([accent - basis.y * 0.05, center + basis.y * (halo_ry + HALO_STONE * 0.5)]), 0.012, 0.012)
	kit.collet(center, facing, PENDANT_R, kit.amethyst, Vector2(PENDANT_WIDTH, 1.0), 4)
	# The halo's frame behind its stones, then the stones round the oval.
	kit.ring(center - facing * 0.012, facing, halo_ry, HALO_STONE * 0.9, Vector2(halo_rx / halo_ry, 1.0))
	var perimeter := TAU * sqrt((halo_rx * halo_rx + halo_ry * halo_ry) / 2.0)
	var stones := int(perimeter / (HALO_STONE * 2.15))
	for k in stones:
		var a := TAU * k / stones
		var at := center + basis.x * cos(a) * halo_rx + basis.y * sin(a) * halo_ry + facing * 0.012
		kit.stone(at, facing, HALO_STONE)
