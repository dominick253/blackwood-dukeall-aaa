extends GutTest

var world_root: Node3D
var mower: Mower
var grid: MowGrid


func before_each() -> void:
	world_root = Node3D.new()
	add_child(world_root)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	var cs := CollisionShape3D.new()
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	world_root.add_child(body)
	grid = MowGrid.new()
	world_root.add_child(grid)
	mower = Mower.new()
	mower.grid = grid
	mower.collision_layer = 1
	mower.collision_mask = 1
	mower.add_to_group("mower_rigidbody")
	var mcs := CollisionShape3D.new()
	var mbs := BoxShape3D.new()
	mbs.size = Vector3(0.75, 0.5, 1.7)
	mcs.position = Vector3(0, 0.5, 0)
	mcs.shape = mbs
	mower.add_child(mcs)
	world_root.add_child(mower)
	mower.global_position = Vector3(20.0, 0.5, 20.0)


func after_each() -> void:
	world_root.queue_free()
	await get_tree().physics_frame


func _run(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func test_cruise_speed_plateau() -> void:
	mower.set_virtual_input(1.0, 0.0, false, false)
	await _run(720)
	var v := mower.linear_velocity.length()
	assert_between(v, 1.45, 1.9, "cruise settles near 6 km/h")


func test_fast_mode_plateau() -> void:
	mower.set_virtual_input(1.0, 0.0, false, true)
	await _run(720)
	var v := mower.linear_velocity.length()
	assert_between(v, 2.9, 3.7, "fast mode settles near 12 km/h")


func test_acceleration_reaches_cruise_in_about_25s() -> void:
	mower.set_virtual_input(1.0, 0.0, false, false)
	var reached := -1.0
	for i in 600:
		await get_tree().physics_frame
		if mower.linear_velocity.length() >= 1.6:
			reached = i / 120.0
			break
	assert_gt(reached, 0.0, "reaches cruise speed")
	assert_between(reached, 1.8, 4.0, "0 to 6 km/h in roughly 2.5 s")


func test_full_steer_turns_with_plausible_radius() -> void:
	mower.set_virtual_input(1.0, 1.0, false, false)
	await _run(480)
	var v := mower.linear_velocity.length()
	var yaw_rate := absf(mower.angular_velocity.y)
	assert_gt(yaw_rate, 0.2, "mower actually turns")
	var radius := v / maxf(yaw_rate, 1e-4)
	assert_between(radius, 1.5, 3.2, "turning radius near pinned 2.2 m")


func test_brake_stops_the_mower() -> void:
	mower.set_virtual_input(1.0, 0.0, false, false)
	await _run(360)
	mower.set_virtual_input(0.0, 0.0, true, false)
	await _run(360)
	assert_lt(mower.linear_velocity.length(), 0.2, "brake brings it to rest")


func test_deck_mows_cells_while_driving() -> void:
	var before := grid.cut_count
	mower.set_virtual_input(1.0, 0.0, false, false)
	await _run(600)
	assert_gt(grid.cut_count, before, "driving under the deck mows cells")
	assert_gt(grid.percent(), 0.0, "mow percentage rises")


func test_headlight_toggle_flips_visibility() -> void:
	var a := SpotLight3D.new()
	var b := SpotLight3D.new()
	world_root.add_child(a)
	world_root.add_child(b)
	mower.attach_visuals({}, null, [a, b])
	assert_true(a.visible and b.visible, "lights start on")
	mower.toggle_headlights()
	assert_false(a.visible or b.visible, "R turns both off")
	mower.toggle_headlights()
	assert_true(a.visible and b.visible, "R turns both back on")
