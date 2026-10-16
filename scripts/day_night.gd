class_name DayNight
extends Node
## Golden hour to dusk: 15 minutes, sun 8 to -4 degrees, 3200 K to 2000 K,
## volumetric fog rising.

const LENGTH := 900.0
const SUN_START_ELEV := 8.0
const SUN_END_ELEV := -4.0

var time := 0.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var audio_holder: Node3D = null
var running := true

# 3200 K and 2000 K blackbody approximations, normalised.
var warm_start := Color(1.0, 0.72, 0.42)
var warm_end := Color(1.0, 0.50, 0.20)


func setup(p_sun: DirectionalLight3D, p_env: Environment) -> void:
	sun = p_sun
	env = p_env
	sky_mat = p_env.sky.sky_material as ProceduralSkyMaterial


func _process(delta: float) -> void:
	if running:
		time = minf(time + delta, LENGTH)
	GameState.day_time = time
	var t := time / LENGTH
	var elev := lerpf(SUN_START_ELEV, SUN_END_ELEV, t)
	var sun_col := warm_start.lerp(warm_end, t)
	sun.rotation_degrees = Vector3(-elev, 35.0, 0.0)
	sun.light_color = sun_col
	sun.light_energy = lerpf(1.6, 0.15, smoothstep(0.55, 1.0, t))
	sky_mat.sky_top_color = Color(0.18, 0.32, 0.60).lerp(Color(0.05, 0.06, 0.16), t)
	sky_mat.sky_horizon_color = Color(0.95, 0.55, 0.25).lerp(Color(0.85, 0.35, 0.15), t)
	sky_mat.ground_horizon_color = Color(0.6, 0.4, 0.25).lerp(Color(0.30, 0.14, 0.08), t)
	env.ambient_light_energy = lerpf(0.45, 0.22, t)
	env.fog_light_energy = lerpf(0.4, 0.15, t)
	# dusk mist via classic fog (volumetric is opt-in; llvmpipe can't march it clean)
	env.fog_density = lerpf(0.004, 0.020, t)
	# keep volumetric fog modest: llvmpipe marchers go blocky above ~0.04
	env.volumetric_fog_density = lerpf(0.010, 0.035, t)
	env.volumetric_fog_albedo = Color(0.62, 0.60, 0.62).lerp(Color(0.45, 0.48, 0.62), t)
	var gust := clampf(0.5 + 0.5 * sin(time * 0.05), 0.5, 1.5)
	GameState.wind = (
		Vector3(0.7 + 0.5 * sin(time * 0.11), 0.0, 0.3 * sin(time * 0.07 + 1.3)).normalized() * gust
	)
	_modulate_audio(t)


func _modulate_audio(t: float) -> void:
	if audio_holder == null:
		return
	var e: AudioStreamPlayer3D = (
		audio_holder.get_meta("engine") if audio_holder.has_meta("engine") else null
	)
	if e != null:
		e.pitch_scale = clampf(0.85 + GameState.mower_velocity.length() / 8.0, 0.8, 1.6)
	var birds: AudioStreamPlayer3D = (
		audio_holder.get_meta("birds") if audio_holder.has_meta("birds") else null
	)
	var crick: AudioStreamPlayer3D = (
		audio_holder.get_meta("crickets") if audio_holder.has_meta("crickets") else null
	)
	if birds != null:
		birds.volume_db = lerpf(-10.0, -35.0, clampf((t - 0.5) * 2.0, 0.0, 1.0))
	if crick != null:
		crick.volume_db = lerpf(-40.0, -8.0, clampf((t - 0.55) * 2.5, 0.0, 1.0))


func set_time(t: float) -> void:
	time = clampf(t, 0.0, LENGTH)
