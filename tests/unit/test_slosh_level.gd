extends GutTest


func test_liquid_stays_world_level_when_bottle_tilts() -> void:
	var parent := Node3D.new()
	parent.rotation.x = 0.6  # bottle tipped back for a drink
	add_child(parent)
	var s := Slosh.new()
	parent.add_child(s)
	s.step(Vector3.ZERO, 0.016)
	var e := s.global_basis.get_euler()
	assert_true(e.length() < 0.05, "surface near-horizontal despite tilt")


func test_pendulum_angles_are_world_deviations() -> void:
	var parent := Node3D.new()
	parent.rotation.z = 0.4
	add_child(parent)
	var s := Slosh.new()
	parent.add_child(s)
	s.inject_accel(Vector3(6.0, 0.0, 0.0))
	var expected := Basis.from_euler(Vector3(s.theta_z, 0.0, s.theta_x))
	assert_true(s.global_basis.is_equal_approx(expected), "tilt expressed in world space")
