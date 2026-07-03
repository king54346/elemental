extends OmniLight3D
## Attach to a light (e.g. the camp lamp) that should only be lit at night.
## The light's energy set in the editor is used as the night brightness; during the
## day it fades to `day_energy` (0 = off). Reacts to EnvState.env_time_changed.

@export var day_energy: float = 0.0
@export var fade_time: float = 1.0

var _night_energy: float = 2.0

func _ready() -> void:
	_night_energy = light_energy          # brightness you set in the editor = night level
	light_energy = _night_energy if EnvState.is_night() else day_energy
	EnvState.env_time_changed.connect(_on_time_changed)

func _on_time_changed(_new_time: String, _old: String) -> void:
	var target: float = _night_energy if EnvState.is_night() else day_energy
	if fade_time > 0.0:
		create_tween().tween_property(self, "light_energy", target, fade_time)
	else:
		light_energy = target
