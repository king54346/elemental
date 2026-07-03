extends Node
## Audio system (autoload) — ported from MusicManager + AmbientSoundManager.
## Music: 3 tracks, random non-repeating, auto-advance. Ambient: season/time gated
## loops + scheduled random one-shots. UI SFX helpers. Gated by `music_enabled`.

const BASE := "res://assets/audio/"
const MUSIC := [
	{"id": "morning_petals", "name": "Morning Petals"},
	{"id": "window_light", "name": "Window Light"},
	{"id": "forest_dreams", "name": "Forest Dreams"},
]
const SOUNDS := {
	"birds_1": "sounds/birds/birds_1.mp3",
	"birds_2": "sounds/birds/birds_2.mp3",
	"birds_3": "sounds/birds/birds_3.mp3",
	"birds_4": "sounds/birds/birds_4.mp3",
	"crickets": "sounds/crickets/crickets.mp3",
	"fire": "sounds/fire/fire_burning.mp3",
	"owl_howling": "sounds/owl/owl_howling.mp3",
	"owl_hooting": "sounds/owl/owl_hooting.mp3",
	"rain": "sounds/rain/rain.mp3",
	"lake": "sounds/waves/lake_waves.mp3",
	"wolf": "sounds/wolf/wolf_howling.mp3",
	"thunder_distant": "sounds/thunder/distant/thunder_distant.mp3",
	"thunder_strike": "sounds/thunder/near/thunder_strike.mp3",
	"click": "sounds/ui_interactions/click.mp3",
	"hover": "sounds/ui_interactions/hover.mp3",
}

signal track_changed(name: String)

var music_enabled := true
var base_volume := 0.8

var _music: AudioStreamPlayer
var _current := -1
var _continuous := {}          # id -> AudioStreamPlayer / AudioStreamPlayer3D
var _gen := 0                  # bumped on every ambient update to cancel schedulers

func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)
	_music.finished.connect(_on_track_finished)
	EnvState.season_changed.connect(_on_env_changed)
	EnvState.env_time_changed.connect(_on_env_changed)
	if music_enabled:
		start_music()
	_update_ambient()

func _on_env_changed(_a: String, _b: String) -> void:
	_update_ambient()

# ---------- music ----------
func start_music() -> void:
	_play_next_track()

func _play_next_track() -> void:
	if not music_enabled:
		return
	var n := _current
	if MUSIC.size() > 1:
		while n == _current:
			n = randi() % MUSIC.size()
	else:
		n = 0
	_current = n
	var track: Dictionary = MUSIC[n]
	_music.stream = load(BASE + "musics/" + track.id + ".mp3")
	_music.volume_db = linear_to_db(base_volume)
	_music.play()
	track_changed.emit(track.name)

func _on_track_finished() -> void:
	if music_enabled:
		_play_next_track()

func toggle_music() -> bool:
	music_enabled = not music_enabled
	if music_enabled:
		start_music()
		_update_ambient()
	else:
		_music.stop()
		_stop_all_ambient()
	return music_enabled

func current_track_name() -> String:
	if _current >= 0:
		return MUSIC[_current].name
	return ""

# ---------- sfx ----------
func play_sfx(id: String, volume := 1.0) -> void:
	if not SOUNDS.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(BASE + SOUNDS[id])
	p.volume_db = linear_to_db(clampf(volume, 0.001, 1.0))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func play_thunder_strike() -> void:
	if music_enabled:
		play_sfx("thunder_strike", base_volume * 0.9)

# ---------- ambient ----------
func _stream(id: String, loop: bool) -> AudioStream:
	var s: AudioStream = load(BASE + SOUNDS[id])
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = loop
	return s

func _start_loop(id: String, volume: float, pos = null) -> void:
	if _continuous.has(id):
		return
	var p: Node
	if pos != null:
		var p3 := AudioStreamPlayer3D.new()
		p3.position = pos
		p3.max_distance = 35.0
		p3.unit_size = 12.0
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.stream = _stream(id, true)
	p.volume_db = linear_to_db(clampf(volume, 0.001, 1.0))
	add_child(p)
	p.play()
	_continuous[id] = p

func _stop_all_ambient() -> void:
	_gen += 1
	for id in _continuous:
		_continuous[id].queue_free()
	_continuous.clear()

func _update_ambient() -> void:
	_stop_all_ambient()
	if not music_enabled:
		return
	var season := EnvState.season
	var night := EnvState.is_night()
	var vol := base_volume * 0.7
	var my_gen := _gen

	# continuous loops
	if season in ["autumn", "spring", "winter"] and night:
		_start_loop("crickets", vol)
	if season == "rainy":
		_start_loop("rain", vol)
	if season != "rainy":
		_start_loop("fire", vol, Vector3(-5.4, 1.0, -6.9))
	_start_loop("lake", vol, Vector3(0, 0, 0))

	# scheduled randoms
	if season in ["autumn", "spring", "winter"] and not night:
		_schedule(my_gen, func(): _play_random_bird(), 8.0, 10.0)
	if night:
		_schedule(my_gen, func(): play_sfx("wolf", base_volume * 0.7), 8.0, 10.0)
	if night and season in ["autumn", "spring", "rainy"]:
		_schedule(my_gen, func(): play_sfx("owl_howling", base_volume), 8.0, 10.0)
	elif night and season == "winter":
		_schedule(my_gen, func(): play_sfx("owl_hooting", base_volume), 8.0, 10.0)
	if season == "rainy":
		_schedule(my_gen, func(): play_sfx("thunder_distant", base_volume * 0.9), 8.0, 10.0)

func _play_random_bird() -> void:
	play_sfx("birds_" + str(randi() % 4 + 1), base_volume)

func _schedule(my_gen: int, fn: Callable, gap_min: float, gap_max: float) -> void:
	while my_gen == _gen and music_enabled:
		await get_tree().create_timer(randf_range(gap_min, gap_max)).timeout
		if my_gen != _gen or not music_enabled:
			return
		fn.call()
