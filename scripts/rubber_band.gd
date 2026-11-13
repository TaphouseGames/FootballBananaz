class_name RubberBand
extends RefCounted
## Comeback assist. When one team is well ahead, the team behind gets a small
## edge on its luck rolls (catches, picks, broken tackles, fumbles) and the
## team ahead loses a smaller one. Nothing inside one score; above that it
## grows smoothly with the gap up to a hard cap. Nothing on screen shows it.
## See the "Comeback assist" group in Tuning.


## 0..1: how hard the assist works at a `gap`-point margin. `late` (0..1) is
## how far into the late-game window the game is; it makes the assist kick in
## sooner but never past the cap.
static func strength_for(gap: int, late: float, tuning: Tuning) -> float:
	if not tuning.comeback_enabled or gap <= tuning.comeback_dead_zone:
		return 0.0
	var span: float = maxf(tuning.comeback_full_gap - tuning.comeback_dead_zone, 1.0)
	var t: float = clampf((gap - tuning.comeback_dead_zone) / span, 0.0, 1.0)
	var s: float = t * t * (3.0 - 2.0 * t)
	s *= lerpf(1.0, tuning.comeback_late_scale, clampf(late, 0.0, 1.0))
	return clampf(s, 0.0, 1.0)


## Signed modifier for a team leading by `margin` points (negative = trailing):
## +comeback_max_boost at most for the team behind, -comeback_max_penalty at
## most for the team ahead.
static func modifier_for(margin: int, late: float, tuning: Tuning) -> float:
	var s: float = strength_for(absi(margin), late, tuning)
	if s <= 0.0:
		return 0.0
	if margin < 0:
		return tuning.comeback_max_boost * s
	if margin > 0:
		return -tuning.comeback_max_penalty * s
	return 0.0


## How far into the late-game window the match is (0..1): only in the second
## half, over its last comeback_late_plays plays' worth of clock.
static func lateness(game: Game) -> float:
	var tuning: Tuning = game.tuning
	if game.half < 2 or tuning.comeback_late_plays <= 0.0:
		return 0.0
	var plays_left: float = game.clock / maxf(game.play_caller.play_time(game), 0.5)
	return clampf(1.0 - plays_left / tuning.comeback_late_plays, 0.0, 1.0)


static func strength(game: Game) -> float:
	return strength_for(absi(game.home.score - game.away.score), lateness(game), game.tuning)


## The modifier for `team` as the game stands.
static func modifier(team: Team, game: Game) -> float:
	if team == null or team.opponent == null:
		return 0.0
	return modifier_for(team.score - team.opponent.score, lateness(game), game.tuning)


## Multiplier for something good for `team` (a catch).
static func good(team: Team, game: Game) -> float:
	return 1.0 + modifier(team, game)


## Multiplier for something bad for `team` (a pick it throws, a tackle on its
## carrier, a fumble).
static func bad(team: Team, game: Game) -> float:
	return 1.0 - modifier(team, game)
