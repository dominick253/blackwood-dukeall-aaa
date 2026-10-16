extends GutTest

var vm: ViewModels


func before_each() -> void:
	vm = ViewModels.new()
	add_child(vm)
	vm.slosh = Slosh.new()
	vm.slosh.volume_ratio = 1.0


func test_each_drink_takes_visible_slug() -> void:
	for i in 4:
		vm.do_drink()
	assert_almost_eq(vm.slosh.volume_ratio, 0.52, 0.001, "4 x 12 percent slugs")


func test_eighth_drink_empties_bottle() -> void:
	for i in 8:
		vm.do_drink()
	assert_true(vm.slosh.volume_ratio <= 0.045, "bottle depleted after 8 drinks")


func test_toss_engages_chuck_state() -> void:
	vm.do_empty_toss()
	assert_gt(vm._toss, 0.0, "chuck animation armed")
	vm.do_drink()
	assert_almost_eq(vm.slosh.volume_ratio, 1.0, 0.001, "no drinking mid-toss")


func test_camera_toggle_flips_mode() -> void:
	var m := Mower.new()
	add_child(m)
	assert_eq(m.cam_mode, 0, "starts first person")
	m.toggle_camera()
	assert_eq(m.cam_mode, 1, "C switches to chase cam")
	m.toggle_camera()
	assert_eq(m.cam_mode, 0, "C returns to first person")
