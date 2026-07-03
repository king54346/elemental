extends MeshInstance3D
## Recolors the ground shader when season/time changes, and is the single control
## point for the density-map orientation: its material's uv_rotation / flip_u /
## flip_v are propagated to the water shader and the grass/flower placement so the
## whole scene stays aligned when you tweak them in the inspector.

func _ready() -> void:
	_apply()
	EnvState.season_changed.connect(_on_changed)
	EnvState.env_time_changed.connect(_on_changed)
	call_deferred("_propagate_orientation")

func _propagate_orientation() -> void:
	var m := get_surface_override_material(0)
	if m == null:
		return
	var rot = m.get_shader_parameter("uv_rotation")
	if rot == null:
		return
	var fu = m.get_shader_parameter("flip_u")
	var fv = m.get_shader_parameter("flip_v")
	if fu == null:
		fu = false
	if fv == null:
		fv = false
	var parent := get_parent()
	# Only the water overlay needs pushing here; grass/flowers read the same values
	# from this material in their own _ready (so they build exactly once).
	var water := parent.get_node_or_null("Water") as GeometryInstance3D
	if water:
		var wm: ShaderMaterial = water.get_surface_override_material(0)
		if wm:
			wm.set_shader_parameter("uv_rotation", rot)
			wm.set_shader_parameter("flip_u", fu)
			wm.set_shader_parameter("flip_v", fv)

func _on_changed(_a: String, _b: String) -> void:
	_apply()

func _process(_dt: float) -> void:
	if EnvState.cycle_enabled:
		_apply()   # continuous dawn/dusk color blend

func _apply() -> void:
	var m := get_surface_override_material(0)
	if m == null:
		return
	var c := EnvState.ground_blended()
	m.set_shader_parameter("ground_color_light", c.light)
	m.set_shader_parameter("ground_color_dark", c.dark)
	m.set_shader_parameter("ground_color_below_grass", c.below)
	m.set_shader_parameter("rock_color", c.rock)
	m.set_shader_parameter("water_shallow", c.wshallow)
	m.set_shader_parameter("water_deep", c.wdeep)
	# grass floor = the season's mid grass tone (between base and tip), so gaps
	# between blades blend in with the grass instead of looking high-contrast.
	var g := EnvState.grass_blended()
	var floor_col: Vector3 = (g.dark as Vector3).lerp(g.light as Vector3, 0.8)
	m.set_shader_parameter("grass_floor", floor_col)
