class_name ViewModels
extends Node3D
## First-person bottle + cigar + hands parented to the camera with layered
## bob, sway and terrain recoil. Viewmodels render on layer 2 so they use
## the camera's near plane without world clipping issues.

var mower: Mower
var bottle_root: Node3D
var liquid_surface: MeshInstance3D
var slosh: Slosh
var _beer: MeshInstance3D
var _foam: MeshInstance3D
var _beer_base_y := 0.0
var _foam_base_y := 0.0
var cigar_root: Node3D
var cigar_sim: CigarSim
var hands_l: Node3D
var hands_r: Node3D
var beads_static: Array[MeshInstance3D] = []
var beads_slide: Array = []
var inspect := 0.0

var _hand_l_local := Vector3.ZERO
var _hand_r_local := Vector3.ZERO
var _bob_t := 0.0
var _sway := Vector3.ZERO
var _bead_rng := RandomNumberGenerator.new()
var _drink_anim := 0.0
var _puff_anim := 0.0
var _flick_anim := 0.0
var _toss := 0.0  # >0: empty-bottle chuck animation running
var _toss_spawned := false
var _refill := 0.0  # >0: fresh bottle rising into frame

var _rest_bottle := Transform3D(
	Basis.from_euler(Vector3(0.18, 0.0, -0.25)), Vector3(-0.26, -0.24, -0.52)
)
var _rest_cigar := Transform3D(
	Basis.from_euler(Vector3(0.10, 0.0, 0.35)), Vector3(0.24, -0.26, -0.50)
)


func build(vm_scene: PackedScene) -> void:
	## v2 viewmodel.glb is one baked assembly with a flat node list. We split
	## it into two articulated groups: left hand travels with the bottle,
	## right hand travels with the cigar. Grips are baked, so hands_l/hands_r
	## stay null and only the group pivots animate.
	var inst := vm_scene.instantiate()
	add_child(inst)
	bottle_root = Node3D.new()
	bottle_root.name = "bottle_root"
	add_child(bottle_root)
	cigar_root = Node3D.new()
	cigar_root.name = "cigar_root"
	add_child(cigar_root)
	for c in inst.get_children().duplicate():
		var nm := String(c.name)
		if nm.begins_with("rh_") or nm.begins_with("cigar_"):
			_reparent(c, cigar_root)
		else:
			_reparent(c, bottle_root)
	_recenter(bottle_root)
	_recenter(cigar_root)
	inst.free()

	bottle_root.transform = _rest_bottle
	var liq_piv := Node3D.new()
	liq_piv.name = "liquid_pivot"
	liq_piv.position = Vector3(0.0, 0.09, 0.0)
	bottle_root.add_child(liq_piv)
	slosh = Slosh.new()
	slosh.name = "Slosh"
	liq_piv.add_child(slosh)
	liquid_surface = _find(bottle_root, "bottle_beer") as MeshInstance3D
	if liquid_surface != null:
		_reparent(liquid_surface, slosh)
	var foam := _find(bottle_root, "bottle_foam") as MeshInstance3D
	if foam != null:
		_reparent(foam, slosh)
	if liquid_surface != null:
		liquid_surface.position.y -= 0.09
	if foam != null:
		foam.position.y -= 0.09
	# surface stays null: the solid beer mesh is level-driven by hand below
	# (bottom-anchored), so drain reads as a falling surface, not a
	# shrinking blob.
	slosh.surface = null
	_beer = liquid_surface
	_foam = foam
	if _beer != null:
		_beer_base_y = _beer.position.y
	if _foam != null:
		_foam_base_y = _foam.position.y

	_override_bottle_materials()
	if OS.get_environment("BDQ_NOBEADS") == "":
		_build_beads()
	if OS.get_environment("BDQ_DBG") != "":
		print(
			(
				"BEADS static=%d slide=%d bottle_children=%d"
				% [beads_static.size(), beads_slide.size(), bottle_root.get_child_count()]
			)
		)
		for mi in beads_static.slice(0, 3):
			print(
				(
					"BEAD pos=%s visible=%s layers=%d aabb=%s"
					% [mi.position, mi.visible, mi.layers, mi.get_aabb()]
				)
			)

	cigar_root.transform = _rest_cigar
	cigar_sim = CigarSim.new()
	cigar_sim.name = "CigarSim"
	cigar_sim.ember = _find(cigar_root, "cigar_ember")
	cigar_sim.ash_node = _find(cigar_root, "cigar_ash")
	cigar_sim.body_node = _find(cigar_root, "cigar_body") as MeshInstance3D
	if cigar_sim.ember != null:
		cigar_sim.y_anchor = (cigar_sim.ember as Node3D).position.y
	_setup_smoke(cigar_root)
	add_child(cigar_sim)
	cigar_sim.position = _rest_cigar.origin
	cigar_sim.rotation = _rest_cigar.basis.get_euler()


func _override_bottle_materials() -> void:
	# 4.6: the in-game bottle is runtime-authored: alpha-blend green glass,
	# emissive liquid and foam, emissive condensation beads. GLB
	# transmittance does not read on the near-plane viewmodel layer.
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.16, 0.30, 0.17, 0.45)
	gm.roughness = 0.06
	gm.metallic_specular = 1.2
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := _find(bottle_root, "bottle_glass") as MeshInstance3D
	if mi != null:
		mi.material_override = gm
	if OS.get_environment("BDQ_DBG") != "":
		print("OVR bottle_glass found=", mi != null)
	var beer := _find(bottle_root, "bottle_beer") as MeshInstance3D
	if beer != null:
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.72, 0.42, 0.08)
		bm.roughness = 0.25
		bm.emission_enabled = true
		bm.emission = Color(0.55, 0.30, 0.05)
		bm.emission_energy_multiplier = 0.35
		beer.material_override = bm
	var foam := _find(bottle_root, "bottle_foam") as MeshInstance3D
	if foam != null:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.95, 0.9, 0.75)
		fm.roughness = 0.4
		fm.emission_enabled = true
		fm.emission = Color(0.85, 0.75, 0.5)
		fm.emission_energy_multiplier = 0.3
		foam.material_override = fm
	var bead_mat := StandardMaterial3D.new()
	bead_mat.albedo_color = Color(0.85, 0.9, 0.95)
	bead_mat.roughness = 0.02
	bead_mat.emission_enabled = true
	bead_mat.emission = Color(0.55, 0.6, 0.7)
	bead_mat.emission_energy_multiplier = 0.5
	for i in 26:
		var b := _find(bottle_root, "bead%d" % i) as MeshInstance3D
		if b != null:
			b.material_override = bead_mat


func _build_beads() -> void:
	_bead_rng.seed = 0xBEEF
	var bead_mat := StandardMaterial3D.new()
	bead_mat.albedo_color = Color(0.85, 0.9, 0.95)
	bead_mat.roughness = 0.02
	bead_mat.metallic = 0.0
	bead_mat.metallic_specular = 2.0
	bead_mat.emission_enabled = true
	bead_mat.emission = Color(0.55, 0.6, 0.7)
	bead_mat.emission_energy_multiplier = 0.5
	for i in 52:
		var mi := MeshInstance3D.new()
		var r := 0.0008 + _bead_rng.randf() * 0.0007
		var m0 := SphereMesh.new()
		m0.radial_segments = 8
		m0.rings = 5
		m0.radius = r
		m0.height = r * 1.6
		mi.mesh = m0
		var phi := _bead_rng.randf_range(0.0, TAU)
		var y := 0.015 + _bead_rng.randf() * 0.145
		var rr := 0.0335 + _bead_rng.randf() * 0.0015
		mi.position = Vector3(cos(phi) * rr, y, sin(phi) * rr)
		bottle_root.add_child(mi)
		beads_static.append(mi)
	var slide_mat := bead_mat.duplicate() as StandardMaterial3D
	slide_mat.albedo_color = Color(0.9, 0.95, 1.0)
	for i in 8:
		var mi2 := MeshInstance3D.new()
		var r2 := 0.001 + _bead_rng.randf() * 0.0005
		var m2 := SphereMesh.new()
		m2.radial_segments = 8
		m2.rings = 5
		m2.radius = r2
		m2.height = r2 * 2.2
		mi2.mesh = m2
		bottle_root.add_child(mi2)
		(
			beads_slide
			. append(
				{
					"mi": mi2,
					"phi": _bead_rng.randf_range(0.0, TAU),
					"y": _bead_rng.randf_range(0.08, 0.16),
					"dwell": _bead_rng.randf_range(0.0, 2.0),
					"speed": _bead_rng.randf_range(0.004, 0.012),
					"r": 0.0335,
				}
			)
		)


func _update_beads(delta: float) -> void:
	for b in beads_slide:
		var dwell := float(b["dwell"])
		if dwell > 0.0:
			b["dwell"] = dwell - delta
			continue
		var y := float(b["y"]) - float(b["speed"]) * delta
		if y < 0.012:
			b["y"] = _bead_rng.randf_range(0.1, 0.16)
			b["dwell"] = _bead_rng.randf_range(0.3, 2.5)
			b["speed"] = _bead_rng.randf_range(0.004, 0.012)
		else:
			b["y"] = y
		var phi := float(b["phi"])
		var rr := float(b["r"])
		(b["mi"] as MeshInstance3D).position = Vector3(cos(phi) * rr, float(b["y"]), sin(phi) * rr)


func set_mower(m: Mower) -> void:
	mower = m


func apply_layer(layer: int) -> void:
	for mi in _all_mesh_instances(self):
		mi.layers = 1 << (layer - 1)


func _all_mesh_instances(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_mesh_instances(c))
	return out


func _reparent(c: Node, t: Node) -> void:
	c.get_parent().remove_child(c)
	t.add_child(c)


func _recenter(root: Node) -> void:
	var sum := Vector3.ZERO
	var n := 0
	for c in root.get_children():
		if c is MeshInstance3D:
			sum += (c as Node3D).position
			n += 1
	if n == 0:
		return
	var cen := sum / float(n)
	for c in root.get_children():
		if c is MeshInstance3D:
			(c as Node3D).position -= cen


func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find(c, name)
		if r != null:
			return r
	return null


func _setup_smoke(cig: Node) -> void:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.006
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.gravity = Vector3(0.7, 1.1, 0.0)
	pm.initial_velocity_min = 0.08
	pm.initial_velocity_max = 0.18
	pm.scale_min = 0.3
	pm.scale_max = 0.8
	pm.linear_accel_min = -0.05
	pm.linear_accel_max = 0.12
	pm.tangential_accel_min = 0.01
	pm.tangential_accel_max = 0.06
	p.process_material = pm
	p.amount = 40
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.visibility_aabb = AABB(Vector3(-0.5, -0.2, -0.5), Vector3(1.0, 1.4, 1.0))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.8, 0.78, 0.75, 0.34)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.disable_receive_shadows = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = mat
	var sq := QuadMesh.new()
	sq.size = Vector2(0.12, 0.12)
	sq.material = mat
	p.draw_pass_1 = sq
	var em := _find(cig, "ember_pivot") as Node3D
	if em == null and cigar_sim != null:
		em = cigar_sim.ember as Node3D
	if em != null:
		em.add_child(p)
	else:
		cig.add_child(p)
	cigar_sim.smoke = p

	var d := GPUParticles3D.new()
	d.name = "AshDebris"
	var dm := ParticleProcessMaterial.new()
	dm.direction = Vector3(0, -1, 0)
	dm.spread = 60.0
	dm.gravity = Vector3(0, -4, 0)
	dm.initial_velocity_min = 0.05
	dm.initial_velocity_max = 0.15
	d.amount = 24
	d.lifetime = 1.6
	d.emitting = false
	d.one_shot = true
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.55, 0.54, 0.52)
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	d.material_override = dmat
	var dq := QuadMesh.new()
	dq.size = Vector2(0.012, 0.012)
	dq.material = dmat
	d.draw_pass_1 = dq
	var ap := _find(cig, "ash_pivot") as Node3D
	if ap == null and cigar_sim != null:
		ap = cigar_sim.ash_node as Node3D
	# Debris lives on the cigar root, NOT the ash column: drop_ash hides
	# the column, and children of a hidden node never render - the falling
	# ash would be invisible exactly when it matters.
	cig.add_child(d)
	if ap != null:
		d.position = ap.position
	cigar_sim.debris = d


func _process(delta: float) -> void:
	var speed := 0.0
	var recoil := Vector3.ZERO
	if mower != null:
		speed = mower.linear_velocity.length()
		_bob_t += delta * (2.0 + speed * 2.2)
		recoil = Vector3(0, -mower.get_final_linear_velocity_hint(), 0) * 0.02
	var bob := sin(_bob_t) * 0.004 * (1.0 + speed * 0.8)
	var bob2 := sin(_bob_t * 0.53 + 1.7) * 0.002
	_sway = _sway.lerp(
		Vector3(clampf(-mower_view_angular(), -0.05, 0.05), 0, 0), clampf(delta * 4.0, 0.0, 1.0)
	)

	_update_beads(delta)
	if _beer != null and slosh != null:
		var vr := clampf(slosh.volume_ratio, 0.0, 1.0)
		_beer.visible = vr > 0.02
		_beer.scale = Vector3(1.0, maxf(vr, 0.02), 1.0)
		_beer.position.y = _beer_base_y - 0.08 * (1.0 - vr)
		if _foam != null:
			_foam.visible = vr > 0.02
			_foam.position.y = _foam_base_y + 0.08 * (vr - 1.0)
	_drink_anim = maxf(0.0, _drink_anim - delta)
	_puff_anim = maxf(0.0, _puff_anim - delta)

	var bt := _rest_bottle
	var lift := 0.0
	if inspect > 0.0:
		# centered in the telephoto lens: at 0.45 m the 32 deg frame is
		# only ~0.10 m half-height, so the inspect pose must sit near axis
		var insp := Transform3D(
			Basis.from_euler(Vector3(-0.12, 0.25, -0.10)), Vector3(-0.04, -0.05, -0.45)
		)
		bt = bt.interpolate_with(insp, clampf(inspect, 0.0, 1.0))
	if _drink_anim > 0.0:
		lift = sin(clampf(1.0 - _drink_anim / 1.2, 0.0, 1.0) * PI)
	bt.origin += Vector3(0.06 * lift, 0.10 * lift, 0.06 * lift)
	bt.basis = bt.basis.rotated(Vector3.RIGHT, -0.55 * lift)
	if _toss > 0.0:
		# Empty: swing the bottle out right and chuck it into the world.
		var k := clampf(1.0 - _toss / 1.3, 0.0, 1.0)
		var throw_pose := Transform3D(
			Basis.from_euler(Vector3(0.7, 1.1, -0.5)), Vector3(0.85, -0.50, -0.10)
		)
		bt = bt.interpolate_with(throw_pose, clampf(k / 0.45, 0.0, 1.0))
		if k >= 0.45 and not _toss_spawned:
			_spawn_thrown_bottle()
			_toss_spawned = true
		_toss -= delta
		if _toss <= 0.0:
			# Fresh full bottle comes in from off-frame.
			if slosh != null:
				slosh.volume_ratio = 1.0
				slosh.theta_x = 0.0
				slosh.theta_z = 0.0
				slosh.jiggle = 0.0
				slosh.jiggle_vel = 0.0
			GameState.beer_volume = 1.0
			GameState.bottles_chucked += 1
			_refill = 0.5
	elif _refill > 0.0:
		bt.origin.y -= 0.55 * clampf(_refill / 0.5, 0.0, 1.0)
		_refill -= delta
	bt.origin += Vector3(0, bob, 0) + _sway
	bt.origin += recoil
	bottle_root.transform = bt
	if hands_l != null:
		hands_l.transform = Transform3D(bt.basis, bt * _hand_l_local)

	var ct := _rest_cigar
	ct.origin += Vector3(0, bob + bob2, 0) + _sway * 0.8
	ct.origin += recoil
	ct.basis = Basis.from_euler(Vector3(0.10 + 0.02 * sin(_bob_t * 0.7), 0.0, 0.35))
	if _flick_anim > 0.0:
		# Wrist snap: quick rotation about the grip axis, ash goes with it.
		var fk := 1.0 - _flick_anim / 0.35
		ct.basis = ct.basis.rotated(Vector3.RIGHT, -0.85 * sin(fk * PI))
		_flick_anim -= delta
	cigar_root.transform = ct
	if hands_r != null:
		hands_r.transform = Transform3D(ct.basis, ct * _hand_r_local)
	if cigar_sim != null:
		cigar_sim.position = ct.origin
		cigar_sim.rotation = ct.basis.get_euler()

	if mower != null:
		if mower.drink_requested:
			mower.drink_requested = false
			do_drink()
		if mower.puff_requested:
			mower.puff_requested = false
			do_puff()
		if mower.ash_requested:
			mower.ash_requested = false
			do_flick()


func mower_view_angular() -> float:
	if mower == null:
		return 0.0
	return mower.angular_velocity.y


func do_drink() -> void:
	if _toss > 0.0 or _refill > 0.0:
		return
	_drink_anim = 1.2
	if slosh != null:
		# Each drink takes a visible slug: 12 % of full, linear, so the
		# level drop per sip is the same at full bottle as near empty.
		slosh.volume_ratio = maxf(slosh.volume_ratio - 0.12, 0.0)
		slosh.jiggle_vel += 0.08
	GameState.beer_volume = slosh.volume_ratio if slosh != null else 0.0
	if slosh != null and slosh.volume_ratio <= 0.045:
		# Depleted: after the drink motion, chuck it and grab a fresh one.
		get_tree().create_timer(0.9).timeout.connect(do_empty_toss)


func do_empty_toss() -> void:
	if _toss > 0.0:
		return
	_toss = 1.3
	_toss_spawned = false


func _spawn_thrown_bottle() -> void:
	## Real physics bottle flung into the distance: it tumbles under gravity
	## and lands on the estate. Lives in the world, not the viewmodel layer.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.033
	cyl.bottom_radius = 0.033
	cyl.height = 0.22
	mi.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.15, 0.28, 0.16, 0.85)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.roughness = 0.08
	bm.metallic_specular = 1.2
	mi.material_override = bm
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.033
	sh.height = 0.22
	cs.shape = sh
	rb.add_child(cs)
	rb.mass = 0.4
	var world := get_tree().current_scene
	world.add_child(rb)
	rb.global_transform = Transform3D(
		cam.global_transform.basis.rotated(Vector3.RIGHT, randf_range(-0.7, 0.7)),
		cam.global_transform.origin - cam.global_transform.basis.z * 0.35
		+ Vector3(0.2, -0.15, 0.0)
	)
	var fwd := -cam.global_transform.basis.z
	rb.linear_velocity = fwd * 11.0 + Vector3(0.0, 3.2, 0.0)
	rb.angular_velocity = Vector3(
		randf_range(-9.0, 9.0), randf_range(-6.0, 6.0), randf_range(-9.0, 9.0)
	)
	get_tree().create_timer(12.0).timeout.connect(
		func() -> void:
			if is_instance_valid(rb):
				rb.queue_free()
	)


func do_flick() -> void:
	_flick_anim = 0.35
	if cigar_sim != null:
		cigar_sim.drop_ash()


func do_puff() -> void:
	_puff_anim = 0.6
	if cigar_sim != null:
		cigar_sim.puff()
