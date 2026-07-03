extends MultiMeshInstance3D
## Flowers — ported from GrassManager.createFlowers. Scatters flower billboards over
## grassy areas (density map green >= threshold), sampling a 2-flower atlas, with a
## per-season visibility fade.

const FLOWER1 := "res://assets/textures/flowers/flower_1_128x128.png"
const FLOWER2 := "res://assets/textures/flowers/flower_2_128x128.png"
const DENSITY_PATH := "res://assets/textures/grass/path_data_rgb_768x768.png"
const SHADER_PATH := "res://shaders/flowers.gdshader"

const WORLD_SIZE := 33.0
const TILE_SIZE := 11.0
const GRID := 3
const FLOWERS_PER_TILE := 20
const DENSITY_THRESHOLD := 0.9

var _mat: ShaderMaterial

# density orientation (synced from the Ground material by GroundMat.gd)
var _uv_rot := -90.0
var _flip_u := false
var _flip_v := true
var _density_img: Image

func _ready() -> void:
	var density_img := _load_image(DENSITY_PATH)
	if density_img == null:
		push_warning("FlowerField: no density image")
		return
	_density_img = density_img
	_read_ground_orientation()   # single build with the correct orientation
	_build(density_img)
	_apply_visibility()
	EnvState.season_changed.connect(_on_env_changed)
	EnvState.env_time_changed.connect(_on_env_changed)

func _on_env_changed(_a: String, _b: String) -> void:
	_apply_visibility()

func _process(_dt: float) -> void:
	if EnvState.cycle_enabled:
		_apply_visibility()   # continuous dawn/dusk fade

func _apply_visibility() -> void:
	if _mat:
		_mat.set_shader_parameter("visibility", float(EnvState.grass_blended().get("flower", 1.0)))

func _load_image(path: String) -> Image:
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

func _make_atlas() -> ImageTexture:
	var a := _load_image(FLOWER1)
	var b := _load_image(FLOWER2)
	if a == null or b == null:
		return null
	var w := a.get_width()
	var h := a.get_height()
	var atlas := Image.create(w * 2, h, false, Image.FORMAT_RGBA8)
	atlas.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(0, 0))
	atlas.blit_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(w, 0))
	return ImageTexture.create_from_image(atlas)

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
	var px := clampi(int(floor(r.x * img.get_width())), 0, img.get_width() - 1)
	var py := clampi(int(floor(r.y * img.get_height())), 0, img.get_height() - 1)
	return img.get_pixel(px, py).g

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
	if _density_img != null:
		_build(_density_img)
		_apply_visibility()

func _build(density_img: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090

	var transforms: Array[Transform3D] = []
	var customs: PackedColorArray = PackedColorArray()
	var start := -(float(GRID - 1) / 2.0) * TILE_SIZE

	for i in GRID:
		for j in GRID:
			var tile_x := start + float(i) * TILE_SIZE
			var tile_z := start + float(j) * TILE_SIZE
			for f in FLOWERS_PER_TILE:
				var wx := tile_x - TILE_SIZE * 0.5 + rng.randf() * TILE_SIZE
				var wz := tile_z - TILE_SIZE * 0.5 + rng.randf() * TILE_SIZE
				if _grass_density(density_img, wx, wz) >= DENSITY_THRESHOLD:
					var y := 0.7 + rng.randf() * 0.2
					transforms.append(Transform3D(Basis(), Vector3(wx, y, wz)))
					var tex_off := 0.0 if rng.randf() < 0.5 else 0.5
					var size := 0.6 + rng.randf() * 0.4
					customs.append(Color(tex_off, 0.0, size, 0.0))

	var count := transforms.size()
	if count == 0:
		return

	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	for k in count:
		mm.set_instance_transform(k, transforms[k])
		mm.set_instance_custom_data(k, customs[k])
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 4, 40))

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("atlas", _make_atlas())
	material_override = _mat
	print("FlowerField: ", count, " flowers")
