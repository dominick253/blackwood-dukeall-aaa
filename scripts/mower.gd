class_name Mower
extends RigidBody3D
## Physics-driven sit-on mower: four raycast wheel contacts, spring-damper
## suspension, steered-slip lateral forces, rear-wheel drive.
##
## Pinned brief values: cruise 6 km/h, fast 12 km/h, 0 to 6 km/h in 2.5 s
## (fast 1.2 s), turning radius 2.2 m at cruise, deck working width 0.6 m.

const CRUISE_SPEED := 1.6667
const FAST_SPEED := 3.3333
const ACCEL_CRUISE := 0.75  # 0 to 6 km/h in ~2.5 s incl drag
const ACCEL_FAST := 12.0 / 3.6 / 1.2
const WHEELBASE := 1.2
const TURN_RADIUS := 2.2
const STEER_MAX := atan2(WHEELBASE, TURN_RADIUS)
const DECK_HALF_W := 0.3
const DECK_HALF_L := 0.375
const SUSP_REST := 0.45
const SUSP_K := 8100.0
const SUSP_C := 1150.0
const SUSP_MAX := 0.2
const MU := 1.25
const CORNERING := 26000.0
const ROLL_RESIST := 9.0
const BRAKE_DECEL := 2.6

var grid: MowGrid
var view_yaw := 0.0
var view_pitch := -0.12  # mowing sightline: hood and front tyres in frame
var steer_angle := 0.0
var wheel_spin := 0.0
var headlights_on := true
var drink_requested := false
var puff_requested := false
var ash_requested := false
var cam_mode := 0  # 0 = first person (hood + front tyres in view), 1 = chase

# Harness/virtual input override; null means use real input.
var virtual: Dictionary = {}

var _wheels: Array = []
var _cam_pivot: Node3D
var _fp_cam: Camera3D
var _tp_cam: Camera3D
var _vm: Node3D
var _lights: Array = []
var _tyre_nodes := {}
var _prev_compression := {}
var _last_up_rate := 0.0


func _ready() -> void:
	mass = 165.0
	angular_damp = 0.6
	center_of_mass_mode = 1  # EXPLICIT
	center_of_mass = Vector3(0.0, -0.15, 0.0)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.8
	_wheels = [
		{"tag": "fl", "x": -0.27, "z": -0.60, "r": 0.155, "steer": true, "drive": false},
		{"tag": "fr", "x": 0.27, "z": -0.60, "r": 0.155, "steer": true, "drive": false},
		{"tag": "rl", "x": -0.33, "z": 0.60, "r": 0.24, "steer": false, "drive": true},
		{"tag": "rr", "x": 0.33, "z": 0.60, "r": 0.24, "steer": false, "drive": true},
	]
	for w in _wheels:
		_prev_compression[w["tag"]] = 0.0


func attach_visuals(tyres: Dictionary, cam_pivot: Node3D, lights: Array) -> void:
	_tyre_nodes = tyres
	_cam_pivot = cam_pivot
	_lights = lights
	if cam_pivot != null:
		for c in cam_pivot.get_children():
			if c is Camera3D:
				_fp_cam = c as Camera3D


func set_tp_cam(c: Camera3D) -> void:
	_tp_cam = c


func set_viewmodels(v: Node3D) -> void:
	_vm = v


func toggle_camera() -> void:
	cam_mode = 1 - cam_mode
	# Godot 4.7: Camera3D has no `enabled`; the active camera is `current`.
	if _tp_cam != null:
		_tp_cam.current = cam_mode == 1
	if _fp_cam != null:
		_fp_cam.current = cam_mode == 0
	if _vm != null:
		_vm.visible = cam_mode == 0


func set_virtual_input(throttle: float, steer: float, brake: bool, fast: bool) -> void:
	virtual = {"throttle": throttle, "steer": steer, "brake": brake, "fast": fast}


func _poll_input() -> Dictionary:
	if not virtual.is_empty():
		return virtual
	var throttle := 0.0
	if Input.is_action_pressed("throttle_forward"):
		throttle += 1.0
	if Input.is_action_pressed("throttle_back"):
		throttle -= 1.0
	var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	return {
		"throttle": throttle,
		"steer": steer,
		"brake": Input.is_action_pressed("brake"),
		"fast": Input.is_action_pressed("fast_mode"),
	}


func _integrate_input(delta: float, inp: Dictionary) -> void:
	var target_steer := clampf(float(inp["steer"]), -1.0, 1.0) * STEER_MAX
	var slew := 2.2 * delta
	steer_angle = clampf(steer_angle, target_steer - slew, target_steer + slew)


func _physics_process(delta: float) -> void:
	var inp := _poll_input()
	_integrate_input(delta, inp)
	var throttle := clampf(float(inp["throttle"]), -1.0, 1.0)
	var braking := bool(inp["brake"])
	var fast := bool(inp["fast"])
	var cap := FAST_SPEED if fast else CRUISE_SPEED
	var a_cap := ACCEL_FAST if fast else ACCEL_CRUISE

	var fwd := -global_transform.basis.z
	var vel := linear_velocity
	var fwd_speed := vel.dot(fwd)

	var total_up := 0.0
	for w in _wheels:
		var mount_global := to_global(Vector3(float(w["x"]), 0.0, float(w["z"])))
		var space := get_world_3d().direct_space_state
		var from := mount_global
		var to := mount_global + Vector3(0, -(SUSP_REST + 0.15), 0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var comp := 0.0
		if hit.is_empty():
			continue
		var hpos: Vector3 = hit["position"]
		var dist := from.distance_to(hpos)
		comp = clampf(SUSP_REST - dist, 0.0, SUSP_MAX)
		var r := hpos - global_position
		var v_mount := vel + angular_velocity.cross(r)
		var rel_rate := clampf(-v_mount.y, -3.0, 3.0)
		_last_up_rate = rel_rate
		_prev_compression[w["tag"]] = comp
		var fz: float = SUSP_K * comp + SUSP_C * rel_rate
		fz = clampf(fz, 0.0, 3500.0)
		total_up += fz
		var contact: Vector3 = hpos
		# Suspension force straight up through the spring.
		apply_force(Vector3(0, fz, 0), contact - global_position)
		# Wheel frame: steered heading for front wheels.
		var wheel_yaw := global_rotation.y + (steer_angle if bool(w["steer"]) else 0.0)
		var wf := Vector3(-sin(wheel_yaw), 0, -cos(wheel_yaw))
		var wr := Vector3(cos(wheel_yaw), 0, -sin(wheel_yaw))
		var v_contact := vel + angular_velocity.cross(contact - global_position)
		var v_fwd := v_contact.dot(wf)
		var v_lat := v_contact.dot(wr)
		# Lateral force opposes slip, measured against the STEERED heading.
		var slip := atan2(v_lat, maxf(absf(v_fwd), 0.4))
		var flat := -CORNERING * slip
		flat = clampf(flat, -MU * fz, MU * fz)
		apply_force(wr * flat, contact - global_position)
		# Drive and brake along the wheel forward axis.
		if bool(w["drive"]):
			var drive := 0.0
			if absf(fwd_speed) < cap or throttle == 0.0:
				drive = throttle * mass * a_cap
			if absf(fwd_speed) >= cap and throttle > 0.0:
				drive = 0.0
			drive /= float(_drive_wheel_count())
			apply_force(wf * drive, contact - global_position)
		if braking:
			var bf := -signf(v_fwd) * mass * BRAKE_DECEL / float(_drive_wheel_count() + 2)
			if absf(v_fwd) < 0.3:
				bf = 0.0
			apply_force(wf * bf, contact - global_position)
		# Rolling resistance signed by motion.
		apply_force(wf * (-ROLL_RESIST * v_fwd / 4.0), contact - global_position)
		w["spin"] = v_fwd / float(w["r"])

	if total_up < 100.0 and linear_velocity.y < -8.0:
		# Falling out of the world guard.
		var h := _ground_height()
		global_position.y = h + 1.0
		linear_velocity = Vector3.ZERO

	_update_camera_look()
	_update_tyre_visuals()
	_mow_pass()
	GameState.mower_velocity = vel
	GameState.mower_position = global_position


func _drive_wheel_count() -> int:
	return 2


func _ground_height() -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 2, 0)
	var to := global_position + Vector3(0, -5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var hp: Vector3 = hit.get("position", Vector3(0, 0, 0))
	return hp.y


func _mow_pass() -> void:
	if grid == null:
		return
	var deck := to_global(Vector3(0, 0.0, -0.05))
	grid.cut_quad(deck, DECK_HALF_W, DECK_HALF_L, global_rotation.y)


func _update_camera_look() -> void:
	if _cam_pivot == null:
		return
	_cam_pivot.rotation.x = clampf(view_pitch, -1.0, 0.7)


func _update_tyre_visuals() -> void:
	for w in _wheels:
		var tag: String = w["tag"]
		if not _tyre_nodes.has(tag):
			continue
		var n: Node3D = _tyre_nodes[tag]
		var yaw := steer_angle if w["steer"] else 0.0
		var spin := float(w.get("spin", wheel_spin))
		n.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, spin)


func get_final_linear_velocity_hint() -> float:
	return _last_up_rate


func toggle_headlights() -> void:
	headlights_on = not headlights_on
	GameState.headlights_on = headlights_on
	for l in _lights:
		l.visible = headlights_on


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				toggle_headlights()
			KEY_E:
				drink_requested = true
			KEY_Q:
				puff_requested = true
			KEY_X:
				ash_requested = true
			KEY_C:
				toggle_camera()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		view_yaw -= event.relative.x * 0.0025
		view_pitch = clampf(view_pitch - event.relative.y * 0.0025, -1.0, 0.7)
		if _cam_pivot != null:
			_cam_pivot.rotation.y = fmod(view_yaw, TAU)


func _process(delta: float) -> void:
	if cam_mode == 1 and _tp_cam != null:
		# Chase rig: high three-quarter rear view, smoothed follow. Basis is
		# built explicitly (right/up/forward) instead of look_at: the engine
		# version's look_at oriented 180 deg off in the harness probe.
		var target := to_global(Vector3(1.2, 2.35, 5.0))
		var f := 1.0 - exp(-5.0 * delta)
		var pos := _tp_cam.global_transform.origin.lerp(target, f)
		var to_t := global_position + Vector3(0.0, 1.0, 0.0) - pos
		if to_t.length_squared() > 1e-4:
			var fr := to_t.normalized()
			var rr := fr.cross(Vector3.UP)
			if rr.length_squared() < 1e-6:
				rr = Vector3.RIGHT
			else:
				rr = rr.normalized()
			var uu := rr.cross(fr)
			_tp_cam.global_transform = Transform3D(Basis(rr, uu, -fr), pos)
