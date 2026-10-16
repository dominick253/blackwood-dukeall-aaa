extends CanvasLayer
## Minimal diegetic-ish HUD: mow %, speed, time to dusk, controls.

var label: Label
var help: Label


func _ready() -> void:
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)
	help = Label.new()
	help.position = Vector2(16, 660)
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "W/S throttle  A/D steer  Space brake  Shift fast  R lights  E beer  Q cigar"
	add_child(help)


func _process(_delta: float) -> void:
	var mower := get_tree().get_first_node_in_group("mower_rigidbody") as RigidBody3D
	var sp := 0.0
	if mower != null:
		sp = mower.linear_velocity.length() * 3.6
	var t := GameState.day_time
	var left := maxf(0.0, GameState.day_length - t)
	label.text = (
		"Mown %.1f%%   %.1f km/h   dusk in %02d:%02d   beer %d%%   ash %d mm"
		% [
			GameState.mow_percent,
			sp,
			int(left) / 60,
			int(left) % 60,
			int(GameState.beer_volume * 100.0 / 0.7),
			int(GameState.ash_length_m * 1000.0),
		]
	)
