extends GameState
## The opening of the broadcast, before the first kickoff of a match started
## from the main menu: the teams stand ready for the kick, the camera comes
## down over the field, and Jim and Tony say how much they are looking forward
## to it. (A) skips it.

## Seconds before a press of (A) counts: the one that started the match is
## still on its way up.
const SKIP_AFTER: float = 0.5
## Where the camera starts and ends, from the ball on its tee: x behind the
## kicking team, z out past the sideline. It looks at AIM, a little way down
## the field, so the kickers fill the picture with the returners beyond them.
const CAMERA_FROM: Vector3 = Vector3(-38.0, 24.0, 54.0)
const CAMERA_TO: Vector3 = Vector3(-12.0, 4.5, 25.0)
const AIM: Vector3 = Vector3(9.0, 1.5, 0.0)

## The booth has been asked to speak, and had something to say.
var _asked: bool = false
var _talking: bool = false
## Seconds since the last word.
var _quiet: float = 0.0


func enter() -> void:
	_asked = false
	_talking = false
	_quiet = 0.0
	game.start_kickoff(game.opening_receiver)
	pc.line_up_kickoff()
	_place_camera(true)
	game.hud.set_hint("")
	game.hud.show_intro()
	if not game.audio.play_music(&"music_open"):
		game.audio.play(&"intro_sting", 0.8)


func exit() -> void:
	game.audio.stop_music()
	game.camera_rig.end_shot()
	game.hud.hide_intro()


func physics_update(delta: float) -> void:
	var tuning: Tuning = game.tuning
	_place_camera(false)
	if not _asked and time_in_state >= tuning.intro_voice_delay:
		_asked = true
		_talking = game.audio.intro()

	var done: bool = time_in_state >= tuning.intro_max_time
	if _asked and _talking:
		_quiet = 0.0 if game.audio.booth_busy() else _quiet + delta
		done = done or (_quiet >= tuning.intro_tail and time_in_state >= tuning.intro_min_time)
	elif _asked:
		done = done or time_in_state >= tuning.intro_silent_time
	if time_in_state >= SKIP_AFTER and Input.is_action_just_pressed(&"confirm"):
		game.audio.hush()
		done = true
	if done:
		machine.transition(&"Kickoff")


## A crane move: down and in toward the field, quick at first and then
## settling, so most of the intro is spent close to the players.
func _place_camera(cut: bool) -> void:
	var tuning: Tuning = game.tuning
	var tee: Vector3 = Vector3(pc.los_x, 0.0, 0.0)
	# Mirrored when the kick goes the other way.
	var along: Vector3 = Vector3(float(game.defense.attack_dir), 1.0, 1.0)
	var t: float = clampf(time_in_state / maxf(tuning.intro_shot_time, 0.1), 0.0, 1.0)
	var eye: Vector3 = tee + CAMERA_FROM.lerp(CAMERA_TO, ease(t, 0.4)) * along
	game.camera_rig.shot(eye, tee + AIM * along, cut)
