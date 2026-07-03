extends Node3D
## Seasonal weather particles: rain (rainy), snow (winter), falling leaves (autumn).
## Each is a GPUParticles3D toggled by EnvState.season.

const SOFT_DOT := "res://assets/textures/particles/particle_alpha_map_256x256.png"
const LEAF_PATH := "res://assets/models/leaf.glb"

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _leaves: Array[GPUParticles3D] = []

func _ready() -> void:
	_rain = _make_rain()
	_snow = _make_snow()
	var leaf_mesh := _load_leaf_mesh()
	_leaves.append(_make_leaves(leaf_mesh, Vector3(-4.0, 7.5, 10.0)))
	_leaves.append(_make_leaves(leaf_mesh, Vector3(4.0, 7.5, -10.0)))
	_apply()
	EnvState.season_changed.connect(_on_season_changed)

func _on_season_changed(_a: String, _b: String) -> void:
	_apply()

func _apply() -> void:
	var s := EnvState.season
	_rain.emitting = s == "rainy"
	_snow.emitting = s == "winter"
	var leaf_on := s == "autumn"
	var col := EnvState.leaf()
	for lp in _leaves:
		lp.emitting = leaf_on
		var mesh := lp.draw_pass_1
		if mesh and mesh.surface_get_material(0) is StandardMaterial3D:
			(mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(col.x, col.y, col.z)

func _add_particles(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = pos
	p.emitting = false
	p.fixed_fps = 30
	add_child(p)
	return p

func _make_rain() -> GPUParticles3D:
	var p := _add_particles(Vector3(0, 22, 0))
	p.amount = 800
	p.lifetime = 3.2
	p.preprocess = 3.0
	p.visibility_aabb = AABB(Vector3(-25, -30, -25), Vector3(50, 60, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20, 3, 20)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.gravity = Vector3(0, -3, 0)
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 12.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.7, 0.8, 0.9, 0.6)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	return p

func _make_snow() -> GPUParticles3D:
	var p := _add_particles(Vector3(0, 20, 0))
	p.amount = 600
	p.lifetime = 14.0
	p.preprocess = 8.0
	p.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 55, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20, 4, 15)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.gravity = Vector3(0, -0.4, 0)
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.5
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.9, 0.9, 1.0, 0.9)
	mat.albedo_texture = load(SOFT_DOT)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	return p

func _make_leaves(leaf_mesh: Mesh, pos: Vector3) -> GPUParticles3D:
	var p := _add_particles(pos)
	p.amount = 35
	p.lifetime = 8.0
	p.preprocess = 4.0
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3, 0.5, 1)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 20.0
	pm.gravity = Vector3(0.2, -1.2, 0.1)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.angular_velocity_min = -120.0
	pm.angular_velocity_max = 120.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.scale_min = 0.6
	pm.scale_max = 0.9
	p.process_material = pm
	if leaf_mesh != null:
		var m := leaf_mesh.duplicate()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.388, 0.278)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.surface_set_material(0, mat)
		p.draw_pass_1 = m
	return p

func _load_leaf_mesh() -> Mesh:
	var ps: PackedScene = load(LEAF_PATH)
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
