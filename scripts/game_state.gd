extends Node
## Global game state shared across subsystems.

var mow_percent := 0.0
var day_time := 0.0
var day_length := 900.0
var wind := Vector3(0.7, 0.0, 0.0)
var mower_velocity := Vector3.ZERO
var mower_position := Vector3.ZERO
var headlights_on := true
var beer_volume := 0.7
var cigar_burn_m := 0.0
var ash_length_m := 0.0
var game_over := false
