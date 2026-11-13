extends SceneTree
## Check of the halftime report.
##
## First the booth's choice of words (HalftimeExchanges): every exchange is well
## formed, each kind of half brings up its own exchanges, the highest priority
## wins, the non sequiturs fill in and now and then butt in, and nothing comes
## up twice running.
## Then the report itself: a match is sent to halftime, the card has to be up
## in place of the scoreboard, Jim and Tony say one whole exchange without
## talking over each other, and after about ten seconds the second half kicks
## off to the team that kicked off the first. A second match skips it with (A).
##
## Real time, so no --fixed-fps. With `out=<dir>` (and a window, so no
## --headless) it saves pictures of the report on the way.
## Run:  godot --headless --path . --script res://tests/halftime_check.gd

enum Step { WATCH, SKIP }

const MIN_SECONDS: float = 9.5
const MAX_SECONDS: float = 13.5
const SKIP_AT: float = 1.5
const PICKS: int = 600
## Seconds into the report at which a picture is taken.
const SHOTS: Array[float] = [0.6, 2.5, 5.0, 8.0]
## A half in which nothing stands out.
const DULL: Dictionary[StringName, float] = {
	&"margin": 10.0, &"points": 24.0, &"low_score": 7.0, &"comeback": 0.0,
	&"possession_share": 0.5, &"pass_yds": 60.0, &"rush_yds": 60.0, &"turnovers": 0.0,
	&"fumbles": 0.0, &"late_hits": 0.0, &"dives": 0.0, &"long_run": 5.0, &"top_tds": 1.0,
}
## What has to be true of a half for each condition to hold, on top of DULL.
const HALVES: Dictionary[StringName, Dictionary] = {
	&"comeback": {&"comeback": 1.0},
	&"blowout": {&"margin": 24.0, &"points": 38.0},
	&"shutout": {&"low_score": 0.0, &"margin": 14.0, &"points": 14.0},
	&"star": {&"top_tds": 2.0},
	&"turnovers": {&"turnovers": 4.0},
	&"late_hits": {&"late_hits": 5.0},
	&"slugfest": {&"points": 7.0, &"margin": 5.0, &"low_score": 1.0},
	&"possession": {&"possession_share": 0.7},
	&"air_show": {&"pass_yds": 180.0},
	&"ground_game": {&"rush_yds": 150.0},
	&"close": {&"margin": 3.0},
	&"long_run": {&"long_run": 55.0},
	&"dives": {&"dives": 20.0},
}

var _tuning: Tuning
var _game: Game
var _step: Step = Step.WATCH
var _sent: bool = false
var _start: int = 0
var _overlaps: int = 0
var _pressed: bool = false
var _last_line: int = -1
var _exchange: Dictionary = {}
var _out: String = ""
var _shots_taken: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	_tuning = load("res://resources/tuning.tres") as Tuning
	_check_table()
	_check_picks()
	_open()


# --- The words -----------------------------------------------------------------------

func _check_table() -> void:
	var ids: Dictionary[StringName, bool] = {}
	var weird: int = 0
	for exchange: Dictionary in HalftimeExchanges.EXCHANGES:
		var id: StringName = exchange[&"id"]
		var lines: Array = exchange[&"lines"]
		if ids.has(id):
			_failures.append("two exchanges are called '%s'" % id)
		ids[id] = true
		if lines.size() < 2 or lines.size() > 4:
			_failures.append("exchange '%s' has %d lines, not 2 to 4" % [id, lines.size()])
		if exchange[&"first"] != HalftimeExchanges.JIM and exchange[&"first"] != HalftimeExchanges.TONY:
			_failures.append("exchange '%s' is not started by Jim or Tony" % id)
		var when: StringName = exchange[&"when"]
		if when == HalftimeExchanges.ALWAYS:
			weird += 1
			if exchange[&"priority"] != 0:
				_failures.append("non sequitur '%s' has a priority" % id)
		else:
			if not HALVES.has(when):
				_failures.append("exchange '%s' has a condition this check does not know: '%s'" % [id, when])
			if exchange[&"priority"] <= 0:
				_failures.append("exchange '%s' ranks no higher than the non sequiturs" % id)
			if HalftimeExchanges.passes(when, DULL, _tuning):
				_failures.append("condition '%s' holds for a half in which nothing happened" % when)
	print("Exchanges: %d, of them %d non sequiturs" % [ids.size(), weird])
	if ids.size() < 15:
		_failures.append("only %d exchanges" % ids.size())
	if weird < 5:
		_failures.append("only %d non sequiturs" % weird)


func _check_picks() -> void:
	# Nothing stands out: only the non sequiturs.
	for pick: Dictionary in _picks(DULL):
		if pick[&"when"] != HalftimeExchanges.ALWAYS:
			_failures.append("a dull half brought up '%s'" % pick[&"id"])
			break
	# Each kind of half brings up its own, with a non sequitur now and then.
	for when: StringName in HALVES:
		var own: int = 0
		var weird: int = 0
		var others: Dictionary[StringName, bool] = {}
		for pick: Dictionary in _picks(_half([when])):
			if pick[&"when"] == when:
				own += 1
			elif pick[&"when"] == HalftimeExchanges.ALWAYS:
				weird += 1
			else:
				others[pick[&"id"]] = true
		if own == 0:
			_failures.append("a '%s' half never brought up its exchange" % when)
		if not others.is_empty():
			_failures.append("a '%s' half brought up %s" % [when, str(others.keys())])
		# With two exchanges of its own the non sequiturs only butt in.
		var share: float = float(weird) / float(PICKS)
		if _count(when) >= 2 and absf(share - _tuning.halftime_random_chance) > 0.06:
			_failures.append("non sequiturs came up %.0f%% of the time in a '%s' half" % [share * 100.0, when])
	# The higher priority wins: a star in a close game is about the star.
	for pick: Dictionary in _picks(_half([&"star", &"close"])):
		if pick[&"when"] == &"close":
			_failures.append("a close game with a star brought up '%s'" % pick[&"id"])
			break
	# Only what is usable, and the same again rather than nothing.
	var only: Callable = func(exchange: Dictionary) -> bool: return exchange[&"id"] == &"bird"
	for i: int in 3:
		var pick: Dictionary = HalftimeExchanges.pick(DULL, _tuning, only)
		if pick.get(&"id", &"") != &"bird":
			_failures.append("with one usable exchange the pick was '%s'" % pick.get(&"id", &""))
	if not HalftimeExchanges.pick(DULL, _tuning, func(_exchange: Dictionary) -> bool: return false).is_empty():
		_failures.append("something was picked with nothing usable")


## PICKS picks in a row for a half with these facts, none twice running.
func _picks(facts: Dictionary[StringName, float]) -> Array[Dictionary]:
	var picks: Array[Dictionary] = []
	var last: StringName = &""
	for i: int in PICKS:
		var pick: Dictionary = HalftimeExchanges.pick(facts, _tuning)
		if pick.is_empty():
			_failures.append("nothing was picked")
			break
		if pick[&"id"] == last:
			_failures.append("'%s' came up twice running" % last)
			break
		last = pick[&"id"]
		picks.append(pick)
	return picks


func _half(conditions: Array[StringName]) -> Dictionary[StringName, float]:
	var facts: Dictionary[StringName, float] = DULL.duplicate()
	for when: StringName in conditions:
		var changes: Dictionary = HALVES[when]
		for key: StringName in changes:
			facts[key] = changes[key]
	return facts


func _count(when: StringName) -> int:
	var count: int = 0
	for exchange: Dictionary in HalftimeExchanges.EXCHANGES:
		if exchange[&"when"] == when:
			count += 1
	return count


# --- The report ----------------------------------------------------------------------

func _open() -> void:
	if _game != null:
		_game.free()
	Game.show_intro = false
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	root.add_child(_game)
	_sent = false
	_pressed = false
	_overlaps = 0
	_last_line = -1


## A first half worth a look, then straight to the end of it.
func _send_to_halftime() -> void:
	_sent = true
	_game.home.score = 21
	_game.away.score = 20
	var home: TeamLine = _game.stat_book.team_line(_game.home)
	var away: TeamLine = _game.stat_book.team_line(_game.away)
	home.pass_yds = 131
	home.rush_yds = 64
	home.first_downs_pass = 5
	home.first_downs_rush = 3
	home.possession = 97.0
	away.pass_yds = 88
	away.rush_yds = 102
	away.first_downs_pass = 3
	away.first_downs_rush = 5
	away.pass_int = 1
	away.possession = 83.0
	_game.clock = 0.0
	_game.play_controller.state_machine.transition(&"Halftime")
	_start = 0


func _process(_delta: float) -> bool:
	var audio: AudioDirector = _game.audio
	var hud: HUD = _game.hud
	var state: StringName = _game.play_controller.state_machine.current_name()
	if not _sent:
		if state == &"Kickoff" or state == &"Live":
			_send_to_halftime()
		return false
	# A switch already under way can swallow the one to Halftime; with the clock
	# at zero the game gets there after the play. Time it from when it does.
	if _start == 0:
		if state != &"Halftime":
			return false
		_start = Time.get_ticks_msec()
	var elapsed: float = float(Time.get_ticks_msec() - _start) / 1000.0
	if audio._announcer.playing and audio._color.playing:
		_overlaps += 1
	if state == &"Halftime":
		_exchange = _game.play_controller.state_machine.get_node(^"Halftime")._exchange
		_last_line = maxi(_last_line, audio.show_line())
	match _step:
		Step.WATCH:
			if elapsed < 0.3:
				return false
			if elapsed < 0.6 and state == &"Halftime" and (hud.top_bar.visible or hud._halftime_card == null):
				_failures.append("the report is not up in place of the scoreboard")
			if _out != "" and _shots_taken < SHOTS.size() and elapsed >= SHOTS[_shots_taken]:
				root.get_texture().get_image().save_png(_out.path_join("halftime_%d.png" % _shots_taken))
				_shots_taken += 1
			if state == &"Halftime" and elapsed < MAX_SECONDS + 3.0:
				return false
			print("Halftime lasted %.1f s, on '%s'.  Exchanges: %s" % [elapsed, _exchange.get(&"id", &""), str(audio.exchange_counts)])
			if state == &"Halftime":
				_failures.append("still at halftime after %.0f s" % elapsed)
			elif elapsed < MIN_SECONDS or elapsed > MAX_SECONDS:
				_failures.append("halftime lasted %.1f s, outside %.1f-%.1f" % [elapsed, MIN_SECONDS, MAX_SECONDS])
			if _exchange.is_empty():
				_failures.append("the booth had nothing to say")
			else:
				if audio.exchange_counts[&"started"] != 1 or audio.exchange_counts[&"finished"] != 1 or audio.exchange_counts[&"cut"] != 0:
					_failures.append("the booth did not say exactly one whole exchange")
				if _last_line != (_exchange[&"lines"] as Array).size() - 1:
					_failures.append("the booth stopped at line %d" % (_last_line + 1))
			if audio.play_counts.get(&"announcer_half", 0) != 0:
				_failures.append("Jim's plain halftime call came up as well")
			if _overlaps > 0:
				_failures.append("the two voices overlapped on %d frames" % _overlaps)
			_check_second_half()
			_step = Step.SKIP
			_open()
		Step.SKIP:
			if not _pressed and elapsed >= SKIP_AT:
				_pressed = true
				if state != &"Halftime":
					_failures.append("halftime was over before it could be skipped")
				Input.action_press(&"confirm")
				return false
			if not _pressed or (state == &"Halftime" and elapsed < SKIP_AT + 1.5):
				return false
			Input.action_release(&"confirm")
			if state == &"Halftime":
				_failures.append("(A) did not skip the report")
			if audio.booth_busy():
				_failures.append("the booth kept talking after the skip")
			_check_second_half()
			return _report()
	return false


## The second half is on: its clock, the scoreboard back, and the kickoff going
## to the team that kicked off the first.
func _check_second_half() -> void:
	if _game.half != 2 or not is_equal_approx(_game.clock, _game.tuning.game_length * 0.5):
		_failures.append("the second half did not start with a full clock")
	if _game.offense != _game.opening_receiver.opponent:
		_failures.append("the second half's kickoff goes to the team that got the first")
	if not _game.hud.top_bar.visible or _game.hud._halftime_card != null:
		_failures.append("the scoreboard did not come back")


func _report() -> bool:
	var audio: AudioDirector = _game.audio
	var silent: PackedStringArray = PackedStringArray()
	for exchange: Dictionary in HalftimeExchanges.EXCHANGES:
		var id: StringName = exchange[&"id"]
		var lines: int = (exchange[&"lines"] as Array).size()
		if audio.show_size(id) == 0:
			silent.append(id)
		elif audio.show_size(id) != lines:
			_failures.append("exchange '%s' has %d lines and %d recordings" % [id, lines, audio.show_size(id)])
	print("Recorded: %d of %d" % [HalftimeExchanges.EXCHANGES.size() - silent.size(), HalftimeExchanges.EXCHANGES.size()])
	if not silent.is_empty():
		print("Not recorded yet (passed over in the game): %s" % ", ".join(silent))
	for chat: String in audio.broken_exchanges:
		_failures.append("exchange '%s' has a part missing or a bad name" % chat)
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("HALFTIME CHECK PASSED" if _failures.is_empty() else "HALFTIME CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
