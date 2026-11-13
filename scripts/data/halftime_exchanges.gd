class_name HalftimeExchanges
extends RefCounted
## What Jim and Tony say to each other on the halftime report, and which of it
## fits the half just played.
##
## Each exchange has an `id`, the condition (`when`) under which it can come up,
## a `priority`, who speaks `first`, and its `lines`, which the two say turn
## about. The lines are recorded as `assets/audio/show_<id>_<n>.ogg`; an
## exchange without a recording of every line is passed over until it has them.
## The ones with `when` ALWAYS are the non sequiturs: they fill in when the
## half gave the booth nothing to talk about, and now and then come up anyway.
##
## To add one: a row here, its files in assets/audio, and if it needs a new
## condition a line in passes().

const ALWAYS: StringName = &"always"
const JIM: StringName = &"jim"
const TONY: StringName = &"tony"

const EXCHANGES: Array[Dictionary] = [
	{&"id": &"comeback", &"when": &"comeback", &"priority": 5, &"first": TONY, &"lines": [
		"They were DEAD, Jim! DEAD AND BURIED!",
		"And now it's a one-score game.",
		"Nobody tell them they were DEAD!"]},
	{&"id": &"blowout_1", &"when": &"blowout", &"priority": 4, &"first": JIM, &"lines": [
		"Tony, this one's getting ugly.",
		"UGLY? Jim, I've seen prettier CAR WRECKS!",
		"And we've got a whole half left."]},
	{&"id": &"blowout_2", &"when": &"blowout", &"priority": 4, &"first": TONY, &"lines": [
		"Jim, is there a MERCY RULE?",
		"There is not.",
		"Then somebody call their MOTHERS!"]},
	{&"id": &"shutout", &"when": &"shutout", &"priority": 4, &"first": JIM, &"lines": [
		"A big goose egg on the board, Tony.",
		"ZERO, Jim! I've had more points on my LICENSE!"]},
	{&"id": &"star_1", &"when": &"star", &"priority": 4, &"first": TONY, &"lines": [
		"One guy is doing EVERYTHING out there, Jim!",
		"Two touchdowns already.",
		"Give the man a RAISE!"]},
	{&"id": &"star_2", &"when": &"star", &"priority": 4, &"first": JIM, &"lines": [
		"Two scores for one player already, Tony.",
		"The rest of the team should send him a FRUIT BASKET!"]},
	{&"id": &"turnovers", &"when": &"turnovers", &"priority": 3, &"first": JIM, &"lines": [
		"Turnovers everywhere in this half, Tony.",
		"It's a BAKERY out there, Jim!",
		"Please never say that again."]},
	{&"id": &"late_hits", &"when": &"late_hits", &"priority": 3, &"first": JIM, &"lines": [
		"A lot of hitting after the whistle, Tony.",
		"The whistle is a SUGGESTION, Jim!",
		"It is not."]},
	{&"id": &"slugfest", &"when": &"slugfest", &"priority": 3, &"first": JIM, &"lines": [
		"Not a lot of points in this one, Tony.",
		"DEFENSE, Jim! Or two really bad offenses!"]},
	{&"id": &"possession", &"when": &"possession", &"priority": 2, &"first": TONY, &"lines": [
		"One team has had the ball ALL HALF, Jim!",
		"The other defense is exhausted.",
		"I'm exhausted WATCHING them!"]},
	{&"id": &"air_show", &"when": &"air_show", &"priority": 2, &"first": JIM, &"lines": [
		"They are throwing it all over the yard, Tony.",
		"Somebody tell the running backs they can go HOME!"]},
	{&"id": &"ground_game", &"when": &"ground_game", &"priority": 2, &"first": TONY, &"lines": [
		"RUN, RUN, RUN! Nobody's throwing the ball, Jim!",
		"Why would they? It's working.",
		"My GRANDFATHER loves this game!"]},
	{&"id": &"close_1", &"when": &"close", &"priority": 2, &"first": JIM, &"lines": [
		"Three points or less at the half, Tony.",
		"I can't feel my HANDS, Jim!"]},
	{&"id": &"close_2", &"when": &"close", &"priority": 2, &"first": TONY, &"lines": [
		"Nobody wants to LOSE this thing, Jim!",
		"Technically, nobody's winning it either.",
		"That's what makes it GREAT!"]},
	{&"id": &"long_run", &"when": &"long_run", &"priority": 2, &"first": JIM, &"lines": [
		"How about that long run, Tony?",
		"He's STILL running, Jim! Somebody check the PARKING LOT!"]},
	{&"id": &"dives", &"when": &"dives", &"priority": 1, &"first": TONY, &"lines": [
		"These guys are diving ALL OVER the place, Jim!",
		"It's football, not a swim meet.",
		"Tell THEM that!"]},
	{&"id": &"replay_button", &"when": ALWAYS, &"priority": 0, &"first": JIM, &"lines": [
		"Tony, you're sitting on the replay button.",
		"THAT'S why this half felt so LONG!"]},
	{&"id": &"snack", &"when": ALWAYS, &"priority": 0, &"first": TONY, &"lines": [
		"Jim, try this! Nacho cheese on a BANANA!",
		"No.",
		"MORE FOR ME!"]},
	{&"id": &"bees", &"when": ALWAYS, &"priority": 0, &"first": TONY, &"lines": [
		"Jim, I think the ball is FILLED WITH BEES!",
		"It's filled with air, Tony.",
		"That's what the BEES want you to think!"]},
	{&"id": &"bird", &"when": ALWAYS, &"priority": 0, &"first": JIM, &"lines": [
		"There's a bird on the field, Tony.",
		"He's WIDE OPEN, Jim! THROW IT TO THE BIRD!"]},
	{&"id": &"coffee", &"when": ALWAYS, &"priority": 0, &"first": JIM, &"lines": [
		"Tony, that's my coffee.",
		"It was DELICIOUS, Jim!",
		"It was soup."]},
	{&"id": &"pizza", &"when": ALWAYS, &"priority": 0, &"first": TONY, &"lines": [
		"Jim, how long is halftime?",
		"About ten seconds.",
		"TEN SECONDS? I just ordered a PIZZA!"]},
]

## The exchange heard last, in this match or the one before.
static var _last_id: StringName = &""


## What the booth knows about the game so far. The keys are the ones passes() reads.
static func facts(game: Game) -> Dictionary[StringName, float]:
	var book: StatBook = game.stat_book
	var home: TeamLine = book.team_line(game.home)
	var away: TeamLine = book.team_line(game.away)
	var tuning: Tuning = game.tuning
	var comeback: bool = false
	for team: Team in [game.home, game.away]:
		var behind: int = team.opponent.score - team.score
		if book.team_line(team).max_deficit >= tuning.halftime_comeback_from and behind <= tuning.halftime_comeback_to:
			comeback = true
	var clock: float = home.possession + away.possession
	return {
		&"margin": float(absi(game.home.score - game.away.score)),
		&"points": float(game.home.score + game.away.score),
		&"low_score": float(mini(game.home.score, game.away.score)),
		&"comeback": float(comeback),
		&"possession_share": maxf(home.possession, away.possession) / clock if clock > 0.0 else 0.5,
		&"pass_yds": float(home.net_pass_yds() + away.net_pass_yds()),
		&"rush_yds": float(home.rush_yds + away.rush_yds),
		&"turnovers": float(home.turnovers() + away.turnovers()),
		&"fumbles": float(home.fumbles + away.fumbles),
		&"late_hits": float(home.late_hits + away.late_hits),
		&"dives": float(home.dives + away.dives),
		&"long_run": float(maxi(book.longest_run(game.home), book.longest_run(game.away))),
		&"top_tds": float(maxi(book.top_scorer_tds(game.home), book.top_scorer_tds(game.away))),
	}


## The condition `when` holds for a game with these `facts`.
static func passes(when: StringName, facts: Dictionary[StringName, float], tuning: Tuning) -> bool:
	var margin: float = facts.get(&"margin", 0.0)
	var points: float = facts.get(&"points", 0.0)
	var pass_yds: float = facts.get(&"pass_yds", 0.0)
	var rush_yds: float = facts.get(&"rush_yds", 0.0)
	match when:
		ALWAYS:
			return true
		&"comeback":
			return facts.get(&"comeback", 0.0) > 0.0
		&"blowout":
			return margin >= tuning.halftime_blowout_points
		&"shutout":
			return facts.get(&"low_score", 0.0) <= 0.0 and points >= tuning.touchdown_points
		&"star":
			return facts.get(&"top_tds", 0.0) >= tuning.halftime_star_tds
		&"turnovers":
			return facts.get(&"turnovers", 0.0) >= tuning.halftime_turnovers
		&"late_hits":
			return facts.get(&"late_hits", 0.0) >= tuning.halftime_late_hits
		&"slugfest":
			return points <= tuning.halftime_slugfest_points
		&"possession":
			return facts.get(&"possession_share", 0.5) >= tuning.halftime_possession_share
		&"air_show":
			return pass_yds >= tuning.halftime_big_yards and pass_yds >= rush_yds * tuning.halftime_big_yards_ratio
		&"ground_game":
			return rush_yds >= tuning.halftime_big_yards and rush_yds >= pass_yds * tuning.halftime_big_yards_ratio
		&"close":
			return margin <= tuning.halftime_close_points
		&"long_run":
			return facts.get(&"long_run", 0.0) >= tuning.halftime_long_run
		&"dives":
			return facts.get(&"dives", 0.0) >= tuning.halftime_dives
	push_warning("HalftimeExchanges: no condition called '%s'" % when)
	return false


## The exchange for this halftime: one of those in the highest priority whose
## condition holds, or `Tuning.halftime_random_chance` of the time one of the
## non sequiturs whatever the half was like. Never the one heard last, unless
## nothing else fits. `usable`, if given, says which exchanges can be picked
## at all (the ones with recordings); empty if none can.
static func pick(facts: Dictionary[StringName, float], tuning: Tuning, usable: Callable = Callable()) -> Dictionary:
	var fitting: Array[Dictionary] = []
	var weird: Array[Dictionary] = []
	var top: int = 0
	var repeat: Dictionary = {}
	for exchange: Dictionary in EXCHANGES:
		if not passes(exchange[&"when"], facts, tuning) or (usable.is_valid() and not usable.call(exchange)):
			continue
		if exchange[&"id"] == _last_id:
			repeat = exchange
			continue
		fitting.append(exchange)
		top = maxi(top, exchange[&"priority"])
		if exchange[&"when"] == ALWAYS:
			weird.append(exchange)
	if fitting.is_empty():
		return repeat
	var pool: Array[Dictionary] = weird
	if weird.is_empty() or randf() >= tuning.halftime_random_chance:
		pool = []
		for exchange: Dictionary in fitting:
			if exchange[&"priority"] == top:
				pool.append(exchange)
	var choice: Dictionary = pool[randi() % pool.size()]
	_last_id = choice[&"id"]
	return choice


## Who says line `index` (from 0) of `exchange`.
static func speaker(exchange: Dictionary, index: int) -> StringName:
	var first: StringName = exchange[&"first"]
	if index % 2 == 0:
		return first
	return JIM if first == TONY else TONY
