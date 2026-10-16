class_name GrassField
extends Node3D
## Chunked MultiMesh grass over the mow grid. Near field: blade tufts with
## per-instance height state and colour; far field: cheap impostors.

const TUFTS_PER_M2 := 16.0
const CHUNK_CELLS := 5
# Pinned by brief: grass stands 12 in (0.3048 m) at game start, cut to
# 2.5 in (0.0635 m). The tuft asset is authored so its tallest blade is
# 0.3048 m at instance scale 1.0; the spawn scale band stays <= 1.0.
const GRASS_TALL_M := 0.3048
const GRASS_CUT_M := 0.0635
const CUT_SCALE := GRASS_CUT_M / GRASS_TALL_M

var grid: MowGrid
var tuft_mesh: Mesh
var impostor_mesh: Mesh
var heightmap: TerrainHeight

var chunks := {}  # Vector2i chunk -> MultiMeshInstance3D
var cell_instances := {}  # Vector2i cell -> Array of [chunk_key, instance_index]


func setup(p_grid: MowGrid, p_tuft: Mesh, p_impostor: Mesh, p_hm: TerrainHeight) -> void:
	grid = p_grid
	tuft_mesh = p_tuft
	impostor_mesh = p_impostor
	heightmap = p_hm
	grid.cell_cut.connect(_on_cell_cut)
	_build_chunks()
	_build_impostors()


func _rng_for(key: Vector2i) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = (key.x * 73856093) ^ (key.y * 19349663) ^ 0xBD
	return r


func _chunk_build(c: Vector2i) -> void:
	var rng := _rng_for(c)
	var per_cell := int(round(TUFTS_PER_M2 * grid.CELL * grid.CELL))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for cy in range(c.y * CHUNK_CELLS, mini((c.y + 1) * CHUNK_CELLS, grid.rows)):
		for cx in range(c.x * CHUNK_CELLS, mini((c.x + 1) * CHUNK_CELLS, grid.cols)):
			if grid.is_blocked(cx, cy):
				continue
			var key := Vector2i(cx, cy)
			if not cell_instances.has(key):
				cell_instances[key] = []
			for i in per_cell:
				var lx := (cx + rng.randf()) * grid.CELL
				var lz := (cy + rng.randf()) * grid.CELL
				var wx := MowGrid.ORIGIN.x + lx
				var wz := MowGrid.ORIGIN.z + lz
				var y := heightmap.height_at(wx, wz)
				var s := 0.88 + rng.randf() * 0.12
				var rot := rng.randf_range(0.0, TAU)
				var xf := Transform3D(
					Basis(Vector3.UP, rot).scaled(Vector3(s, 1.0, s)), Vector3(wx, y, wz)
				)
				var idx := transforms.size()
				transforms.append(xf)
				colors.append(
					Color(
						0.75 + rng.randf() * 0.25,
						0.85 + rng.randf() * 0.15,
						0.6 + rng.randf() * 0.2
					)
				)
				cell_instances[key].append([c, idx])
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visibility_range_end = 55.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(mmi)
	chunks[c] = mmi


func _build_chunks() -> void:
	var ccols := int(ceil(float(grid.cols) / float(CHUNK_CELLS)))
	var crows := int(ceil(float(grid.rows) / float(CHUNK_CELLS)))
	for cy in crows:
		for cx in ccols:
			_chunk_build(Vector2i(cx, cy))


func _on_cell_cut(cx: int, cy: int) -> void:
	var key := Vector2i(cx, cy)
	if not cell_instances.has(key):
		return
	var band := int(floor(float(cx) / 3.0)) % 2
	var cut_col := Color(0.95, 1.0, 0.8) if band == 0 else Color(0.8, 0.9, 0.68)
	for pair in cell_instances[key]:
		var mmi: MultiMeshInstance3D = chunks[pair[0]]
		var mm: MultiMesh = mmi.multimesh
		var idx: int = pair[1]
		var xf := mm.get_instance_transform(idx)
		var b := xf.basis
		b = b.scaled(Vector3(1.0, CUT_SCALE, 1.0))
		mm.set_instance_transform(idx, Transform3D(b, xf.origin))
		mm.set_instance_color(idx, cut_col)


func _build_impostors() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = impostor_mesh
	var pts: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	var step := 1.6
	var z := MowGrid.ORIGIN.z
	while z < MowGrid.ORIGIN.z + MowGrid.LAWN_H:
		var x := MowGrid.ORIGIN.x
		while x < MowGrid.ORIGIN.x + MowGrid.LAWN_W:
			var wx := x + rng.randf_range(-0.4, 0.4)
			var wz := z + rng.randf_range(-0.4, 0.4)
			if not (absf(wx) < 15.5 and absf(wz) < 7.5):
				var c := grid.cell_of(Vector3(wx, 0, wz))
				if not grid.is_blocked(c.x, c.y):
					var y := heightmap.height_at(wx, wz)
					var rot := rng.randf_range(0.0, TAU)
					pts.append(Transform3D(Basis(Vector3.UP, rot), Vector3(wx, y, wz)))
			x += step
		z += step
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, pts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
