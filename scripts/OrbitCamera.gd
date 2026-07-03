extends Camera3D
## Orbit camera replicating the Three.js OrbitControls setup from the original
## project: orbits a fixed target, damped rotation, zoom, and polar-angle limits.
## Original: fov 25, pos (18.25, 10.69, 27.32), maxPolar PI/2.2, minPolar PI/4.

@export var target: Vector3 = Vector3.ZERO
@export var min_distance: float = 12.0
@export var max_distance: float = 35.0
## Polar angle measured from +Y (like Three.js). Elevation = PI/2 - polar.
@export var min_polar: float = PI / 4.0      # 45°
@export var max_polar: float = PI / 2.2      # ~81.8°
@export var rotate_speed: float = 0.006
@export var zoom_speed: float = 1.5
@export var damping: float = 8.0

var _yaw: float
var _pitch: float          # elevation angle from the horizontal plane
var _target_yaw: float
var _target_pitch: float
var _distance: float
var _target_distance: float
var _dragging: bool = false

var _shake_t: float = 0.0
var _shake_dur: float = 0.65
var _shake_intensity: float = 0.0

func add_shake(intensity: float = 0.85, duration: float = 0.65) -> void:
	_shake_intensity = intensity
	_shake_dur = duration
	_shake_t = duration

func _ready() -> void:
	var offset := global_position - target
	_target_distance = clampf(offset.length(), min_distance, max_distance)
	_distance = _target_distance
	_target_yaw = atan2(offset.x, offset.z)
	_target_pitch = asin(clampf(offset.y / max(offset.length(), 0.001), -1.0, 1.0))
	_yaw = _target_yaw
	_pitch = _target_pitch

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - zoom_speed, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + zoom_speed, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		_target_yaw -= event.relative.x * rotate_speed
		_target_pitch += event.relative.y * rotate_speed
		# Clamp elevation to the equivalent of Three.js polar-angle limits.
		var min_elev := PI / 2.0 - max_polar
		var max_elev := PI / 2.0 - min_polar
		_target_pitch = clampf(_target_pitch, min_elev, max_elev)

func _process(delta: float) -> void:
	var t := clampf(damping * delta, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, _target_yaw, t)
	_pitch = lerpf(_pitch, _target_pitch, t)
	_distance = lerpf(_distance, _target_distance, t)

	var cp := cos(_pitch)
	var offset := Vector3(
		_distance * cp * sin(_yaw),
		_distance * sin(_pitch),
		_distance * cp * cos(_yaw)
	)
	global_position = target + offset
	look_at(target, Vector3.UP)

	if _shake_t > 0.0:
		_shake_t -= delta
		var f := clampf(_shake_t / _shake_dur, 0.0, 1.0)
		var amp := _shake_intensity * f * f
		global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * amp
