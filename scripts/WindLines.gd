extends Node3D
## Wind lines — ported from the original WindLines component. A small pool of wavy
## ribbon meshes that periodically sweep across the scene at y=3 and fade out.

const SHADER_PATH := "res://shaders/windlines.gdshader"
const WIND_COLOR := Color(1, 1, 1)   # spring windLines.color = 0xffffff

const DURATION := 4.0
const TRANSLATION := 1.0
const THICKNESS := 0.25
const RADIUS := 25.0
const INTERVAL_MIN := 0.3
const INTERVAL_MAX := 2.0

var _pool: Array = []          # each: {mesh: MeshInstance3D, mat: ShaderMaterial, available: bool}

func _ready() -> void:
	var mesh := _build_ribbon_mesh()
	for i in 3:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER_PATH)
		mat.set_shader_parameter("thickness", THICKNESS)
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("wind_color", WIND_COLOR)
		mat.set_shader_parameter("tangent", Vector3(0.0, 0.7071, -0.7071))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position.y = 3.0
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pool.append({"mesh": mi, "mat": mat, "available": true})
	_apply_color()
	EnvState.season_changed.connect(_on_season_changed)
	_loop()

func _on_season_changed(_a: String, _b: String) -> void:
	_apply_color()

func _apply_color() -> void:
	var v := EnvState.windline()
	for s in _pool:
		s["mat"].set_shader_parameter("wind_color", Color(v.x, v.y, v.z))

func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _build_ribbon_mesh(length: float = 11.0, handles_count: int = 4, amplitude: float = 1.0, divisions: int = 30) -> ArrayMesh:
	var half := length / 2.0
	var span := length / float(handles_count - 1)
	var handles: Array[Vector3] = []
	for i in handles_count:
		handles.append(Vector3(0.0, (float(i % 2) - 0.5) * amplitude, -half + float(i) * span))

	# sample a catmull-rom curve through the handles -> (divisions+1) points
	var pts: Array[Vector3] = []
	var segs := handles_count - 1
	for d in divisions + 1:
		var gt := float(d) / float(divisions) * float(segs)
		var seg := int(floor(gt))
		if seg >= segs:
			seg = segs - 1
		var lt := gt - float(seg)
		var p0 := handles[max(seg - 1, 0)]
		var p1 := handles[seg]
		var p2 := handles[seg + 1]
		var p3 := handles[min(seg + 2, handles_count - 1)]
		pts.append(_catmull(p0, p1, p2, p3, lt))

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in pts.size():
		var ratio := float(i) / float(pts.size() - 1)
		verts.append(pts[i]); verts.append(pts[i])
		uvs.append(Vector2(ratio, 0.0)); uvs.append(Vector2(ratio, 1.0))
		if i < pts.size() - 1:
			var base := i * 2
			indices.append(base); indices.append(base + 1); indices.append(base + 2)
			indices.append(base + 1); indices.append(base + 3); indices.append(base + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.custom_aabb = AABB(Vector3(-1, -2, -6), Vector3(2, 4, 12))
	return am

func _loop() -> void:
	_display()
	var delay := randf_range(INTERVAL_MIN, INTERVAL_MAX)
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		_loop()

func _display() -> void:
	var slot = null
	for s in _pool:
		if s["available"]:
			slot = s
			break
	if slot == null:
		return

	var angle := PI
	var mi: MeshInstance3D = slot["mesh"]
	var mat: ShaderMaterial = slot["mat"]
	slot["available"] = false

	mi.position.x = (randf() - 0.5) * RADIUS
	mi.position.z = (randf() - 0.5) * RADIUS
	mi.position.y = 3.0
	mi.rotation.y = angle
	mi.visible = true

	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("progress", v), 0.0, 1.0, DURATION)
	tw.parallel().tween_property(mi, "position:x", mi.position.x + sin(angle) * TRANSLATION, DURATION)
	tw.parallel().tween_property(mi, "position:z", mi.position.z + cos(angle) * TRANSLATION, DURATION)
	tw.tween_callback(func():
		mi.visible = false
		slot["available"] = true)
