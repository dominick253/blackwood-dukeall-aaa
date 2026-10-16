extends GutTest

var sim: CigarSim


func before_each() -> void:
	sim = CigarSim.new()
	add_child(sim)


func _ticks(n: int, dt: float) -> void:
	for i in n:
		sim._physics_process(dt)


func test_burn_advances_over_time() -> void:
	_ticks(1200, 1.0)
	assert_gt(sim.burn_m, 0.1, "burn line advances")
	assert_lt(sim.burn_m, CigarSim.CIGAR_LEN + 0.001, "burn never exceeds cigar")


func test_full_burn_takes_about_20_minutes() -> void:
	_ticks(1199, 1.0)
	assert_lt(sim.burn_m, CigarSim.CIGAR_LEN, "not finished before 20 min")
	_ticks(2, 1.0)
	assert_gt(sim.burn_m, CigarSim.CIGAR_LEN - 0.002, "finished at about 20 min")


func test_ash_drops_at_max_length() -> void:
	watch_signals(sim)
	_ticks(240, 1.0)
	assert_signal_emitted(sim, "ash_dropped", "ash sheds at 30 mm")
	assert_lt(sim.ash_len, CigarSim.ASH_MAX, "ash resets after drop")


func test_drink_tap_knocks_ash() -> void:
	_ticks(60, 1.0)
	watch_signals(sim)
	sim.drink_tap()
	assert_signal_emitted(sim, "ash_dropped", "tapping the beer shakes ash loose")


func test_puff_flare_decays_in_two_seconds() -> void:
	sim.puff()
	assert_gt(sim.flare, 0.9, "puff flares")
	_ticks(180, 1.0 / 60.0)
	assert_lt(sim.flare, 0.05, "flare decays over about 2 s")


func test_ember_pulse_oscillates() -> void:
	var vals: Array[float] = []
	for i in 400:
		sim._physics_process(0.02)
		vals.append(0.5 + 0.5 * sin(TAU * sim.pulse_phase / sim.pulse_period))
	var lo: float = vals.min()
	var hi: float = vals.max()
	assert_lt(lo, 0.2, "ember pulse reaches low")
	assert_gt(hi, 0.8, "ember pulse reaches high")


func test_body_shortens_as_it_burns() -> void:
	var s := CigarSim.new()
	var body := MeshInstance3D.new()
	body.position = Vector3(0.0, 0.06, 0.0)
	s.body_node = body
	s.add_child(body)
	add_child(s)  # _ready captures the base y
	for i in 600:
		s._physics_process(1.0)
	assert_lt(body.scale.y, 0.4, "wrapper shrinks past 40% by half burn")
	assert_gt(body.position.y, 0.06, "center rises as the burning end eats in")
	assert_lt(body.position.y, 0.06 + 0.045, "mouth end stays put")


func test_flick_drops_full_ash_column() -> void:
	_ticks(200, 1.0)
	watch_signals(sim)
	sim.drop_ash()
	assert_signal_emitted(sim, "ash_dropped", "flick knocks the column off")
	assert_almost_eq(sim.ash_len, 0.0, 1e-9, "ash reset after flick")
