class_name AudioDirector
extends Node
## Every sound in the game: one-shot effects, the quarterback's voice, the huddle
## and the crowd. Gameplay code calls play(), say() and crowd_react(); the loops
## and the sounds tied to a game state run off the state machine's signal.
##
## Sounds are files in assets/audio named `<sound>_<n>.<ext>`; every numbered
## take of a sound is a variation picked at random.

const AUDIO_DIR: String = "res://assets/audio"
const EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
const BUS_SFX: StringName = &"SFX"
const BUS_CROWD: StringName = &"Crowd"
const BUS_VOICE: StringName = &"Voice"
const BUS_UI: StringName = &"UI"
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
const BREAKAWAY_YARDS: float = 20.0
const BREAKAWAY_RETURN_YARDS: float = 40.0

var game: Game
var tuning: Tuning
## How worked up the crowd is, 0..1. Drives the roar under the steady murmur.
var excitement: float = 0.0
## Times each sound was asked for, and the ones asked for that have no file.
var play_counts: Dictionary[StringName, int] = {}
var missing: Dictionary[StringName, bool] = {}
## Times a remark was asked for, before the dice and the gap had their say.
var remark_asks: Dictionary[StringName, int] = {}

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
	_make_buses()
	_load_streams()
	for i: int in POOL_SIZE:
		_pool.append(_make_player(BUS_SFX))
	_bed = _make_loop(&"crowd_bed", BUS_CROWD)
	_roar = _make_loop(&"crowd_roar", BUS_CROWD)
	_huddle = _make_loop(&"huddle_murmur", BUS_VOICE)
	_chant = _make_player(BUS_CROWD)
	_voice = _make_player(BUS_VOICE)
	_announcer = _make_player(BUS_VOICE)
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
	if _announcer.playing or not _announcer_queue.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_remark < int(tuning.audio_remark_gap * 1000.0):
		return
	if randf() >= chance * tuning.audio_remark_scale:
		return
	_last_remark = now
	_speak(sound)


## The announcer drops everything and shouts `sound`.
func shout(sound: StringName) -> void:
	_announcer_queue.clear()
	_speak(sound)


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


func _speak(sound: StringName) -> void:
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var stream: AudioStream = _pick(sound)
	if stream == null or not tuning.audio_enabled:
		return
	_announcer.stream = stream
	_announcer.volume_linear = tuning.audio_announcer_level
	_announcer.play()


## A line from the quarterback. A new line cuts off the one before it.
func say(sound: StringName) -> void:
	play_counts[sound] = play_counts.get(sound, 0) + 1
	var stream: AudioStream = _pick(sound)
	if stream == null or not tuning.audio_enabled:
		return
	_voice.stream = stream
	_voice.play()


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
	if not _announcer_queue.is_empty() and not _announcer.playing:
		_speak(_announcer_queue.pop_front())
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
		PlayController.Phase.LOOSE:
			return 0.75
		PlayController.Phase.RUN:
			var carrier: Player = game.ball.carrier
			if carrier == null:
				return 0.2
			var start: float = tuning.own_goal_x(carrier.team.attack_dir) if pc.kickoff else pc.los_x
			var gain: float = (carrier.position.x - start) * float(carrier.team.attack_dir)
			if not _breakaway_called and gain >= (BREAKAWAY_RETURN_YARDS if pc.kickoff else BREAKAWAY_YARDS):
				_breakaway_called = true
				remark(&"announcer_room", REMARK_ROOM)
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
			if game.human.is_active():
				_huddle_on = true
				if not _huddle.playing and tuning.audio_enabled:
					_huddle.play()
			_plan_chant()
		&"PreSnap":
			say(&"qb_cadence")
		&"Live":
			_breakaway_called = false
			_chant_in = -1.0
			_chant_fading = true
		&"Scored":
			var scorer: Team = game.play_controller.final_team
			shout(&"announcer_touchdown")
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
					crowd_react(game.offense, 0.7)
				_:
					crowd_react(game.offense, 0.5)
		&"Halftime":
			play(&"buzzer")
			shout(&"announcer_half")
		&"GameOver":
			play(&"buzzer")
			shout(&"announcer_final")
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
	return _streams.has(sound)


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
func _make_buses() -> void:
	var levels: Dictionary[StringName, float] = {
		BUS_SFX: tuning.audio_sfx_db,
		BUS_CROWD: tuning.audio_crowd_db,
		BUS_VOICE: tuning.audio_voice_db,
		BUS_UI: tuning.audio_ui_db,
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
	var seen: Dictionary[String, bool] = {}
	for file: String in DirAccess.get_files_at(AUDIO_DIR):
		var path: String = file.trim_suffix(".import")
		if seen.has(path) or not EXTENSIONS.has(path.get_extension()):
			continue
		seen[path] = true
		var base: String = path.get_basename()
		var cut: int = base.rfind("_")
		if cut < 0 or not base.substr(cut + 1).is_valid_int():
			continue
		var stream: AudioStream = load(AUDIO_DIR.path_join(path)) as AudioStream
		if stream == null:
			continue
		var sound: StringName = StringName(base.substr(0, cut))
		if not _streams.has(sound):
			_streams[sound] = []
		_streams[sound].append(stream)
