extends RefCounted
## Shared pieces for the 3D jewelry renders (tools/build_tiara.gd, tools/build_necklace.gd):
## a studio of softboxes that polished metal and gem facets reflect, the materials, and
## builders for wire, spheres, rings and faceted stones. A build script makes one of
## these, adds its piece to `scene`, then awaits capture() for the finished picture.
## Needs a window (not --headless) and the Forward+ renderer; see the build scripts.

const SIZE := 256
const SKY_SHADER := """
shader_type sky;

// A soft-edged round light source in direction `center`, `size` radians across.
float softbox(vec3 dir, vec3 center, float size, float soft) {
	float a = acos(clamp(dot(dir, normalize(center)), -1.0, 1.0));
	return 1.0 - smoothstep(size, size + soft, a);
}

void sky() {
	vec3 d = EYEDIR;
	// A dim room ringed with big softboxes, so facets flash between bright and dark.
	vec3 col = mix(vec3(0.03, 0.033, 0.045), vec3(0.12, 0.125, 0.14), smoothstep(-0.2, 0.6, d.y));
	col += vec3(6.0) * softbox(d, vec3(-0.6, 0.7, 0.8), 0.45, 0.08);
	col += vec3(4.0, 4.2, 4.6) * softbox(d, vec3(0.85, 0.35, 0.6), 0.35, 0.06);
	col += vec3(5.0) * softbox(d, vec3(0.0, 1.0, 0.15), 0.5, 0.12);
	col += vec3(3.0) * softbox(d, vec3(0.3, -0.1, 1.0), 0.3, 0.06);
	col += vec3(2.6, 2.9, 3.6) * softbox(d, vec3(-0.5, 0.0, 1.0), 0.2, 0.04);
	col += vec3(4.0, 3.5, 3.0) * softbox(d, vec3(-0.9, 0.05, -0.3), 0.2, 0.04);
	// Small colored lights: the "fire" a diamond splits out of white light.
	col += vec3(6.0, 3.4, 1.4) * softbox(d, vec3(0.6, 0.6, 0.9), 0.1, 0.02);
	col += vec3(2.0, 3.6, 6.5) * softbox(d, vec3(-0.2, 0.45, 1.0), 0.08, 0.02);
	col += vec3(0.3, 0.27, 0.24) * smoothstep(0.0, -0.6, d.y);
	COLOR = col;
}
"""

var scene := Node3D.new()
var platinum := StandardMaterial3D.new()
var diamond := StandardMaterial3D.new()
var amethyst := StandardMaterial3D.new()
var pearl := StandardMaterial3D.new()
var _brilliant: ArrayMesh
var _viewport := SubViewport.new()
var _world_env := WorldEnvironment.new()
var _rng := RandomNumberGenerator.new()
var _tree: SceneTree


## Sets up the studio in `tree`, rendering `render_size` square from a camera at `from`
## looking at `to`.
func _init(tree: SceneTree, render_size: int, from: Vector3, to: Vector3, fov: float, rng_seed: int) -> void:
	_tree = tree
	_rng.seed = rng_seed
	_make_materials()
	_brilliant = _brilliant_mesh()
	_viewport.size = Vector2i(render_size, render_size)
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_8X
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(_viewport)
	_viewport.add_child(scene)
	_add_studio(from, to, fov)


## Renders, crops to the piece, centers it in a square where it fills `fill` of the
## longer side, and scales down to SIZE.
func capture(fill: float) -> Image:
	# "-- preview=<file.png>" also saves the full render over the studio, to judge the look.
	var preview := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("preview="):
			preview = arg.trim_prefix("preview=")
	if preview:
		_world_env.environment.background_mode = Environment.BG_SKY
		_viewport.transparent_bg = false
		for i in 10:
			await _tree.process_frame
		_viewport.get_texture().get_image().save_png(preview)
		_world_env.environment.background_mode = Environment.BG_CLEAR_COLOR
		_viewport.transparent_bg = true
	for i in 10:
		await _tree.process_frame
	var shot := _viewport.get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var used := shot.get_used_rect()
	var side := int(maxi(used.size.x, used.size.y) / fill)
	var square := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	square.blit_rect(shot, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	square.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return square


func _make_materials() -> void:
	platinum.albedo_color = Color(0.83, 0.84, 0.87)
	platinum.metallic = 1.0
	platinum.roughness = 0.14
	platinum.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A diamond's sparkle is its facets mirroring bright and dark parts of the room.
	diamond.albedo_color = Color(0.93, 0.95, 1.0)
	diamond.metallic = 1.0
	diamond.roughness = 0.02
	diamond.cull_mode = BaseMaterial3D.CULL_DISABLED
	# An amethyst mirrors the room tinted violet (deep where it's dark, bright purple where
	# it catches a light), under a clear white surface shine.
	amethyst.albedo_color = Color(0.5, 0.08, 0.85)
	amethyst.metallic = 1.0
	amethyst.roughness = 0.03
	amethyst.clearcoat_enabled = true
	amethyst.clearcoat = 0.45
	amethyst.clearcoat_roughness = 0.0
	# A little glow of its own, so facets facing the dark room stay deep violet, not black.
	amethyst.emission_enabled = true
	amethyst.emission = Color(0.1, 0.0, 0.2)
	amethyst.cull_mode = BaseMaterial3D.CULL_DISABLED
	pearl.albedo_color = Color(0.93, 0.9, 0.85)
	pearl.roughness = 0.24
	pearl.clearcoat_enabled = true
	pearl.clearcoat = 0.7
	pearl.clearcoat_roughness = 0.1
	pearl.rim_enabled = true
	pearl.rim = 0.25


func _add_studio(from: Vector3, to: Vector3, fov: float) -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = Shader.new()
	sky_material.shader.code = SKY_SHADER
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = Sky.new()
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world_env.environment = env
	scene.add_child(_world_env)
	for light: Array in [[Vector3(-3, 4, 4), 1.6], [Vector3(4, 2, 3), 0.7], [Vector3(0, 3, -4), 0.9]]:
		var sun := DirectionalLight3D.new()
		sun.light_energy = light[1]
		scene.add_child(sun)
		sun.look_at_from_position(light[0], Vector3.ZERO)
	var camera := Camera3D.new()
	camera.fov = fov
	scene.add_child(camera)
	camera.look_at_from_position(from, to)
	camera.current = true


## A basis whose Z points along `facing` (Y kept as close to up as it can), scaled.
func facing_basis(facing: Vector3, scale: float) -> Basis:
	var z := facing.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x * scale, y * scale, z * scale)


func sphere(at: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	scene.add_child(node)
	node.position = at
	return node


## A platinum ring of `radius` facing `facing`, `thickness` from its middle line out;
## `stretch` makes it oval (x, y across its face).
func ring(at: Vector3, facing: Vector3, radius: float, thickness: float, stretch := Vector2.ONE) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thickness
	torus.outer_radius = radius + thickness
	torus.rings = 64
	var node := MeshInstance3D.new()
	node.mesh = torus
	node.material_override = platinum
	scene.add_child(node)
	var oval := Basis.from_scale(Vector3(stretch.x, stretch.y, 1.0))
	node.transform = Transform3D(facing_basis(facing, 1.0) * oval * Basis(Vector3.RIGHT, PI / 2), at)


## A brilliant-cut stone with its table facing `facing`, girdle radius `radius`; `stretch`
## makes it an oval cut (x, y across its face).
func stone(at: Vector3, facing: Vector3, radius: float, material: Material = null, stretch := Vector2.ONE) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _brilliant
	node.material_override = material if material else diamond
	scene.add_child(node)
	# Round stones are each turned a little differently, so neighbors catch the light
	# differently; an oval keeps its long axis upright.
	var spin := Basis(Vector3.BACK, _rng.randf() * TAU) if stretch == Vector2.ONE else Basis()
	var oval := Basis.from_scale(Vector3(stretch.x, stretch.y, 1.0))
	node.transform = Transform3D(facing_basis(facing, radius) * oval * spin, at)


## A brilliant in a platinum collet with claws (`stretch` as for stone()).
func collet(at: Vector3, facing: Vector3, radius: float, material: Material = null, stretch := Vector2.ONE, claws := 6) -> void:
	ring(at - facing.normalized() * radius * 0.05, facing, radius * 1.06, radius * 0.1, stretch)
	stone(at, facing, radius, material, stretch)
	var basis := facing_basis(facing, 1.0)
	for k in claws:
		var around := Vector2.from_angle(TAU * k / claws + (0.3 if claws == 6 else PI / 4)) * radius * 1.02
		around *= stretch
		sphere(at + basis.x * around.x + basis.y * around.y + facing.normalized() * radius * 0.16, radius * 0.14, platinum)


## A round platinum wire along the points, its radius tapering from r0 to r1, with
## rounded ends.
func tube(points: PackedVector3Array, r0: float, r1: float) -> void:
	const SIDES := 16
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var count := points.size()
	var normal := Vector3.ZERO
	for i in count:
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		if i == 0:
			normal = tangent.cross(Vector3.FORWARD if absf(tangent.z) < 0.9 else Vector3.UP).normalized()
		# Carry the frame along the curve so the tube doesn't twist.
		normal = (normal - tangent * normal.dot(tangent)).normalized()
		var binormal := tangent.cross(normal)
		var r := lerpf(r0, r1, float(i) / (count - 1))
		for k in SIDES:
			var a := TAU * k / SIDES
			var n := normal * cos(a) + binormal * sin(a)
			vertices.append(points[i] + n * r)
			normals.append(n)
	for i in count - 1:
		for k in SIDES:
			var a := i * SIDES + k
			var b := i * SIDES + (k + 1) % SIDES
			# Clockwise seen from outside: Godot's front face.
			indices.append_array([a, a + SIDES, b, b, a + SIDES, b + SIDES])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = platinum
	scene.add_child(node)
	sphere(points[0], r0, platinum)
	sphere(points[count - 1], r1, platinum)


## A round brilliant, girdle radius 1, table toward +Z: an octagonal table, a crown of 8
## star, 8 kite (each split along its long axis) and 16 upper-girdle facets down to a
## 16-sided girdle, and 48 pavilion facets down to the culet.
## Flat shaded, so each facet mirrors its own piece of the room. The table is domed very
## slightly into 8 wedges: a real stone shows the pavilion's pattern through its table,
## and the wedges catching the light differently stand in for that.
func _brilliant_mesh() -> ArrayMesh:
	const TABLE_R := 0.52
	const STAR_R := 0.76
	const CROWN := 0.16
	const DOME := 0.035
	const GIRDLE := 0.025
	const PAVILION := 0.43
	var table: Array[Vector3] = []
	var star: Array[Vector3] = []
	for k in 8:
		var a := TAU * k / 8.0
		table.append(Vector3(cos(a) * TABLE_R, sin(a) * TABLE_R, CROWN))
		var b := TAU * (k + 0.5) / 8.0
		star.append(Vector3(cos(b) * STAR_R, sin(b) * STAR_R, CROWN * 0.52))
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for j in 16:
		var a := TAU * j / 16.0
		top.append(Vector3(cos(a), sin(a), 0.0))
		bottom.append(Vector3(cos(a), sin(a), -GIRDLE))
	var tris: Array = []
	var table_center := Vector3(0, 0, CROWN + DOME)
	for k in 8:
		var t0 := table[k]
		var t1 := table[(k + 1) % 8]
		var s := star[k]
		var s_prev := star[(k + 7) % 8]
		var g_main := top[2 * k]  # under t0, the kite's lower point
		tris.append([table_center, t0, t1])
		tris.append([t0, t1, s])  # star facet
		tris.append([t0, s_prev, g_main])  # kite, two halves
		tris.append([t0, g_main, s])
		tris.append([s, g_main, top[2 * k + 1]])  # upper girdle facets
		tris.append([s, top[2 * k + 1], top[(2 * k + 2) % 16]])
	var culet := Vector3(0, 0, -GIRDLE - PAVILION)
	for j in 16:
		var a0 := top[j]
		var a1 := top[(j + 1) % 16]
		var b0 := bottom[j]
		var b1 := bottom[(j + 1) % 16]
		tris.append([a0, b0, b1])
		tris.append([a0, b1, a1])
		var mid_angle := TAU * (j + 0.5) / 16.0
		var mid := Vector3(cos(mid_angle) * 0.55, sin(mid_angle) * 0.55, -GIRDLE - PAVILION * 0.55)
		tris.append([b0, b1, mid])
		tris.append([b0, mid, culet])
		tris.append([mid, b1, culet])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0, -0.1)
	for tri: Array in tris:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c) / 3.0 - center) < 0.0:
			n = -n
		else:
			# Clockwise seen from outside: Godot's front face.
			var swap := b
			b = c
			c = swap
		for v in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()
