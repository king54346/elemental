extends MultiMeshInstance3D
## Builds the grass field as a MultiMesh, ported from the original GrassManager.
## Scatters candidate blades over a 3x3 tile grid, keeps those where the density
## map (green channel) >= threshold, and packs per-instance (worldX, worldZ, scale)
## into custom data for the grass shader.

const WORLD_SIZE := 33.0
const TILE_SIZE := 11.0
const GRID := 3
const GRASS_PER_TILE := 15000
const GRASS_SIZE := 1
const DENSITY_THRESHOLD := 0.9

const DENSITY_PATH := "res://assets/textures/grass/path_data_rgb_768x768.png"
const DISPLACEMENT_PATH := "res://assets/textures/grass/displacement_map_256x256.png"
const BLADE_PATH := "res://assets/models/grass_blade.glb"
const SHADER_PATH := "res://shaders/grass.gdshader"

# spring / day grass colors (linear, from SeasonManager)
const GRASS_DARK := Vector3(0.0, 0.29, 0.02)
const GRASS_LIGHT := Vector3(0.48, 0.68, 0.007)
const GRASS_SHADOW := Vector3(0.01, 0.16, 0.0)

# density orientation (synced from the Ground material by GroundMat.gd)
var _uv_rot := -90.0
var _flip_u := false
var _flip_v := true
var _blade_mesh: Mesh
var _density_img: Image

func _ready() -> void:
	var blade_mesh := _make_blade_mesh()
	if blade_mesh == null:
		push_warning("GrassField: could not build blade mesh")
		return
	var density_img := _load_density_image()
	if density_img == null:
		push_warning("GrassField: could not read density image")
		return

	_blade_mesh = blade_mesh
	_density_img = density_img
	_read_ground_orientation()   # single build with the correct orientation
	_build(blade_mesh, density_img)
	_setup_material(blade_mesh)
	_apply_colors()
	EnvState.season_changed.connect(_on_env_changed)
	EnvState.env_time_changed.connect(_on_env_changed)

	position.y = -0.3
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	# grass covers the central world area; keep a generous AABB so it is not culled
	custom_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))

## Procedurally builds one curved, tapered 3D grass blade (approach C).
func _make_blade_mesh() -> ArrayMesh:
	var segs := 4
	var height := 1.0
	var base_w := 0.07
	var curve := 0.14        # forward lean of the tip
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in segs + 1:
		var t := float(i) / float(segs)
		var w := base_w * (1.0 - t)          # taper to a point
		var y := t * height
		var z := curve * t * t               # curved forward
		verts.append(Vector3(-w * 0.5, y, z))
		verts.append(Vector3(w * 0.5, y, z))
		var n := Vector3(0.0, 0.35 + 0.4 * t, 1.0).normalized()
		normals.append(n)
		normals.append(n)
	for i in segs:
		var a := i * 2
		var b := i * 2 + 1
		var c := (i + 1) * 2
		var d := (i + 1) * 2 + 1
		indices.append(a); indices.append(c); indices.append(b)
		indices.append(b); indices.append(c); indices.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

func _load_blade_mesh() -> Mesh:
	var ps: PackedScene = load(BLADE_PATH)
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	var mesh: Mesh = null
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	inst.queue_free()
	return mesh

func _load_density_image() -> Image:
	var tex: Texture2D = load(DENSITY_PATH)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	return img

## Rotate/flip a world UV about center, identical to the shaders' rot_density().
func _rot_uv(u: float, v: float) -> Vector2:
	var a := deg_to_rad(_uv_rot)
	var s := sin(a)
	var c := cos(a)
	var px := u - 0.5
	var py := v - 0.5
	var r := Vector2(px * c - py * s + 0.5, px * s + py * c + 0.5)
	if _flip_u:
		r.x = 1.0 - r.x
	if _flip_v:
		r.y = 1.0 - r.y
	return r

func _grass_density(img: Image, wx: float, wz: float) -> float:
	var r := _rot_uv(wx / WORLD_SIZE + 0.5, wz / WORLD_SIZE + 0.5)
	var px := clampi(int(floor(r.x * float(img.get_width()))), 0, img.get_width() - 1)
	var py := clampi(int(floor(r.y * float(img.get_height()))), 0, img.get_height() - 1)
	return img.get_pixel(px, py).g

## Reads the density orientation from the Ground material so grass builds once with
## the correct values (the material exists at instantiation, before any _ready runs).
func _read_ground_orientation() -> void:
	var g := get_node_or_null("../Ground") as GeometryInstance3D
	if g == null:
		return
	var m: ShaderMaterial = g.get_surface_override_material(0)
	if m == null:
		return
	var rot = m.get_shader_parameter("uv_rotation")
	if rot != null:
		_uv_rot = rot
	var fu = m.get_shader_parameter("flip_u")
	if fu != null:
		_flip_u = fu
	var fv = m.get_shader_parameter("flip_v")
	if fv != null:
		_flip_v = fv

## Called only for runtime re-orientation; startup uses _read_ground_orientation.
func apply_orientation(rot: float, fu: bool, fv: bool) -> void:
	_uv_rot = rot
	_flip_u = fu
	_flip_v = fv
	if _blade_mesh != null and _density_img != null:
		_build(_blade_mesh, _density_img)
	if material_override:
		material_override.set_shader_parameter("uv_rotation", rot)
		material_override.set_shader_parameter("flip_u", fu)
		material_override.set_shader_parameter("flip_v", fv)

func _build(blade_mesh: Mesh, density_img: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337

	var transforms: Array[Transform3D] = []
	var customs: PackedColorArray = PackedColorArray()

	var start := -(float(GRID - 1) / 2.0) * TILE_SIZE
	for i in GRID:
		for j in GRID:
			var tile_x := start + float(i) * TILE_SIZE
			var tile_z := start + float(j) * TILE_SIZE
			for g in GRASS_PER_TILE:
				var wx := tile_x - TILE_SIZE * 0.5 + rng.randf() * TILE_SIZE
				var wz := tile_z - TILE_SIZE * 0.5 + rng.randf() * TILE_SIZE
				if _grass_density(density_img, wx, wz) >= DENSITY_THRESHOLD:
					var scale := GRASS_SIZE + rng.randf() * 0.5
					# real blade: fixed random yaw + scale baked into the transform
					var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale, scale))
					transforms.append(Transform3D(basis, Vector3(wx, 0.0, wz)))
					customs.append(Color(wx, wz, rng.randf(), 0.0))

	var count := transforms.size()
	if count == 0:
		push_warning("GrassField: no grass accepted (check density threshold)")
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = blade_mesh
	mm.instance_count = count
	for k in count:
		mm.set_instance_transform(k, transforms[k])
		mm.set_instance_custom_data(k, customs[k])
	multimesh = mm
	print("GrassField: placed ", count, " blades")

func _setup_material(blade_mesh: Mesh) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("density_map", load(DENSITY_PATH))
	mat.set_shader_parameter("displacement_map", load(DISPLACEMENT_PATH))
	mat.set_shader_parameter("ground_size", WORLD_SIZE)
	mat.set_shader_parameter("density_threshold", DENSITY_THRESHOLD)
	mat.set_shader_parameter("grass_color_dark", GRASS_DARK)
	mat.set_shader_parameter("grass_color_light", GRASS_LIGHT)
	mat.set_shader_parameter("shadow_color", GRASS_SHADOW)

	var aabb := blade_mesh.get_aabb()
	mat.set_shader_parameter("blade_height", maxf(aabb.size.y, 1e-4))
	mat.set_shader_parameter("uv_rotation", _uv_rot)
	mat.set_shader_parameter("flip_u", _flip_u)
	mat.set_shader_parameter("flip_v", _flip_v)

	material_override = mat

func _on_env_changed(_a: String, _b: String) -> void:
	_apply_colors()

func _process(_dt: float) -> void:
	if EnvState.cycle_enabled:
		_apply_colors()   # continuous dawn/dusk color blend (colors are uniforms, cheap)

func _apply_colors() -> void:
	if material_override == null:
		return
	var c := EnvState.grass_blended()
	material_override.set_shader_parameter("grass_color_dark", c.dark)
	material_override.set_shader_parameter("grass_color_light", c.light)
	material_override.set_shader_parameter("shadow_color", c.shadow)
