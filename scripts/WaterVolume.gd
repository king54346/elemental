extends MeshInstance3D
## Drives the volumetric water surface (water_volume.gdshader). Replaces the whole
## C# WaterManager/WaterBody layer from the reference IWS with a few lines of
## GDScript, since this is a static diorama pond, not an interactive ocean:
##   - advances sim_time so the Gerstner waves + micro-normals animate,
##   - uploads a small fixed Gerstner wave set for a calm pond,
##   - keeps sun_direction / sun_color / sun_elevation in sync with EnvState's
##     day/night cycle so reflections, scatter and caustics match the sky,
##   - nudges wind/foam/absorption per season (calm spring, choppier rain,
##     icy-tinted winter).

const MAX_WAVES := 8
const WAVE_NONLINEAR_EXP := 1.3   # must match the material's wave_nonlinear_exp
const SIM_SIZE := 22.0            # world size the GPU ripple sim covers (matches the water mesh)
const FISH_COUNT := 8
const POND_CENTER := Vector2(1.0, -1.1)   # rough pond centre, for fish steering

# Calm-pond Gerstner set: gentle, short, low amplitude. dir, wavelength, amp, speed, steepness.
# Wave 0 is a slow, long-wavelength swell — the wind-driven gentle heave the pond
# rides on (the boat bobs on this); the rest are finer surface ripples.
const WAVES := [
	{ "dir": Vector2(1.0, 0.27),  "wl": 9.0, "amp": 0.060, "spd": 0.5, "steep": 0.06 },
	{ "dir": Vector2(1.0, 0.2),   "wl": 4.0, "amp": 0.045, "spd": 0.9, "steep": 0.15 },
	{ "dir": Vector2(-0.7, 1.0),  "wl": 2.6, "amp": 0.030, "spd": 1.1, "steep": 0.12 },
	{ "dir": Vector2(0.4, -0.9),  "wl": 1.7, "amp": 0.018, "spd": 1.4, "steep": 0.10 },
]

var _mat: ShaderMaterial
var _sun: DirectionalLight3D
var _t := 0.0

# GPU wave-equation ripple simulation (see RippleSim.gd)
var _sim: RippleSim = null
var _sim_center := Vector2.ZERO
var _wave_scale := 1.0      ## 0 = flat (winter ice), <1 = calmer (spring); also scales boat bob
var _ice_amount := 0.0      ## 0 = water, 1 = frozen ice (tweened on season change)
var _season_tween: Tween
var _fish: Array = []       ## koi: each { pos:Vector2, ang, speed, phase, wander, wspeed }
var _boat_pos := Vector2(9999.0, 9999.0)
var _boat_radius := 1.1

# density map (pond mask) sampled on the CPU so the boat can be constrained to water
var _density_img: Image = null
var _dw := 0
var _dh := 0
var _ground_size := 33.0
var _uv_rotation := 0.0
var _flip_u := false
var _flip_v := true

func _ready() -> void:
	_mat = get_surface_override_material(0)
	if _mat == null:
		push_warning("WaterVolume: no surface material 0")
		set_process(false)
		return
	_sun = get_node_or_null("../Sun") as DirectionalLight3D
	_upload_waves()
	_apply_season(true)
	_load_density()
	_setup_sim()
	_mat.set_shader_parameter("fish_count", 0)   # fish are now real 3D models (FishSchool)
	EnvState.season_changed.connect(_on_season)
	_sync_sun()

func _setup_sim() -> void:
	_sim_center = Vector2(global_position.x, global_position.z)
	_sim = RippleSim.new()
	_mat.set_shader_parameter("sim_center", _sim_center)
	_mat.set_shader_parameter("sim_size", SIM_SIZE)
	# the sim binds sim_height_tex itself, on the render thread, once it's valid
	_sim.setup(_build_sim_mask(), _mat, "sim_height_tex")

# ── Koi fish ─────────────────────────────────────────────────────────────────
func _spawn_fish() -> void:
	_fish.clear()
	var tries := 0
	while _fish.size() < FISH_COUNT and tries < 500:
		tries += 1
		var p := POND_CENTER + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		if water_amount(p) > 0.5:
			_fish.append({
				"pos": p, "ang": randf() * TAU, "speed": randf_range(0.25, 0.5),
				"phase": randf() * TAU, "wander": randf() * 10.0, "wspeed": randf_range(0.5, 1.2),
			})
	_mat.set_shader_parameter("fish_size", 0.4)

func _update_fish(dt: float) -> void:
	if _fish.is_empty():
		return
	var speed_scale := 1.0 - _ice_amount    # koi go dormant under the ice
	var arr := PackedVector4Array()
	arr.resize(12)
	for i in range(mini(_fish.size(), 12)):
		var f: Dictionary = _fish[i]
		var dir := Vector2(cos(f.ang), sin(f.ang))
		if water_amount(f.pos + dir * 0.7) < 0.3:              # shore ahead: steer to centre
			f.ang = _turn(f.ang, (POND_CENTER - f.pos).angle(), 3.0 * dt)
		else:
			f.wander += dt
			f.ang += sin(f.wander * f.wspeed + f.phase) * 0.7 * dt
		if f.pos.distance_to(_boat_pos) < 1.3:                 # avoid the boat
			f.ang = _turn(f.ang, (f.pos - _boat_pos).angle(), 3.5 * dt)
		f.pos += Vector2(cos(f.ang), sin(f.ang)) * f.speed * speed_scale * dt
		if water_amount(f.pos) < 0.1:                          # safety: nudge back to water
			f.pos = f.pos.lerp(POND_CENTER, 0.08)
		f.phase += dt
		arr[i] = Vector4(f.pos.x, f.pos.y, f.ang, f.phase)
	_mat.set_shader_parameter("fish_count", mini(_fish.size(), 12))
	_mat.set_shader_parameter("fish_data", arr)

func _turn(from_ang: float, to_ang: float, max_step: float) -> float:
	var diff := wrapf(to_ang - from_ang, -PI, PI)
	return from_ang + clampf(diff, -max_step, max_step)

# Rasterise the pond mask over the sim rect: 1 = water (ripples travel), 0 = land
# (fixed wall the ripples reflect off).
func _build_sim_mask() -> PackedFloat32Array:
	var res := RippleSim.RES
	var m := PackedFloat32Array()
	m.resize(res * res)
	for py in range(res):
		for px in range(res):
			var uv := Vector2((float(px) + 0.5) / res, (float(py) + 0.5) / res)
			var world := _sim_center + (uv - Vector2(0.5, 0.5)) * SIM_SIZE
			m[py * res + px] = 1.0 if water_amount(world) > 0.15 else 0.0
	return m

func _to_sim_uv(world_xz: Vector2) -> Vector2:
	return (world_xz - _sim_center) / SIM_SIZE + Vector2(0.5, 0.5)

func _load_density() -> void:
	var tex = _mat.get_shader_parameter("density_map")
	if tex is Texture2D:
		_density_img = (tex as Texture2D).get_image()
		if _density_img != null and _density_img.is_compressed():
			_density_img.decompress()
		if _density_img != null:
			_dw = _density_img.get_width()
			_dh = _density_img.get_height()
	var gs = _mat.get_shader_parameter("ground_size")
	if gs != null: _ground_size = gs
	var rot = _mat.get_shader_parameter("uv_rotation")
	if rot != null: _uv_rotation = rot
	var fu = _mat.get_shader_parameter("flip_u")
	if fu != null: _flip_u = fu
	var fv = _mat.get_shader_parameter("flip_v")
	if fv != null: _flip_v = fv

func _on_season(_a: String, _b: String) -> void:
	_apply_season(false)

func _process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("sim_time", _t)
	_sync_sun()
	if _sim != null:
		_sim.step()
	_mat.set_shader_parameter("boat_pos", _boat_pos)
	_mat.set_shader_parameter("boat_radius", _boat_radius)
	_mat.set_shader_parameter("wave_scale", _wave_scale)
	_mat.set_shader_parameter("ice_amount", _ice_amount)

func _exit_tree() -> void:
	if _sim != null:
		_sim.cleanup()

## Inject a disturbance into the ripple sim at a world XZ (call from the boat).
## radius is in world units; strength is the velocity impulse.
func add_ripple(world_xz: Vector2, strength: float, radius := 0.6) -> void:
	if _sim != null:
		_sim.add_brush(_to_sim_uv(world_xz), radius / SIM_SIZE, strength)

## Tell the water where the hull is, for the displacement dip + foam collar.
func set_boat(world_xz: Vector2, radius: float) -> void:
	_boat_pos = world_xz
	_boat_radius = radius

## Carve the water out of the boat hull using up to 4 tapering trapezoid segments
## (bow/mid/stern) that hug the hull outline. Each seg is a Dictionary:
## { center:Vector3, right:Vector3, forward:Vector3, half_width, half_length,
##   start_w, end_w, shape_type(0 box /1 taper), max_y, feather }.
func set_hull_cutouts(segs: Array) -> void:
	var n: int = mini(segs.size(), 4)
	var centers := PackedVector4Array(); centers.resize(4)
	var axes := PackedVector4Array(); axes.resize(4)
	var shapes := PackedVector4Array(); shapes.resize(4)
	var widths := PackedVector4Array(); widths.resize(4)
	var vert := PackedVector4Array(); vert.resize(4)
	for i in range(n):
		var s: Dictionary = segs[i]
		var c: Vector3 = s.center
		var r: Vector3 = s.right
		var f: Vector3 = s.forward
		centers[i] = Vector4(c.x, c.y, c.z, 0.0)
		axes[i] = Vector4(r.x, r.z, f.x, f.z)
		shapes[i] = Vector4(s.half_width, s.half_length, 0.0, s.shape_type)
		widths[i] = Vector4(s.start_w, s.end_w, 0.0, 0.0)
		vert[i] = Vector4(0.0, s.max_y, s.feather, 0.0)
	_mat.set_shader_parameter("hull_cut_count", n)
	_mat.set_shader_parameter("hull_cut_centers", centers)
	_mat.set_shader_parameter("hull_cut_axes", axes)
	_mat.set_shader_parameter("hull_cut_shapes", shapes)
	_mat.set_shader_parameter("hull_cut_widths", widths)
	_mat.set_shader_parameter("hull_cut_vert", vert)

## Pond mask (density.b) at a world XZ: ~0 = dry ground, ~1 = deep water. Used to
## keep the boat inside the actual pond shape. 1.0 if the mask isn't available.
func water_amount(world_xz: Vector2) -> float:
	if _density_img == null:
		return 1.0
	var uv := _world_to_density_uv(world_xz)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return 0.0
	var px := int(clampf(uv.x, 0.0, 0.999) * float(_dw))
	var py := int(clampf(uv.y, 0.0, 0.999) * float(_dh))
	return _density_img.get_pixel(px, py).b

# Mirrors ground.gdshader / water_volume.gdshader rot_density() so CPU sampling
# lines up exactly with the shader's pond mask.
func _world_to_density_uv(world_xz: Vector2) -> Vector2:
	var uv := (world_xz + Vector2(_ground_size, _ground_size) * 0.5) / _ground_size
	var a := deg_to_rad(_uv_rotation)
	var p := uv - Vector2(0.5, 0.5)
	p = Vector2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a))
	var r := p + Vector2(0.5, 0.5)
	if _flip_u: r.x = 1.0 - r.x
	if _flip_v: r.y = 1.0 - r.y
	return r

func _upload_waves() -> void:
	var dirs := PackedVector2Array()
	var wls := PackedFloat32Array()
	var amps := PackedFloat32Array()
	var spds := PackedFloat32Array()
	var steeps := PackedFloat32Array()
	dirs.resize(MAX_WAVES); wls.resize(MAX_WAVES); amps.resize(MAX_WAVES)
	spds.resize(MAX_WAVES); steeps.resize(MAX_WAVES)
	for i in range(WAVES.size()):
		var w: Dictionary = WAVES[i]
		dirs[i] = w.dir
		wls[i] = w.wl
		amps[i] = w.amp
		spds[i] = w.spd
		steeps[i] = w.steep
	_mat.set_shader_parameter("wave_count", WAVES.size())
	_mat.set_shader_parameter("wave_directions", dirs)
	_mat.set_shader_parameter("wave_wavelengths", wls)
	_mat.set_shader_parameter("wave_amplitudes", amps)
	_mat.set_shader_parameter("wave_speeds", spds)
	_mat.set_shader_parameter("wave_steepnesses", steeps)

func _sync_sun() -> void:
	var sd := EnvState.sun_dir()                       # direction TO the sun
	var df := EnvState.day_factor()                    # 0 night .. 1 day
	_mat.set_shader_parameter("sun_direction", sd)
	_mat.set_shader_parameter("sun_elevation", asin(clampf(sd.y, 0.0, 1.0)))
	var base := Vector3(1.0, 0.95, 0.85)
	if _sun != null:
		base = Vector3(_sun.light_color.r, _sun.light_color.g, _sun.light_color.b)
	_mat.set_shader_parameter("sun_color", base * (0.2 + 0.8 * df))

func _apply_season(instant: bool) -> void:
	# absorption/visibility set clarity; wind + wave_scale set how choppy it reads;
	# ice freezes the surface in winter.
	var absorption := Vector3(0.9, 0.35, 0.18)
	var visibility := 4.0
	var wind := 0.4
	var shallow := Color(0.13, 0.52, 0.55)
	var deep := Color(0.02, 0.16, 0.22)
	var wave_target := 0.85
	var ice_target := 0.0
	match EnvState.season:
		"spring", "":
			# calm + clear: low absorption, see deeper, gentle waves
			wind = 0.3; wave_target = 0.55
			absorption = Vector3(0.5, 0.22, 0.12); visibility = 6.5
			shallow = Color(0.16, 0.58, 0.62); deep = Color(0.03, 0.22, 0.3)
		"rainy":
			wind = 1.1; wave_target = 1.25
			absorption = Vector3(0.9, 0.35, 0.18); visibility = 3.5
		"winter":
			# freeze: flat surface, icy tint, ice sheet on top
			wind = 0.12; wave_target = 0.0; ice_target = 1.0
			absorption = Vector3(0.6, 0.5, 0.45); visibility = 3.0
			shallow = Color(0.55, 0.68, 0.72); deep = Color(0.15, 0.3, 0.36)
		"autumn":
			wind = 0.5; wave_target = 0.85
			absorption = Vector3(0.8, 0.45, 0.28); visibility = 3.5
			shallow = Color(0.22, 0.42, 0.4)
	_mat.set_shader_parameter("wind_speed", wind)
	_mat.set_shader_parameter("absorption_coeff", absorption)
	_mat.set_shader_parameter("visibility_distance", visibility)
	_mat.set_shader_parameter("color_shallow", shallow)
	_mat.set_shader_parameter("color_deep", deep)
	# smoothly freeze/thaw (and calm/roughen) the surface
	if _season_tween != null and _season_tween.is_valid():
		_season_tween.kill()
	if instant:
		_wave_scale = wave_target
		_ice_amount = ice_target
	else:
		_season_tween = create_tween().set_parallel(true)
		_season_tween.tween_property(self, "_wave_scale", wave_target, 2.5)
		_season_tween.tween_property(self, "_ice_amount", ice_target, 2.5)

## Evaluates the water surface at a world XZ, mirroring the shader's Gerstner sum
## exactly (same non-linear exponent + normal formula) so floating objects sit on
## the visible surface. Returns { height, normal, waterline }.
func sample_wave(world_xz: Vector2) -> Dictionary:
	var h := 0.0
	var grad := Vector2.ZERO   # dH/dx, dH/dz
	var nexp: float = maxf(WAVE_NONLINEAR_EXP, 1.0)
	for w in WAVES:
		var k: float = TAU / maxf(w.wl, 0.001)
		var d: Vector2 = (w.dir as Vector2).normalized()
		var phase: float = k * (d.x * world_xz.x + d.y * world_xz.y) - w.spd * _t
		var sp := sin(phase)
		var cp := cos(phase)
		var asp := absf(sp)
		h += w.amp * pow(asp, nexp) * signf(sp)
		var pow_term: float = 0.0 if asp < 1e-5 else w.amp * nexp * pow(asp, nexp - 1.0) * cp
		grad.x += pow_term * k * d.x
		grad.y += pow_term * k * d.y
	h *= _wave_scale               # calmer in spring, flat under winter ice
	grad *= _wave_scale
	var normal := Vector3(-grad.x, 1.0, -grad.y).normalized()
	var waterline: float = global_position.y
	return { "height": h, "normal": normal, "waterline": waterline }

## World-space water surface Y at a world XZ (base Gerstner waves, no GPU ripples).
## Used by the boat's buoyancy probes.
func water_height(world_xz: Vector2) -> float:
	var s := sample_wave(world_xz)
	return s.waterline + s.height
