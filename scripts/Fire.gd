extends Node3D
## Campfire — ported from the original Fire component's CPU particle system to
## Godot GPUParticles3D. Three emitters (fire / smoke / amber embers) plus two
## flickering point lights. World positions match the original (fire pit at
## roughly (-5.4, 1.0, -6.9)).

const FIRE_TEX := "res://assets/textures/fire/fire_256x256.png"
const SMOKE_TEX := "res://assets/textures/fire/smoke_256x256.png"
const AMBER_TEX := "res://assets/textures/particles/particle_alpha_map_256x256.png"

var _light1: OmniLight3D
var _light2: OmniLight3D
var _light1_base := 3.0
var _light2_base := 1.6
var _flicker_speed := 10.0
var _flicker_amount := 0.4
var _t := 0.0
var _off1 := randf() * 100.0
var _off2 := randf() * 100.0

func _ready() -> void:
	_make_fire()
	_make_smoke()
	_make_amber()
	_make_lights()

func _grad(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offsets(PackedFloat32Array(offsets))
	g.set_colors(PackedColorArray(colors))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _curve(points: Array, max_value: float = 2.0) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_value
	for p in points:
		c.add_point(p)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

func _billboard_mat(tex_path: String, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_texture = load(tex_path)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m

func _emitter(amount: int, lifetime: float, pos: Vector3, quad_size: float, additive: bool, tex: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.position = pos
	p.explosiveness = 0.0
	p.randomness = 0.4
	p.fixed_fps = 30
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = _billboard_mat(tex, additive)
	p.draw_pass_1 = quad
	add_child(p)
	return p

func _make_fire() -> void:
	var p := _emitter(500, 1.0, Vector3(-5.4, 1.0, -6.9), 0.7, true, FIRE_TEX)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 0.6
	pm.damping_min = 0.4
	pm.damping_max = 0.6
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	pm.scale_curve = _curve([Vector2(0.0, 0.25), Vector2(0.5, 1.0), Vector2(1.0, 0.1)])
	pm.color_ramp = _grad(
		[0.0, 0.2, 0.3, 0.7, 0.85, 1.0],
		[Color(0.58, 0.38, 0.063, 0.0), Color(0.6, 0.41, 0.06, 1.0),
		Color(0.62, 0.44, 0.059, 0.95), Color(0.99, 0.28, 0.0, 0.85),
		Color(0.99, 0.1, 0.0, 0.7), Color(0.99, 0.0, 0.0, 0.0)])
	p.process_material = pm

func _make_smoke() -> void:
	var p := _emitter(150, 3.0, Vector3(-5.4, 1.9, -6.9), 1.2, false, SMOKE_TEX)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.gravity = Vector3(0, 0.15, 0)
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.damping_min = 0.0
	pm.damping_max = 0.1
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.25
	pm.turbulence_noise_scale = 1.2
	pm.scale_min = 1.0
	pm.scale_max = 1.4
	pm.scale_curve = _curve([Vector2(0.0, 0.25), Vector2(0.5, 1.0), Vector2(1.0, 0.35)])
	# smoke is very faint (alpha ~0.1 max)
	pm.color_ramp = _grad(
		[0.0, 0.1, 0.55, 1.0],
		[Color(1.0, 0.945, 0.8, 0.0), Color(1.0, 0.98, 0.94, 0.1),
		Color(1.0, 1.0, 1.0, 0.04), Color(1.0, 1.0, 1.0, 0.01)])
	p.process_material = pm

func _make_amber() -> void:
	# rising sparks / embers: shoot up out of the fire, decelerate, twinkle, fade
	var p := _emitter(110, 1.9, Vector3(-5.4, 1.0, -6.9), 0.07, true, AMBER_TEX)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 16.0
	pm.gravity = Vector3(0, -1.6, 0)          # rise then arc back down
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 4.2
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	pm.turbulence_enabled = true               # gentle wobble as they drift up
	pm.turbulence_noise_strength = 0.3
	pm.turbulence_noise_scale = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _curve([Vector2(0.0, 0.4), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	pm.color_ramp = _grad(
		[0.0, 0.15, 0.5, 1.0],
		[Color(1.0, 0.85, 0.4, 0.0), Color(1.0, 0.8, 0.25, 1.0),
		Color(1.0, 0.45, 0.1, 0.8), Color(1.0, 0.2, 0.0, 0.0)])
	p.process_material = pm

func _make_lights() -> void:
	_light1 = OmniLight3D.new()
	_light1.light_color = Color(0.97, 0.42, 0.106)
	_light1.light_energy = _light1_base
	_light1.omni_range = 9.0                # reach further so the lit->dark edge is gentle
	_light1.omni_attenuation = 1.0          # gentler falloff (was 2.0 = hard edge)
	_light1.position = Vector3(-5.5, 1.0, -7.0)
	_light1.shadow_enabled = true          # campfire casts shadows at night
	_light1.shadow_bias = 0.08
	_light1.light_size = 0.9                # soft shadow penumbra (was 0 = hard)
	add_child(_light1)

	_light2 = OmniLight3D.new()
	_light2.light_color = Color(0.97, 0.5, 0.18)
	_light2.light_energy = _light2_base
	_light2.omni_range = 2.5
	_light2.omni_attenuation = 2.0
	_light2.position = Vector3(-5.5, 0.5, -7.0)
	_light2.shadow_enabled = false
	add_child(_light2)

func _smooth_noise(x: float) -> float:
	return (sin(x) + sin(x * 2.3) * 0.5 + sin(x * 4.7) * 0.25) / 1.5

func _process(delta: float) -> void:
	if _light1 == null:
		return
	_t += delta
	if _t > 628.0:
		_t -= 628.0
	var f1 := _smooth_noise(_t * _flicker_speed + _off1)
	var f2 := _smooth_noise(_t * _flicker_speed * 1.3 + _off2)
	var combined := (f1 + f2 * 0.5) / 1.5
	_light1.light_energy = _light1_base + combined * _light1_base * _flicker_amount
	_light1.position.y = 1.0 + sin(_t * 2.0) * 0.1
	var f3 := _smooth_noise(_t * _flicker_speed * 0.8 + _off2 + 50.0)
	_light2.light_energy = _light2_base + f3 * _flicker_amount * 2.0
