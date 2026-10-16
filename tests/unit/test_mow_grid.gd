extends GutTest

var grid: MowGrid


func before_each() -> void:
	grid = MowGrid.new()
	add_child(grid)


func test_cut_cell_marks_and_counts() -> void:
	assert_false(grid.is_cut(10, 10), "fresh cell uncut")
	assert_true(grid.cut_cell(10, 10), "first cut succeeds")
	assert_true(grid.is_cut(10, 10), "cell reads cut")
	assert_false(grid.cut_cell(10, 10), "second cut is a no-op")
	assert_eq(grid.cut_count, 1)


func test_percent_rises_with_cuts() -> void:
	var p0 := grid.percent()
	for i in 50:
		grid.cut_cell(5 + i, 5)
	assert_gt(grid.percent(), p0, "mow percentage rises")


func test_hall_footprint_is_blocked() -> void:
	var c := grid.cell_of(Vector3(0, 0, 0))
	assert_true(grid.is_blocked(c.x, c.y), "under-hall cells are not mowable")
	assert_false(grid.cut_cell(c.x, c.y), "cannot cut blocked cell")


func test_mowable_area_meets_brief() -> void:
	var area := float(grid.mowable_count) * grid.CELL * grid.CELL
	assert_gt(area, 2499.0, "at least 2500 sq m of mowable turf")


func test_cut_quad_cuts_deck_rectangle() -> void:
	var center := Vector3(20.0, 0.0, 20.0)
	var n := grid.cut_quad(center, 0.3, 0.375, 0.0)
	assert_gt(n, 0, "deck footprint cuts cells")
	var cc := grid.cell_of(center)
	assert_true(grid.is_cut(cc.x, cc.y), "cell under deck centre is cut")
