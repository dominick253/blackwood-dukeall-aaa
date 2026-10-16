class_name MowGrid
extends Node
## Persistent mow state for the estate lawn.

signal cell_cut(cx, cy)

const CELL := 0.5
const LAWN_W := 70.0
const LAWN_H := 45.0
const ORIGIN := Vector3(-LAWN_W / 2.0, 0.0, -LAWN_H / 2.0)

var cols := int(LAWN_W / CELL)
var rows := int(LAWN_H / CELL)
var cut: Array = []
var mowable := PackedInt32Array()
var mowable_count := 0
var cut_count := 0


func _init() -> void:
	cut.resize(cols * rows)
	cut.fill(0)
	# Hall footprint is not mowable.
	for cy in rows:
		for cx in cols:
			var wx := ORIGIN.x + (cx + 0.5) * CELL
			var wz := ORIGIN.z + (cy + 0.5) * CELL
			if absf(wx) < 15.5 and absf(wz) < 7.5:
				cut[cy * cols + cx] = -1  # blocked
			else:
				mowable.append(cy * cols + cx)
	mowable_count = mowable.size()


func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < cols and cy < rows


func is_cut(cx: int, cy: int) -> bool:
	if not in_bounds(cx, cy):
		return false
	return cut[cy * cols + cx] == 1


func is_blocked(cx: int, cy: int) -> bool:
	if not in_bounds(cx, cy):
		return true
	return cut[cy * cols + cx] == -1


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - ORIGIN.x) / CELL)), int(floor((pos.z - ORIGIN.z) / CELL)))


func cut_cell(cx: int, cy: int) -> bool:
	## Returns true if this call newly cut the cell.
	if not in_bounds(cx, cy):
		return false
	var idx := cy * cols + cx
	if cut[idx] != 0:
		return false
	cut[idx] = 1
	cut_count += 1
	GameState.mow_percent = 100.0 * float(cut_count) / float(mowable_count)
	cell_cut.emit(cx, cy)
	return true


func cut_quad(center: Vector3, half_w: float, half_l: float, yaw: float) -> int:
	## Cut every cell whose centre falls inside the deck rectangle.
	var n := 0
	var c := cos(yaw)
	var s := sin(yaw)
	var cc := cell_of(center)
	var span := int(ceil((half_w + half_l) / CELL)) + 1
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var cx := cc.x + dx
			var cy := cc.y + dy
			if not in_bounds(cx, cy):
				continue
			var wx := ORIGIN.x + (cx + 0.5) * CELL - center.x
			var wz := ORIGIN.z + (cy + 0.5) * CELL - center.z
			var lx := wx * c + wz * -s
			var lz := wx * s + wz * c
			if absf(lx) <= half_w and absf(lz) <= half_l:
				if cut_cell(cx, cy):
					n += 1
	return n


func percent() -> float:
	if mowable_count == 0:
		return 0.0
	return 100.0 * float(cut_count) / float(mowable_count)
