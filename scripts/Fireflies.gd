extends MultiMeshInstance3D
## Fireflies — 50 glowing quads in a ring around the origin, visible at night.
## Ported from the original FireFlies component (ring radius 9..16, y ~1).

const SHADER_PATH := "res://shaders/fireflies.gdshader"
const COUNT := 50
const MIN_RADIUS := 9.0
const MAX_RADIUS := 16.0

func _ready() -> void:
	_build()
	visible = EnvState.is_night()
	EnvState.env_time_changed.connect(_on_time_changed)

func _on_time_changed(_a: String, _b: String) -> void:
	visible = EnvState.is_night()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = COUNT

	for i in COUNT:
		var theta := rng.randf() * TAU
		var ri2 := MIN_RADIUS * MIN_RADIUS
		var ro2 := MAX_RADIUS * MAX_RADIUS
		var r := sqrt(rng.randf() * (ro2 - ri2) + ri2) + (rng.randf() - 0.5) * 0.6
		var x := r * cos(theta)
		var z := r * sin(theta)
		var y := 1.0 + (rng.randf() - 0.5) * 3.0
		var size := rng.randf() * 0.35 + 0.25
		var basis := Basis().scaled(Vector3(size, size, size))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		# (phase, colorMix, driftSeed, 0)
		mm.set_instance_custom_data(i, Color(rng.randf() * TAU, rng.randf(), rng.randf() * 10.0, 0.0))

	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 10, 40))

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	material_override = mat
