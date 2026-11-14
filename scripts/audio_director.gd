class_name AudioDirector
extends Node
## Every sound in the game: one-shot effects, the quarterback's voice, the huddle
## and the crowd. Gameplay code calls play(), say() and crowd_react(); the loops
## and the sounds tied to a game state run off the state machine's signal.
##
## Sounds are files in assets/audio named `<sound>_<n>.<ext>`; every numbered
## take of a sound is a variation picked at random.
##
## The booth is Jim, who calls the play (`announcer_*`), and Tony, who has
## opinions about it (`color_*`). An exchange between the two is a set of files
## `chat_<moment>_<t|j><k>_<part>.<ext>`: the letter is who speaks first (Tony
## or Jim), the parts alternate, and it comes up as one of the lines of
## `color_<moment>`.

const AUDIO_DIR: String = "res://assets/audio"
const EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
const BUS_SFX: StringName = &"SFX"
const BUS_CROWD: StringName = &"Crowd"
const BUS_VOICE: StringName = &"Voice"
const BUS_UI: StringName = &"UI"
const BUS_MUSIC: StringName = &"Music"
const MUSIC_PREFIX: String = "music_"
const POOL_SIZE: int = 16
## Real seconds before the same sound may start again.
const MIN_REPEAT: float = 0.06
const FADE_TIME: float = 0.5
const SILENT: float = 0.001
## Crowd reactions smaller than this only stir the crowd; no cheer or groan.
const REACTION_SHOUT: float = 0.5
## Chance the announcer remarks on each kind of moment, and the yards past the
## line (or up the field on a kick return) that make a run a breakaway.
const REMARK_CATCH: float = 0.6
const REMARK_THROW: float = 0.45
const REMARK_HIT: float = 0.3
const REMARK_BREAK: float = 0.25
const REMARK_HURDLE: float = 0.7
const REMARK_ROOM: float = 0.5
const REMARK_PANCAKE: float = 0.25
## A plain wrap-up is rare (most tackles are dives, which count as hits), so it
## gets its word often when it comes.
const REMARK_TACKLE: float = 0.5
const REMARK_SPIN: float = 0.45
const REMARK_STIFF_ARM: float = 0.45
## Chance the color commentator has something to say about each kind of moment.
const QUIP_BOLD: float = 0.6
const QUIP_FOURTH: float = 0.6
const QUIP_DOG: float = 0.2
const QUIP_QB_RUN: float = 0.6
const QUIP_INTERCEPTION: float = 0.8
const QUIP_CONFUSED: float = 0.6
const QUIP_HOT: float = 0.6
const QUIP_BAD_THROW: float = 0.6
const QUIP_TOUCHDOWN: float = 0.75
const QUIP_LAWN_CHAIR: float = 0.2
const QUIP_SACK: float = 0.5
const QUIP_HURDLE: float = 0.6
const QUIP_CATCH: float = 0.4
const QUIP_DOWNS: float = 0.6
const QUIP_HALF: float = 0.9
const QUIP_FINAL: float = 0.9
const QUIP_BREAKAWAY: float = 0.5
const QUIP_JUICE: float = 0.6
const QUIP_FUMBLE: float = 0.6
const QUIP_DROP: float = 0.5
const QUIP_TACKLE: float = 0.4
const QUIP_SPIN: float = 0.4
const QUIP_STIFF_ARM: float = 0.4
## Real seconds a quip waits for the announcer before it is too late to say it.
const QUIP_STALE: float = 8.0
## Real seconds of quiet between one voice finishing and the next starting.
const BOOTH_BREATH: float = 0.25
## Idle chatter: the usual kind, and the kinds for a rout and for a tight
## second half. All of them start with the first name.
const QUIP_IDLE: StringName = &"color_idle"
const QUIP_IDLE_BLOWOUT: StringName = &"color_idle_blowout"
const QUIP_IDLE_CLOSE: StringName = &"color_idle_close"
## The noises from the supply closet, and what the two say to cover for them:
## only while the story has the commissioner in there (BoothStory.captive()).
const QUIP_IDLE_CAPTIVE: StringName = &"color_idle_captive"
## With a couple of plays left: Tony before the break, and at the end of a
## rout, of a tight one and of anything between. All start with QUIP_LATE.
const QUIP_LATE: StringName = &"color_late"
const QUIP_LATE_HALF: StringName = &"color_late_half"
const QUIP_LATE_BLOWOUT: StringName = &"color_late_blowout"
const QUIP_LATE_CLOSE: StringName = &"color_late_close"
## Jim's word that the half or the game is nearly over, and on its last play.
const CALL_LATE_HALF: StringName = &"announcer_late_half"
const CALL_LATE_GAME: StringName = &"announcer_late_game"
const CALL_LAST_PLAY: StringName = &"announcer_last_play"
## Jim calls the warning when the half's clock gets under Tuning.warning_time.
const CALL_WARNING: StringName = &"announcer_warning"
## "As I was saying": what Jim or Tony says to pick up a chapter of the story
## that a call interrupted.
const CALL_RESUME: StringName = &"announcer_resume"
const QUIP_RESUME: StringName = &"color_resume"
## The quarterback's extra shouts before the snap (B), and his silly ones.
const QB_CALL: StringName = &"qb_call"
const QB_SILLY: StringName = &"qb_silly"
## Fourth and twenty: the booth cannot let 4:20 go by.
const QUIP_BLAZE: StringName = &"color_blaze"
const BLAZE_DOWN: int = 4
const BLAZE_YARDS: int = 20
## The exchanges that open the broadcast, before the first kickoff.
const QUIP_INTRO: StringName = &"color_intro"
## What the booth says about the season. A moment's lines for a game of the
## season, for a playoff game and for the final (the Fruit Cup) are files under
## the moment's own name with one of these after it: `color_idle_playoff_1`,
## `chat_intro_cup_j1_1`, `announcer_final_cup_1`. Where there are none the
## moment's usual lines are said (see _season_take()).
const SEASON_SUFFIX: String = "_season"
const PLAYOFF_SUFFIX: String = "_playoff"
const CUP_SUFFIX: String = "_cup"
## Jim's call that the game is level at the end and goes to sudden death;
## Tony's thought on it is `color_overtime`.
const CALL_OVERTIME: StringName = &"announcer_overtime"
const OVERTIME_MOMENT: String = "overtime"
const QUIP_OVERTIME_CHANCE: float = 0.9
const CHAT_PREFIX: String = "chat_"
## The halftime report's exchanges: files `show_<id>_<part>`, picked by id
## (see HalftimeExchanges), not at random.
const SHOW_PREFIX: String = "show_"
## The chapters of the booth's story: files `story_<id>_<part>`, told in order
## (see BoothStory), one at a time in the huddle.
const STORY_PREFIX: String = "story_"
const QUIP_PREFIX: String = "color_"
## The main menu's lines (see MenuBooth), which are none of this director's.
const MENU_PREFIX: String = "menu_"
const BREAKAWAY_YARDS: float = 20.0
const BREAKAWAY_RETURN_YARDS: float = 40.0

## The openings not heard yet this time round, by their place among the
## exchanges of QUIP_INTRO, and the one heard last. Kept from match to match:
## the director itself is made again with every one.
static var _intro_bags: Dictionary[StringName, Array] = {}
static var _last_intros: Dictionary[StringName, int] = {}

var game: Game
var tuning: Tuning
## How worked up the crowd is, 0..1. Drives the roar under the steady murmur.
var excitement: float = 0.0
## Times each sound was asked for, and the ones asked for that have no file.
var play_counts: Dictionary[StringName, int] = {}
var missing: Dictionary[StringName, bool] = {}
## Times a remark was asked for, before the dice and the gap had their say.
var remark_asks: Dictionary[StringName, int] = {}
## The same for the color commentator's quips.
var quip_asks: Dictionary[StringName, int] = {}
## Exchanges between the two that started, got to the last line, or were cut
## short by a call, and the `chat_*` sets left out for a missing part.
var exchange_counts: Dictionary[StringName, int] = {&"started": 0, &"finished": 0, &"cut": 0, &"resumed": 0}
var broken_exchanges: PackedStringArray = PackedStringArray()
## The booth tells its story (see BoothStory): in the games of a season only,
## never in an exhibition. Off with the CPU playing both teams, so the
## headless tests leave the person's place in it alone.
var story_on: bool = false
## Chapters of the story heard to the end in this match.
var stories_told: int = 0

var _streams: Dictionary[StringName, Array] = {}
var _last_played: Dictionary[StringName, int] = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _bed: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _huddle: AudioStreamPlayer
var _chant: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _announcer: AudioStreamPlayer
## Announcer clips waiting for the one before them to finish.
var _announcer_queue: Array[StringName] = []
var _last_remark: int = -1000000
var _color: AudioStreamPlayer
## The broadcast music, and whether it is on its way out.
var _music: AudioStreamPlayer
var _music_stopping: bool = false
var _music_level: float = 0.0
## The quip Tony is holding until Jim is done, and when it came up.
var _quip_pending: StringName = &""
var _quip_asked: int = 0
var _last_quip: int = -1000000
## Real seconds since either of the two voices was last heard.
var _booth_quiet: float = 1.0
## Lines of each sound not said yet this time round, so none comes up twice in
## a row. A line is a stream, or for a quip an exchange.
var _bags: Dictionary[StringName, Array] = {}
## When Tony last said a line of each quip.
var _quip_said: Dictionary[StringName, int] = {}
## The exchanges of each quip. One is {tony_first: bool, parts: Array[AudioStream]}.
var _exchanges: Dictionary[StringName, Array] = {}
## The lines still to come of the exchange going on: [by Tony, stream] each.
var _exchange_parts: Array[Array] = []
## The halftime exchanges by id, each the streams of its lines in order, and
## how many lines the one going on has (0 when none is).
var _shows: Dictionary[StringName, Array] = {}
var _show_lines: int = 0
## The story's chapters by id, each the streams of its lines in order; the one
## waiting for the microphone and the one being told; huddles so far in this
## match, and the one in which the last chapter was told.
var _stories: Dictionary[StringName, Array] = {}
var _story_pending: StringName = &""
var _story_playing: StringName = &""
## The thread of the chapter being told, and the chapters of each thread
## heard to the end in this match.
var _story_thread: StringName = &""
var _told: Dictionary[StringName, int] = {}
var _huddles: int = 0
var _story_huddle: int = 0
## A chapter that a call interrupted: its id and its lines still to come, from
## the last one said, which is said again. The last line of the chapter being
## told that was started, and whether this huddle may take the held one up.
var _story_held_id: StringName = &""
var _story_held: Array[Array] = []
var _story_last: Array = []
var _story_resume: bool = false
## The half (1 or 2, 0 for none yet) in which Jim last said time was short,
## in which he last called the last play, and in which Tony got his say on it.
var _late_called_half: int = 0
var _last_play_called_half: int = 0
var _late_quip_said_half: int = 0
## The run in progress has already been called a breakaway (or passed over).
var _breakaway_called: bool = false
var _roar_level: float = 0.0
var _huddle_on: bool = false
var _huddle_level: float = 0.0
var _chant_fading: bool = false
var _chant_in: float = -1.0
var _chant_name: StringName = &""
var _last_tick: int = 0


func setup(p_game: Game) -> void:
	game = p_game
	tuning = p_game.tuning
	make_buses(tuning)
	_load_streams()
	story_on = tuning.story_enabled and game.season() != null
	if story_on:
		_retire_stories()
	for i: int in POOL_SIZE:
		_pool.append(_make_player(BUS_SFX))
	_bed = _make_loop(&"crowd_bed", BUS_CROWD)
	_roar = _make_loop(&"crowd_roar", BUS_CROWD)
	_huddle = _make_loop(&"huddle_murmur", BUS_VOICE)
	_chant = _make_player(BUS_CROWD)
	_voice = _make_player(BUS_VOICE)
	_announcer = _make_player(BUS_VOICE)
	_color = _make_player(BUS_VOICE)
	_music = _make_player(BUS_MUSIC)
	_bed.volume_linear = tuning.audio_crowd_bed_level
	_roar.volume_linear = SILENT
	_huddle.volume_linear = SILENT
	if tuning.audio_enabled:
		_bed.play()
		_roar.play()
	_last_tick = Time.get_ticks_usec()
	game.play_controller.state_machine.state_changed.connect(_on_state_changed)
	game.ball.bounced.connect(_on_ball_bounced)


# --- Playing -------------------------------------------------------------------------

## Plays one take of `sound`. `volume` is linear (1 = as mixed), `pitch` a speed
## scale. Asking again within a few hundredths of a second does nothing.
func play(sound: StringName, volume: float = 1.0, pitch: float = 1.0) -> void:
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var stream: AudioStream = _pick(sound)
	if stream == null or not tuning.audio_enabled:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_played.get(sound, -100000) < int(MIN_REPEAT * 1000.0):
		return
	_last_played[sound] = now
	var bus: StringName = _bus_of(sound)
	var player: AudioStreamPlayer = _free_player()
	player.stream = stream
	player.bus = bus
	player.volume_linear = volume
	# Hits and whooshes vary a little each time; jingles and voices stay in tune.
	player.pitch_scale = pitch * (randf_range(0.94, 1.06) if bus == BUS_SFX else 1.0)
	player.play()


## The announcer says `sounds` one after the other, once he has finished
## whatever he is saying now.
func announce(sounds: Array[StringName]) -> void:
	_announcer_queue.append_array(sounds)


## A passing remark on the play, `chance` of the time. He keeps quiet if he is
## already talking or has just made one, so it never gets in the way of a call.
func remark(sound: StringName, chance: float) -> void:
	remark_asks[sound] = remark_asks.get(sound, 0) + 1
	if _announcer.playing or not _announcer_queue.is_empty() or _color.playing or not _exchange_parts.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_remark < int(tuning.audio_remark_gap * 1000.0):
		return
	if randf() >= chance * tuning.audio_remark_scale:
		return
	_last_remark = now
	_speak(sound)


## The announcer shouts `sound` next, ahead of anything else he had lined up.
## Whoever is talking finishes the sentence first, and the rest of an exchange
## between the two is dropped; a chapter of the story is held for later.
func shout(sound: StringName) -> void:
	_cut_exchange(true)
	_show_lines = 0
	_announcer_queue.clear()
	_announcer_queue.append(sound)


## Tony has a thought about the play, `chance` of the time. He waits for Jim to
## finish and never says two in a row; a newer thought replaces one he is still
## holding, but idle chatter replaces nothing.
func quip(sound: StringName, chance: float) -> void:
	quip_asks[sound] = quip_asks.get(sound, 0) + 1
	if _color.playing or not _exchange_parts.is_empty():
		return
	if String(sound).begins_with(String(QUIP_IDLE)) and _quip_pending != &"":
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_quip < int(tuning.audio_color_gap * 1000.0):
		return
	# A moment with one line comes round again slowly; one with seven, sooner.
	var lines: int = maxi(_line_count(sound), 1)
	if now - _quip_said.get(sound, -100000000) < int(tuning.audio_color_repeat_gap * 1000.0 / float(lines)):
		return
	if randf() >= chance * tuning.audio_color_scale:
		return
	_quip_pending = sound
	_quip_asked = now


## The carrier got out of a tackle with `move` (&"spin", &"stiff_arm" or
## anything else for plain strength): the booth's lines for that move, or the
## ones for any broken tackle where the move has none of its own.
func broke_tackle(move: StringName) -> void:
	var said: StringName = &"announcer_break"
	var thought: StringName = &"color_dog"
	var remark_chance: float = REMARK_BREAK
	var quip_chance: float = QUIP_DOG
	if move == &"spin" and has_sound(&"announcer_spin") and has_sound(&"color_spin"):
		said = &"announcer_spin"
		thought = &"color_spin"
		remark_chance = REMARK_SPIN
		quip_chance = QUIP_SPIN
	elif move == &"stiff_arm" and has_sound(&"announcer_stiff_arm") and has_sound(&"color_stiff_arm"):
		said = &"announcer_stiff_arm"
		thought = &"color_stiff_arm"
		remark_chance = REMARK_STIFF_ARM
		quip_chance = QUIP_STIFF_ARM
	remark(said, remark_chance)
	quip(thought, quip_chance)


## Tony says `sound` next whatever the dice or the gap since his last line
## would have said, in place of any thought he was holding. He still waits his
## turn at the microphone.
func _insist(sound: StringName) -> void:
	quip_asks[sound] = quip_asks.get(sound, 0) + 1
	_quip_pending = sound
	_quip_asked = Time.get_ticks_msec()


## Jim and Tony open the broadcast with one of their exchanges, a different one
## every match until all have been heard. False if there is nothing to say.
func intro() -> bool:
	# A playoff game opens with its own word, a week of the season now and then.
	var moment: StringName = QUIP_INTRO
	if game.is_playoff() or (game.season_round >= 0 and randf() < tuning.season_intro_chance):
		moment = _season_take(QUIP_INTRO)
	play_counts[moment] = play_counts.get(moment, 0) + 1
	var openings: Array = _exchanges.get(moment, [])
	if openings.is_empty():
		missing[moment] = true
		return false
	if not tuning.audio_enabled:
		return false
	var opening: Dictionary = openings[next_intro(openings.size(), moment)]
	var tony: bool = opening[&"tony_first"]
	for stream: AudioStream in opening[&"parts"]:
		_exchange_parts.append([tony, stream])
		tony = not tony
	exchange_counts[&"started"] += 1
	return true


## Which of the `count` openings of `moment` comes next: each once in a random
## order, and the first of a new round is never the last of the one before.
static func next_intro(count: int, moment: StringName = QUIP_INTRO) -> int:
	var bag: Array = (_intro_bags.get(moment, []) as Array).filter(func(index: int) -> bool: return index < count)
	if bag.is_empty():
		bag.assign(range(count))
		bag.shuffle()
		if count > 1 and bag.back() == _last_intros.get(moment, -1):
			bag.push_front(bag.pop_back())
	var pick: int = bag.pop_back()
	_intro_bags[moment] = bag
	_last_intros[moment] = pick
	return pick


## `sound` as it is said in the game being played: its lines for the final of
## the season, for a playoff game or for any game of the season, if there are
## any on file; otherwise, and in an exhibition, `sound` itself.
func _season_take(sound: StringName) -> StringName:
	if game.season_round < 0:
		return sound
	var suffix: String = SEASON_SUFFIX
	if game.season_round == Season.FINAL_ROUND:
		suffix = CUP_SUFFIX
	elif game.is_playoff():
		suffix = PLAYOFF_SUFFIX
	var special: StringName = StringName(String(sound) + suffix)
	return special if has_sound(special) else sound


## Jim and Tony say halftime exchange `id` (see HalftimeExchanges) once whoever
## is talking has finished the sentence, in place of anything else they had
## lined up. False if there is nothing to hear.
func play_show(id: StringName, tony_first: bool) -> bool:
	var sound: StringName = StringName(SHOW_PREFIX + id)
	play_counts[sound] = play_counts.get(sound, 0) + 1
	if not _shows.has(id):
		missing[sound] = true
		return false
	if not tuning.audio_enabled:
		return false
	_cut_exchange(true)
	_announcer_queue.clear()
	_quip_pending = &""
	var tony: bool = tony_first
	for stream: AudioStream in _shows[id]:
		_exchange_parts.append([tony, stream])
		tony = not tony
	_show_lines = _exchange_parts.size()
	exchange_counts[&"started"] += 1
	return true


## How many lines there are on file for halftime exchange `id`.
func show_size(id: StringName) -> int:
	return (_shows.get(id, []) as Array).size()


## Which line of the halftime exchange was started last, from 0: -1 before the
## first, and when none is going on.
func show_line() -> int:
	return _show_lines - _exchange_parts.size() - 1 if _show_lines > 0 else -1


## Somebody in the booth is talking or is about to.
func booth_busy() -> bool:
	return _announcer.playing or _color.playing or not _exchange_parts.is_empty() or not _announcer_queue.is_empty()


## Somebody in the booth is talking or still has something to say, Tony's
## thought he is waiting to get in included.
func booth_pending() -> bool:
	return booth_busy() or _quip_pending != &""


## Who is talking right now: &"jim", &"tony" or nobody.
func speaker() -> StringName:
	if _color.playing:
		return &"tony"
	return &"jim" if _announcer.playing else &""


## Both of them stop in the middle of the word and forget what came next.
func hush() -> void:
	_cut_exchange()
	_story_pending = &""
	_show_lines = 0
	_announcer_queue.clear()
	_quip_pending = &""
	_announcer.stop()
	_color.stop()


## A cue of the broadcast music, from the start, in place of any playing.
## Returns false when there is no file for it.
func play_music(sound: StringName) -> bool:
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var stream: AudioStream = _pick(sound)
	if stream == null:
		return false
	if not tuning.audio_enabled:
		return true
	_music.stream = stream
	_music_stopping = false
	_music_level = _music_target()
	_music.volume_linear = maxf(_music_level, SILENT)
	_music.play()
	return true


## The music fades out over Tuning.audio_music_fade.
func stop_music() -> void:
	_music_stopping = true


func music_playing() -> bool:
	return _music.playing and not _music_stopping


func _music_target() -> float:
	if _music_stopping:
		return 0.0
	return tuning.audio_music_level * (tuning.audio_music_duck if booth_busy() else 1.0)


## Down under the booth, back up after, and out when asked.
func _update_music(delta: float) -> void:
	if not _music.playing:
		return
	_music_level = move_toward(_music_level, _music_target(), delta / maxf(tuning.audio_music_fade, 0.01))
	_music.volume_linear = maxf(_music_level, SILENT)
	if _music_stopping and _music_level <= 0.0:
		_music.stop()
		_music_stopping = false


## The two voices share one microphone: nobody starts until the other has
## finished and a breath has passed. An exchange under way carries on first,
## then Jim's calls, then Tony's quips.
func _update_booth(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if _quip_pending != &"" and now - _quip_asked > int(QUIP_STALE * 1000.0):
		_quip_pending = &""
	if _announcer.playing or _color.playing:
		_booth_quiet = 0.0
		return
	_booth_quiet += delta
	if _booth_quiet < BOOTH_BREATH:
		return
	if not _exchange_parts.is_empty():
		_say_part()
	elif not _announcer_queue.is_empty():
		_speak(_announcer_queue.pop_front())
	elif _story_resume:
		_resume_story()
	elif _story_pending != &"":
		_tell_story()
	elif _quip_pending != &"":
		_say_quip()


## Says the quip Tony is holding: a line of his own, or with the ball dead
## perhaps the start of an exchange with Jim.
func _say_quip() -> void:
	var now: int = Time.get_ticks_msec()
	var sound: StringName = _quip_pending
	_quip_pending = &""
	_last_quip = now
	_quip_said[sound] = now
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var line: Variant = _pick_fresh(sound, not game.play_controller.ball_dead)
	if line != null and String(sound).begins_with(String(QUIP_LATE)):
		_late_quip_said_half = game.half
	if line == null or not tuning.audio_enabled:
		return
	if line is Dictionary:
		var tony: bool = line[&"tony_first"]
		for stream: AudioStream in line[&"parts"]:
			_exchange_parts.append([tony, stream])
			tony = not tony
		exchange_counts[&"started"] += 1
		_say_part()
		return
	_color.stream = line as AudioStream
	_color.volume_linear = tuning.audio_color_level
	_color.play()


## The next line of the exchange going on.
func _say_part() -> void:
	var part: Array = _exchange_parts.pop_front()
	var player: AudioStreamPlayer = _color if part[0] else _announcer
	player.stream = part[1] as AudioStream
	player.volume_linear = tuning.audio_color_level if part[0] else tuning.audio_announcer_level
	player.play()
	# The wait before Tony's next thought counts from the end of the exchange.
	_last_quip = Time.get_ticks_msec()
	# A line of the chapter itself, not the "as I was saying" before it.
	if _story_playing != &"" and part.size() < 3:
		_story_last = part
	if _exchange_parts.is_empty():
		exchange_counts[&"finished"] += 1
		if _story_playing != &"":
			BoothStory.mark_heard(_story_playing)
			_story_playing = &""
			_story_last = []
			stories_told += 1
			_told[_story_thread] = _told.get(_story_thread, 0) + 1
			_story_huddle = _huddles


## Drops the lines still to come of the exchange going on, if there is one.
## With `hold`, a chapter of the story cut short this way is kept, from the
## last line said, and taken up again in a later huddle (_resume_story);
## without it the chapter, and any that was being held, has not been heard and
## comes again from the start.
func _cut_exchange(hold: bool = false) -> void:
	if not hold:
		_story_held.clear()
	elif _story_playing != &"" and not _exchange_parts.is_empty():
		_story_held.clear()
		_story_held_id = _story_playing
		if not _story_last.is_empty():
			_story_held.append(_story_last)
		for part: Array in _exchange_parts:
			if part.size() < 3:
				_story_held.append(part)
	if not _exchange_parts.is_empty():
		_exchange_parts.clear()
		exchange_counts[&"cut"] += 1
	_story_playing = &""
	_story_last = []
	_story_resume = false


## Takes up the chapter a call interrupted, if the ball is still dead: whoever
## had the last word says "as I was saying", says it again, and the chapter
## carries on from there. One that misses its huddle waits for the next.
func _resume_story() -> void:
	_story_resume = false
	if _story_held.is_empty() or not game.play_controller.ball_dead:
		return
	var thread: StringName = BoothStory.thread_of_next(_story_held_id)
	if thread == &"":
		_story_held.clear()
		return
	var tony: bool = _story_held[0][0]
	var bridge: StringName = QUIP_RESUME if tony else CALL_RESUME
	if has_sound(bridge):
		_exchange_parts.append([tony, _pick_fresh(bridge, true), true])
	_exchange_parts.append_array(_story_held)
	_story_held = []
	_story_playing = _story_held_id
	_story_thread = thread
	_story_last = []
	exchange_counts[&"resumed"] += 1
	_say_part()


## The chapter of the story that is due in this huddle, or none: the match has
## had fewer than its share, enough huddles have gone by, Tony has nothing
## more pressing to say, and a thread has a chapter on file that it may still
## tell in this match. Of several threads, the one that has had least of its
## share goes first.
func _story_due() -> StringName:
	if not story_on or not tuning.audio_enabled or game.conversion:
		return &""
	if _quip_pending != &"" or not _exchange_parts.is_empty() or _story_pending != &"" or not _story_held.is_empty():
		return &""
	if stories_told >= tuning.story_per_match or _huddles < tuning.story_first_huddle:
		return &""
	if stories_told > 0 and _huddles - _story_huddle < tuning.story_huddle_gap:
		return &""
	var due: StringName = &""
	var least: float = 1.0
	for thread: StringName in BoothStory.THREADS:
		var chapter: Dictionary = BoothStory.next(thread)
		var share: float = float(_told.get(thread, 0)) / float(maxi(BoothStory.share(thread), 1))
		if chapter.is_empty() or not story_recorded(chapter) or share >= least:
			continue
		least = share
		due = chapter[&"id"]
	return due if due != &"" and randf() < tuning.story_chance else &""


## There is a recording of every line of `chapter`.
func story_recorded(chapter: Dictionary) -> bool:
	return (_stories.get(chapter[&"id"], []) as Array).size() == (chapter[&"lines"] as Array).size()


## Starts the chapter that was waiting, if the ball is still dead; one that
## missed its huddle is asked for again at the next.
func _tell_story() -> void:
	var id: StringName = _story_pending
	_story_pending = &""
	var thread: StringName = BoothStory.thread_of_next(id)
	if not game.play_controller.ball_dead or thread == &"":
		return
	var chapter: Dictionary = BoothStory.next(thread)
	if not story_recorded(chapter):
		return
	_story_thread = thread
	var sound: StringName = StringName(STORY_PREFIX + id)
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var tony: bool = chapter[&"first"] == BoothStory.TONY
	for stream: AudioStream in _stories[id]:
		_exchange_parts.append([tony, stream])
		tony = not tony
	_story_playing = id
	exchange_counts[&"started"] += 1
	_say_part()


## The chapters of every thread that has been told to the end come up from
## now on like any other idle exchange.
func _retire_stories() -> void:
	for thread: StringName in BoothStory.THREADS:
		if not BoothStory.finished(thread):
			continue
		for chapter: Dictionary in BoothStory.chapters(thread):
			if not story_recorded(chapter):
				continue
			if not _exchanges.has(QUIP_IDLE):
				_exchanges[QUIP_IDLE] = []
			_exchanges[QUIP_IDLE].append({&"tony_first": chapter[&"first"] == BoothStory.TONY, &"parts": _stories[chapter[&"id"]]})


## A line of `sound` not said since the last time through them all: a stream,
## or an exchange (see _exchanges) unless only a `solo` line will do.
func _pick_fresh(sound: StringName, solo: bool = false) -> Variant:
	if _line_count(sound) == 0:
		missing[sound] = true
		return null
	var bag: Array = _bags.get(sound, [])
	if bag.is_empty():
		bag = (_streams.get(sound, []) as Array).duplicate()
		bag.append_array(_exchanges.get(sound, []))
		bag.shuffle()
	_bags[sound] = bag
	if not solo:
		return bag.pop_back()
	for i: int in range(bag.size() - 1, -1, -1):
		if bag[i] is AudioStream:
			return bag.pop_at(i)
	return null


## How many different lines there are for `sound`, exchanges included.
func _line_count(sound: StringName) -> int:
	return (_streams.get(sound, []) as Array).size() + (_exchanges.get(sound, []) as Array).size()


## The idle chatter that fits the score: a rout, a tight second half, or any
## old thing. Falls back on the usual kind where the other has no lines.
func _idle_quip() -> StringName:
	# With the commissioner in the closet, now and then it is him they hear.
	if story_on and BoothStory.captive() and has_sound(QUIP_IDLE_CAPTIVE) and randf() < tuning.story_captive_chance:
		return QUIP_IDLE_CAPTIVE
	# In a game of the season, now and then it is the season they talk about.
	if game.season_round >= 0 and randf() < tuning.season_idle_chance:
		var special: StringName = _season_take(QUIP_IDLE)
		if special != QUIP_IDLE:
			return special
	var margin: int = absi(game.home.score - game.home.opponent.score)
	var sound: StringName = QUIP_IDLE
	if margin >= tuning.audio_blowout_points:
		sound = QUIP_IDLE_BLOWOUT
	elif game.half >= 2 and margin <= tuning.audio_close_points:
		sound = QUIP_IDLE_CLOSE
	return sound if has_sound(sound) else QUIP_IDLE


## What Tony makes of the time running out: the break coming up, or the end of
## a rout, of a tight one or of anything between.
func _late_quip() -> StringName:
	var margin: int = absi(game.home.score - game.home.opponent.score)
	var sound: StringName = QUIP_LATE
	if game.half < 2:
		sound = QUIP_LATE_HALF
	elif margin >= tuning.audio_blowout_points:
		sound = QUIP_LATE_BLOWOUT
	elif margin <= tuning.audio_close_points:
		sound = QUIP_LATE_CLOSE
	return sound if has_sound(sound) else QUIP_LATE


## In the huddle with only a few plays' worth of clock left, Jim says so once
## a half and Tony has his say; on the last play Jim says that too. Tony's line
## is asked for again at each huddle until he has got it out. The try is
## untimed, so nothing is said before one.
func _late_calls() -> void:
	if game.conversion:
		return
	var plays_left: float = game.play_caller.situation(game).plays_left
	if plays_left > tuning.audio_late_plays:
		return
	if plays_left <= tuning.ai_call_last_play:
		if _last_play_called_half != game.half:
			_last_play_called_half = game.half
			_late_called_half = game.half
			announce([CALL_LAST_PLAY])
	elif _late_called_half != game.half:
		_late_called_half = game.half
		announce([CALL_LATE_HALF if game.half < 2 else CALL_LATE_GAME])
	if _late_quip_said_half != game.half:
		_insist(_late_quip())


## Down and distance for the play being lined up: "Second down. Seven to go."
func announce_down() -> void:
	if game.conversion:
		return
	var distance: StringName = &"announcer_goal"
	if not game.goal_to_go:
		var yards: int = game.yards_to_go()
		distance = StringName("announcer_togo%d" % yards) if yards <= 40 else &"announcer_long"
	_announcer_queue.clear()
	announce([StringName("announcer_down%d" % clampi(game.down, 1, 4)), distance])


## The play being lined up is fourth and twenty, and there is a joke on file.
func blaze_down() -> bool:
	return not game.conversion and game.down == BLAZE_DOWN and not game.goal_to_go \
			and game.yards_to_go() == BLAZE_YARDS and has_sound(QUIP_BLAZE)


func _speak(sound: StringName) -> void:
	play_counts[sound] = play_counts.get(sound, 0) + 1
	# In turn, so a remark with several takes does not repeat itself.
	var stream: AudioStream = _pick_fresh(sound, true) as AudioStream
	if stream == null or not tuning.audio_enabled:
		return
	_announcer.stream = stream
	_announcer.volume_linear = tuning.audio_announcer_level
	_announcer.play()


## A line from the quarterback. A new line cuts off the one before it. `fresh`
## goes through all the takes before one comes up again. Returns the line's
## length in seconds, 0 if nothing is heard.
func say(sound: StringName, fresh: bool = false) -> float:
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var stream: AudioStream = (_pick_fresh(sound, true) as AudioStream) if fresh else _pick(sound)
	if stream == null or not tuning.audio_enabled:
		return 0.0
	_voice.stream = stream
	_voice.play()
	return stream.get_length()


## The quarterback's cadence as the teams line up, now and then a silly line
## instead. Returns the length of a silly line, which is worth hearing out
## before the snap, and 0 for the usual cadence.
func qb_open() -> float:
	if has_sound(QB_SILLY) and randf() < tuning.qb_silly_open_chance:
		return say(QB_SILLY, true)
	say(&"qb_cadence")
	return 0.0


## One more shout from the quarterback before the snap, some of them silly.
func qb_call() -> void:
	var sound: StringName = QB_CALL
	if has_sound(QB_SILLY) and randf() < tuning.qb_silly_chance:
		sound = QB_SILLY
	elif not has_sound(QB_CALL):
		sound = &"qb_cadence"
	say(sound, true)


## Stirs the crowd without a cheer or a groan.
func excite(amount: float) -> void:
	excitement = clampf(excitement + amount, 0.0, 1.0)


## Something good happened for `team`, `size` 0..1. The crowd is the home
## team's: it cheers for it and groans (or boos, at the worst) for the visitors.
func crowd_react(team: Team, size: float) -> void:
	if team == game.home:
		excite(size)
		if size >= REACTION_SHOUT:
			play(&"crowd_cheer", size)
	else:
		excite(size * 0.3)
		if size >= 0.95:
			play(&"crowd_boo", size * 0.8)
		elif size >= REACTION_SHOUT:
			play(&"crowd_groan", size)


## A hit on `victim`: the crunch, and him landing. The person's own collisions
## are louder than the ones going on around them.
func hit(attacker: Player, victim: Player, big: bool) -> void:
	var mine: Player = game.human.controlled
	var near: bool = victim.has_ball or (mine != null and (attacker == mine or victim == mine))
	var volume: float = 1.0 if near else 0.5
	play(&"big_hit" if big else &"tackle", volume)
	play(&"body_fall", volume * 0.8)


## An action by `player` (dive, jump, spin...), quieter for the players the
## person is not controlling.
func action(player: Player, sound: StringName) -> void:
	play(sound, 1.0 if player == game.human.controlled or player.has_ball else 0.45)


# --- Following the game --------------------------------------------------------------

func _process(_delta: float) -> void:
	if game == null:
		return
	# Real time: hit-stop and the tests' fast-forward both bend the engine's delta.
	var now: int = Time.get_ticks_usec()
	var delta: float = minf(float(now - _last_tick) / 1000000.0, 0.1)
	_last_tick = now

	excitement = maxf(maxf(excitement - tuning.audio_crowd_decay * delta, 0.0), _live_excitement())
	# Quick to rise, slow to settle.
	var rate: float = 3.0 if excitement > _roar_level else 0.8
	_roar_level = move_toward(_roar_level, excitement, rate * delta)
	_roar.volume_linear = maxf(_roar_level * _roar_level * tuning.audio_crowd_roar_level, SILENT)

	_huddle_level = move_toward(_huddle_level, 1.0 if _huddle_on else 0.0, delta / FADE_TIME)
	_huddle.volume_linear = maxf(_huddle_level * tuning.audio_huddle_level, SILENT)
	if _huddle_level <= 0.0 and _huddle.playing:
		_huddle.stop()

	if _chant_in >= 0.0:
		_chant_in -= delta
		if _chant_in < 0.0:
			_start_chant()
	_update_booth(delta)
	_update_music(delta)
	if _chant_fading and _chant.playing:
		_chant.volume_linear = move_toward(_chant.volume_linear, 0.0, delta / FADE_TIME)
		if _chant.volume_linear <= SILENT:
			_chant.stop()


## What the play in progress alone is worth: a ball in the air, a long run, a
## loose ball. Keeps the crowd up for as long as it lasts.
func _live_excitement() -> float:
	var pc: PlayController = game.play_controller
	if pc.ball_dead:
		return 0.0
	match pc.phase:
		PlayController.Phase.AIR:
			return 0.35
		PlayController.Phase.LOOSE, PlayController.Phase.TIPPED:
			return 0.75
		PlayController.Phase.RUN:
			var carrier: Player = game.ball.carrier
			if carrier == null:
				return 0.2
			var start: float = tuning.own_goal_x(carrier.team.attack_dir) if pc.kickoff else pc.los_x
			if pc.scramble:
				start = pc.return_from_x
			var gain: float = (carrier.position.x - start) * float(carrier.team.attack_dir)
			if not _breakaway_called and gain >= (BREAKAWAY_RETURN_YARDS if pc.kickoff else BREAKAWAY_YARDS):
				_breakaway_called = true
				remark(&"announcer_room", REMARK_ROOM)
				# A handed-off back breaking loose gets his own line.
				if not pc.kickoff and not pc.scramble and pc.handoff_done and not pc.pass_completed() and carrier.ratings.position == "RB":
					quip(&"color_juice", QUIP_JUICE)
				else:
					quip(&"color_breakaway", QUIP_BREAKAWAY)
			return clampf(0.2 + gain / 25.0, 0.2, 0.9)
	return 0.0


func _on_state_changed(from: StringName, to: StringName) -> void:
	if from == &"PlaySelect":
		_huddle_on = false
		if game.human.is_active():
			play(&"huddle_break", 0.9)
	match to:
		&"PlaySelect":
			announce_down()
			_late_calls()
			if blaze_down():
				_insist(QUIP_BLAZE)
			_huddles += 1
			# A chapter a call interrupted is taken up before anything new.
			_story_resume = not _story_held.is_empty() and _quip_pending == &"" and _exchange_parts.is_empty() and tuning.audio_enabled
			_story_pending = _story_due()
			if _story_pending == &"" and not _story_resume:
				quip(_idle_quip(), tuning.audio_color_idle_chance)
			if game.human.is_active():
				_huddle_on = true
				if not _huddle.playing and tuning.audio_enabled:
					_huddle.play()
			_plan_chant()
		&"Live":
			_breakaway_called = false
			_chant_in = -1.0
			_chant_fading = true
		&"Scored":
			var scorer: Team = game.play_controller.final_team
			shout(&"announcer_touchdown")
			if game.play_controller.touchdown_quip != &"":
				quip(game.play_controller.touchdown_quip, QUIP_TOUCHDOWN)
			if scorer == game.home:
				play(&"air_horn", 0.8)
			crowd_react(scorer, 1.0)
		&"Turnover":
			match game.banner_text:
				"SAFETY!":
					shout(&"announcer_safety")
					crowd_react(game.offense, 1.0)
				"TURNOVER ON DOWNS":
					shout(&"announcer_downs")
					quip(&"color_downs", QUIP_DOWNS)
					crowd_react(game.offense, 0.7)
				_:
					crowd_react(game.offense, 0.5)
		&"Warning":
			play(&"whistle")
			shout(CALL_WARNING)
			excite(0.3)
		&"Halftime":
			play(&"buzzer")
			# The halftime report has an exchange of its own (HalftimeState).
			if not game.has_halftime_show():
				shout(&"announcer_half")
				quip(&"color_half", QUIP_HALF)
		&"Overtime":
			play(&"buzzer")
			excite(0.6)
			if has_sound(CALL_OVERTIME):
				shout(CALL_OVERTIME)
			var thought: StringName = StringName(QUIP_PREFIX + OVERTIME_MOMENT)
			if has_sound(thought):
				quip(thought, QUIP_OVERTIME_CHANCE)
		&"GameOver":
			# After sudden death the buzzer has already gone.
			if not game.overtime:
				play(&"buzzer")
			play_music(&"music_final")
			# A playoff game and the final of the season end on words of their own.
			shout(_season_take(StringName("announcer_final")))
			quip(_season_take(StringName(QUIP_PREFIX + "final")), QUIP_FINAL)
			var mine: Team = game.human.team if game.human.is_active() and game.human.team != null else game.home
			if mine.score > mine.opponent.score:
				crowd_react(mine, 1.0)
			elif mine.score < mine.opponent.score:
				crowd_react(mine.opponent, 1.0)


func _on_ball_bounced(strength: float) -> void:
	play(&"ball_bounce", clampf(strength, 0.25, 1.0))


## Between plays the crowd sometimes starts a chant: "defense" when the home
## team is defending, one of the others when it has the ball.
func _plan_chant() -> void:
	if _chant.playing or randf() >= tuning.audio_chant_chance:
		return
	if game.defense == game.home:
		_chant_name = &"crowd_chant_defense"
	else:
		_chant_name = &"crowd_chant_stomp_clap" if randf() < 0.5 else &"crowd_chant_lets_go"
	_chant_in = randf_range(0.3, 1.2)


func _start_chant() -> void:
	play_counts[_chant_name] = play_counts.get(_chant_name, 0) + 1
	var stream: AudioStream = _pick(_chant_name)
	if stream == null or not tuning.audio_enabled:
		return
	_chant_fading = false
	_chant.stream = stream
	_chant.volume_linear = tuning.audio_chant_level
	_chant.play()


# --- Internals -----------------------------------------------------------------------

## There is at least one file for `sound`.
func has_sound(sound: StringName) -> bool:
	return _line_count(sound) > 0


## A take of `sound` for somebody who plays it on a player of their own (the
## pause menu: everything here stops while the game is paused).
func stream_for(sound: StringName) -> AudioStream:
	return _pick(sound) if tuning.audio_enabled else null


func _pick(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		missing[sound] = true
		return null
	var takes: Array = _streams[sound]
	var stream: AudioStream = takes[randi() % takes.size()]
	return stream


func _bus_of(sound: StringName) -> StringName:
	var text: String = String(sound)
	if text.begins_with("crowd_") or text == "air_horn":
		return BUS_CROWD
	if text.begins_with("qb_") or text.begins_with("huddle_"):
		return BUS_VOICE
	if text.begins_with("ui_"):
		return BUS_UI
	if text.begins_with(MUSIC_PREFIX):
		return BUS_MUSIC
	return BUS_SFX


## A player that is idle, or failing that the next one in turn.
func _free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _pool:
		if not player.playing:
			return player
	_next_voice = (_next_voice + 1) % _pool.size()
	return _pool[_next_voice]


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _make_loop(sound: StringName, bus: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = _make_player(bus)
	var stream: AudioStream = _pick(sound)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	player.stream = stream
	return player


## The buses live in the AudioServer, which outlasts a reload of the scene.
## The main menu makes them too: it plays its sounds before any match has.
static func make_buses(tuning: Tuning) -> void:
	var levels: Dictionary[StringName, float] = {
		BUS_SFX: tuning.audio_sfx_db,
		BUS_CROWD: tuning.audio_crowd_db,
		BUS_VOICE: tuning.audio_voice_db,
		BUS_UI: tuning.audio_ui_db,
		BUS_MUSIC: tuning.audio_music_db,
	}
	for bus: StringName in levels:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			index = AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
		AudioServer.set_bus_volume_db(index, levels[bus])
	AudioServer.set_bus_volume_db(0, tuning.audio_master_db)


## Finds every take in the audio folder. An exported game lists the imported
## files as `name.ext.import`, so that ending is ignored.
func _load_streams() -> void:
	# The parts of each exchange by number, under its `chat_...` name.
	var chats: Dictionary[String, Dictionary] = {}
	var seen: Dictionary[String, bool] = {}
	for file: String in DirAccess.get_files_at(AUDIO_DIR):
		var path: String = file.trim_suffix(".import")
		if seen.has(path) or not EXTENSIONS.has(path.get_extension()) or path.begins_with(MENU_PREFIX):
			continue
		seen[path] = true
		var base: String = path.get_basename()
		var cut: int = base.rfind("_")
		if cut < 0 or not base.substr(cut + 1).is_valid_int():
			continue
		var stream: AudioStream = load(AUDIO_DIR.path_join(path)) as AudioStream
		if stream == null:
			continue
		var key: String = base.substr(0, cut)
		if key.begins_with(CHAT_PREFIX) or key.begins_with(SHOW_PREFIX) or key.begins_with(STORY_PREFIX):
			if not chats.has(key):
				chats[key] = {}
			chats[key][base.substr(cut + 1).to_int()] = stream
			continue
		var sound: StringName = StringName(key)
		if not _streams.has(sound):
			_streams[sound] = []
		_streams[sound].append(stream)
	for chat: String in chats:
		if chat.begins_with(SHOW_PREFIX):
			_add_show(chat, chats[chat], SHOW_PREFIX, _shows)
		elif chat.begins_with(STORY_PREFIX):
			_add_show(chat, chats[chat], STORY_PREFIX, _stories)
		else:
			_add_exchange(chat, chats[chat])


## Files `show_<id>_<part>` make halftime exchange `id`, and `story_<id>_<part>`
## chapter `id` of the story: the lines in order, filed in `into` under the
## name less its `prefix`. One with a part missing is left out.
func _add_show(show: String, parts: Dictionary, prefix: String, into: Dictionary[StringName, Array]) -> void:
	var streams: Array[AudioStream] = []
	for part: int in range(1, parts.size() + 1):
		if parts.has(part):
			streams.append(parts[part])
	if streams.size() != parts.size() or streams.size() < 2:
		broken_exchanges.append(show)
		return
	into[StringName(show.trim_prefix(prefix))] = streams


## Files `chat_<moment>_<t|j><k>_<part>` make one exchange of `color_<moment>`:
## Tony or Jim first, then turn about. One with a part missing is left out.
func _add_exchange(chat: String, parts: Dictionary) -> void:
	var cut: int = chat.rfind("_")
	var who: String = chat.substr(cut + 1, 1)
	var moment: String = chat.substr(CHAT_PREFIX.length(), cut - CHAT_PREFIX.length())
	var streams: Array[AudioStream] = []
	for part: int in range(1, parts.size() + 1):
		if parts.has(part):
			streams.append(parts[part])
	if streams.size() != parts.size() or streams.size() < 2 or moment.is_empty() or not (who == "t" or who == "j"):
		broken_exchanges.append(chat)
		return
	var sound: StringName = StringName(QUIP_PREFIX + moment)
	if not _exchanges.has(sound):
		_exchanges[sound] = []
	_exchanges[sound].append({&"tony_first": who == "t", &"parts": streams})
