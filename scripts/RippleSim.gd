extends RefCounted
class_name RippleSim
## GPU ripple simulation: solves the 2D wave equation on a height field with a
## compute shader (shaders/ripple_sim.glsl), ping-ponging two rg32f textures on
## the main RenderingDevice. The pond mask pins land cells to zero so ripples
## reflect off the real shoreline. The live height field is exposed as a
## Texture2DRD the water material samples. All RenderingDevice work runs on the
## render thread via RenderingServer.call_on_render_thread.

const RES := 256
const SUBSTEPS := 3
const LOCAL := 8

var ok := false

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _field_a: RID
var _field_b: RID
var _field_disp: RID     # stable texture the material samples (copied into each step)
var _mask_tex: RID
var _brush_buf: RID
var _uset_ab: RID
var _uset_ba: RID
var _tex := Texture2DRD.new()

var _ping := true                       # true: read A write B
var _mask_bytes := PackedByteArray()
var _brush_bytes := PackedByteArray()
var _pc_bytes := PackedByteArray()
var _pending_brushes: Array = []        # [Vector4(uv.x,uv.y,radius,strength), ...]
var _inited := false
var _ready_flag := false                # true once the GPU texture rid is valid
var _bind_mat: ShaderMaterial = null    # material to hand the field texture to (on the render thread)
var _bind_param := ""

# tuning (packed into the push constant each step)
var c2 := 0.22
var damping := 0.993
var height_clamp := 4.0
var inject_scale := 1.0

func get_texture() -> Texture2DRD:
	return _tex

## True once the GPU field texture exists — only then is it safe for the water
## material to sample it (avoids "not a valid texture" on the first frames).
func is_ready() -> bool:
	return _ready_flag

## mask_floats: RES*RES row-major, 1 = water, 0 = land. The field texture is bound
## to bind_mat's bind_param on the render thread once it's valid (avoids the
## material ever sampling an uninitialised rid).
func setup(mask_floats: PackedFloat32Array, bind_mat: ShaderMaterial, bind_param: String) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		push_warning("RippleSim: no RenderingDevice (needs Forward+/Mobile). Sim disabled.")
		return
	_mask_bytes = mask_floats.to_byte_array()
	_brush_bytes.resize(16 + 64 * 16)   # int count + 3 pad, then 64 * vec4
	_bind_mat = bind_mat
	_bind_param = bind_param
	ok = true
	RenderingServer.call_on_render_thread(_init_gpu)

## Queue a disturbance. uv in [0,1] over the sim rect; radius in uv units.
func add_brush(uv: Vector2, radius: float, strength: float) -> void:
	if not ok:
		return
	if uv.x < -0.1 or uv.x > 1.1 or uv.y < -0.1 or uv.y > 1.1:
		return
	_pending_brushes.append(Vector4(uv.x, uv.y, radius, strength))

func step() -> void:
	if ok:
		RenderingServer.call_on_render_thread(_step_gpu)

func cleanup() -> void:
	if not ok:
		return
	ok = false
	# stop the material referencing the field texture before we free it
	if _bind_mat != null:
		_bind_mat.set_shader_parameter(_bind_param, null)
	RenderingServer.call_on_render_thread(_free_gpu)

# ── render thread ────────────────────────────────────────────────────────────

func _init_gpu() -> void:
	var shader_file: RDShaderFile = load("res://shaders/ripple_sim.glsl")
	_shader = _rd.shader_create_from_spirv(shader_file.get_spirv())
	_pipeline = _rd.compute_pipeline_create(_shader)

	# rg16f (not rg32f): 32-bit float formats aren't guaranteed linear-filterable,
	# and the water material samples the field with filter_linear. r16f is.
	var zero := PackedByteArray()
	zero.resize(RES * RES * 4)   # rg16f = 4 bytes/texel
	_field_a = _make_tex(RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, zero)
	_field_b = _make_tex(RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, zero)
	_field_disp = _make_tex(RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, zero)
	_mask_tex = _make_tex(RenderingDevice.DATA_FORMAT_R32_SFLOAT, _mask_bytes)

	_brush_buf = _rd.storage_buffer_create(_brush_bytes.size(), _brush_bytes)

	_uset_ab = _make_uset(_field_a, _field_b)
	_uset_ba = _make_uset(_field_b, _field_a)

	# The material samples _field_disp only — a stable rid that never changes, so
	# its uniform set is never invalidated. Each step copies the live state in.
	_tex.texture_rd_rid = _field_disp
	_inited = true
	_ready_flag = true
	if _bind_mat != null:
		_bind_mat.set_shader_parameter(_bind_param, _tex)

func _make_tex(fmt: int, data: PackedByteArray) -> RID:
	var tf := RDTextureFormat.new()
	tf.width = RES
	tf.height = RES
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.format = fmt
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(tf, RDTextureView.new(), [data])

func _make_uset(in_tex: RID, out_tex: RID) -> RID:
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(in_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(out_tex)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(_mask_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u3.binding = 3
	u3.add_id(_brush_buf)
	return _rd.uniform_set_create([u0, u1, u2, u3], _shader, 0)

func _step_gpu() -> void:
	if not _inited:
		return
	var groups := int(ceil(float(RES) / float(LOCAL)))
	var pf := PackedFloat32Array([c2, damping, height_clamp, inject_scale])
	_pc_bytes = pf.to_byte_array()

	var last_out := _field_a
	for s in range(SUBSTEPS):
		# brushes injected on the first substep only
		_write_brushes(_pending_brushes if s == 0 else [])
		_rd.buffer_update(_brush_buf, 0, _brush_bytes.size(), _brush_bytes)

		var uset := _uset_ab if _ping else _uset_ba
		last_out = _field_b if _ping else _field_a
		var cl := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
		_rd.compute_list_bind_uniform_set(cl, uset, 0)
		_rd.compute_list_set_push_constant(cl, _pc_bytes, _pc_bytes.size())
		_rd.compute_list_dispatch(cl, groups, groups, 1)
		_rd.compute_list_end()
		_ping = not _ping

	# publish the final state into the stable display texture the material samples
	_rd.texture_copy(last_out, _field_disp, Vector3(), Vector3(),
		Vector3(RES, RES, 1), 0, 0, 0, 0)
	_pending_brushes.clear()

func _write_brushes(list: Array) -> void:
	var n: int = min(list.size(), 64)
	_brush_bytes.encode_s32(0, n)
	_brush_bytes.encode_s32(4, 0)
	_brush_bytes.encode_s32(8, 0)
	_brush_bytes.encode_s32(12, 0)
	for i in range(n):
		var b: Vector4 = list[i]
		var o := 16 + i * 16
		_brush_bytes.encode_float(o + 0, b.x)
		_brush_bytes.encode_float(o + 4, b.y)
		_brush_bytes.encode_float(o + 8, b.z)
		_brush_bytes.encode_float(o + 12, b.w)

func _free_gpu() -> void:
	_tex.texture_rd_rid = RID()   # detach before freeing the underlying texture
	for r in [_field_a, _field_b, _field_disp, _mask_tex, _brush_buf, _pipeline, _shader]:
		if r.is_valid():
			_rd.free_rid(r)
