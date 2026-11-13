extends SceneTree
## Headless check that the Hail Mary takes the top-left card's place (the first
## offensive play) only in the second half's last Tuning.hail_mary_time seconds,
## and never on a conversion try.
##
## Run:  godot --headless --path . --script res://tests/hail_mary_check.gd

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
	_expect(book.hail_mary != null, "the offense playbook has no Hail Mary")
	_expect(not book.plays.has(book.hail_mary), "the Hail Mary is also in the regular playbook")
	_check(2, limit - 1.0, false, book.hail_mary, "last seconds of the game")
	_check(2, limit, false, book.hail_mary, "exactly at the limit")
	_check(2, 0.0, false, book.hail_mary, "clock run out (last play)")
	_check(2, limit + 1.0, false, first, "just over the limit")
	_check(1, limit - 1.0, false, first, "last seconds of the first half")
	_check(2, limit - 1.0, true, first, "conversion try")
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


func _check(half: int, clock: float, conversion: bool, want: OffensePlay, label: String) -> void:
	_game.half = half
	_game.clock = clock
	_game.conversion = conversion
	var got: OffensePlay = _game.offense_plays()[0]
	_expect(got == want, "%s: first card is %s, wanted %s" % [label, got.play_name, want.play_name])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
