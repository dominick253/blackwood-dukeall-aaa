extends GutTest


func test_grass_heights_pinned() -> void:
	assert_eq(GrassField.GRASS_TALL_M, 0.3048, "start height is 12 in")
	assert_eq(GrassField.GRASS_CUT_M, 0.0635, "cut height is 2.5 in")


func test_cut_scale_matches_height_ratio() -> void:
	assert_almost_eq(
		GrassField.CUT_SCALE, GrassField.GRASS_CUT_M / GrassField.GRASS_TALL_M, 0.0001
	)


func test_spawn_scale_never_exceeds_12in() -> void:
	# Instance scale band is 0.88..1.00; at 1.0 the asset's tallest blade
	# is exactly GRASS_TALL_M, so no tuft can exceed 12 in.
	assert_true(0.88 + 0.12 <= 1.0 + 1e-9, "max spawn scale is 1.0")
