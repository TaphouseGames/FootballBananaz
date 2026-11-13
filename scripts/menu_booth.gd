class_name MenuBooth
extends Node
## Jim and Tony on the main menu and the team select: they welcome the person,
## remark on the button that is highlighted and on what gets picked, and wonder
## aloud when nothing happens. Who they are is in docs/booth.md.
##
## The lines are files `menu_<moment>_<t|j><k>_<part>.<ext>` in assets/audio:
## line `k` of a moment, the letter saying who speaks first (Tony or Jim), the
## parts said turn about. A line with one part is one of them on his own.
##
## A moment's lines come up in a random order, each once before any comes
## again, and that order is kept from one visit to the menu to the next.

const PREFIX: String = "menu_"
## Seconds of quiet between one voice finishing and the next starting.
const BREATH: float = 0.25
## Seconds a remark waits for whoever is talking before it is not worth making.
const STALE: float = 2.5

## The lines of each moment not said yet this time round (their place among the
## moment's lines), and the one said last.
static var _bags: Dictionary[StringName, Array] = {}
static var _last: Dictionary[StringName, int] = {}

var tuning: Tuning
## Times each moment was asked for, before the dwell, the rest and the dice.
var asks: Dictionary[StringName, int] = {}
## Every line said, in order: [moment, its place among the moment's lines].
var history: Array[Array] = []
## The sets left out for a missing part or a bad name.
var broken: PackedStringArray = PackedStringArray()

## The lines of each moment. One is {tony_first: bool, parts: Array[AudioStream]}.
var _lines: Dictionary[StringName, Array] = {}
var _jim: AudioStreamPlayer
var _tony: AudioStreamPlayer
## The parts still to come of the line being said: [by Tony, stream] each.
var _parts: Array[Array] = []
var _quiet: float = BREATH
## The remark held back until the highlight has stayed put: its moment, the
## seconds still to wait, whether it cuts in on whoever is talking, and whether
## a lesser remark may take its place.
var _pending: StringName = &""
var _pending_in: float = 0.0
var _pending_age: float = 0.0
var _pending_urgent: bool = false
var _pending_sticky: bool = false
## Seconds since each moment was last talked about, and since the last input.
var _rest: Dictionary[StringName, float] = {}
var _idle: float = 0.0


func setup(p_tuning: Tuning) -> void:
	tuning = p_tuning
	_jim = _make_player()
	_tony = _make_player()
	_load_lines()


# --- Asking --------------------------------------------------------------------------

## The two say a line of `moment` now, in place of whatever they were saying.
## False if nothing will be heard.
func react(moment: StringName) -> bool:
	asks[moment] = asks.get(moment, 0) + 1
	_pending = &""
	touch()
	return _say(moment, true)


## They may remark on `moment` (`chance` of the time) once `dwell` seconds have
## passed without another remark coming up in its place. An `urgent` one cuts
## in on whoever is talking and rests only `gap` seconds; the others wait their
## turn. A `sticky` one is not replaced by a remark that is not urgent.
func consider(moment: StringName, chance: float, dwell: float, gap: float, urgent: bool = false, sticky: bool = false) -> void:
	asks[moment] = asks.get(moment, 0) + 1
	touch()
	if _pending_sticky and _pending != &"" and not urgent:
		return
	_pending = &""
	_pending_sticky = false
	if not has(moment) or _rest.get(moment, 1000.0) < gap or randf() >= chance:
		return
	_pending = moment
	_pending_in = dwell
	_pending_age = 0.0
	_pending_urgent = urgent
	_pending_sticky = sticky


## The highlight moved on to something they have nothing to say about.
func forget() -> void:
	if not _pending_sticky:
		_pending = &""
	touch()


## Something was pressed: they are not left wondering if anyone is there.
func touch() -> void:
	_idle = 0.0


## Both stop in the middle of the word.
func hush() -> void:
	_parts.clear()
	_pending = &""
	_jim.stop()
	_tony.stop()


func busy() -> bool:
	return _jim.playing or _tony.playing or not _parts.is_empty()


## Who is talking right now: &"jim", &"tony" or nobody.
func speaker() -> StringName:
	if _tony.playing:
		return &"tony"
	return &"jim" if _jim.playing else &""


## There is at least one line for `moment`.
func has(moment: StringName) -> bool:
	return line_count(moment) > 0


func line_count(moment: StringName) -> int:
	return (_lines.get(moment, []) as Array).size()


func moments() -> Array[StringName]:
	return _lines.keys()


# --- Talking -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if tuning == null:
		return
	for rested: StringName in _rest:
		_rest[rested] += delta
	_idle += delta
	_update_pending(delta)
	if _jim.playing or _tony.playing:
		_quiet = 0.0
		return
	_quiet += delta
	if _quiet < BREATH:
		return
	if not _parts.is_empty():
		_say_part()
	elif _pending == &"" and _idle >= tuning.menu_voice_idle_time:
		_idle = 0.0
		asks[&"idle"] = asks.get(&"idle", 0) + 1
		_say(&"idle", false)


func _update_pending(delta: float) -> void:
	if _pending == &"":
		return
	_pending_in -= delta
	if _pending_in > 0.0:
		return
	if busy() and not _pending_urgent:
		_pending_age += delta
		if _pending_age > STALE:
			_pending = &""
		return
	var moment: StringName = _pending
	_pending = &""
	_pending_sticky = false
	_say(moment, _pending_urgent)


## Starts a line of `moment`. False if there is none or the sound is off.
func _say(moment: StringName, cut_in: bool) -> bool:
	var lines: Array = _lines.get(moment, [])
	if lines.is_empty() or (busy() and not cut_in):
		return false
	var index: int = _next(moment, lines.size())
	history.append([moment, index])
	_rest[moment] = 0.0
	if not tuning.audio_enabled:
		return false
	if cut_in:
		hush()
	var line: Dictionary = lines[index]
	var tony: bool = line[&"tony_first"]
	for stream: AudioStream in line[&"parts"]:
		_parts.append([tony, stream])
		tony = not tony
	_say_part()
	return true


func _say_part() -> void:
	var part: Array = _parts.pop_front()
	var player: AudioStreamPlayer = _tony if part[0] else _jim
	player.stream = part[1] as AudioStream
	player.volume_linear = tuning.audio_color_level if part[0] else tuning.audio_announcer_level
	player.play()
	_quiet = 0.0


## Which of `count` lines of `moment` comes next: each once in a random order,
## and the first of a new round is never the last of the one before.
static func _next(moment: StringName, count: int) -> int:
	var bag: Array = (_bags.get(moment, []) as Array).filter(func(index: int) -> bool: return index < count)
	if bag.is_empty():
		bag.assign(range(count))
		bag.shuffle()
		if count > 1 and bag.back() == _last.get(moment, -1):
			bag.push_front(bag.pop_back())
	var index: int = bag.pop_back()
	_bags[moment] = bag
	_last[moment] = index
	return index


# --- Internals -----------------------------------------------------------------------

func _make_player() -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = AudioDirector.BUS_VOICE
	add_child(player)
	return player


## Finds every menu line in the audio folder. An exported game lists the
## imported files as `name.ext.import`, so that ending is ignored.
func _load_lines() -> void:
	# The parts of each line by number, under its `menu_<moment>_<t|j><k>` name.
	var sets: Dictionary[String, Dictionary] = {}
	var seen: Dictionary[String, bool] = {}
	for file: String in DirAccess.get_files_at(AudioDirector.AUDIO_DIR):
		var path: String = file.trim_suffix(".import")
		if seen.has(path) or not path.begins_with(PREFIX) or not AudioDirector.EXTENSIONS.has(path.get_extension()):
			continue
		seen[path] = true
		var base: String = path.get_basename()
		var cut: int = base.rfind("_")
		if cut < 0 or not base.substr(cut + 1).is_valid_int():
			broken.append(base)
			continue
		var stream: AudioStream = load(AudioDirector.AUDIO_DIR.path_join(path)) as AudioStream
		if stream == null:
			broken.append(base)
			continue
		var key: String = base.substr(0, cut)
		if not sets.has(key):
			sets[key] = {}
		sets[key][base.substr(cut + 1).to_int()] = stream
	var names: Array[String] = sets.keys()
	# In the order of their names, so a line keeps its place from run to run.
	names.sort()
	for key: String in names:
		_add_line(key, sets[key])


func _add_line(key: String, parts: Dictionary) -> void:
	var cut: int = key.rfind("_")
	var who: String = key.substr(cut + 1, 1)
	var moment: String = key.substr(PREFIX.length(), cut - PREFIX.length())
	var streams: Array[AudioStream] = []
	for part: int in range(1, parts.size() + 1):
		if parts.has(part):
			streams.append(parts[part])
	if streams.size() != parts.size() or cut < PREFIX.length() or moment.is_empty() or not (who == "t" or who == "j"):
		broken.append(key)
		return
	var key_moment: StringName = StringName(moment)
	if not _lines.has(key_moment):
		_lines[key_moment] = []
	_lines[key_moment].append({&"tony_first": who == "t", &"parts": streams})
