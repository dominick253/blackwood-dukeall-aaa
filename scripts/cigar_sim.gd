class_name CigarSim
extends Node3D
## Burn progression, ash build and drop, ember pulse and puff flare,
## wind-and-motion-driven smoke.

signal ash_dropped(length_m)

const FULL_BURN_SECONDS := 1200.0
const CIGAR_LEN := 0.178
const ASH_MAX := 0.030
const ASH_SEGMENT := 0.010

var burn_m := 0.0
var ash_len := 0.0
var flare := 0.0
var pulse_phase := 0.0
var pulse_period := 4.0
var y_anchor := 0.059  # ember rest height in the cigar group frame
var ember: MeshInstance3D
var ember_mat: StandardMaterial3D
var ash_node: MeshInstance3D
var body_node: MeshInstance3D  # cigar_body, shrinks as the burn eats it
var _body_base_y := 0.0
const BODY_LEN := 0.140
var smoke: GPUParticles3D
var smoke_mat: ParticleProcessMaterial
var debris: GPUParticles3D
var running := true


func _ready() -> void:
	if ember != null:
		ember_mat = ember.get_active_material(0) as StandardMaterial3D
	if smoke != null:
		smoke_mat = smoke.process_material as ParticleProcessMaterial
	if body_node != null:
		_body_base_y = body_node.position.y


func _physics_process(delta: float) -> void:
	if running:
		var rate := CIGAR_LEN / FULL_BURN_SECONDS
		burn_m = minf(burn_m + rate * delta, CIGAR_LEN)
		ash_len += rate * delta
		GameState.cigar_burn_m = burn_m
		if ash_len >= ASH_MAX:
			drop_ash()
		if ash_len >= ASH_SEGMENT and ash_node != null:
			ash_node.visible = true
			ash_node.scale = Vector3(1.0, clampf(ash_len / 0.012, 0.3, 2.6), 1.0)
		if ember != null:
			ember.position.y = y_anchor - burn_m
			if ash_node != null:
				ash_node.position.y = y_anchor - burn_m - ash_len * 0.5
		if body_node != null:
			# The wrapper shortens from the burning end: top (mouth) end
			# stays put, center rises as length shrinks.
			var bl := maxf(BODY_LEN - burn_m, 0.012)
			body_node.scale.y = bl / BODY_LEN
			body_node.position.y = _body_base_y + (BODY_LEN - bl) * 0.5
	GameState.ash_length_m = ash_len
	_update_ember(delta)
	_update_smoke()


func _update_ember(delta: float) -> void:
	pulse_phase += delta
	if pulse_phase > pulse_period:
		pulse_phase -= pulse_period
		pulse_period = randf_range(3.0, 5.0)
	flare = maxf(0.0, flare - delta / 2.0)
	if ember_mat != null:
		var pulse := 0.5 + 0.5 * sin(TAU * pulse_phase / pulse_period)
		var strength := lerpf(4.5, 7.0, pulse) + flare * 10.0
		ember_mat.emission_enabled = true
		ember_mat.emission_energy_multiplier = strength
		ember_mat.emission = Color(1.0, 0.29, 0.0).lerp(Color(1.0, 0.55, 0.25), minf(flare, 1.0))


func _update_smoke() -> void:
	if smoke == null or smoke_mat == null:
		return
	var wind := GameState.wind
	var drag := -GameState.mower_velocity * 0.7
	smoke_mat.gravity = wind + drag


func puff() -> void:
	flare = 1.0
	pulse_phase = 0.0
	if smoke != null:
		smoke.amount = 90
		smoke.preprocess = 0.0
		# Restore idle amount after the puff column clears.
		get_tree().create_timer(1.5).timeout.connect(func() -> void: smoke.amount = 40)


func drink_tap() -> void:
	if ash_len > 0.004:
		drop_ash()


func drop_ash() -> void:
	var dropped := ash_len
	ash_len = 0.0
	if ash_node != null:
		ash_node.visible = false
	if debris != null:
		# Catch the falling column to where the ash just was.
		if ash_node != null and debris.get_parent() == ash_node.get_parent():
			debris.position = (ash_node as Node3D).position
		debris.emitting = true
		get_tree().create_timer(0.6).timeout.connect(func() -> void: debris.emitting = false)
	ash_dropped.emit(dropped)
