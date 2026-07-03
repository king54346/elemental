extends Node3D
## Lightning system — ported from the original Lightning class. On strike: a jagged
## glowing bolt tube, an explosion particle burst, a screen flash, camera shake and
## a thunder clap. Auto-strikes every 10-20s in the rainy season; the ⚡ UI button
## calls manual_strike() via the "lightning" group.

const BOLT_SHADER := "res://shaders/lightning.gdshader"
const PARTICLE_TEX := "res://assets/textures/particles/particle_alpha_map_256x256.png"
const BOLT_HEIGHT := 15.0
const BOLT_DURATION := 3.0
const BOUND := 11.0

@export var camera_path: NodePath = ^"../Camera3D"

var _explosion: GPUParticles3D
var _flash: ColorRect
var _timer := 0.0
var _test := false

func _ready() -> void:
	add_to_group("lightning")
	_make_explosion()
	_make_flash()
	_test = OS.has_environment("LIGHTNING_TEST")
	_timer = 0.6 if _test else randf_range(10.0, 20.0)

func _process(delta: float) -> void:
	if _test:
		_timer -= delta
		if _timer <= 0.0:
			strike_random()
			_timer = 1.2
	elif EnvState.season == "rainy":
		_timer -= delta
		if _timer <= 0.0:
			strike_random()
			_timer = randf_range(10.0, 20.0)

func manual_strike() -> void:
	strike_random()

func strike_random() -> void:
	strike(Vector3(randf_range(-BOUND, BOUND), 0.0, randf_range(-BOUND, BOUND)))

func strike(pos: Vector3) -> void:
	_spawn_bolt(pos)
	_spawn_explosion(pos)
	_do_flash()
	var cam := get_node_or_null(camera_path)
	if cam and cam.has_method("add_shake"):
		cam.add_shake(0.85, 0.65)
	AudioManager.play_thunder_strike()

# ---------- bolt ----------
func _spawn_bolt(pos: Vector3) -> void:
	var n := 15
	var step := BOLT_HEIGHT / float(n - 1)
	var pts: Array[Vector3] = []
	for i in n:
		pts.append(Vector3((randf() - 0.5), float(i) * step, (randf() - 0.5)))

	var mi := MeshInstance3D.new()
	mi.mesh = _build_tube(pts, 0.07, 6)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load(BOLT_SHADER)
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("bolt_height", BOLT_HEIGHT)
	mat.set_shader_parameter("color_a", Color(0, 0, 1))
	mat.set_shader_parameter("color_b", Color(0, 1, 1))
	mat.set_shader_parameter("intensity", 3.0)
	mi.material_override = mat
	add_child(mi)

	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 0.0, 1.0, BOLT_DURATION)
	tw.tween_callback(mi.queue_free)

func _build_tube(pts: Array[Vector3], radius: float, sides: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in pts.size():
		var dir: Vector3
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		dir = dir.normalized()
		var up_ref := Vector3(1, 0, 0)
		if absf(dir.dot(up_ref)) > 0.9:
			up_ref = Vector3(0, 0, 1)
		var right := dir.cross(up_ref).normalized()
		var up2 := right.cross(dir).normalized()
		for s in sides:
			var a := TAU * float(s) / float(sides)
			var off := right * cos(a) + up2 * sin(a)
			verts.append(pts[i] + off * radius)
			normals.append(off)
	for i in pts.size() - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a := i * sides + s
			var b := i * sides + s2
			var c := (i + 1) * sides + s
			var d := (i + 1) * sides + s2
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

# ---------- explosion ----------
func _make_explosion() -> void:
	_explosion = GPUParticles3D.new()
	_explosion.amount = 100
	_explosion.lifetime = 1.3
	_explosion.one_shot = true
	_explosion.explosiveness = 1.0
	_explosion.emitting = false
	_explosion.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 30, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, -1.5, 0)
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 6.0
	pm.scale_min = 0.1
	pm.scale_max = 0.2
	pm.color_ramp = _ramp()
	_explosion.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = load(PARTICLE_TEX)
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	_explosion.draw_pass_1 = quad
	add_child(_explosion)

func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offsets(PackedFloat32Array([0.0, 0.5, 1.0]))
	g.set_colors(PackedColorArray([
		Color(1.0, 0.506, 0.09, 1.0),
		Color(1.0, 0.67, 0.045, 0.8),
		Color(1.0, 0.835, 0.0, 0.0)]))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _spawn_explosion(pos: Vector3) -> void:
	_explosion.position = pos
	_explosion.restart()
	_explosion.emitting = true

# ---------- flash ----------
func _make_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)

func _do_flash() -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.5, 0.06)
	tw.tween_property(_flash, "color:a", 0.0, 0.3)
