extends GutTest

var slosh: Slosh


func before_each() -> void:
	slosh = Slosh.new()
	add_child(slosh)


func test_lateral_accel_tilts_surface() -> void:
	for i in 40:
		slosh.step(Vector3(3.0, 0.0, 0.0), 1.0 / 120.0)
	assert_gt(absf(slosh.theta_x), 0.15, "slosh angle builds under lateral accel")


func test_tilt_respects_25_degree_clamp() -> void:
	for i in 240:
		slosh.step(Vector3(20.0, 20.0, 0.0), 1.0 / 120.0)
	var limit := deg_to_rad(25.0) + 0.01
	assert_lt(absf(slosh.theta_x), limit, "primary tilt clamped to 25 deg")
	assert_lt(absf(slosh.theta_z), limit, "primary tilt clamped to 25 deg")


func test_surface_settles_after_disturbance() -> void:
	for i in 30:
		slosh.step(Vector3(4.0, 0.0, 0.0), 1.0 / 120.0)
	for i in 480:
		slosh.step(Vector3.ZERO, 1.0 / 120.0)
	assert_lt(absf(slosh.theta_x), 0.06, "damped pendulum settles")


func test_bump_rings_secondary_spring() -> void:
	slosh.step(Vector3(0.0, 0.0, 0.0), 1.0 / 120.0)
	slosh.step(Vector3(8.0, 0.0, 0.0), 1.0 / 120.0)
	var rang := false
	for i in 240:
		slosh.step(Vector3.ZERO, 1.0 / 120.0)
		if absf(slosh.jiggle) > 0.0005:
			rang = true
	assert_true(rang, "secondary jiggle rings after a jerk")


func test_drain_reduces_volume() -> void:
	var v0 := slosh.volume_ratio
	slosh.drain_fraction(0.1)
	assert_lt(slosh.volume_ratio, v0, "drink drains 10 percent")
