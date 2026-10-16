extends Node
## Headless audit: triangles, AABBs and named pivots for every GLB asset.

const ASSETS := [
	"res://assets/mower.glb",
	"res://assets/viewmodel.glb",
	"res://assets/oak.glb",
	"res://assets/beech.glb",
	"res://assets/dead.glb",
	"res://assets/grass.glb",
	"res://assets/manor.glb",
	"res://assets/props.glb",
	"res://assets/terrain.glb",
]

var _frames := 0


func _process(_d: float) -> void:
	_frames += 1
	if _frames < 30:
		return
	_run()


func _run() -> void:
	for path in ASSETS:
		var ps: PackedScene = load(path)
		if ps == null:
			print("AUDIT %s MISSING" % path)
			continue
		var root := ps.instantiate()
		var tris := 0
		var meshes := 0
		var pivots: Array[String] = []
		var aabb := AABB()
		var first := true
		for n in _walk(root):
			if n is Node3D and n.get_parent() != root and n.name.ends_with("_pivot"):
				pivots.append(String(n.name))
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var m: Mesh = mi.mesh
				if m == null:
					continue
				meshes += 1
				tris += _mesh_tris(m)
				var local := m.get_aabb()
				var xf: Transform3D = mi.global_transform
				var g := _xform_aabb(local, xf)
				if first:
					aabb = g
					first = false
				else:
					aabb = aabb.merge(g)
		print(
			(
				"AUDIT %s meshes=%d tris=%d aabb=(%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f) pivots=%s"
				% [
					path,
					meshes,
					tris,
					aabb.position.x,
					aabb.position.y,
					aabb.position.z,
					aabb.end.x,
					aabb.end.y,
					aabb.end.z,
					",".join(pivots) if pivots.size() > 0 else "-",
				]
			)
		)
		root.free()
	var stats := _scene_stats()
	print("AUDIT SCENE tris=%d" % stats)
	get_tree().quit()


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _mesh_tris(m: Mesh) -> int:
	var total := 0
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var idx: Array = arr[Mesh.ARRAY_INDEX]
		var vtx: Array = arr[Mesh.ARRAY_VERTEX]
		if idx != null and idx.size() > 0:
			total += idx.size() / 3
		elif vtx != null:
			total += vtx.size() / 3
	return total


func _xform_aabb(a: AABB, xf: Transform3D) -> AABB:
	var pts := [
		a.position,
		a.position + Vector3(a.size.x, 0, 0),
		a.position + Vector3(0, a.size.y, 0),
		a.position + Vector3(0, 0, a.size.z),
		a.position + Vector3(a.size.x, a.size.y, 0),
		a.position + Vector3(a.size.x, 0, a.size.z),
		a.position + Vector3(0, a.size.y, a.size.z),
		a.position + a.size,
	]
	var res := AABB(xf * pts[0], Vector3.ZERO)
	for p in pts.slice(1):
		res = res.expand(xf * p)
	return res


func _scene_stats() -> int:
	var total := 0
	var by_name := {}
	for c in get_tree().root.get_children():
		if c.name == "Main":
			for n in _walk(c):
				var tris := 0
				var mult := 1
				if n is MeshInstance3D and (n as MeshInstance3D).layers == 1:
					var m: Mesh = (n as MeshInstance3D).mesh
					if m != null:
						tris = _mesh_tris(m)
				elif n is MultiMeshInstance3D:
					var mmi := n as MultiMeshInstance3D
					if mmi.multimesh != null and mmi.multimesh.mesh != null:
						tris = _mesh_tris(mmi.multimesh.mesh)
						mult = mmi.multimesh.instance_count
				if tris > 0:
					var share := tris * mult
					total += share
					var key := String(n.name)
					by_name[key] = int(by_name.get(key, 0)) + share
	var keys := by_name.keys()
	keys.sort_custom(func(a, b): return by_name[a] > by_name[b])
	for i in mini(12, keys.size()):
		print("TOP %s = %d" % [keys[i], by_name[keys[i]]])
	return total
