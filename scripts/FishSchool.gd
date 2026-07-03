extends Node3D
## A school of animated 3D fish as real physics bodies. Each fish is a RigidBody3D
## with a collision sphere (so fish bump each other and the boat) and buoyancy
## (an upward force that cancels gravity and holds it at its swim depth — neutral
## buoyancy). Boids-style steering forces make them shoal, occasionally regroup
## around a drifting bait point, stay in the pond, avoid the boat, and scatter
## (physical impulse) when the boat is shoved. The swim animation loops.

const FISH_SCENE := preload("res://assets/models/fish/alien/source/Alien fish animated.fbx")

@export var count := 12
@export var swim_depth := 0.3           ## how far below the waterline the school swims
@export var cruise_speed := 0.7
@export var max_speed := 1.7
@export var fish_scale := 0.28
@export_group("Physics")
@export var fish_mass := 0.5
@export var body_radius := 0.22         ## collision sphere radius
@export var steer_accel := 3.5          ## boid steering force strength
@export var depth_k := 26.0             ## buoyancy depth spring
@export var depth_damp := 5.0
@export var cruise_thrust := 1.3         ## steady forward drive so fish never stop swimming
@export_group("Boids (even spread)")
@export var neighbor_radius := 3.0
@export var separation_radius := 1.5     ## medium-range repulsion → fish spread out evenly
@export var cohesion_w := 0.15           ## weak (don't clump into one ball)
@export var alignment_w := 0.45
@export var separation_w := 1.5
@export var wander_w := 0.55
@export var center_w := 0.25             ## gentle pull to the pond middle so they fill it
@export_group("Environment")
@export var boat_avoid_radius := 1.9
@export var scatter_radius := 3.4
@export var flee_time := 1.6             ## how long a startled fish flees (smooth, decaying)
@export var flee_accel := 6.0
@export var pond_center := Vector2(1.0, -1.1)
@export var pond_radius := 4.0

var _water: Node = null
var _boat: Node3D = null
var _fish: Array = []
var _water_y := 0.1
var _gravity := 9.8

func _ready() -> void:
	add_to_group("fish_school")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	_water = get_node_or_null("../Water")
	_boat = get_node_or_null("../Boat") as Node3D
	if _water != null:
		_water_y = (_water as Node3D).global_position.y
	for i in range(count):
		_spawn(i)

func _spawn(i: int) -> void:
	var body := RigidBody3D.new()
	body.mass = fish_mass
	body.gravity_scale = 1.0                     # gravity is cancelled by buoyancy below
	body.linear_damp = 1.8                        # water drag (stable)
	body.axis_lock_angular_x = true               # don't tumble; the visual is oriented by velocity
	body.axis_lock_angular_y = true
	body.axis_lock_angular_z = true
	body.continuous_cd = true
	body.can_sleep = false            # never sleep: keep responding to forces + keep swimming
	add_child(body)

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = body_radius
	col.shape = sph
	body.add_child(col)

	var pivot := Node3D.new()                     # orients the model toward the swim direction
	body.add_child(pivot)
	var model: Node3D = FISH_SCENE.instantiate()
	pivot.add_child(model)
	var s := fish_scale * randf_range(0.85, 1.2)
	model.scale = Vector3(s, s, s)
	model.rotation = Vector3(0.0, deg_to_rad(180.0), 0.0)   # model +Z -> pivot forward (-Z)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	if ap != null and not ap.get_animation_list().is_empty():
		var an: StringName = ap.get_animation_list()[0]
		var res := ap.get_animation(an)
		if res != null:
			res.loop_mode = Animation.LOOP_LINEAR
		ap.play(an)
		ap.speed_scale = randf_range(0.9, 1.4)

	var p := _random_water_pos()
	var ty := _water_y - swim_depth - randf_range(0.0, 0.12)
	body.global_position = Vector3(p.x, ty, p.y)
	body.linear_velocity = Vector3(cos(randf() * TAU), 0.0, sin(randf() * TAU)) * cruise_speed
	_fish.append({
		"body": body, "pivot": pivot, "target_y": ty, "bob": randf() * TAU,
		"flee_t": 0.0, "flee_dir": Vector2.ZERO,
	})

func _random_water_pos() -> Vector2:
	for _t in range(60):
		var p := pond_center + Vector2(randf_range(-3.5, 3.5), randf_range(-3.5, 3.5))
		if _in_water(p, 0.5):
			return p
	return pond_center

func _in_water(p: Vector2, thresh: float) -> bool:
	if _water == null or not _water.has_method("water_amount"):
		return true
	return _water.water_amount(p) > thresh

func _physics_process(dt: float) -> void:
	var boat_xz := Vector2(9999.0, 9999.0)
	if _boat != null:
		boat_xz = Vector2(_boat.global_position.x, _boat.global_position.z)

	for f in _fish:
		var body: RigidBody3D = f.body
		var gp := body.global_position
		var pos := Vector2(gp.x, gp.z)
		var vel := Vector2(body.linear_velocity.x, body.linear_velocity.z)

		# ── Boids steering ────────────────────────────────────────────────
		var steer := Vector2.ZERO
		var com := Vector2.ZERO
		var vel_sum := Vector2.ZERO
		var sep := Vector2.ZERO
		var n := 0
		for g in _fish:
			if g == f:
				continue
			var gpos := Vector2((g.body as RigidBody3D).global_position.x, (g.body as RigidBody3D).global_position.z)
			var d := gpos - pos
			var dist := d.length()
			if dist < neighbor_radius and dist > 0.001:
				com += gpos
				vel_sum += Vector2((g.body as RigidBody3D).linear_velocity.x, (g.body as RigidBody3D).linear_velocity.z)
				n += 1
				if dist < separation_radius:
					sep -= d / dist * (separation_radius - dist)
		if n > 0:
			com /= float(n)
			vel_sum /= float(n)
			steer += (com - pos).normalized() * cohesion_w
			if vel_sum.length() > 0.001:
				steer += vel_sum.normalized() * alignment_w
			steer += sep * separation_w
		# gentle pull toward the pond middle (stronger the further out) → even spread
		var from_c := pos - pond_center
		if from_c.length() > pond_radius * 0.5:
			steer += (-from_c).normalized() * center_w * (from_c.length() / pond_radius)
		f.bob += dt
		steer += Vector2(cos(f.bob * 1.3 + pos.x), sin(f.bob * 1.1 + pos.y)) * wander_w * 0.4
		var dir: Vector2 = vel.normalized() if vel.length() > 0.01 else Vector2.RIGHT
		if not _in_water(pos + dir * 0.8, 0.3):
			steer += (pond_center - pos).normalized() * 3.5
		var bd: float = pos.distance_to(boat_xz)
		if bd < boat_avoid_radius and bd > 0.001:
			steer += (pos - boat_xz).normalized() * 3.0 * (1.0 - bd / boat_avoid_radius)
		# smooth flee after a scare (decaying force, not an instant jolt)
		if f.flee_t > 0.0:
			steer += f.flee_dir * flee_accel * (f.flee_t / flee_time)
			f.flee_t -= dt

		# ── Apply forces ──────────────────────────────────────────────────
		body.apply_central_force(Vector3(steer.x, 0.0, steer.y) * body.mass * steer_accel)
		# steady forward drive so fish always keep swimming (never stall)
		body.apply_central_force(Vector3(dir.x, 0.0, dir.y) * body.mass * cruise_thrust)
		# buoyancy: cancel gravity + hold the swim depth (neutral buoyancy)
		var fy: float = _gravity + (f.target_y - gp.y) * depth_k - body.linear_velocity.y * depth_damp
		body.apply_central_force(Vector3(0.0, fy * body.mass, 0.0))

		# clamp horizontal speed
		var hv := Vector2(body.linear_velocity.x, body.linear_velocity.z)
		var cap: float = (max_speed if f.flee_t > 0.0 else cruise_speed) * 1.4
		if hv.length() > cap and hv.length() > 0.001:
			hv = hv.normalized() * cap
			body.linear_velocity = Vector3(hv.x, body.linear_velocity.y, hv.y)

		# orient the visual toward travel
		if hv.length() > 0.05:
			(f.pivot as Node3D).look_at(gp + Vector3(hv.x, 0.0, hv.y), Vector3.UP)

## Startle the school away from a world XZ point — a smooth decaying flee (not an
## instant jolt), so nearby fish accelerate away and ease back to cruising.
func scatter_from(center: Vector2) -> void:
	for f in _fish:
		var gp: Vector3 = (f.body as RigidBody3D).global_position
		var away := Vector2(gp.x, gp.z) - center
		var dist := away.length()
		if dist < scatter_radius and dist > 0.001:
			f.flee_dir = away.normalized()
			f.flee_t = flee_time * (1.0 - dist / scatter_radius * 0.5)   # closer = flee harder
