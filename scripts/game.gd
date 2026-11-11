class_name Game
extends Node3D
## Root of the match: score, clock, possession, down and distance. Wires the
## scene together and hands the shared Tuning resource to everything.

const DOWN_NAMES: Array[String] = ["1ST", "2ND", "3RD", "4TH"]

## Normal Engine.time_scale. Hit-stop returns to this (tests raise it).
static var base_time_scale: float = 1.0

@export var tuning: Tuning
@export var offense_playbook: OffensePlaybook
@export var defense_playbook: DefensePlaybook
## CPU plays both teams. Used by the headless smoke test; also a handy attract mode.
@export var autoplay: bool = false

var offense: Team
var defense: Team
var down: int = 1
var los_x: float = 0.0
var first_down_x: float = 0.0
var goal_to_go: bool = false
var clock: float = 0.0
## Message for the banner shown by the Turnover state.
var banner_text: String = ""
var stats: Dictionary[StringName, int] = {}
## Calls the plays for whichever side the CPU runs.
var play_caller: PlayCaller = PlayCaller.new()

var _hit_stop_left: float = 0.0

@onready var field: Field = $Field
@onready var home: Team = $HomeTeam
@onready var away: Team = $AwayTeam
@onready var ball: Ball = $Ball
@onready var play_controller: PlayController = $PlayController
@onready var human: HumanController = $HumanController
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: HUD = $HUD


func _ready() -> void:
	home.setup(tuning, away)
	away.setup(tuning, home)
	field.setup(tuning, home, away)
	camera_rig.setup(tuning)
	human.setup(self)
	play_controller.setup(self)
	hud.setup(self)

	clock = tuning.game_length
	var first: Team = home if home.is_human or not away.is_human else away
	start_drive(first, tuning.yard_to_x(first.attack_dir, tuning.drive_start_yard))
	play_controller.state_machine.transition(&"PlaySelect")
	camera_rig.snap_to(_camera_target(), _camera_facing())


func _exit_tree() -> void:
	Engine.time_scale = base_time_scale


func _physics_process(delta: float) -> void:
	camera_rig.follow(_camera_target(), _camera_facing(), delta)


func _process(delta: float) -> void:
	if _hit_stop_left > 0.0:
		# delta is scaled by the hit-stop itself; count down in real time.
		_hit_stop_left -= delta / maxf(Engine.time_scale, 0.0001) * base_time_scale
		if _hit_stop_left <= 0.0:
			Engine.time_scale = base_time_scale


# --- Feel ------------------------------------------------------------------------

## Camera shake plus a brief hit-stop. `stop_scale` scales the hit-stop length.
func impact(shake: float, stop_scale: float) -> void:
	camera_rig.add_trauma(shake)
	var duration: float = tuning.hit_stop_time * stop_scale
	if duration <= 0.0:
		return
	_hit_stop_left = maxf(_hit_stop_left, duration)
	Engine.time_scale = base_time_scale * tuning.hit_stop_time_scale


# --- Drive bookkeeping -----------------------------------------------------------

func start_drive(team: Team, x: float) -> void:
	offense = team
	defense = team.opponent
	los_x = clampf(x, 1.0, tuning.field_length - 1.0)
	down = 1
	_set_first_down_target()
	add_stat(&"drives")


func tick_clock(delta: float) -> void:
	clock = maxf(clock - delta, 0.0)


func is_time_up() -> bool:
	return clock <= 0.0


func award_touchdown(team: Team) -> void:
	team.score += tuning.touchdown_points


## After a touchdown the other team gets the ball.
func start_drive_after_score(scoring_team: Team) -> void:
	var next: Team = scoring_team.opponent
	start_drive(next, tuning.yard_to_x(next.attack_dir, tuning.drive_start_yard))


## Applies the result of a finished play and returns the next state.
func resolve_play(result: PlayController.Result, spot_x: float, final_team: Team) -> StringName:
	banner_text = ""
	match result:
		PlayController.Result.INCOMPLETE:
			down += 1
		PlayController.Result.TACKLED, PlayController.Result.OUT_OF_BOUNDS:
			if final_team != offense:
				# Interception or fumble return ended here.
				var x: float = spot_x
				if _in_own_end_zone(final_team, x):
					x = tuning.yard_to_x(final_team.attack_dir, tuning.touchback_yard)
				start_drive(final_team, x)
				add_stat(&"turnovers")
				banner_text = "FUMBLE!" if play_controller.was_fumble else "INTERCEPTION!"
				return &"Turnover"
			if _in_own_end_zone(offense, spot_x):
				var scorer: Team = defense
				scorer.score += tuning.safety_points
				start_drive(scorer, tuning.yard_to_x(scorer.attack_dir, tuning.drive_start_yard))
				banner_text = "SAFETY!"
				return &"Turnover"
			los_x = clampf(spot_x, 1.0, tuning.field_length - 1.0)
			var dir: float = float(offense.attack_dir)
			if not goal_to_go and (los_x - first_down_x) * dir >= 0.0:
				down = 1
				_set_first_down_target()
				add_stat(&"first_downs")
			else:
				down += 1

	if down > tuning.downs_per_series:
		start_drive(defense, los_x)
		add_stat(&"turnovers")
		banner_text = "TURNOVER ON DOWNS"
		return &"Turnover"
	return next_play_state()


func next_play_state() -> StringName:
	return &"GameOver" if is_time_up() else &"PlaySelect"


# --- Text for the HUD ------------------------------------------------------------

func down_text() -> String:
	var ordinal: String = DOWN_NAMES[clampi(down - 1, 0, DOWN_NAMES.size() - 1)]
	if goal_to_go:
		return "%s & GOAL" % ordinal
	return "%s & %d" % [ordinal, maxi(ceili(absf(first_down_x - los_x) - 0.01), 1)]


func ball_on_text() -> String:
	var from_own_goal: float = absf(los_x - tuning.own_goal_x(offense.attack_dir))
	var yard: int = roundi(from_own_goal)
	var half: int = roundi(tuning.field_length * 0.5)
	if yard == half:
		return "MIDFIELD"
	if yard < half:
		return "OWN %d" % yard
	return "OPP %d" % (roundi(tuning.field_length) - yard)


func clock_text() -> String:
	var seconds: int = ceili(clock)
	@warning_ignore("integer_division")
	var minutes: int = seconds / 60
	return "%d:%02d" % [minutes, seconds % 60]


func add_stat(key: StringName) -> void:
	var current: int = stats.get(key, 0)
	stats[key] = current + 1


func get_stat(key: StringName) -> int:
	var value: int = stats.get(key, 0)
	return value


# --- Internals -------------------------------------------------------------------

func _set_first_down_target() -> void:
	var dir: int = offense.attack_dir
	var goal: float = tuning.goal_x(dir)
	var target: float = los_x + float(dir) * tuning.yards_to_gain
	goal_to_go = (target - goal) * float(dir) >= 0.0
	first_down_x = goal if goal_to_go else target


func _in_own_end_zone(team: Team, x: float) -> bool:
	return (x - tuning.own_goal_x(team.attack_dir)) * float(team.attack_dir) <= 0.0


## The camera always follows the ball.
func _camera_target() -> Vector3:
	return ball.flat_position()


## The camera always sits behind the offense, looking the way it attacks, so on
## defense the person plays toward the camera.
func _camera_facing() -> float:
	return float(offense.attack_dir) if offense != null else 1.0
