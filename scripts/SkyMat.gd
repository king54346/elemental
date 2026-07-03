extends WorldEnvironment
## Drives the sky + sun/moon directional light from EnvState's continuous
## time_of_day: the sun arcs across the sky, the moon sits opposite, the directional
## light comes from whichever body is up (warm sun by day, dim cool moon by night),
## and sky colors / light energy blend by sun elevation. When EnvState.cycle_enabled
## is false it snaps to noon/midnight based on env_time.

@export var sun_path: NodePath = ^"../Sun"
var _sun: DirectionalLight3D
var _m: ShaderMaterial

func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_m = environment.sky.sky_material as ShaderMaterial
	EnvState.season_changed.connect(_on_changed)
	EnvState.env_time_changed.connect(_on_changed)
	set_process(EnvState.cycle_enabled)
	if not EnvState.cycle_enabled:
		EnvState.time_of_day = 0.0 if EnvState.is_night() else 0.5
	_update()

func _on_changed(_a: String, _b: String) -> void:
	if not EnvState.cycle_enabled:
		EnvState.time_of_day = 0.0 if EnvState.is_night() else 0.5
	_update()

func _process(_dt: float) -> void:
	_update()

func _update() -> void:
	if _m == null:
		return
	var sd := EnvState.sun_dir()
	var df := EnvState.day_factor()
	var is_day := sd.y > 0.0
	var sday := EnvState.sky_day()
	var snight := EnvState.sky_night()

	# sky gradient blends between night and day by sun elevation
	_m.set_shader_parameter("zenith_color", (snight.zenith as Vector3).lerp(sday.zenith, df))
	_m.set_shader_parameter("horizon_color", (snight.horizon as Vector3).lerp(sday.horizon, df))
	_m.set_shader_parameter("ground_color", (snight.ground as Vector3).lerp(sday.ground, df))
	_m.set_shader_parameter("season", float(EnvState.season_index()))
	_m.set_shader_parameter("is_night", 0.0 if is_day else 1.0)
	_m.set_shader_parameter("sun_position", sd)
	_m.set_shader_parameter("moon_position", -sd)
	if is_day:
		_m.set_shader_parameter("sun_color", sday.sun)
		_m.set_shader_parameter("sun_glow_color", sday.sunglow)
	else:
		_m.set_shader_parameter("moon_color", snight.moon)
		_m.set_shader_parameter("moon_glow_color", snight.moonglow)
		_m.set_shader_parameter("star_color", snight.star)

	# directional light comes from whichever body is above the horizon
	if _sun:
		var body := sd if is_day else -sd
		_sun.look_at(_sun.global_position - body, Vector3.UP)
		# By day the sun casts shadows. At night the dim moonlight does NOT cast
		# shadows (it's fill only) — otherwise it throws directional shadows that
		# don't match the campfire/lamp (the actually-visible night light sources),
		# which reads as "shadows out of nowhere". Fire/lamp point lights cast the
		# night shadows instead.
		_sun.shadow_enabled = is_day
		# also ignore the tent (layer 2) at night so the moonlight's N·L shading
		# doesn't split the tent into light/dark halves; TentFill lights it.
		_sun.light_cull_mask = 1048575 if is_day else 1048573
		if is_day:
			var hi := clampf(sd.y * 2.5, 0.0, 1.0)           # reach full brightness soon after sunrise
			_sun.light_energy = lerpf(0.9, 1.55, hi)
			# warm golden sunlight (never pure white) for the sunny reference look
			_sun.light_color = Color(1.0, 0.87, 0.7).lerp(Color(1.0, 0.96, 0.85), hi)
			_sun.light_angular_distance = 0.5                # crisp shadows (large = gauzy/low-contrast)
		else:
			_sun.light_energy = 0.12                          # faint moonlight; fire/lamp dominate
			_sun.light_color = Color(0.5, 0.62, 0.95)
			_sun.light_angular_distance = 1.0

	if environment:
		environment.ambient_light_energy = lerpf(0.06, 0.6, df)
