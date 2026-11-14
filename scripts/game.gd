class_name Game
extends Node3D
## Root of the match: score, clock, possession, down and distance. Wires the
## scene together and hands the shared Tuning resource to everything.

const DOWN_NAMES: Array[String] = ["1ST", "2ND", "3RD", "4TH"]

## Normal Engine.time_scale. Hit-stop returns to this (tests raise it).
static var base_time_scale: float = 1.0
## The next match opens with the pregame intro. The main menu sets it; the
## tests go straight to the kickoff.
static var show_intro: bool = false
## The team the person plays, picked on the team select: 0 home, 1 away.
## -1 leaves it to Team.is_human.
static var human_side: int = -1
## The league teams picked on the team select for home and away, as places in
## `league.teams`. -1 leaves the scene's own team.
static var team_picks: PackedInt32Array = PackedInt32Array([-1, -1])

@export var tuning: Tuning
## Every team there is to play as.
@export var league: League
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
## 1 or 2. `clock` counts down the half being played.
var half: int = 1
## The half (0 for none yet) in which the warning was given (Tuning.warning_time).
var warning_half: int = 0
## The play being lined up or run is the try after a touchdown.
var conversion: bool = false
## Team that receives the kickoff that is due, or null when none is.
var kickoff_to: Team
## A scramble is due: the ball goes up from midfield and both teams go for it.
## Each half opens with one (see the Scramble state).
var scramble_due: bool = false
## Message for the banner shown by the Turnover state.
var banner_text: String = ""
var stats: Dictionary[StringName, int] = {}
## Calls the plays for whichever side the CPU runs.
var play_caller: PlayCaller = PlayCaller.new()
## What each defense has seen the other offense do.
var scout: Scout = Scout.new()
## The box score: each team's and each player's numbers (see the pause menu).
var stat_book: StatBook = StatBook.new()

var _hit_stop_left: float = 0.0
## Team the camera sits behind, and the offense it was last set from.
var _camera_team: Team
var _camera_offense: Team

@onready var field: Field = $Field
@onready var home: Team = $HomeTeam
@onready var away: Team = $AwayTeam
@onready var ball: Ball = $Ball
@onready var play_controller: PlayController = $PlayController
@onready var human: HumanController = $HumanController
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: HUD = $HUD
@onready var audio: AudioDirector = $Audio


func _ready() -> void:
	if human_side >= 0:
		home.is_human = human_side == 0
		away.is_human = human_side == 1
	var sides: Array[Team] = [home, away]
	for i: int in sides.size():
		if league != null and team_picks[i] >= 0 and team_picks[i] < league.teams.size():
			sides[i].data = league.teams[team_picks[i]]
	home.white_kit = true
	home.setup(tuning, away)
	away.setup(tuning, home)
	stat_book.setup(home, away)
	field.setup(tuning, home, away)
	camera_rig.setup(tuning)
	human.setup(self)
	play_controller.setup(self)
	hud.setup(self)
	audio.setup(self)

	clock = tuning.game_length * 0.5
	scramble_due = true
	var opening: StringName = &"Intro" if show_intro and tuning.intro_enabled and not autoplay else &"Scramble"
	show_intro = false
	play_controller.state_machine.transition(opening)
	camera_rig.snap_to(_camera_target(), _camera_facing())
	# Up out of black, if the way in left it there.
	ScreenFade.of(get_tree()).reveal()


func _exit_tree() -> void:
	Engine.time_scale = base_time_scale


func _physics_process(delta: float) -> void:
	# A change of sides in the middle of a play (interception, lost fumble) swings
	# the camera round; between plays it cuts.
	camera_rig.follow(_camera_target(), _camera_facing(), delta, not play_controller.ball_dead)


func _process(delta: float) -> void:
	if _hit_stop_left > 0.0:
		# delta is scaled by the hit-stop itself; count down in real time.
		_hit_stop_left -= delta / maxf(Engine.time_scale, 0.0001) * base_time_scale
		if _hit_stop_left <= 0.0:
			Engine.time_scale = base_time_scale


## Puts the camera where it belongs at once, without the pan.
func snap_camera() -> void:
	camera_rig.snap_to(_camera_target(), _camera_facing())


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
	stat_book.begin_drive(team)


## The try after a touchdown is untimed.
func tick_clock(delta: float) -> void:
	if not conversion:
		clock = maxf(clock - delta, 0.0)


func is_time_up() -> bool:
	return clock <= 0.0


func award_touchdown(team: Team) -> void:
	team.score += tuning.touchdown_points
	stat_book.note_score()


## After a touchdown the scoring team gets one play from close in for two more.
func start_conversion(team: Team) -> void:
	conversion = true
	offense = team
	defense = team.opponent
	var dir: int = team.attack_dir
	los_x = tuning.goal_x(dir) - float(dir) * tuning.conversion_distance
	down = 1
	_set_first_down_target()
	add_stat(&"conversion_tries")


## Puts `receiving` in possession for a kickoff. The drive starts where the
## return ends.
func start_kickoff(receiving: Team) -> void:
	offense = receiving
	defense = receiving.opponent
	down = 1
	goal_to_go = false


## Nobody has the ball in a scramble, but the game needs an offense: the
## person's team, so the camera starts behind it, or either.
func start_scramble() -> void:
	var side: Team = home if randf() < 0.5 else away
	if human.is_active() and human.team != null:
		side = human.team
	offense = side
	defense = side.opponent
	down = 1
	goal_to_go = false


## Halftime is the full report, not just the banner.
func has_halftime_show() -> bool:
	return tuning.halftime_show_enabled and not autoplay


func start_second_half() -> void:
	half = 2
	clock = tuning.game_length * 0.5
	kickoff_to = null
	scramble_due = true


## Applies the result of a finished play and returns the next state.
func resolve_play(result: PlayController.Result, spot_x: float, final_team: Team) -> StringName:
	banner_text = ""
	if conversion:
		conversion = false
		if result == PlayController.Result.TOUCHDOWN:
			# The defense can run a turnover all the way back for two of its own.
			final_team.score += tuning.conversion_points
			stat_book.note_score()
			add_stat(&"conversions_made")
			audio.crowd_react(final_team, 0.8)
			audio.shout(&"announcer_trygood")
		else:
			audio.crowd_react(defense, 0.6)
			audio.shout(&"announcer_trymissed")
		kickoff_to = defense
		return next_play_state()
	if play_controller.scramble:
		if play_controller.scramble_team == null:
			# Out of bounds, or nobody could get hold of it: up it goes again.
			scramble_due = true
			add_stat(&"scramble_do_overs")
			banner_text = "DO-OVER!"
			return &"Turnover"
		var x: float = spot_x
		if _in_own_end_zone(final_team, x):
			x = tuning.yard_to_x(final_team.attack_dir, tuning.touchback_yard)
		var lost: bool = final_team != play_controller.scramble_team
		start_drive(final_team, x)
		if lost:
			add_stat(&"turnovers")
		banner_text = "FUMBLE!" if lost else "SCRAMBLE WON!"
		return &"Turnover"
	if play_controller.kickoff:
		var x: float = spot_x
		if _in_own_end_zone(final_team, x):
			x = tuning.yard_to_x(final_team.attack_dir, tuning.touchback_yard)
		var lost: bool = final_team != offense
		start_drive(final_team, x)
		if lost:
			add_stat(&"turnovers")
			banner_text = "FUMBLE!"
			return &"Turnover"
		return next_play_state()
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
				# The team that gave it up kicks off to the team that scored.
				var scorer: Team = defense
				scorer.score += tuning.safety_points
				stat_book.note_score()
				start_kickoff(scorer)
				kickoff_to = scorer
				add_stat(&"safeties")
				banner_text = "SAFETY!"
				return &"Turnover"
			los_x = clampf(spot_x, 1.0, tuning.field_length - 1.0)
			var dir: float = float(offense.attack_dir)
			if not goal_to_go and (los_x - first_down_x) * dir >= 0.0:
				down = 1
				_set_first_down_target()
				add_stat(&"first_downs")
				audio.crowd_react(offense, 0.5)
			else:
				down += 1

	if down > tuning.downs_per_series:
		start_drive(defense, los_x)
		add_stat(&"turnovers")
		banner_text = "TURNOVER ON DOWNS"
		return &"Turnover"
	return next_play_state()


## A half ends once its clock has run out and the play (and any try) is over.
## The warning comes after the play (and any try) that took the clock under
## Tuning.warning_time, before the next snap or kickoff.
func next_play_state() -> StringName:
	if is_time_up():
		return &"Halftime" if half == 1 else &"GameOver"
	if warning_due():
		return &"Warning"
	if scramble_due:
		return &"Scramble"
	return &"Kickoff" if kickoff_to != null else &"PlaySelect"


## The clock is under the warning time and this half has not had its warning.
func warning_due() -> bool:
	return tuning.warning_time > 0.0 and warning_half != half and clock <= tuning.warning_time and not conversion


## The offensive plays on offer for the next snap: the playbook, with the Hail
## Mary in the first play's place in either half's last Tuning.hail_mary_time
## seconds, but only from more than Tuning.hail_mary_min_distance yards out.
func offense_plays() -> Array[OffensePlay]:
	var plays: Array[OffensePlay] = offense_playbook.plays.duplicate()
	var hail_mary: OffensePlay = offense_playbook.hail_mary
	var to_goal: float = absf(tuning.goal_x(offense.attack_dir) - los_x)
	if hail_mary != null and not plays.is_empty() and not conversion \
			and clock <= tuning.hail_mary_time and to_goal > tuning.hail_mary_min_distance:
		plays[0] = hail_mary
	return plays


# --- Text for the HUD ------------------------------------------------------------

func down_text() -> String:
	if conversion:
		return "2-POINT TRY"
	if play_controller.scramble:
		return "SCRAMBLE"
	if play_controller.kickoff:
		return "KICKOFF"
	var ordinal: String = DOWN_NAMES[clampi(down - 1, 0, DOWN_NAMES.size() - 1)]
	if goal_to_go:
		return "%s & GOAL" % ordinal
	return "%s & %d" % [ordinal, yards_to_go()]


## Whole yards to the first-down line, never less than one.
func yards_to_go() -> int:
	return maxi(ceili(absf(first_down_x - los_x) - 0.01), 1)


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
	return "%s  %d:%02d" % ["1ST" if half == 1 else "2ND", minutes, seconds % 60]


func add_stat(key: StringName, amount: int = 1) -> void:
	var current: int = stats.get(key, 0)
	stats[key] = current + amount


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


## The camera follows the ball, except on a kickoff: there it waits behind the
## returner while the kick is in the air.
func _camera_target() -> Vector3:
	var pc: PlayController = play_controller
	if pc.kickoff and pc.returner != null and ball.carrier == null and pc.result == PlayController.Result.NONE:
		return Vector3(pc.returner.position.x, 0.0, pc.returner.position.z)
	# In a scramble the ball starts a long way from everybody: the camera stays
	# behind the person's player until somebody has it.
	if pc.scramble_open() and pc.result == PlayController.Result.NONE and human.controlled != null:
		return Vector3(human.controlled.position.x, 0.0, human.controlled.position.z)
	# After a score it stays on the scorer, wherever the spiked ball bounces to.
	if pc.ball_dead and pc.scorer != null:
		return Vector3(pc.scorer.position.x, 0.0, pc.scorer.position.z)
	return ball.flat_position()


## The camera sits behind the team with the ball, looking the way it attacks, so
## on defense the person plays toward the camera. That is the offense until the
## other team comes up with the ball in the middle of a play; from then on it is
## that team, through the whistle and into its drive.
func _camera_facing() -> float:
	if offense == null:
		return 1.0
	if offense != _camera_offense:
		_camera_offense = offense
		_camera_team = offense
	if not play_controller.ball_dead and ball.carrier != null:
		_camera_team = ball.carrier.team
	return float(_camera_team.attack_dir)
