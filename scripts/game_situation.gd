class_name GameSituation
extends RefCounted
## What the score and the clock ask of the offense on the play about to be
## called. Down and distance are not in here: PlayCaller reads those itself.

## Plays that still fit in the half, counting this one.
var plays_left: float = 99.0
## Offense's score minus the defense's.
var margin: int = 0
## Yards from the line of scrimmage to the end zone.
var to_goal: float = 0.0
## 0..1: how much the clock forces the offense to throw downfield.
var urgency: float = 0.0
## 0..1: how much a leading offense wants to run the clock out.
var clock_kill: float = 0.0
## Last play, points needed and too far out for anything but a long throw.
var heave: bool = false


## `play_time` is how many seconds of clock a play takes on average.
static func read(game: Game, play_time: float) -> GameSituation:
	var now: GameSituation = GameSituation.new()
	if game.offense == null or game.defense == null:
		return now
	var tuning: Tuning = game.tuning
	now.margin = game.offense.score - game.defense.score
	now.to_goal = absf(tuning.goal_x(game.offense.attack_dir) - game.los_x)
	# The try after a touchdown is untimed and worth the same whatever the score.
	# So is sudden death: there is no clock to beat or to run out.
	if game.conversion or game.overtime:
		return now
	now.plays_left = game.clock / maxf(play_time, 0.5)

	var last_half: bool = game.half >= 2
	if last_half and now.margin > 0:
		now.clock_kill = clampf(1.0 - (now.plays_left - 1.0) / maxf(tuning.ai_call_kill_plays - 1.0, 1.0), 0.0, 1.0)
		return now

	# Points are needed (second half) or there for the taking (first half)
	# before this clock runs out. Two scores behind, the same clock also has to
	# hold a stop and another drive, so each drive gets a share of it.
	var legs: float = 1.0
	if last_half:
		var possessions: float = ceilf(float(-now.margin) / float(tuning.touchdown_points + tuning.conversion_points))
		legs = 2.0 * maxf(possessions, 1.0) - 1.0
	var snaps: float = maxf(now.plays_left / legs, 1.0)
	var normal: float = tuning.yards_to_gain / float(tuning.downs_per_series)
	var pace: float = now.to_goal / snaps / maxf(normal, 0.1)
	now.urgency = clampf(inverse_lerp(tuning.ai_call_calm_pace, tuning.ai_call_urgent_pace, pace), 0.0, 1.0)
	if now.margin > 0:
		now.urgency *= tuning.ai_call_half_urgency_leading
	else:
		now.heave = now.plays_left <= tuning.ai_call_last_play and now.to_goal > tuning.ai_call_heave_distance
	return now
