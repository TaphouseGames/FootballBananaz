extends SceneTree
## Headless check that the Hail Mary takes the top-left card's place (the first
## offensive play) only in either half's last Tuning.hail_mary_time seconds,
## only from more than Tuning.hail_mary_min_distance yards out, and never on a
## conversion try.
##
## Run:  godot --headless --path . --script res://tests/hail_mary_check.gd

const FAR: float = 50.0

var _game: Game
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = true
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null or not _game.is_node_ready():
		return false
	var book: OffensePlaybook = _game.offense_playbook
	var first: OffensePlay = book.plays[0]
	var limit: float = _game.tuning.hail_mary_time
	var min_distance: float = _game.tuning.hail_mary_min_distance
	_expect(book.hail_mary != null, "the offense playbook has no Hail Mary")
	_expect(not book.plays.has(book.hail_mary), "the Hail Mary is also in the regular playbook")
	_check(2, limit - 1.0, false, FAR, book.hail_mary, "last seconds of the game")
	_check(2, limit, false, FAR, book.hail_mary, "exactly at the limit")
	_check(2, 0.0, false, FAR, book.hail_mary, "clock run out (last play)")
	_check(2, limit + 1.0, false, FAR, first, "just over the limit")
	_check(1, limit - 1.0, false, FAR, book.hail_mary, "last seconds of the first half")
	_check(1, limit + 1.0, false, FAR, first, "first half, just over the limit")
	_check(1, limit - 1.0, false, 5.0, first, "first half, close to the goal line")
	_check(2, limit - 1.0, true, FAR, first, "conversion try")
	_check(2, limit - 1.0, false, min_distance + 1.0, book.hail_mary, "just outside the minimum distance")
	_check(2, limit - 1.0, false, min_distance, first, "exactly at the minimum distance")
	_check(2, limit - 1.0, false, 5.0, first, "close to the goal line")
	var plays: Array[OffensePlay] = _game.offense_plays()
	_expect(plays.size() == book.plays.size(), "the play count changed")
	_expect(book.plays[0] == first, "the playbook itself was changed")
	if _failures.is_empty():
		print("hail_mary_check PASSED")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("hail_mary_check FAILED")
	quit(0 if _failures.is_empty() else 1)
	return true


func _check(half: int, clock: float, conversion: bool, to_goal: float, want: OffensePlay, label: String) -> void:
	_game.half = half
	_game.clock = clock
	_game.conversion = conversion
	var dir: int = _game.offense.attack_dir
	_game.los_x = _game.tuning.goal_x(dir) - float(dir) * to_goal
	var got: OffensePlay = _game.offense_plays()[0]
	_expect(got == want, "%s: first card is %s, wanted %s" % [label, got.play_name, want.play_name])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
