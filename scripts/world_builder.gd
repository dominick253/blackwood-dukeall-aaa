extends Node3D
## Assembles the estate: terrain, hall, fence/hedge/trees, mower with camera
## and viewmodels, grass field, environment and day/night.

var rng := RandomNumberGenerator.new()
var terrain_hm := TerrainHeight.new()
var grid: MowGrid
var mower: Mower
var day_night: DayNight
var grass: GrassField
var view_models: ViewModels


func _ready() -> void:
	rng.seed = 0xBDDC
	if not terrain_hm.load_from("res://assets/terrain_height.png"):
		push_error("terrain heightmap missing")
	grid = MowGrid.new()
	add_child(grid)
	_build_environment()
	_build_terrain()
	_build_manor()
	if OS.get_environment("BDQ_NOGRASS") == "":
		_build_grass()
	_build_props_and_plants()
	_build_mower()
	_build_audio()
	if OS.get_environment("BDQ_NOHUD") == "":
		add_child(preload("res://scripts/hud.gd").new())
	if OS.get_environment("BDQ_FPS") != "":
		var fp := _FpsPrinter.new()
		add_child(fp)
	if "--harness" in OS.get_cmdline_user_args():
		var h := preload("res://scripts/harness.gd").new()
		add_child(h)


func _gltf(path: String) -> PackedScene:
	return load(path)


func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var r := _find(c, name)
		if r != null:
			return r
	return null


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_energy = 0.4
	env.fog_light_color = Color(0.68, 0.64, 0.60)
	env.fog_density = 0.004
	# llvmpipe marchers render volumetric fog as blocky rectangles; opt-in only
	env.volumetric_fog_enabled = OS.get_environment("BDQ_VOLFOG") != ""
	env.volumetric_fog_density = 0.010
	env.volumetric_fog_albedo = Color(0.62, 0.60, 0.62)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 60.0
	env.volumetric_fog_detail_spread = 4.0
	env.volumetric_fog_gi_inject = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Golden-hour sheen: glow on sun and headlights, gentle grade
	env.glow_enabled = true
	env.glow_strength = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.set("glow_levels/1", 0.15)
	env.set("glow_levels/2", 0.25)
	env.set("glow_levels/3", 0.25)
	env.set("glow_levels/4", 0.2)
	env.set("glow_levels/5", 0.1)
	env.set("adjustment_enabled", true)
	env.set("adjustment_saturation", 1.08)
	env.set("adjustment_contrast", 1.05)

	# Procedural sky sun glow (4.7 exposes sun_curve/sun_angle_max only)
	sky_mat.sun_curve = 0.6
	sky_mat.sun_angle_max = 90.0
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = OS.get_environment("BDQ_NOSUNSH") == ""
	sun.directional_shadow_max_distance = 110.0
	sun.set_shadow_mode(DirectionalLight3D.SHADOW_ORTHOGONAL)
	sun.directional_shadow_fade_split = 0.45
	sun.light_angular_distance = 2.0
	add_child(sun)

	day_night = DayNight.new()
	add_child(day_night)
	day_night.setup(sun, env)


func _build_terrain() -> void:
	var ts: PackedScene = _gltf("res://assets/terrain.glb")
	var tinst := ts.instantiate()
	add_child(tinst)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	var data := PackedFloat32Array()
	data.resize(TerrainHeight.SIZE * TerrainHeight.SIZE)
	for z in TerrainHeight.SIZE:
		for x in TerrainHeight.SIZE:
			data[z * TerrainHeight.SIZE + x] = terrain_hm.heights[z * TerrainHeight.SIZE + x]
	shape.map_data = data
	shape.map_width = TerrainHeight.SIZE
	shape.map_depth = TerrainHeight.SIZE
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _static_box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "sbox_%d_%d" % [int(center.x * 10), int(center.z * 10)]
	sb.collision_layer = 1
	sb.collision_mask = 0
	var bs := BoxShape3D.new()
	bs.size = size
	var cs := CollisionShape3D.new()
	cs.shape = bs
	cs.position = center
	sb.add_child(cs)
	parent.add_child(sb)


func _static_cyl(parent: Node3D, center: Vector3, radius: float, height: float) -> void:
	var sb := StaticBody3D.new()
	sb.name = "scyl_%d_%d" % [int(center.x * 10), int(center.z * 10)]
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cy := CylinderShape3D.new()
	cy.radius = radius
	cy.height = height
	var cs := CollisionShape3D.new()
	cs.shape = cy
	cs.position = center
	sb.add_child(cs)
	parent.add_child(sb)


func _build_manor() -> void:
	var ms: PackedScene = _gltf("res://assets/manor.glb")
	var inst := ms.instantiate()
	add_child(inst)
	_static_box(self, Vector3(0, 4, -7.0), Vector3(30.2, 8, 0.7))
	_static_box(self, Vector3(0, 4, 7.0), Vector3(30.2, 8, 0.7))
	_static_box(self, Vector3(-15.0, 4, 0), Vector3(0.7, 8, 14.2))
	_static_box(self, Vector3(15.0, 4, 0), Vector3(0.7, 8, 14.2))


func _build_props_and_plants() -> void:
	if OS.get_environment("BDQ_NOTREES") != "":
		_build_props_no_trees()
		return
	var props: PackedScene = _gltf("res://assets/props.glb")
	var oak_s: PackedScene = _gltf("res://assets/oak.glb")
	var beech_s: PackedScene = _gltf("res://assets/beech.glb")
	var dead_s: PackedScene = _gltf("res://assets/dead.glb")
	var proto := props.instantiate()
	var fence_piv := _find(proto, "fence_pivot").duplicate()
	var gate_piv := _find(proto, "gate_pivot").duplicate()
	var hedge_piv := _find(proto, "hedge_pivot").duplicate()
	var fountain_piv := _find(proto, "fountain_pivot").duplicate()
	var stones_piv := _find(proto, "stones_pivot").duplicate()
	var leaf_piv := _find(proto, "leaf_pivot").duplicate()
	proto.free()

	# Iron fence along the south boundary with a gate gap in the middle.
	var x := -34.0
	while x <= 34.0:
		if absf(x) > 2.0:
			var y := terrain_hm.height_at(x, 22.5)
			_place_scene_node(fence_piv.duplicate(), Vector3(x, y, 22.5), 0.0)
			_static_box(self, Vector3(x, y + 0.8, 22.5), Vector3(2.0, 1.6, 0.15))
		x += 2.0
	_place_scene_node(gate_piv.duplicate(), Vector3(0, terrain_hm.height_at(0, 22.5), 22.5), 0.0)

	# Hedges along east and west lawn edges.
	for z in range(-20, 21, 2):
		for side in [-1, 1]:
			var hx: float = side * 34.5
			_place_scene_node(
				hedge_piv.duplicate(),
				Vector3(hx, terrain_hm.height_at(hx, z), z),
				PI / 2.0,
				rng.randf()
			)
	# Overgrown hedge row behind the hall (north).
	for hx in range(-24, 25, 2):
		_place_scene_node(
			hedge_piv.duplicate(),
			Vector3(hx, terrain_hm.height_at(hx, -24.0), -24.0),
			0.0,
			rng.randf()
		)

	# Dead fountain on the west lawn with bench and stones.
	var fy := terrain_hm.height_at(-14, -2)
	_place_scene_node(fountain_piv.duplicate(), Vector3(-14, fy, -2), 0.0)
	_static_cyl(self, Vector3(-14, fy + 1.0, -2), 2.7, 2.0)
	_place_scene_node(stones_piv.duplicate(), Vector3(9, terrain_hm.height_at(9, 12), 12), 0.8)

	# Oaks inside/around the lawn, beeches along the north, dead trees.
	var oak := oak_s.instantiate()
	var beech := beech_s.instantiate()
	var dead := dead_s.instantiate()
	var spots_oak: Array[Vector3] = [
		Vector3(-28, 0, 16),
		Vector3(-20, 0, 4),
		Vector3(-26, 0, -12),
		Vector3(24, 0, 16),
		Vector3(28, 0, -4),
		Vector3(20, 0, -16),
		Vector3(-8, 0, 18),
		Vector3(12, 0, 19),
		Vector3(30, 0, 20),
		Vector3(-32, 0, 2),
		Vector3(6, 0, -19),
		Vector3(-4, 0, -20),
	]
	for p in spots_oak:
		var sc := 0.85 + rng.randf() * 0.4
		var yy := terrain_hm.height_at(p.x, p.z)
		var o := oak.duplicate()
		_no_canopy_shadow(o)
		_place_scene_node(o, Vector3(p.x, yy, p.z), rng.randf() * TAU, sc)
		_static_cyl(self, Vector3(p.x, yy + 1.5, p.z), 0.5 * sc, 3.0)
	for bx in range(-30, 31, 7):
		var bz := -27.0
		var yy := terrain_hm.height_at(bx, bz)
		_place_scene_node(
			beech.duplicate(), Vector3(bx, yy, bz), rng.randf() * TAU, 0.8 + rng.randf() * 0.4
		)
	for dt in [Vector3(26, 0, 8), Vector3(-30, 0, -18), Vector3(2, 0, 21)]:
		var yy := terrain_hm.height_at(dt.x, dt.z)
		_place_scene_node(
			dead.duplicate(), Vector3(dt.x, yy, dt.z), rng.randf() * TAU, 0.9 + rng.randf() * 0.3
		)

	# Leaf litter MultiMesh under the trees.
	var leaf_mesh_mi := _find(leaf_piv, "leaf_cluster") as MeshInstance3D
	if leaf_mesh_mi != null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = leaf_mesh_mi.mesh
		var pts: Array[Transform3D] = []
		for p in spots_oak:
			for i in 26:
				var lx := p.x + rng.randf_range(-2.4, 2.4)
				var lz := p.z + rng.randf_range(-2.4, 2.4)
				var yy := terrain_hm.height_at(lx, lz)
				pts.append(
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(lx, yy + 0.01, lz))
				)
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, pts[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _place_scene_node(node: Node3D, pos: Vector3, yaw: float, scale_f: float = 1.0) -> void:
	node.position = pos
	node.rotation.y = yaw
	if scale_f != 1.0:
		node.scale = Vector3(scale_f, scale_f, scale_f)
	add_child(node)


func _build_props_no_trees() -> void:
	pass


func _build_grass() -> void:
	var gp: PackedScene = _gltf("res://assets/grass.glb")
	var proto := gp.instantiate()
	var tuft_mi := _find(proto, "tuft_tall") as MeshInstance3D
	var imp_mi := _find(proto, "grass_impostor") as MeshInstance3D
	var tuft_mesh := tuft_mi.mesh
	var imp_mesh := imp_mi.mesh
	proto.free()
	grass = GrassField.new()
	grass.name = "GrassField"
	add_child(grass)
	grass.setup(grid, tuft_mesh, imp_mesh, terrain_hm)


func _build_mower() -> void:
	mower = Mower.new()
	mower.grid = grid
	mower.collision_layer = 1
	mower.collision_mask = 1
	mower.add_to_group("mower_rigidbody")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.75, 0.5, 1.7)
	cs.position = Vector3(0, 0.5, 0)
	cs.shape = bs
	mower.add_child(cs)

	var vis: PackedScene = _gltf("res://assets/mower.glb")
	var vinst := vis.instantiate()
	mower.add_child(vinst)

	var tyres := {}
	for tag in ["fl", "fr", "rl", "rr"]:
		var t := _find(vinst, "tyre_" + tag) as Node3D
		if t != null:
			tyres[tag] = t

	var cam_pivot := Node3D.new()
	cam_pivot.name = "cam_pivot"
	cam_pivot.position = Vector3(0, 1.05, 0.35)
	mower.add_child(cam_pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.35, 0)
	cam.near = 0.05
	cam.far = 320.0
	cam.current = true
	cam.cull_mask = 0b11
	cam_pivot.add_child(cam)

	var lights: Array = []
	# Work lights ride the camera pivot: the beam follows where the operator
	# looks, which is also where the dusk captures need the turf lit.
	for tag in ["L", "R"]:
		var spot := SpotLight3D.new()
		spot.name = "headlight_" + tag
		spot.spot_angle = 30.0
		spot.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 4.0)
		spot.spot_range = 30.0
		spot.light_energy = 3.2
		spot.light_color = Color(1.0, 0.85, 0.65)
		spot.shadow_enabled = false
		spot.rotation_degrees = Vector3(-8, 0, 0)
		spot.position = Vector3(0.35 if tag == "R" else -0.35, -0.55, -0.3)
		cam_pivot.add_child(spot)
		lights.append(spot)

	add_child(mower)
	mower.attach_visuals(tyres, cam_pivot, lights)
	if OS.get_environment("BDQ_DBG") != "":
		for l in lights:
			print(
				"HL ",
				l.name,
				" vis=",
				l.visible,
				" e=",
				l.light_energy,
				" layers=",
				l.layers,
				" range=",
				l.spot_range,
				" ang=",
				l.spot_angle
			)
	var start_z := 18.0
	mower.global_position = Vector3(6.0, terrain_hm.height_at(6.0, start_z) + 0.5, start_z)
	mower.global_rotation.y = PI  # face the hall (+Z)

	_build_viewmodels(cam)


func _build_viewmodels(cam: Camera3D) -> void:
	var vm := Node3D.new()
	vm.name = "ViewModels"
	cam.add_child(vm)

	var vmr := preload("res://scripts/viewmodels.gd").new()
	vmr.name = "ViewModelRig"
	view_models = vmr
	vm.add_child(vmr)

	var vmg: PackedScene = _gltf("res://assets/viewmodel.glb")
	vmr.build(vmg)
	vmr.set_mower(mower)
	vmr.apply_layer(2)
	if OS.get_environment("BDQ_DBG") != "":
		var b0 = vmr.get("beads_static")
		print("POSTLAY bead0 layers=%s" % str((b0[0] as MeshInstance3D).layers))


func _no_canopy_shadow(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var nm := String((c as MeshInstance3D).name)
			if "canopy" in nm:
				(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_canopy_shadow(c)


func _build_audio() -> void:
	var holder := Node3D.new()
	holder.name = "Audio"
	add_child(holder)
	var defs := [
		["engine_loop.wav", -3.0],
		["blade_loop.wav", -5.0],
		["wind_loop.wav", -8.0],
		["birds_loop.wav", -10.0],
		["crickets_loop.wav", -10.0],
	]
	for d in defs:
		var path: String = "res://audio/" + String(d[0])
		if not ResourceLoader.exists(path):
			push_warning("audio missing: " + path)
			continue
		var pl := AudioStreamPlayer3D.new()
		pl.stream = load(path)
		pl.volume_db = float(d[1])
		pl.max_db = 0.0
		holder.add_child(pl)
		pl.play()
		if String(d[0]) == "engine_loop.wav":
			holder.set_meta("engine", pl)
		if String(d[0]) == "birds_loop.wav":
			holder.set_meta("birds", pl)
		if String(d[0]) == "crickets_loop.wav":
			holder.set_meta("crickets", pl)
	if day_night != null:
		day_night.audio_holder = holder


class _FpsPrinter:
	extends Node
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		if int(t) != int(t - d) and int(t) % 4 == 0:
			var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			print(
				(
					"FPSPROBE t=%.0f fps=%.1f prim=%d objs=%d"
					% [t, Engine.get_frames_per_second(), prim, objs]
				)
			)
