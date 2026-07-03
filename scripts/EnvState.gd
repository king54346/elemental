extends Node
## Autoload singleton for season / time-of-day state, ported from the original
## SeasonManager + EnvironmentTimeManager. Emits signals when either changes so
## components can recolor themselves. Toggle with keys S (season) and T (time).
## Initial state can be overridden via env vars ELEM_SEASON / ELEM_TIME (for
## headless screenshots).

signal season_changed(new_season: String, old_season: String)
signal env_time_changed(new_time: String, old_time: String)

const SEASONS := ["spring", "winter", "autumn", "rainy"]
const TIMES := ["day", "night"]

var season := "spring"
var env_time := "day"

## Continuous day/night cycle. time_of_day: 0=midnight, .25=sunrise, .5=noon,
## .75=sunset. The sun/moon light + sky bodies move with it (see SkyMat.gd); when
## the sun crosses the horizon, env_time flips (day/night) so all the discrete
## systems (fireflies, lamp, weather, sounds, material colors) still work.
@export var cycle_enabled := true
@export var day_length_sec := 120.0
var time_of_day := 0.5

func _ready() -> void:
	if OS.has_environment("ELEM_SEASON"):
		var s := OS.get_environment("ELEM_SEASON")
		if s in SEASONS:
			season = s
	if OS.has_environment("ELEM_TIME"):
		var t := OS.get_environment("ELEM_TIME")
		if t in TIMES:
			env_time = t
	time_of_day = 0.0 if env_time == "night" else 0.5
	if OS.has_environment("ELEM_TOD"):
		time_of_day = fposmod(OS.get_environment("ELEM_TOD").to_float(), 1.0)
		env_time = "night" if sun_dir().y <= 0.0 else "day"
	set_process(cycle_enabled)

func _process(delta: float) -> void:
	if not cycle_enabled:
		return
	time_of_day = fposmod(time_of_day + delta / maxf(day_length_sec, 1.0), 1.0)
	var want := "night" if sun_dir().y <= 0.0 else "day"
	if want != env_time:
		set_env_time(want)

## Direction TO the sun from the origin, arcing across the sky over time_of_day.
func sun_dir() -> Vector3:
	var a := time_of_day * TAU
	return Vector3(sin(a) * 0.85, -cos(a), -0.45).normalized()

## 0 = full night, 1 = full day, smooth around sunrise/sunset.
func day_factor() -> float:
	return clampf(sun_dir().y * 3.5 + 0.5, 0.0, 1.0)

func sky_day() -> Dictionary: return SeasonData.SKY[season]["day"]
func sky_night() -> Dictionary: return SeasonData.SKY[season]["night"]

## Blend a season's night->day color dicts by the current day_factor, so materials
## transition smoothly through dawn/dusk instead of snapping at the horizon crossing.
func _blend(n: Dictionary, d: Dictionary, t: float) -> Dictionary:
	var r := {}
	for k in n:
		var nv = n[k]
		if nv is Vector3:
			r[k] = (nv as Vector3).lerp(d[k], t)
		else:
			r[k] = lerpf(float(nv), float(d[k]), t)
	return r

func ground_blended() -> Dictionary: return _blend(SeasonData.GROUND[season]["night"], SeasonData.GROUND[season]["day"], day_factor())
func grass_blended() -> Dictionary: return _blend(SeasonData.GRASS[season]["night"], SeasonData.GRASS[season]["day"], day_factor())
func rocks_blended() -> Dictionary: return _blend(SeasonData.ROCKS[season]["night"], SeasonData.ROCKS[season]["day"], day_factor())
func bush_blended() -> Dictionary: return _blend(SeasonData.BUSH[season]["night"], SeasonData.BUSH[season]["day"], day_factor())

func set_season(s: String) -> void:
	if not s in SEASONS or s == season:
		return
	var old := season
	season = s
	season_changed.emit(season, old)

func set_env_time(t: String) -> void:
	if not t in TIMES or t == env_time:
		return
	var old := env_time
	env_time = t
	env_time_changed.emit(env_time, old)

func toggle_season() -> void:
	var i := SEASONS.find(season)
	set_season(SEASONS[(i + 1) % SEASONS.size()])

func toggle_time() -> void:
	if cycle_enabled:
		time_of_day = fposmod(time_of_day + 0.5, 1.0)   # jump to the opposite half
		set_env_time("night" if sun_dir().y <= 0.0 else "day")
	else:
		set_env_time("night" if env_time == "day" else "day")

func is_night() -> bool:
	return env_time == "night"

func season_index() -> int:
	return SeasonData.SEASON_INDEX[season]

# --- color getters for the current state ---
func ground() -> Dictionary: return SeasonData.GROUND[season][env_time]
func grass() -> Dictionary: return SeasonData.GRASS[season][env_time]
func rocks() -> Dictionary: return SeasonData.ROCKS[season][env_time]
func bush() -> Dictionary: return SeasonData.BUSH[season][env_time]
func sky() -> Dictionary: return SeasonData.SKY[season][env_time]
func windline() -> Vector3: return SeasonData.WINDLINE[season]
func leaf() -> Vector3: return SeasonData.LEAF[season]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				toggle_season()
			KEY_T:
				toggle_time()
