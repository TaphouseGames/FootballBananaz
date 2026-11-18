extends SceneTree
## Headless check of what the moves cost in stamina (the turbo meter):
## - a jump, a dive, a spin and a stiff arm each spend their Tuning
##   *_stamina_cost scaled by the player's endurance (Player.stamina_cost),
##   and a dive out of a jump pays for both;
## - with less than the cost left the move spends what there is, empties and
##   locks the meter and is that much weaker;
## - on an empty meter the move still happens at Tuning.move_min_strength:
##   a lower jump, a shorter dive, a slower spin with a smaller sidestep;
## - a dive after the whistle (`free`) costs nothing;
## - the CPU's look ahead (move_strength with `spend` off) spends nothing.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/stamina_check.gd
## A few seconds. All of it happens within one physics tick.

const RUN: Vector3 = Vector3(6.0, 0.0, 0.0)

var _game: Game
var _tuning: Tuning
var _man: Player
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready() or _game.human == null or _game.human.team == null:
		return
	_tuning = _game.tuning
	_man = _game.human.team.players[0]
	var low: float = _tuning.move_min_strength
	var half: float = lerpf(low, 1.0, 0.5)
	_expect(low > 0.0 and low < 1.0, "move_min_strength is %.2f: an empty meter should give a weak move, not none or a full one" % low)

	# Each move at a full meter, half its cost left, and nothing left.
	var moves: Array[Dictionary] = [
		{"name": "jump", "cost": _tuning.jump_stamina_cost, "want": 0.15},
		{"name": "dive", "cost": _tuning.dive_stamina_cost, "want": 0.03},
		{"name": "spin", "cost": _tuning.spin_stamina_cost, "want": 0.05},
		{"name": "stiff arm", "cost": _tuning.stiff_arm_stamina_cost, "want": 0.05},
	]
	for move: Dictionary in moves:
		var what: String = move["name"]
		var base: float = move["cost"]
		_expect(absf(base - float(move["want"])) < 0.0001, "%s costs %.3f, should be %.3f" % [what, base, float(move["want"])])
		# What this man pays: the tuning value scaled by his endurance.
		var cost: float = _man.stamina_cost(base)
		var full: float = _effect(what, 1.0)
		_expect(absf(_man.turbo - (1.0 - cost)) < 0.0001, "%s on a full meter leaves %.3f, should be %.3f" % [what, _man.turbo, 1.0 - cost])
		_expect(not _man.turbo_locked, "%s on a full meter locked turbo" % what)
		_expect(absf(_strength(what) - 1.0) < 0.0001, "%s on a full meter has strength %.2f" % [what, _strength(what)])

		var exact: float = _effect(what, cost)
		_expect(absf(_strength(what) - 1.0) < 0.0001, "%s with exactly its cost left has strength %.2f" % [what, _strength(what)])
		_expect(_man.turbo <= 0.0 and _man.turbo_locked, "%s with exactly its cost left did not empty and lock the meter" % what)
		_expect(absf(exact - full) < 0.0001, "%s with exactly its cost left is weaker than a full one" % what)

		var short: float = _effect(what, cost * 0.5)
		_expect(_man.turbo <= 0.0 and _man.turbo_locked, "%s with half its cost left did not empty and lock the meter (%.3f)" % [what, _man.turbo])
		_expect(absf(_strength(what) - half) < 0.0001, "%s with half its cost left has strength %.3f, should be %.3f" % [what, _strength(what), half])

		var empty: float = _effect(what, 0.0)
		_expect(_state(what), "%s on an empty meter did not happen" % what)
		_expect(absf(_strength(what) - low) < 0.0001, "%s on an empty meter has strength %.3f, should be %.3f" % [what, _strength(what), low])
		print("%s: costs %.2f; full %.3f, half the cost %.3f, empty %.3f" % [what, cost, full, short, empty])
		if what != "stiff arm":
			_expect(short < full - 0.0001 and empty < short - 0.0001, "%s does not get weaker with less stamina (%.3f, %.3f, %.3f)" % [what, full, short, empty])
		if what == "jump" or what == "dive":
			_expect(absf(short - full * half) < 0.001, "%s with half its cost left comes to %.3f, should be %.3f" % [what, short, full * half])
			_expect(absf(empty - full * low) < 0.001, "%s on an empty meter comes to %.3f, should be %.3f" % [what, empty, full * low])

	# A juking spin sidesteps less.
	_ready_man(1.0)
	_man.start_spin(1.0, true)
	var wide: float = absf(_man.velocity.z)
	_ready_man(0.0)
	_man.start_spin(1.0, true)
	_expect(wide > 0.1 and absf(absf(_man.velocity.z) - wide * low) < 0.001, "a juke on an empty meter slides at %.2f, a full one at %.2f" % [absf(_man.velocity.z), wide])

	# A dive out of a jump pays for the jump and for the dive.
	_ready_man(1.0)
	_expect(_man.start_jump(), "he does not jump")
	_expect(_man.start_jump_dive(Vector3.RIGHT), "he does not dive out of the jump")
	var jump_cost: float = _man.stamina_cost(_tuning.jump_stamina_cost)
	var both: float = jump_cost + _man.stamina_cost(_tuning.dive_stamina_cost)
	_expect(absf(_man.turbo - (1.0 - both)) < 0.0001, "a jump dive leaves %.3f, should be %.3f" % [_man.turbo, 1.0 - both])
	var far: float = _man.velocity.length()
	# With only the jump paid for the dive is a weak one.
	_ready_man(jump_cost)
	_man.start_jump()
	_expect(absf(_man.jump_strength - 1.0) < 0.0001, "the jump he could pay for is a weak one")
	_man.start_jump_dive(Vector3.RIGHT)
	_expect(absf(_man.velocity.length() - far * low) < 0.001, "a jump dive with nothing left for the dive flies at %.2f, should be %.2f" % [_man.velocity.length(), far * low])

	# After the whistle a dive is free.
	_ready_man(0.5)
	_man.start_dive(Vector3.RIGHT, -1.0, true)
	_expect(absf(_man.turbo - 0.5) < 0.0001 and absf(_man.dive_strength - 1.0) < 0.0001, "a free dive cost stamina or came out weak")

	# Looking ahead spends nothing.
	_ready_man(jump_cost * 0.5)
	var peek: float = _man.move_strength(_tuning.jump_stamina_cost, false)
	_expect(absf(peek - half) < 0.0001, "the look ahead says %.3f, should be %.3f" % [peek, half])
	_expect(absf(_man.turbo - jump_cost * 0.5) < 0.0001 and not _man.turbo_locked, "the look ahead spent stamina")
	_expect(absf(_man.jump_height(peek) - _man.jump_height(1.0) * half) < 0.0001, "jump_height does not take the strength it is given")

	# Endurance scales what a move costs, as it scales the sprint drain.
	var own: int = _man.ratings.endurance
	for rated: Array in [[0, _tuning.endurance_drain_low], [50, lerpf(_tuning.endurance_drain_low, _tuning.endurance_drain_high, 0.5)], [100, _tuning.endurance_drain_high]]:
		_man.ratings.endurance = int(rated[0])
		var want: float = _tuning.jump_stamina_cost * float(rated[1])
		_ready_man(1.0)
		_man.start_jump()
		print("endurance %d: a jump costs %.3f" % [int(rated[0]), 1.0 - _man.turbo])
		_expect(absf(_man.turbo - (1.0 - want)) < 0.0001, "at %d endurance a jump leaves %.3f, should be %.3f" % [int(rated[0]), _man.turbo, 1.0 - want])
		_expect(absf(_man.jump_strength - 1.0) < 0.0001, "at %d endurance a jump on a full meter is a weak one" % int(rated[0]))
	_man.ratings.endurance = own
	_expect(_tuning.endurance_drain_high < _tuning.endurance_drain_low, "good endurance does not make moves cheaper")

	_ready_man(1.0)
	_man.frozen = true
	_finish()


## Does the move with `stamina` on the meter and returns what there is to
## measure of it: the height of the jump, the speed of the dive or the spin.
func _effect(what: String, stamina: float) -> float:
	_ready_man(stamina)
	match what:
		"jump":
			_man.start_jump()
			return _man.jump_height()
		"dive":
			_man.start_dive(Vector3.RIGHT)
			return _man.velocity.length()
		"spin":
			_man.start_spin(1.0)
			return _man.velocity.length()
		_:
			_man.start_stiff_arm(1.0)
			return _man.stiff_arm_strength


func _strength(what: String) -> float:
	match what:
		"jump":
			return _man.jump_strength
		"dive":
			return _man.dive_strength
		"spin":
			return _man.spin_strength
	return _man.stiff_arm_strength


func _state(what: String) -> bool:
	match what:
		"jump":
			return _man.state == Player.State.JUMPING
		"dive":
			return _man.state == Player.State.DIVING
		"spin":
			return _man.state == Player.State.SPINNING
	return _man.state == Player.State.STIFF_ARM


func _ready_man(stamina: float) -> void:
	_man.state = Player.State.NORMAL
	_man.frozen = false
	_man.turbo = stamina
	_man.turbo_locked = false
	_man.move_cooldown = 0.0
	_man.jump_cooldown = 0.0
	_man.facing = Vector3.RIGHT
	_man.velocity = RUN


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("STAMINA CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("STAMINA CHECK FAILED: %s" % failure)
		quit(1)
