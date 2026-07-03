extends Node3D
## Foliage — ported from the original Bush + BushManager. Scatters leaf billboards
## over the surface of the bushEmitter mesh, once per bush definition, translated to
## the bush position. Colors depend only on bush type (default/tree/birch), so we
## build one MultiMesh per type and pass the per-leaf surface normal via custom data.

const EMITTER_PATH := "res://assets/models/bushEmitter.glb"
const ALPHA_PATH := "res://assets/textures/bush/leave_alpha_map_256x256.png"
const SHADER_PATH := "res://shaders/bush.gdshader"

# spring / day palettes (linear), from SeasonManager.bush
const PALETTES := {
	"default": {
		"shadow": Vector3(0.003, 0.074, 0.003),
		"mid": Vector3(0.06, 0.23, 0.0),
		"highlight": Vector3(0.44, 0.5, 0.0),
		"mult": Vector3(0.46, 0.65, 0.3),
	},
	"tree": {
		"shadow": Vector3(0.03, 0.07, 0.003),
		"mid": Vector3(0.06, 0.23, 0.0),
		"highlight": Vector3(0.45, 0.55, 0.002),
		"mult": Vector3(0.77, 0.71, 0.35),
	},
	"birch": {
		"shadow": Vector3(0.09, 0.03, 0.0),
		"mid": Vector3(0.2, 0.03, 0.0),
		"highlight": Vector3(1.0, 0.58, 0.1),
		"mult": Vector3(0.68, 0.56, 0.22),
	},
}

# [x, y, z, scale, leafCount, type]
const BUSHES := [
	[7.3, 1.0, 3, 1.2, 45, "default"],
	[9, 0.2, 4.1, 0.6, 45, "default"],
	[10, 0.3, 0.0, 0.6, 45, "default"],
	[11, 0.1, 1.5, 0.8, 45, "default"],
	[-10, 0.7, -5.5, 1.2, 45, "default"],
	[-12, 1.0, -5.5, 2.0, 45, "default"],
	[-11, 0.2, -8.5, 0.7, 45, "default"],
	[-2, 0.2, -7.5, 1.0, 45, "default"],
	[8, 0.5, -9.5, 0.6, 45, "default"],
	[-4.0, 0.5, 10.5, 0.7, 45, "default"],
	[0.0, 0.5, 11.5, 0.5, 45, "default"],
	[1.8, 0.2, 9.5, 0.5, 45, "default"],
	[-4, 0.0, -15.5, 1.0, 45, "default"],
	[-6, 0.0, -15, 0.9, 45, "default"],
	[-9.8, 0.5, 4.5, 1.2, 30, "default"],
	[-8.8, 0.5, 8.5, 1.0, 30, "default"],
	[-6.5, 0.1, 8.5, 0.8, 30, "default"],
	[12.0, 5.0, -0.2, 0.6, 45, "tree"],
	[12.0, 7.0, 1.5, 0.7, 45, "tree"],
	[12.5, 5.0, 3.2, 0.7, 45, "tree"],
	[13.5, 5.0, 0.5, 0.6, 45, "tree"],
	[11.0, 6.0, 2.5, 0.6, 45, "tree"],
	[8.1, 6.5, -5.5, 1.0, 45, "birch"],
	[8.5, 7.5, -8.5, 1.0, 45, "birch"],
	[6.0, 7.5, -7.5, 1.0, 45, "birch"],
	[-10.5, 4.5, 0.0, 1.0, 45, "tree"],
	[-9.5, 5.0, -2.5, 1.0, 45, "tree"],
	[-8, 4.0, -2.5, 1.0, 45, "tree"],
	[-7, 3.7, -9.0, 1.0, 45, "tree"],
	[-7, 5.0, -11.0, 1.0, 45, "tree"],
	[-5, 3.7, -11.0, 1.0, 45, "tree"],
	[-10, 6.0, 7.0, 1.0, 45, "tree"],
	[-11, 6.0, 5.0, 1.0, 45, "tree"],
	[-12, 4.0, 4.0, 1.0, 45, "tree"],
	[-12, 6.0, 6.0, 1.0, 45, "tree"],
	[-12, 4.0, 7.0, 1.0, 45, "tree"],
	[-3.1, 8.0, 10.5, 1.0, 45, "birch"],
	[-3.0, 6.0, 10.5, 1.5, 45, "birch"],
	[-5.0, 7.5, 11.5, 1.0, 45, "birch"],
	[-4.0, 6.0, 12.5, 1.0, 45, "birch"],
]

# emitter surface triangles (emitter space)
var _tri_a: PackedVector3Array = PackedVector3Array()
var _tri_b: PackedVector3Array = PackedVector3Array()
var _tri_c: PackedVector3Array = PackedVector3Array()
var _tri_na: PackedVector3Array = PackedVector3Array()
var _tri_nb: PackedVector3Array = PackedVector3Array()
var _tri_nc: PackedVector3Array = PackedVector3Array()
var _cum_area: PackedFloat32Array = PackedFloat32Array()
var _total_area := 0.0
var _rng := RandomNumberGenerator.new()
var _mats := {}   # type -> ShaderMaterial

const KEYS := {
	"default": ["shadow", "mid", "high", "mult"],
	"tree": ["tshadow", "tmid", "thigh", "tmult"],
	"birch": ["bshadow", "bmid", "bhigh", "bmult"],
}

func _ready() -> void:
	var mesh := _load_emitter()
	if mesh == null:
		push_warning("BushField: emitter mesh not found")
		return
	if not _build_sampler(mesh):
		push_warning("BushField: emitter has no usable surface")
		return
	_rng.seed = 12345
	for type in PALETTES.keys():
		_build_type(type)
	_apply_colors()
	EnvState.season_changed.connect(_on_env_changed)
	EnvState.env_time_changed.connect(_on_env_changed)

func _on_env_changed(_a: String, _b: String) -> void:
	_apply_colors()

func _process(_dt: float) -> void:
	if EnvState.cycle_enabled:
		_apply_colors()   # continuous dawn/dusk color blend

func _apply_colors() -> void:
	var b := EnvState.bush_blended()
	for type in _mats:
		var m: ShaderMaterial = _mats[type]
		var k: Array = KEYS[type]
		m.set_shader_parameter("shadow_color", b[k[0]])
		m.set_shader_parameter("mid_color", b[k[1]])
		m.set_shader_parameter("highlight_color", b[k[2]])
		m.set_shader_parameter("color_multiplier", b[k[3]])

func _load_emitter() -> Mesh:
	var ps: PackedScene = load(EMITTER_PATH)
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	var found := _find_mesh(inst, Transform3D.IDENTITY)
	inst.queue_free()
	if found.is_empty():
		return null
	_emitter_xform = found[1]
	return found[0]

var _emitter_xform := Transform3D.IDENTITY

func _find_mesh(node: Node, accum: Transform3D) -> Array:
	var x := accum
	if node is Node3D:
		x = accum * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return [(node as MeshInstance3D).mesh, x]
	for c in node.get_children():
		var r := _find_mesh(c, x)
		if not r.is_empty():
			return r
	return []

func _build_sampler(mesh: Mesh) -> bool:
	var arr := mesh.surface_get_arrays(0)
	if arr.is_empty():
		return false
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	var indices: PackedInt32Array = idx
	if indices.is_empty():
		indices = PackedInt32Array()
		for i in verts.size():
			indices.append(i)

	var basis := _emitter_xform.basis
	var running := 0.0
	for t in range(0, indices.size(), 3):
		var ia := indices[t]
		var ib := indices[t + 1]
		var ic := indices[t + 2]
		var a := _emitter_xform * verts[ia]
		var b := _emitter_xform * verts[ib]
		var c := _emitter_xform * verts[ic]
		var na := (basis * norms[ia]).normalized() if norms.size() > ia else Vector3.UP
		var nb := (basis * norms[ib]).normalized() if norms.size() > ib else Vector3.UP
		var nc := (basis * norms[ic]).normalized() if norms.size() > ic else Vector3.UP
		var area := 0.5 * (b - a).cross(c - a).length()
		running += area
		_tri_a.append(a); _tri_b.append(b); _tri_c.append(c)
		_tri_na.append(na); _tri_nb.append(nb); _tri_nc.append(nc)
		_cum_area.append(running)
	_total_area = running
	return _total_area > 0.0

func _sample() -> Array:
	var r := _rng.randf() * _total_area
	var lo := 0
	var hi := _cum_area.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if _cum_area[mid] < r:
			lo = mid + 1
		else:
			hi = mid
	var u := _rng.randf()
	var v := _rng.randf()
	if u + v > 1.0:
		u = 1.0 - u
		v = 1.0 - v
	var w := 1.0 - u - v
	var pos := _tri_a[lo] * w + _tri_b[lo] * u + _tri_c[lo] * v
	var nrm := (_tri_na[lo] * w + _tri_nb[lo] * u + _tri_nc[lo] * v).normalized()
	return [pos, nrm]

func _build_type(type: String) -> void:
	var transforms: Array[Transform3D] = []
	var customs: PackedColorArray = PackedColorArray()

	for def in BUSHES:
		if def[5] != type:
			continue
		var bush_pos := Vector3(def[0], def[1], def[2])
		var bush_scale: float = def[3]
		var leaf_count: int = def[4]
		for i in leaf_count:
			var s := _sample()
			var lpos: Vector3 = s[0] + bush_pos
			var lnrm: Vector3 = s[1]
			var leaf_scale := _rng.randf() * 0.5 + bush_scale
			var basis := Basis().scaled(Vector3(leaf_scale, leaf_scale, leaf_scale))
			transforms.append(Transform3D(basis, lpos))
			customs.append(Color(lnrm.x, lnrm.y, lnrm.z, 0.0))

	var count := transforms.size()
	if count == 0:
		return

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	for k in count:
		mm.set_instance_transform(k, transforms[k])
		mm.set_instance_custom_data(k, customs[k])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	mmi.custom_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 20, 40))

	var pal: Dictionary = PALETTES[type]
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("alpha_map", load(ALPHA_PATH))
	mat.set_shader_parameter("shadow_color", pal["shadow"])
	mat.set_shader_parameter("mid_color", pal["mid"])
	mat.set_shader_parameter("highlight_color", pal["highlight"])
	mat.set_shader_parameter("color_multiplier", pal["mult"])
	mmi.material_override = mat
	_mats[type] = mat

	add_child(mmi)
	print("BushField: ", type, " -> ", count, " leaves")
