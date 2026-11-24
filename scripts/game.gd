class_name Game
extends Node3D
## Root of the match: score, clock, possession, down and distance. Wires the
## scene together and hands the shared Tuning resource to everything.

const DOWN_NAMES: Array[String] = ["1ST", "2ND", "3RD", "4TH"]

## OFFLINE: the match is played on this machine, as ever. SERVER: this is the
## server of an online match, and both teams are played by people whose buttons
## come in over the network (see NetServer). CLIENT: this is a person's machine
## in an online match; nothing is decided here, the match is drawn as the
## server tells it (see NetView).
enum NetMode { OFFLINE, SERVER, CLIENT }

## Normal Engine.time_scale. Hit-stop returns to this (tests raise it).
static var base_time_scale: float = 1.0
## The next match opens with the pregame intro. The main menu sets it; the
## tests go straight to the kickoff.
static var show_intro: bool = false
## The team the person plays, picked on the team select: 0 home, 1 away.
## -1 leaves it to Team.is_human.
static var human_side: int = -1
## Two people play, one team each: player one the team of `human_side` (home
## when that is not set), player two the other. Each on their own gamepad (see
## Controllers). The team select sets it.
static var two_players: bool = false
## The league teams picked on the team select for home and away, as places in
## `league.teams`. -1 leaves the scene's own team.
static var team_picks: PackedInt32Array = PackedInt32Array([-1, -1])
## The match is a game of the season (Season.current): its result is booked at
## the final whistle, the booth tells its stories and talks about the table,
## and the way out leads back to the season. The season's screen sets it.
static var season_match: bool = false
## What this match is to the network. NetServer sets it.
static var net_mode: NetMode = NetMode.OFFLINE
## On the server: the buttons of each person, by seat, as the network brings them.
static var remote_pads: Array[PadInput] = []

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
## Sudden death: the second half ended level, and the next score wins. The
## clock stays at zero.
var overtime: bool = false
## Team that receives the kickoff that is due, or null when none is.
var kickoff_to: Team
## Team that received the opening kickoff. The other one gets the second half's.
var opening_receiver: Team
## The kickoff that is due opens a half or sudden death, and the booth has a
## word for it. Cleared once it has been kicked.
var opening_kickoff: bool = false
## Message for the banner shown by the Turnover state.
var banner_text: String = ""
var stats: Dictionary[StringName, int] = {}
## Calls the plays for whichever side the CPU runs.
var play_caller: PlayCaller = PlayCaller.new()
## The plays the coach advised the person on the play-select screen for the
## down being played (PlayCaller.coach_offense or coach_defense). The audible
## menu at the line takes its plays from them. Written by PlaySelectState for
## every down; empty with nobody playing.
var coach_plays: Array[Resource] = []
## What each defense has seen the other offense do.
var scout: Scout = Scout.new()
## The box score: each team's and each player's numbers (see the pause menu).
var stat_book: StatBook = StatBook.new()
## In a game of the season: its round (see Season), as it was at the start.
## The season itself moves on at the final whistle. -1 in an exhibition.
var season_round: int = -1

## Shakes the gamepad of each person playing.
var rumble: Rumble = Rumble.new()
## The people playing, player one first: one against the CPU, two against each
## other, nobody in autoplay. `human` is the first of them (and there with no
## team when nobody plays).
var humans: Array[HumanController] = []
## Draws a play on the turf before the snap (LT and the stick).
var play_art: PlayArt
## Debug builds: tries out a network delay offline (F9, F10). Null otherwise.
var net_feel: NetFeel

var _hit_stop_left: float = 0.0
## Team the camera sits behind, and the offense it was last set from.
var _camera_team: Team
var _camera_offense: Team
## Set while the turnover-on-downs banner is up: the camera stays where the play
## ended and only goes round behind the new offense when the next play is set up.
var hold_camera_side: bool = false

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
	if season() != null:
		season_round = season().current_round()
	if two_players:
		home.is_human = true
		away.is_human = true
	elif human_side >= 0:
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
	field.stadium.watch(self)
	ball.ground_at = field.stadium.surface_height
	ball.wall_normal_at = func(x: float, z: float) -> Vector3: return Stadium.wall_normal(tuning, x, z)
	camera_rig.setup(tuning)
	_seat_people()
	play_controller.setup(self)
	add_child(rumble)
	rumble.setup(self)
	hud.setup(self)
	audio.setup(self)
	var hole_debug: HoleDebug = HoleDebug.new()
	hole_debug.setup(self)
	add_child(hole_debug)
	play_art = PlayArt.new()
	play_art.setup(self)
	add_child(play_art)
	if OS.is_debug_build():
		net_feel = NetFeel.new()
		add_child(net_feel)
		net_feel.setup(self)

	clock = tuning.game_length * 0.5
	opening_receiver = home if randf() < 0.5 else away
	kickoff_to = opening_receiver
	opening_kickoff = true
	var opening: StringName = &"Intro" if show_intro and tuning.intro_enabled and not autoplay else &"Kickoff"
	show_intro = false
	if net_mode != NetMode.CLIENT:
		play_controller.state_machine.transition(opening)
	camera_rig.snap_to(_camera_target(), _camera_facing())
	# Up out of black, if the way in left it there.
	ScreenFade.of(get_tree()).reveal()


func _exit_tree() -> void:
	Engine.time_scale = base_time_scale
	Controllers.of(get_tree()).leave_match(self)


## The half of the screen that is `person`'s for what each of two people has
## of their own (play select, the menus at the line): 0 the left one, the home
## team's, and 1 the right one. Always 0 with one person playing.
func screen_slot(person: HumanController) -> int:
	return 1 if humans.size() > 1 and person.team == away else 0


## Gives each team a person plays its HumanController and that person's buttons.
func _seat_people() -> void:
	var controllers: Controllers = Controllers.of(get_tree())
	var playing: Array[Team] = []
	if not autoplay:
		if two_players:
			playing.assign([away, home] if human_side == 1 else [home, away])
		else:
			for team: Team in [home, away]:
				if team.is_human:
					playing = [team]
	humans.clear()
	for seat: int in playing.size():
		var person: HumanController = human
		if seat > 0:
			person = HumanController.new()
			person.name = "HumanController%d" % (seat + 1)
			add_child(person)
		var pad: PadInput = controllers.input_for(seat) if two_players else controllers.any
		if net_mode == NetMode.SERVER and seat < remote_pads.size():
			pad = remote_pads[seat]
		person.setup(self, playing[seat], pad, seat)
		humans.append(person)
	if humans.is_empty():
		human.setup(self, null, controllers.any)
		humans.append(human)
	controllers.enter_match(self)


func _physics_process(delta: float) -> void:
	# A change of sides in the middle of a play (interception, lost fumble) swings
	# the camera round; between plays it cuts.
	if not autoplay and Input.is_action_just_pressed(&"camera_view"):
		camera_rig.toggle_view()
	camera_rig.keep_in_view(_camera_must_see())
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
	# The server's clock is both people's: it does not stop for a hit.
	if duration <= 0.0 or net_mode == NetMode.SERVER:
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
	if not conversion and not overtime:
		clock = maxf(clock - delta, 0.0)


func is_time_up() -> bool:
	return clock <= 0.0


## The clock has run out with the ball still live, and `team` has nothing to
## lose by keeping it alive: any score counts before the half, and at the end
## of the game the team that is behind needs one.
func last_gasp(team: Team) -> bool:
	if conversion or overtime or not is_time_up():
		return false
	return half < 2 or team.score < team.opponent.score


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


## Halftime is the full report, not just the banner.
func has_halftime_show() -> bool:
	return tuning.halftime_show_enabled and not autoplay


## The second half's kickoff goes to the team that kicked off the first.
func start_second_half() -> void:
	half = 2
	clock = tuning.game_length * 0.5
	kickoff_to = opening_receiver.opponent
	opening_kickoff = true


## The second half ended level: a kickoff to either team, and the first score
## of any kind wins.
func start_overtime() -> void:
	overtime = true
	conversion = false
	kickoff_to = home if randf() < 0.5 else away
	opening_kickoff = true
	add_stat(&"overtimes")


func is_tied() -> bool:
	return home.score == away.score


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
		PlayController.Result.TACKLED, PlayController.Result.OUT_OF_PLAY:
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
		hold_camera_side = true
		return &"Turnover"
	return next_play_state()


## A half ends once its clock has run out and the play (and any try) is over.
## The warning comes after the play (and any try) that took the clock under
## Tuning.warning_time, before the next snap or kickoff. Nobody ties: a second
## half that ends level goes to sudden death, which lasts until the scores differ.
func next_play_state() -> StringName:
	if is_time_up():
		if half == 1:
			return &"Halftime"
		if not is_tied():
			return &"GameOver"
		if not overtime:
			return &"Overtime"
	if warning_due():
		return &"Warning"
	return &"Kickoff" if kickoff_to != null else &"PlaySelect"


## The clock is under the warning time and this half has not had its warning.
func warning_due() -> bool:
	return tuning.warning_time > 0.0 and warning_half != half and clock <= tuning.warning_time and not conversion and not overtime


# --- Text for the HUD ------------------------------------------------------------

func down_text() -> String:
	if conversion:
		return "2-POINT TRY"
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
	if overtime:
		return half_text()
	return "%s  %s" % [half_text(), time_text()]


## The half being played, or sudden death.
func half_text() -> String:
	if overtime:
		return "OT"
	return "1ST" if half == 1 else "2ND"


## What is left of the half. Nothing in sudden death, which has no clock.
func time_text() -> String:
	if overtime:
		return ""
	var seconds: int = ceili(clock)
	@warning_ignore("integer_division")
	var minutes: int = seconds / 60
	return "%d:%02d" % [minutes, seconds % 60]


## A game of the season's playoffs: the semifinal or the final.
func is_playoff() -> bool:
	return season_round >= Season.WEEKS


## The season this match is a game of, or null: an exhibition, or a test.
func season() -> Season:
	return Season.current if season_match and not autoplay else null


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
## returner while the kick is in the air. Before the snap the close view stands
## behind the quarterback.
func _camera_target() -> Vector3:
	var pc: PlayController = play_controller
	if pc.kickoff and pc.returner != null and ball.carrier == null and pc.result == PlayController.Result.NONE:
		return Vector3(pc.returner.position.x, 0.0, pc.returner.position.z)
	# After a score it stays on the scorer, wherever the spiked ball bounces to.
	if pc.ball_dead and pc.scorer != null:
		return Vector3(pc.scorer.position.x, 0.0, pc.scorer.position.z)
	# The close view starts behind the quarterback: with the ball on the line he
	# would stand under the camera's lower edge.
	if CameraRig.view == CameraRig.View.CLOSE and pc.ball_dead and pc.result == PlayController.Result.NONE and not pc.kickoff and pc.qb != null:
		return Vector3(pc.qb.position.x, 0.0, pc.qb.position.z)
	return ball.flat_position()


## Who has to be in the picture: the person's quarterback and the receivers he
## can throw to, from the line-up until the ball leaves his hands, however far
## to one side he rolls out. Nobody on a run play once it is snapped, on a kickoff
## or when the CPU has the ball.
func _camera_must_see() -> Array[Vector3]:
	var pc: PlayController = play_controller
	var spots: Array[Vector3] = []
	if pc.qb == null or pc.kickoff or pc.qb.team.human == null:
		return spots
	var before_snap: bool = pc.ball_dead and pc.result == PlayController.Result.NONE
	var in_pocket: bool = not pc.ball_dead and pc.phase == PlayController.Phase.POCKET and ball.carrier == pc.qb and not pc.off_play.is_run
	if before_snap or in_pocket:
		spots.append(pc.qb.position + Vector3.UP)
		for receiver: Player in pc.eligible:
			spots.append(receiver.position + Vector3.UP)
	return spots


## The camera sits behind the team with the ball, looking the way it attacks, so
## on defense the person plays toward the camera. That is the offense until the
## other team comes up with the ball in the middle of a play; from then on it is
## that team, through the whistle and into its drive.
func _camera_facing() -> float:
	if offense == null:
		return 1.0
	if offense != _camera_offense and not hold_camera_side:
		_camera_offense = offense
		_camera_team = offense
	if not play_controller.ball_dead and ball.carrier != null:
		_camera_team = ball.carrier.team
	return float(_camera_team.attack_dir)
