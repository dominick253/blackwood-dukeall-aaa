class_name TerrainHeight
extends RefCounted
## Samples terrain height from the PNG exported by the Blender terrain build.
## Value convention: stored = height + 1.0.

const SIZE := 161
const WORLD := 160.0

var heights := PackedFloat32Array()


func load_from(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return false
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return false
	heights.resize(SIZE * SIZE)
	for z in SIZE:
		for x in SIZE:
			heights[z * SIZE + x] = img.get_pixel(x, z).r - 1.0
	return true


func height_at(wx: float, wz: float) -> float:
	var fx := clampf(wx + WORLD / 2.0, 0.0, WORLD)
	var fz := clampf(wz + WORLD / 2.0, 0.0, WORLD)
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var x1 := mini(x0 + 1, SIZE - 1)
	var z1 := mini(z0 + 1, SIZE - 1)
	var tx := fx - x0
	var tz := fz - z0
	var a := lerpf(heights[z0 * SIZE + x0], heights[z0 * SIZE + x1], tx)
	var b := lerpf(heights[z1 * SIZE + x0], heights[z1 * SIZE + x1], tx)
	return lerpf(a, b, tz)
