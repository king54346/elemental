extends RigidBody3D
## Voxel-based buoyancy (adapted from the IWS IWSBuoyancyBody): the collision box
## is filled with a grid of voxels; each submerged voxel gets a proper Archimedes
## up-force (water_density · g · voxel_volume · submersion), so the boat finds its
## own waterline from displaced volume, and its centre of buoyancy shifts with the
## waves for natural rocking. Submersion is smoothed over a radius (no jitter).
##
##   - CLICK the boat to shove it (impulse + a little roll).
##   - Moving through the water injects ripples into the GPU sim (displacement).
##   - Tapering trapezoid cutouts carve the water out of the open hull.
##   - Paddles from the source model are hidden.

@export_group("Buoyancy (voxel)")
@export var buoyancy_volume := 0.04       ## total displaced volume (m³) when fully submerged — tune for draft
@export var water_density := 1000.0
@export var submersion_radius := 0.12     ## smoothing distance across the waterline (anti-jitter)
@export var voxel_drag := 15.0            ## water resistance per submerged voxel
@export var voxels := Vector3i(5, 2, 3)   ## voxel grid resolution filling the hull box

@export_group("Click push")
@export var push_impulse := 7.0
@export var push_rock := 0.4              ## roll on shove — keep small so a tilt doesn't dip a rim underwater
@export var click_radius := 2.0
@export var max_tilt_deg := 14.0         ## clamp roll/pitch so the hull can't tip a side under water

@export_group("Water interaction")
@export var collar_radius := 1.1
@export var enable_cutout := true              ## carve water out of the hull so the surface never shows inside
## The cutout shape is defined by WaterCutoutTrapezoid child nodes (Bow/Mid/Stern),
## editable in the editor. They're collected on ready and fed to the water each frame.
@export var ripple_spacing := 0.22       ## distance travelled between wake ripples
@export var ripple_speed_min := 0.25
@export var ripple_gain := 1.4
@export var edge_water := 0.2            ## pond-mask value below which the edge force kicks in
@export var edge_push := 90.0
@export var pond_center := Vector2(1.0, -1.1)

var _water: Node = null
var _voxels: PackedVector3Array = PackedVector3Array()
var _vox_volume := 0.0
var _gravity := 9.8
var _cutouts: Array = []      ## WaterCutoutTrapezoid child nodes (Bow/Mid/Stern)
var _ripple_accum := 0.0
var _press_pos := Vector2.ZERO
var _press_active := false

func _ready() -> void:
	_water = get_node_or_null("../Water")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	for m in find_children("*", "MeshInstance3D", true, false):
		if "addle" in String(m.name):
			(m as MeshInstance3D).visible = false
	_build_voxels()
	_cutouts = find_children("*", "WaterCutoutTrapezoid", true, false)
	# freeze the boat into the ice in winter, thaw otherwise
	EnvState.season_changed.connect(_on_season)
	_on_season(EnvState.season, "")
	if _water == null or not _water.has_method("water_height"):
		push_warning("FloatingBoat: no Water/water_height; buoyancy disabled.")
		set_physics_process(false)

func _on_season(s: String, _old: String) -> void:
	# winter: lock the hull in place (frozen in the ice); other seasons: float freely
	freeze = (s == "winter")

# Fill the collision box with a voxel grid (local space) for buoyancy sampling.
func _build_voxels() -> void:
	var size := Vector3(3.0, 0.58, 1.05)
	var center := Vector3(0.0, 0.31, 0.0)
	var col := get_node_or_null("Col") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		size = (col.shape as BoxShape3D).size
		center = col.position
	_voxels = PackedVector3Array()
	var n := Vector3i(maxi(voxels.x, 1), maxi(voxels.y, 1), maxi(voxels.z, 1))
	for ix in n.x:
		for iy in n.y:
			for iz in n.z:
				var t := Vector3((ix + 0.5) / float(n.x), (iy + 0.5) / float(n.y), (iz + 0.5) / float(n.z))
				_voxels.append(center + (t - Vector3(0.5, 0.5, 0.5)) * size)
	_vox_volume = buoyancy_volume / maxf(float(_voxels.size()), 1.0)

# Safety limit: keep the boat from tilting far enough to capsize / dip a rim
# deep under. Voxel buoyancy handles the rest naturally.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var xf := state.transform
	var up := xf.basis.y.normalized()
	if up.dot(Vector3.UP) < cos(deg_to_rad(max_tilt_deg)):
		var target := up.slerp(Vector3.UP, 0.5)
		var axis := up.cross(target)
		var ang := up.angle_to(target)
		if axis.length() > 1e-4 and ang > 1e-5:
			xf.basis = (Basis(axis.normalized(), ang) * xf.basis).orthonormalized()
			state.angular_velocity *= 0.3
			state.transform = xf

func _physics_process(dt: float) -> void:
	# Voxel Archimedes buoyancy: each submerged voxel displaces water. apply_force
	# positions are offsets from the body origin in world space (Godot accounts for
	# the centre of mass internally).
	for v in _voxels:
		var wp := to_global(v)
		var off := wp - global_position
		var wy: float = _water.water_height(Vector2(wp.x, wp.z))
		var sub := clampf(0.5 + (wy - wp.y) / (2.0 * submersion_radius), 0.0, 1.0)
		if sub > 0.0:
			apply_force(Vector3.UP * water_density * _gravity * _vox_volume * sub, off)
			var pv := linear_velocity + angular_velocity.cross(off)
			apply_force(-pv * sub * voxel_drag, off)

	var c := Vector2(global_position.x, global_position.z)

	# keep the boat inside the real pond shape
	if _water.has_method("water_amount"):
		var wa: float = _water.water_amount(c)
		if wa < edge_water:
			var toward := pond_center - c
			if toward.length() > 0.001:
				toward = toward.normalized()
				apply_central_force(Vector3(toward.x, 0.0, toward.y) * edge_push)

	# ripples from the boat's actual motion (displacing water)
	var hv := Vector2(linear_velocity.x, linear_velocity.z)
	var speed := hv.length()
	_ripple_accum += speed * dt
	if speed > ripple_speed_min and _ripple_accum > ripple_spacing and _water.has_method("add_ripple"):
		_ripple_accum = 0.0
		_water.add_ripple(c, clampf(speed * ripple_gain, 0.2, 2.5), 0.5)
	if _water.has_method("set_boat"):
		_water.set_boat(c, collar_radius)
	# carve the water out of the hull using the WaterCutoutTrapezoid child nodes
	if enable_cutout and _water.has_method("set_hull_cutouts") and not _cutouts.is_empty():
		var segs: Array = []
		for cut in _cutouts:
			segs.append(cut.get_segment())
		_water.set_hull_cutouts(segs)

# Click (not drag) shoves the boat. Drag still orbits the camera.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
			_press_active = true
		elif _press_active:
			_press_active = false
			if event.position.distance_to(_press_pos) <= 6.0:
				_try_push(event.position)
	elif event is InputEventMouseMotion and _press_active:
		if event.position.distance_to(_press_pos) > 6.0:
			_press_active = false

func _try_push(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-4:
		return
	var wy: float = (_water as Node3D).global_position.y
	var t := (wy - from.y) / dir.y
	if t < 0.0:
		return
	var hit := from + dir * t
	var hit_xz := Vector2(hit.x, hit.z)
	var boat_xz := Vector2(global_position.x, global_position.z)
	if hit_xz.distance_to(boat_xz) > click_radius:
		return
	var push := boat_xz - hit_xz
	if push.length() < 0.15:
		push = Vector2(dir.x, dir.z)
	push = push.normalized()
	apply_central_impulse(Vector3(push.x, 0.0, push.y) * push_impulse)
	apply_torque_impulse(Vector3(push.y, 0.0, -push.x) * push_rock)
	if _water.has_method("add_ripple"):
		_water.add_ripple(boat_xz, 2.2, 1.0)
	get_tree().call_group("fish_school", "scatter_from", boat_xz)   # startle the fish
