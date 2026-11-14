extends SceneTree
## Headless check of the booth's stories (BoothStory, the `story_*` files).
## Waits for the first line-up from scrimmage of a CPU game, then walks the
## director through huddles by hand: the chapters of each thread have to come
## in order, no sooner and no more often than Tuning and the threads' shares
## say, a chapter cut short has to come again, the place in each thread has to
## survive a fresh read of the save file, the commissioner must not turn up in
## the closet before the Carol thread is over, and the noises from the closet
## must be heard only while he is in it.
##
## The save goes to a file of its own, never the person's. A chapter with no
## recording yet is given stand-in streams, so the check runs before a batch
## is recorded; "Recorded" says how many are really on file.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/story_check.gd

const STUCK_FRAMES: int = 20000
const SAVE_PATH: String = "user://story_check.cfg"
const MATCHES_MAX: int = 60

var _game: Game
var _audio: AudioDirector
var _frames: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	BoothStory.save_path = SAVE_PATH
	BoothStory.reset()
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	_frames += 1
	if _frames > STUCK_FRAMES:
		_failures.append("no line-up from scrimmage came up")
		return _finish()
	var pc: PlayController = _game.play_controller
	if pc.state_machine.current_name() != &"PreSnap" or pc.kickoff or pc.heave or _game.conversion:
		return false
	_audio = _game.audio
	_expect(not _audio.story_on, "the story is on with the CPU playing both teams")
	_audio.story_on = true
	_game.tuning.story_chance = 1.0
	_check_text()
	_check_files()
	_check_pacing()
	_check_cut()
	_check_save()
	_check_rest()
	return _finish()


func _check_text() -> void:
	var ids: Dictionary[StringName, bool] = {}
	for thread: StringName in BoothStory.THREADS:
		_expect(not BoothStory.chapters(thread).is_empty(), "thread '%s' has no chapters" % thread)
		_expect(BoothStory.PER_MATCH.get(thread, 0) > 0, "thread '%s' has no share of a match" % thread)
	for chapter: Dictionary in BoothStory.all_chapters():
		var id: StringName = chapter[&"id"]
		var lines: int = (chapter[&"lines"] as Array).size()
		_expect(not ids.has(id), "two chapters are called '%s'" % id)
		ids[id] = true
		_expect(lines >= 2 and lines <= 4, "chapter '%s' has %d lines, not 2 to 4" % [id, lines])
		_expect(chapter[&"first"] == BoothStory.JIM or chapter[&"first"] == BoothStory.TONY, "chapter '%s' has nobody speaking first" % id)
		if chapter.has(&"after"):
			_expect(BoothStory.THREADS.has(chapter[&"after"]), "chapter '%s' waits for a thread that is not there" % id)
	_expect(ids.has(BoothStory.CAPTIVE_FROM) and ids.has(BoothStory.CAPTIVE_UNTIL), "the closet's chapters are not in the story")


## Counts the chapters on file and gives the others stand-in streams.
func _check_files() -> void:
	var recorded: int = 0
	var all: Array[Dictionary] = BoothStory.all_chapters()
	var stand_in: AudioStream = (_audio._streams[AudioDirector.QUIP_IDLE] as Array)[0]
	for chapter: Dictionary in all:
		var id: StringName = chapter[&"id"]
		if _audio.story_recorded(chapter):
			recorded += 1
			continue
		_expect(not _audio._stories.has(id), "chapter '%s' has the wrong number of files" % id)
		var streams: Array[AudioStream] = []
		streams.resize((chapter[&"lines"] as Array).size())
		streams.fill(stand_in)
		_audio._stories[id] = streams
	print("Chapters: %d in %d threads.  Recorded: %d of %d" % [all.size(), BoothStory.THREADS.size(), recorded, all.size()])
	var captive: StringName = AudioDirector.QUIP_IDLE_CAPTIVE
	print("Closet noises: %d solo lines, %d exchanges" % [(_audio._streams.get(captive, []) as Array).size(), (_audio._exchanges.get(captive, []) as Array).size()])
	for chat: String in _audio.broken_exchanges:
		if chat.begins_with(AudioDirector.STORY_PREFIX) or chat.contains("captive"):
			_failures.append("'%s' has a part missing" % chat)


## The first chapter waits for its huddle, the next for the gap, and the
## threads take turns: Carol, the commissioner, Carol.
func _check_pacing() -> void:
	var tuning: Tuning = _game.tuning
	var carol: Array[Dictionary] = BoothStory.chapters(BoothStory.CAROL)
	var first: StringName = carol[0][&"id"]
	var missing: StringName = BoothStory.chapters(BoothStory.COMMISSIONER)[0][&"id"]
	_audio._huddles = 0
	for huddle: int in range(1, tuning.story_first_huddle):
		_expect(_huddle() == &"", "a chapter came up in huddle %d" % huddle)
	_expect(_huddle() == first, "huddle %d: '%s' was waiting, not '%s'" % [tuning.story_first_huddle, _audio._story_pending, first])
	# Fourth and twenty comes first, and the chapter keeps for the next huddle.
	if _audio.has_sound(AudioDirector.QUIP_BLAZE):
		_expect(_huddle(4, 20.0) == &"", "a chapter came up on 4th & 20")
	_expect(_huddle() == first, "the chapter did not wait for the next huddle")
	_tell(first)
	_expect(BoothStory.heard(BoothStory.CAROL) == 1, "after one chapter the Carol thread is at %d" % BoothStory.heard(BoothStory.CAROL))
	_expect(_audio.stories_told == 1, "the match counts %d chapters after one" % _audio.stories_told)
	for huddle: int in range(1, tuning.story_huddle_gap):
		_expect(_huddle() == &"", "the second chapter came up %d huddles after the first" % huddle)
	_expect(_huddle() == missing, "after the gap '%s' was waiting, not '%s'" % [_audio._story_pending, missing])
	_tell(missing)
	_expect(BoothStory.heard(BoothStory.COMMISSIONER) == 1, "after 'missing' the commissioner thread is at %d" % BoothStory.heard(BoothStory.COMMISSIONER))
	_expect(_after_gap() == carol[1][&"id"], "third in the match '%s' was waiting, not '%s'" % [_audio._story_pending, carol[1][&"id"]])


## A shout in the middle of a chapter: it has not been heard and comes again,
## and after it the match has had its share.
func _check_cut() -> void:
	var second: StringName = BoothStory.chapters(BoothStory.CAROL)[1][&"id"]
	_audio._tell_story()
	_expect(_audio._story_playing == second, "'%s' did not start" % second)
	var lines: int = (BoothStory.chapters(BoothStory.CAROL)[1][&"lines"] as Array).size()
	_audio.shout(&"announcer_touchdown")
	_expect(_audio._story_playing == &"" and _audio._exchange_parts.is_empty(), "a shout did not cut the chapter short")
	_expect(BoothStory.heard(BoothStory.CAROL) == 1, "a chapter cut short moved the story on to %d" % BoothStory.heard(BoothStory.CAROL))
	# It is held from the line just said, and the next huddle takes it up
	# again behind an "as I was saying" instead of starting anything new.
	_expect(_audio._story_held.size() == lines, "%d lines of the chapter were held, not %d" % [_audio._story_held.size(), lines])
	_expect(_huddle() == &"" and _audio._story_resume, "the next huddle did not take the chapter up again")
	_audio._resume_story()
	var bridge: int = 1 if _audio.has_sound(AudioDirector.CALL_RESUME) else 0
	_expect(_audio._story_playing == second, "'%s' was not taken up again" % second)
	_expect(_audio._exchange_parts.size() == lines + bridge - 1, "%d lines were left after the first of the chapter taken up again" % _audio._exchange_parts.size())
	# Interrupted again two lines on: held from the second line this time.
	_audio._say_part()
	_audio._say_part()
	_audio.shout(&"announcer_touchdown")
	_expect(_audio._story_held.size() == lines - bridge, "held a second time, %d lines were kept" % _audio._story_held.size())
	_expect(_huddle() == &"" and _audio._story_resume, "the chapter held a second time was not taken up")
	_audio._resume_story()
	while not _audio._exchange_parts.is_empty():
		_audio._say_part()
	_expect(_audio._story_playing == &"" and _audio._story_held.is_empty(), "the chapter taken up again did not end")
	_expect(BoothStory.heard(BoothStory.CAROL) == 2, "after two chapters the Carol thread is at %d" % BoothStory.heard(BoothStory.CAROL))
	_expect(_audio.exchange_counts[&"resumed"] == 2, "the chapter was taken up %d times, not 2" % _audio.exchange_counts[&"resumed"])
	for huddle: int in _game.tuning.story_huddle_gap * 2:
		_expect(_huddle() == &"", "a chapter past the match's share came up")
	# A chapter that misses its huddle is dropped, not told over the play.
	_new_match()
	_expect(_after_gap() != &"", "nothing was waiting in a new match")
	_game.play_controller.ball_dead = false
	_audio._tell_story()
	_game.play_controller.ball_dead = true
	_expect(_audio._story_playing == &"" and BoothStory.heard(BoothStory.CAROL) == 2, "a chapter started with the ball live")


## The place in each thread is in the file, not only in memory.
func _check_save() -> void:
	BoothStory.save_path = SAVE_PATH
	_expect(BoothStory.heard(BoothStory.CAROL) == 2, "read back from the file the Carol thread is at %d, not 2" % BoothStory.heard(BoothStory.CAROL))
	_expect(BoothStory.heard(BoothStory.COMMISSIONER) == 1, "read back from the file the commissioner thread is at %d, not 1" % BoothStory.heard(BoothStory.COMMISSIONER))


## The rest of both threads, match after match: each in order and within its
## share, the closet not before the Carol thread is over, its noises only
## while the commissioner is in it; then nothing more comes and the chapters
## join the idle chatter.
func _check_rest() -> void:
	var tuning: Tuning = _game.tuning
	tuning.story_captive_chance = 1.0
	var captive: StringName = AudioDirector.QUIP_IDLE_CAPTIVE
	var commissioner: Array[Dictionary] = BoothStory.chapters(BoothStory.COMMISSIONER)
	var was_captive: bool = false
	var matches: int = 0
	while matches < MATCHES_MAX and not _all_told():
		matches += 1
		_new_match()
		var shares: Dictionary[StringName, int] = {}
		for turn: int in tuning.story_per_match + 1:
			var id: StringName = _after_gap()
			if id == &"":
				break
			var thread: StringName = BoothStory.thread_of_next(id)
			_expect(thread != &"", "'%s' came up out of its turn" % id)
			if thread == &"":
				return
			var chapter: Dictionary = BoothStory.next(thread)
			if chapter.has(&"after"):
				_expect(BoothStory.finished(chapter[&"after"]), "'%s' came up before the %s thread was over" % [id, chapter[&"after"]])
			shares[thread] = shares.get(thread, 0) + 1
			_expect(shares[thread] <= BoothStory.PER_MATCH[thread], "match %d brought %d chapters of the %s thread" % [matches, shares[thread], thread])
			_expect(turn < tuning.story_per_match, "match %d brought more than %d chapters" % [matches, tuning.story_per_match])
			_tell(id)
			# The closet is heard from once he is in it, and not after he is out.
			var in_closet: bool = BoothStory.captive()
			_expect(in_closet == (_idle() == captive), "after '%s' the closet noises are %s" % [id, "missing" if in_closet else "still heard"])
			if id == BoothStory.CAPTIVE_FROM:
				_expect(in_closet, "after '%s' the commissioner is not in the closet" % id)
			if id == BoothStory.CAPTIVE_UNTIL:
				_expect(was_captive and not in_closet, "after '%s' the commissioner is still in the closet" % id)
			was_captive = in_closet
	_expect(_all_told(), "the stories were not told in %d matches" % MATCHES_MAX)
	_expect(BoothStory.heard(BoothStory.COMMISSIONER) == commissioner.size(), "the commissioner thread stopped at %d" % BoothStory.heard(BoothStory.COMMISSIONER))
	print("Both threads told in %d matches" % matches)
	_new_match()
	_expect(_after_gap() == &"", "a chapter came up after the last")
	var before: int = (_audio._exchanges.get(AudioDirector.QUIP_IDLE, []) as Array).size()
	_audio._retire_stories()
	var after: int = (_audio._exchanges[AudioDirector.QUIP_IDLE] as Array).size()
	_expect(after - before == BoothStory.all_chapters().size(), "%d chapters joined the idle chatter" % (after - before))


func _all_told() -> bool:
	for thread: StringName in BoothStory.THREADS:
		if not BoothStory.finished(thread):
			return false
	return true


## The director's count of this match starts over.
func _new_match() -> void:
	_audio.stories_told = 0
	_audio._told.clear()
	_audio._huddles = _game.tuning.story_first_huddle
	_audio._story_huddle = 0


## The chapter left waiting by the first huddle a chapter may come in.
func _after_gap() -> StringName:
	_audio._huddles += _game.tuning.story_huddle_gap
	return _huddle()


## The kind of idle chatter Tony would have now.
func _idle() -> StringName:
	return _audio._idle_quip()


## The chapter left waiting by a huddle on `down` and `yards` to go.
func _huddle(down: int = 1, yards: float = 10.0) -> StringName:
	_game.down = down
	_game.goal_to_go = false
	_game.first_down_x = _game.los_x + yards * float(_game.play_controller.offense.attack_dir)
	_quiet()
	_audio._on_state_changed(&"", &"PlaySelect")
	return _audio._story_pending


## Tells the chapter that is waiting, to its last line.
func _tell(id: StringName) -> void:
	_audio._tell_story()
	_expect(_audio._story_playing == id, "'%s' did not start" % id)
	while not _audio._exchange_parts.is_empty():
		_audio._say_part()
	_expect(_audio._story_playing == &"", "'%s' did not end" % id)


## Nobody talking and nothing held back.
func _quiet() -> void:
	_audio._color.stop()
	_audio._announcer.stop()
	_audio._exchange_parts.clear()
	_audio._quip_pending = &""
	_audio._story_pending = &""
	_audio._story_playing = &""


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("STORY CHECK PASSED" if _failures.is_empty() else "STORY CHECK FAILED")
	_game.free()
	_game = null
	quit(0 if _failures.is_empty() else 1)
	return true
