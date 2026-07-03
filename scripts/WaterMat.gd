extends MeshInstance3D
## Sets the water overlay's ripple/splash/ice ratios based on season.
## rainy -> ripples + splashes, winter -> ice, otherwise -> gentle ripples.

func _ready() -> void:
	_apply()
	EnvState.season_changed.connect(_on_changed)

func _on_changed(_a: String, _b: String) -> void:
	_apply()

func _apply() -> void:
	var m := get_surface_override_material(0)
	if m == null:
		return
	var ripples := 1.0
	var splashes := 0.0
	var ice := 0.0
	match EnvState.season:
		"rainy":
			ripples = 1.0; splashes = 1.0; ice = 0.0
		"winter":
			ripples = 0.0; splashes = 0.0; ice = 1.0
		_:
			ripples = 1.0; splashes = 0.0; ice = 0.0
	m.set_shader_parameter("ripples_ratio", ripples)
	m.set_shader_parameter("splashes_ratio", splashes)
	m.set_shader_parameter("ice_ratio", ice)
