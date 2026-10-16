class_name Slosh
extends Node3D
## Liquid surface as a damped driven pendulum plus a secondary jiggle spring.
## Pinned: primary 2.2 Hz, damping 0.15, clamp 25 degrees; secondary 0.8 Hz,
## damping 0.08.

const F1 := 2.2
const Z1 := 0.15
const CLAMP_DEG := 25.0
const F2 := 0.8
const Z2 := 0.08
const G := 9.81

var theta_x := 0.0  # roll tilt from lateral accel
var theta_z := 0.0  # pitch tilt from fore/aft accel
var vel_x := 0.0
var vel_z := 0.0
var jiggle := 0.0
var jiggle_vel := 0.0
var volume_ratio := 1.0
var surface: MeshInstance3D

var _omega1 := TAU * F1
var _omega2 := TAU * F2
var _prev_v := Vector3.ZERO
var _prev_accel := Vector3.ZERO


func inject_accel(local_accel: Vector3) -> void:
	## Direct forcing used by tests and bumps.
	step(local_accel, get_physics_process_delta_time())


func step(la: Vector3, delta: float) -> void:
	var ell := G / (_omega1 * _omega1)
	var pairs := [[theta_x, vel_x, -la.x / ell], [theta_z, vel_z, -la.z / ell]]
	var out := []
	for p in pairs:
		var th: float = p[0]
		var v: float = p[1]
		var ax: float = p[2]
		var acc := -(_omega1 * _omega1) * th - 2.0 * Z1 * _omega1 * v + ax
		v += acc * delta
		th += v * delta
		th = clampf(th, -deg_to_rad(CLAMP_DEG), deg_to_rad(CLAMP_DEG))
		out.append([th, v])
	theta_x = out[0][0]
	vel_x = out[0][1]
	theta_z = out[1][0]
	vel_z = out[1][1]
	var jerk := (la - _prev_accel).length()
	_prev_accel = la
	if jerk > 1.5:
		jiggle_vel += minf(jerk, 8.0) * 0.012
	var jacc := -(_omega2 * _omega2) * jiggle - 2.0 * Z2 * _omega2 * jiggle_vel
	jiggle_vel += jacc * delta
	jiggle += jiggle_vel * delta
	jiggle = clampf(jiggle, -0.012, 0.012)
	_apply()


func _physics_process(delta: float) -> void:
	var la := _mower_local_accel(delta)
	step(la, delta)


func _mower_local_accel(_delta: float) -> Vector3:
	var rig := get_tree().get_first_node_in_group("mower_rigidbody")
	if not (rig is RigidBody3D):
		return Vector3.ZERO
	var rb := rig as RigidBody3D
	var a := (rb.linear_velocity - _prev_v) / maxf(_delta, 1e-4)
	_prev_v = rb.linear_velocity
	return rb.global_transform.basis.inverse() * a


func _apply() -> void:
	# The liquid surface stays level with world gravity: the pendulum angles
	# are deviations from world-level, so they are applied in world space.
	# When the bottle tips for a drink, the beer counter-rotates and stays
	# horizontal inside the tilted glass.
	global_transform.basis = Basis.from_euler(Vector3(theta_z, 0.0, theta_x))
	if surface != null:
		surface.position.y = jiggle
		surface.scale = Vector3(1.0, maxf(volume_ratio, 0.05), 1.0)


func drain_fraction(frac: float) -> void:
	volume_ratio = maxf(volume_ratio * (1.0 - frac), 0.05)
	jiggle_vel += 0.05
