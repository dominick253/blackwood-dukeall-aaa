extends Node
## Scripted 60-second gameplay pass on real hardware: drives the mower with
## virtual input, captures frames, measures FPS, quits with a PASS marker.

const FRAMES_DIR := "res://evidence/frames"

var mower: Mower
var vm: ViewModels
var dn: DayNight
var t := 0.0
var frames := []
var frame_times: Array[float] = []
var capture_at := {
	1.0: "t01_cruise_start",
	12.0: "t12_fast_turn",
	15.0: "t15_fast_turn_bottle",
	26.0: "t26_bump",
	31.0: "t31_lights_off",
	34.0: "t34_lights_on",
	41.0: "t41_beer_lift",
	44.0: "t44_bottle_inspect",
	46.0: "t46_puff_smoke",
	52.0: "t52_dusk_start",
	59.0: "t59_dusk_end",
	65.0: "t65_third_person",
	76.0: "t76_bottle_toss",
	78.5: "t78_new_bottle",
	82.0: "t82_ash_long",
	83.5: "t83_ash_flicked",
}
var slosh_samples := []
var slow_log: Array = []
var world: Node

var _stat_cold := 0
var _drunk := false
var _stuck := 0.0
var _rev := 0.0
var _puffed := false
var _puffed2 := false
var _cam_tp := false
var _cam_fp := false
var _drinks_done := 0
var _ash_set := false
var _flicked := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAMES_DIR))
	world = get_tree().root.get_node("Main")
	mower = world.get("mower") as Mower
	dn = world.get("day_night") as DayNight
	vm = world.get("view_models") as ViewModels
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if mower != null:
		mower.contact_monitor = true
		mower.max_contacts_reported = 8
		# Start on open south lawn driving north toward the hall.
		var th = world.get("terrain_hm")
		var hy: float = th.call("height_at", -24.0, -16.0) if th != null else 0.0
		mower.global_position = Vector3(-24.0, hy + 0.5, -16.0)
		mower.global_rotation = Vector3(0.0, PI, 0.0)
		mower.linear_velocity = Vector3.ZERO
		mower.angular_velocity = Vector3.ZERO


func _swivel_camera(delta: float) -> void:
	if t < 50.0 or mower == null:
		return
	var pivot := mower.get_node_or_null("cam_pivot") as Node3D
	if pivot == null:
		return
	var d := -mower.global_position
	d.y = 0.0
	if d.length() < 4.0:
		return
	var want := atan2(-d.x, -d.z)
	var rel := wrapf(want - mower.global_rotation.y, -PI, PI)
	pivot.rotation.y = lerp_angle(pivot.rotation.y, rel, minf(1.0, 2.0 * delta))


func _drive_inputs(delta: float) -> void:
	var throttle := 1.0
	var steer := 0.0
	var brake := false
	var fast := false
	if t < 12.0:
		steer = 0.0
	elif t < 22.0:
		fast = true
		steer = -0.4
	elif t < 32.0:
		# Waypoint cruise onto the south lawn (clear of the hall), weaving.
		var wp := Vector3(-24.0, 0.0, 16.0)
		var d1 := wp - mower.global_position
		d1.y = 0.0
		var want1 := atan2(-d1.x, -d1.z)
		var err1 := wrapf(want1 - mower.global_rotation.y, -PI, PI)
		steer = clampf(err1 * 0.8, -1.0, 1.0) + 0.25 * sin(t * 1.5)
		fast = d1.length() > 10.0
	elif t < 44.0:
		var wp2 := Vector3(-8.0, 0.0, 20.0)
		var d2 := wp2 - mower.global_position
		d2.y = 0.0
		var want2 := atan2(-d2.x, -d2.z)
		var err2 := wrapf(want2 - mower.global_rotation.y, -PI, PI)
		steer = clampf(err2 * 0.8, -1.0, 1.0) + 0.2 * sin(t * 1.5)
	else:
		# Park ~30 m south of the hall, then hold facing it for dusk frames.
		var d := Vector3(4.0, 0.0, 36.0) - mower.global_position
		d.y = 0.0
		if d.length() > 8.0:
			var want := atan2(-d.x, -d.z)
			var err := wrapf(want - mower.global_rotation.y, -PI, PI)
			steer = clampf(err * 0.9, -1.0, 1.0)
			fast = d.length() > 12.0
			if mower.linear_velocity.length() < 0.4 and throttle > 0.0:
				_stuck += delta
			else:
				_stuck = 0.0
			if _stuck > 1.2:
				_rev = 2.0
				_stuck = 0.0
			if _rev > 0.0:
				_rev -= delta
				throttle = -0.6
				steer = clampf(-err * 0.6, -1.0, 1.0)
		else:
			# Parked: hold position; the camera swivels to face the hall.
			throttle = 0.0
			steer = 0.0
			brake = true
	mower.set_virtual_input(throttle, steer, brake, fast)


func _process(delta: float) -> void:
	t += delta
	GameState.day_time = t
	_swivel_camera(delta)
	if _stat_cold > 0:
		# Frames around a GPU readback: excluded from FPS stats (harness cost).
		_stat_cold -= 1
	else:
		frame_times.append(delta)
	slow_log.append([t, delta])
	_drive_inputs(delta)
	if dn != null:
		if t >= 50.0 and t < 58.0:
			dn.set_time(600.0)
		elif t >= 58.0 and t < 68.0:
			dn.set_time(895.0)
		elif t >= 68.0:
			# Afternoon light for the bottle-toss and ash-flick set pieces.
			dn.set_time(240.0)
	for stamp in capture_at.keys():
		if t >= stamp and not capture_at[stamp] in frames:
			_capture(capture_at[stamp])
	if int(t) != int(t - delta):
		_sample_slosh()
		if mower != null and int(t) % 5 == 0:
			var cols := ""
			for c in mower.get_colliding_bodies():
				cols += String(c.name) + " "
			print(
				(
					"TELEM t=%.0f pos=%s vel=%s yaw=%.2f steer=%.2f contacts=%s"
					% [
						t,
						mower.global_position,
						mower.linear_velocity,
						mower.global_rotation.y,
						mower.steer_angle,
						cols
					]
				)
			)
	if mower != null:
		# Time-jump choreography: light/dusk set pieces need their real light.
		if absf(t - 30.0) < delta and dn != null:
			dn.time = 700.0  # sun ~ -1.3 deg: headlights must carry the scene
		if absf(t - 51.0) < delta and dn != null:
			dn.time = 870.0  # sun below horizon: true dusk, rising mist
		if absf(t - 31.0) < delta:
			mower.toggle_headlights()
		if absf(t - 34.0) < delta:
			mower.toggle_headlights()
	if vm != null:
		vm.inspect = 1.0 if (t >= 12.0 and t <= 18.0) or (t >= 41.0 and t <= 47.0) else 0.0
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			# Telephoto director lens for the two bottle inspect captures.
			cam.fov = 32.0 if (t >= 14.6 and t <= 15.4) or (t >= 43.6 and t <= 44.4) else 75.0
		if absf(t - 40.0) < delta and not _drunk:
			_drunk = true
			vm.do_drink()
		if absf(t - 45.0) < delta and not _puffed:
			_puffed = true
			vm.do_puff()
		if absf(t - 55.0) < delta and not _puffed2:
			_puffed2 = true
			vm.do_puff()
		if absf(t - 61.0) < delta and not _cam_tp and mower != null:
			_cam_tp = true
			mower.toggle_camera()  # -> third-person chase
		if absf(t - 67.5) < delta and not _cam_fp and mower != null:
			_cam_fp = true
			mower.toggle_camera()  # -> back to first person
		if t >= 70.0 and _drinks_done < 8 and fmod(t - 70.0, 0.7) < delta:
			# Drain the bottle to empty: each sip is a visible 12 % slug;
			# the eighth triggers the chuck-and-replace set piece.
			_drinks_done += 1
			vm.do_drink()
		if t >= 81.0 and not _ash_set and vm.cigar_sim != null:
			_ash_set = true
			vm.cigar_sim.ash_len = 0.022  # long ash column, awaiting flick
		if absf(t - 83.0) < delta and not _flicked:
			_flicked = true
			vm.do_flick()
	if OS.get_environment("BDQ_DBG") != "" and t >= 44.0 and t < 44.0 + delta and vm != null:
		var camd := get_viewport().get_camera_3d()
		print(
			"INSPECT dbg=",
			vm.inspect,
			" bpos=",
			vm.bottle_root.global_position,
			" cpos=",
			camd.global_position,
			" cfov=",
			camd.fov,
			" rel=",
			camd.global_position - vm.bottle_root.global_position
		)
		print(
			"INSPECT2 local=",
			vm.bottle_root.transform,
			" parent=",
			vm.bottle_root.get_parent(),
			" parentglobal=",
			vm.bottle_root.get_parent().global_transform
		)
		if vm.cigar_sim != null and vm.cigar_sim.smoke != null:
			var sm := vm.cigar_sim.smoke
			print(
				"SMOKE emitting=",
				sm.emitting,
				" amount=",
				sm.amount,
				" life=",
				sm.lifetime,
				" pos=",
				sm.global_position,
				" parent=",
				sm.get_parent().name
			)
		else:
			print("SMOKE missing cigar_sim=", vm.cigar_sim != null)
	if t >= 85.0:
		_finish()


func _sample_slosh() -> void:
	if vm != null and vm.slosh != null:
		slosh_samples.append([t, vm.slosh.theta_x, vm.slosh.theta_z])


func _capture(tag: String) -> void:
	frames.append(tag)
	_stat_cold = 3
	var img := get_viewport().get_texture().get_image()
	if img == null or img.get_width() == 0:
		return
	var path := FRAMES_DIR + "/" + tag + ".png"
	img.save_png(path)
	print("FRAME SAVED ", path)


func _finish() -> void:
	var n := frame_times.size()
	var total := 0.0
	for d in frame_times:
		total += d
	var fps_avg := float(n) / total
	var sorted_deltas := slow_log.duplicate()
	sorted_deltas.sort_custom(func(a, b): return a[1] > b[1])
	var worst := ""
	var shown := 0
	for e in sorted_deltas:
		if shown >= 40:
			break
		worst += "t=%.1f:%.0fms " % [e[0], e[1] * 1000.0]
		shown += 1
	print("WORST " + worst)
	var sorted := frame_times.duplicate()
	sorted.sort()
	var p99: float = sorted[int(0.99 * (n - 1))]
	var fps_1pct := 1.0 / p99
	var grid: MowGrid = world.get("grid")
	var mow_pct := grid.percent()
	print("SLOSH_SAMPLES ", JSON.stringify(slosh_samples))
	print("MOW_PCT %.2f" % mow_pct)
	print(
		(
			"HARNESS frames=%d fps_avg=%.2f fps_1pct_low=%.2f captures=%d"
			% [n, fps_avg, fps_1pct, frames.size()]
		)
	)
	if fps_avg >= 60.0 and fps_1pct >= 45.0 and frames.size() >= 10:
		print("HARNESS PASS")
	else:
		print("HARNESS FAIL")
	get_tree().quit()
