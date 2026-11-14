extends SceneTree
## Headless check of the jump dive (dive pressed in the air from a jump):
## it goes further than a dive off the ground, and further from the top of the
## jump than from low down; the diver lands dazed, with stars round his head,
## and stays down for the daze; a carrier scores in the air with it; the
## person's buttons start one; and the CPU uses it for the goal line and for a
## carrier who is getting away.
##
## Run:  godot --headless --fixed-fps 60 --path . --script res://tests/jump_dive_check.gd

enum Case { GROUND, LOW, TOP, GOAL_LINE, DAZE, BUTTONS, CPU_LINE, CPU_CHASE }

const CASE_NAMES: Array[String] = ["ground dive", "jump dive, low", "jump dive, top", "goal line", "daze", "buttons", "cpu at the line", "cpu chase"]
const STUCK_TICKS: int = 600
## Ticks into the jump at which the low jump dive is let go.
const LOW_TICK: int = 3

var _game: Game
var _pc: PlayController
var _tuning: Tuning
var _person: Team
var _cpu: Team
var _case: int = -1
var _ticks: int = 0
var _man: Player
var _dir: float = 1.0
var _dived: bool = false
var _dive_x: float = 0.0
var _dive_height: float = 0.0
var _landed: bool = false
var _distances: Array[float] = [0.0, 0.0, 0.0]
var _down_ticks: int = 0
var _stars_seen: int = 0
var _stars_high: bool = true
var _healthy: PlayerRatings
var _speed_before: int = 0
var _stat_before: Dictionary[StringName, int] = {}
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as Game
	_game.autoplay = false
	root.add_child(_game)
	physics_frame.connect(_tick)


func _tick() -> void:
	if _game == null or not _game.is_node_ready():
		return
	if _pc == null:
		_pc = _game.play_controller
		_tuning = _game.tuning
		_person = _game.human.team
		if _person == null:
			_failures.append("nobody is playing: the scene has no person's team")
			_finish()
			return
		_cpu = _person.opponent
		# The CPU always goes for it, so the two CPU cases do not hang on a roll.
		_tuning.ai_jump_dive_chance = 1.0
		_tuning.ai_edge_jump_dive_chance = 1.0
		_next()
		return
	_ticks += 1
	if _ticks > STUCK_TICKS:
		_fail("never finished")
		_next()
		return
	match _case:
		Case.GROUND, Case.LOW, Case.TOP:
			_tick_distance()
		Case.GOAL_LINE:
			_tick_goal_line()
		Case.DAZE:
			_tick_daze()
		Case.BUTTONS:
			_tick_buttons()
		Case.CPU_LINE:
			_tick_cpu_line()
		Case.CPU_CHASE:
			_tick_cpu_chase()


## Lets go of the jump at the moment the case asks for. True once he has dived.
func _release(top: bool) -> bool:
	if _dived:
		return true
	if _man.state != Player.State.JUMPING:
		return false
	var due: bool = _man.state_timer <= _tuning.jump_time * 0.5 if top else _ticks >= LOW_TICK
	if not due:
		return false
	_dive_height = _man.air_height()
	_dive_x = _man.position.x
	_pc.do_jump_dive(_man, Vector3(_dir, 0.0, 0.0))
	_dived = true
	_expect(_man.state == Player.State.DIVING and _man.jump_dive, "the jump dive did not start")
	return true


func _tick_distance() -> void:
	if _case != Case.GROUND and not _release(_case == Case.TOP):
		return
	if not _landed and _man.is_down():
		_landed = true
		_distances[_case] = (_man.position.x - _dive_x) * _dir
		_expect(_man.is_dazed() == (_case != Case.GROUND), "dazed: %s" % _man.is_dazed())
		_expect(not _pc.ball_dead, "whistle on the tick the leap ended, before he landed")
	if not _pc.ball_dead:
		return
	print("%-16s %.2f yd in the air from %.2f up, down by his own dive: %s" % [CASE_NAMES[_case], _distances[_case], _dive_height, _pc.was_dive])
	_expect(_landed, "the play ended before he came down")
	_expect(_pc.result == PlayController.Result.TACKLED and _pc.was_dive, "not ruled down by his own dive")
	_expect(_man.is_grounded(), "whistle before the fall had landed")
	if _case == Case.TOP:
		_expect(_distances[Case.LOW] > _distances[Case.GROUND] + 0.5, "a low jump dive went no further than a ground dive")
		_expect(_distances[Case.TOP] > _distances[Case.LOW] + 0.5, "a jump dive from the top went no further than a low one")
		_expect(_dive_height > _tuning.jump_height * 0.8, "let go only %.2f up" % _dive_height)
	_next()


func _tick_goal_line() -> void:
	if not _release(true):
		return
	if not _pc.ball_dead:
		return
	print("%-16s %s, state %s" % [CASE_NAMES[_case], _pc.result_text(), Player.State.keys()[_man.state]])
	_expect(_pc.result == PlayController.Result.TOUCHDOWN, "no score")
	_expect(_man.state == Player.State.DIVING, "did not score in the air")
	_next()


func _tick_daze() -> void:
	if not _release(true):
		return
	if _pc.ball_dead:
		_fail("the play ended under him: %s after %.2f s, %d ticks down" % [_pc.result_text(), _pc.live_time, _down_ticks])
		_next()
		return
	if _man.state == Player.State.DIVING:
		return
	if _man.is_down():
		_down_ticks += 1
		_expect(not _man.can_act(), "can act while down")
		if _man.is_dazed() and _man.daze_fx != null and _man.daze_fx.visible:
			_stars_seen += 1
			if _man.daze_fx.global_position.y < _man.head_position().y + 0.3:
				_stars_high = false
		return
	var want: int = roundi(_tuning.jump_dive_daze_time * 60.0)
	var audio: AudioDirector = _game.audio
	print("%-16s down for %d ticks (daze is %d), stars shown on %d of them" % [CASE_NAMES[_case], _down_ticks, want, _stars_seen])
	_expect(absi(_down_ticks - want) <= 2, "down for %d ticks, the daze is %d" % [_down_ticks, want])
	_expect(_stars_seen >= want - 3, "stars on only %d ticks" % _stars_seen)
	_expect(_stars_high, "the stars were not over his head")
	_expect(not _man.is_dazed(), "still dazed on his feet")
	_expect(_gained(&"dazes") == 1, "%d dazes counted" % _gained(&"dazes"))
	_expect(_gained(&"jump_dives") == 1, "%d jump dives counted" % _gained(&"jump_dives"))
	for sound: StringName in [&"jump_dive", &"daze_land", &"daze_stars"]:
		_expect(audio.play_counts.get(sound, 0) > 0, "'%s' was never asked for" % sound)
		_expect(audio.has_sound(sound), "no file for '%s'" % sound)
	_check_injury()
	_next()


## Up from the daze he is injured: every rating halved for the rest of this
## play and the next, a few stars left over his head, and hurting himself again
## only makes it last a play longer.
func _check_injury() -> void:
	var own: PlayerRatings = _healthy
	var half: int = roundi(float(own.speed) * _tuning.injury_rating_scale)
	print("%-16s injured: %s, speed %d -> %d, tackling %d -> %d, %d more plays" % [CASE_NAMES[_case], _man.injured, own.speed, _man.ratings.speed, own.tackling, _man.ratings.tackling, _man.injured_plays])
	_expect(_man.injured, "not injured once he is up")
	_expect(_gained(&"injuries") == 1, "%d injuries counted" % _gained(&"injuries"))
	_expect(_man.ratings != own and _man.ratings.speed == half, "speed is %d, half of %d is %d" % [_man.ratings.speed, own.speed, half])
	for key: StringName in PlayerRatings.CARD_ORDER:
		var was: int = own.get(key)
		var now: int = _man.ratings.get(key)
		_expect(now == roundi(float(was) * _tuning.injury_rating_scale), "%s is %d, was %d" % [key, now, was])
	_expect(own.speed == _speed_before, "his own ratings were changed")
	_expect(_man.ratings.display_name == own.display_name, "the injured ratings lost his name")
	_expect(_man.injured_plays == _tuning.injury_plays, "%d more plays" % _man.injured_plays)
	# The next play: still hurt, stars still up.
	_man.next_play()
	_man._update_visual(0.0, true)
	_expect(_man.injured and _man.injured_plays == 0, "not injured on the next play")
	_expect(_man.daze_fx.visible, "no stars over an injured player")
	var shown: int = 0
	_man._update_visual(1.0, false)
	for star: Node in _man.daze_fx._stars:
		if (star as Node3D).scale.x > 0.02:
			shown += 1
	_expect(shown == DazeFx.INJURED_STARS, "%d stars over an injured player" % shown)
	# Hurt again while injured: the same ratings, one more play of it.
	_man.injure()
	_expect(_man.ratings.speed == half, "a second injury changed his ratings again: speed %d" % _man.ratings.speed)
	_expect(_man.injured_plays == _tuning.injury_plays, "a second injury did not add a play")
	_man.next_play()
	_expect(_man.injured, "healed a play early after a second injury")
	_man.next_play()
	_man._update_visual(0.0, true)
	_expect(not _man.injured and _man.ratings == own, "never got over it")
	_expect(not _man.daze_fx.visible, "stars over a healthy player")
	# The whistle before he is up: injured for the play that follows only.
	_man._injury_pending = true
	_man.next_play()
	_expect(_man.injured and _man.injured_plays == 0, "not injured on the next play after lying through the whistle")
	_man.next_play()
	_expect(not _man.injured, "still injured two plays after lying through the whistle")
	# Through the game's own line-ups, which come twice before each snap (play
	# select): injured in this play, he is still injured when the next is snapped.
	var off_play: OffensePlay = _game.offense_playbook.plays[0]
	var def_play: DefensePlay = _game.defense_playbook.plays[0]
	_man.injure()
	_pc.line_up(off_play, def_play)
	_pc.line_up(off_play, def_play)
	_expect(_man.injured, "healed by the two line-ups before the next snap")
	_expect(_man.daze_fx.visible, "no stars at the line-up of the next play")
	_pc.snap()
	_pc.live_time = 1.0
	_expect(_man.injured, "not injured during the next play")
	_pc.line_up(off_play, def_play)
	_pc.line_up(off_play, def_play)
	_expect(not _man.injured, "still injured the play after next")


func _tick_buttons() -> void:
	match _ticks:
		1:
			# Dive on the ground is an ordinary dive; here he only jumps.
			Input.action_press(&"jump")
		3:
			Input.action_release(&"jump")
			_expect(_man.state == Player.State.JUMPING, "(Y) did not jump")
		9:
			Input.action_press(&"action")
		12:
			Input.action_release(&"action")
			print("%-16s state %s, jump dive: %s" % [CASE_NAMES[_case], Player.State.keys()[_man.state], _man.jump_dive])
			_expect(_man.state == Player.State.DIVING and _man.jump_dive, "(X) in the air did not jump dive")
			_expect(_gained(&"jump_dives") == 1, "%d jump dives counted" % _gained(&"jump_dives"))
			_next()


func _tick_cpu_line() -> void:
	if not _pc.ball_dead:
		return
	print("%-16s %s, leaps for the line %d, jump dives %d" % [CASE_NAMES[_case], _pc.result_text(), _gained(&"leaps_for_line"), _gained(&"jump_dives")])
	_expect(_gained(&"leaps_for_line") == 1, "he did not go up for the line")
	_expect(_gained(&"jump_dives") == 1, "he did not dive out of the jump")
	_expect(_pc.result == PlayController.Result.TOUCHDOWN, "no score: %s" % _pc.result_text())
	_next()


func _tick_cpu_chase() -> void:
	var chaser: Player = _man
	if _gained(&"jump_dives") == 0 and not _pc.ball_dead and _ticks < 300:
		return
	print("%-16s after %d ticks: leaps at the carrier %d, jump dives %d, chaser %s" % [CASE_NAMES[_case], _ticks, _gained(&"leaps_at_carrier"), _gained(&"jump_dives"), Player.State.keys()[chaser.state]])
	_expect(_gained(&"leaps_at_carrier") >= 1, "the last defender never went up after him")
	_expect(_gained(&"jump_dives") >= 1, "he never dived out of the jump")
	_next()


func _gained(stat: StringName) -> int:
	return _game.get_stat(stat) - _stat_before.get(stat, 0)


func _next() -> void:
	for action: StringName in [&"jump", &"action"]:
		Input.action_release(action)
	_case += 1
	if _case >= Case.size():
		_finish()
		return
	var buttons: bool = _case == Case.BUTTONS
	var offense: Team = _person if buttons else _cpu
	_dir = float(offense.attack_dir)
	var goal: float = _tuning.goal_x(offense.attack_dir)
	var middle: float = _tuning.field_length * 0.5
	_game.human.team = _person
	_game.start_drive(offense, _tuning.yard_to_x(offense.attack_dir, 30.0))
	var play: OffensePlay = null
	for candidate: OffensePlay in _game.offense_playbook.plays:
		if candidate.is_run == (_case != Case.DAZE) and not candidate.play_action:
			play = candidate
			break
	_pc.line_up(play, _game.defense_playbook.plays[0])
	_pc.snap()
	_pc.state_machine.transition(&"Live")
	if not buttons:
		# Nobody at the controls: every player thinks for himself.
		_game.human.set_controlled(null)
		_game.human.team = null

	# Everybody else well behind the play, standing still.
	for player: Player in _pc.players:
		# The quarterback keeps the ball where he is: the rest wait out of bounds.
		if _case != Case.DAZE or player != _pc.qb:
			player.position = Vector3(middle - _dir * 30.0, 0.0, float(player.index) * 2.0 - 30.0)
		player.velocity = Vector3.ZERO
		player.frozen = true

	if _case == Case.DAZE:
		# A defender on his own, the quarterback still holding the ball.
		_man = offense.opponent.players[0]
		_place(_man, middle, 0.0)
	else:
		_man = _pc.runner
		var start_x: float = middle
		if _case == Case.GOAL_LINE or _case == Case.CPU_LINE:
			start_x = goal - _dir * 5.0
		elif _case == Case.CPU_CHASE:
			start_x = middle - _dir * 15.0
		_place(_man, start_x, 0.0)
		_pc.handoff_done = true
		_pc.phase = PlayController.Phase.RUN
		_pc.ball.give_to(_man)
		if buttons:
			_game.human.set_controlled(_man)

	for player: Player in _pc.players:
		player.heal()
	_healthy = _man.ratings
	_speed_before = _healthy.speed
	_ticks = 0
	_dived = false
	_landed = false
	_dive_x = _man.position.x
	_dive_height = 0.0
	_down_ticks = 0
	_stars_seen = 0
	_stars_high = true
	for stat: StringName in [&"jump_dives", &"dazes", &"injuries", &"leaps_for_line", &"leaps_at_carrier"]:
		_stat_before[stat] = _game.get_stat(stat)

	match _case:
		Case.GROUND:
			_pc.do_dive(_man, Vector3(_dir, 0.0, 0.0))
			_expect(_man.state == Player.State.DIVING and not _man.jump_dive, "the dive did not start")
		Case.LOW, Case.TOP, Case.GOAL_LINE, Case.DAZE:
			# On the ground there is nothing to dive out of.
			_pc.do_jump_dive(_man, Vector3(_dir, 0.0, 0.0))
			_expect(_man.state == Player.State.NORMAL, "a jump dive started from the ground")
			_pc.do_jump(_man)
			_expect(_man.state == Player.State.JUMPING, "the jump did not start")
		Case.CPU_LINE:
			# A tackler right behind him, five yards from the goal line.
			_man.velocity = Vector3(_dir * 6.0, 0.0, 0.0)
			var tackler: Player = offense.opponent.players[0]
			tackler.position = _man.position - Vector3(_dir * 3.0, 0.0, 0.0)
		Case.CPU_CHASE:
			# One defender left, behind the carrier and no faster than him.
			_man.velocity = Vector3(_dir * 7.0, 0.0, 0.0)
			var chaser: Player = offense.opponent.players[0]
			_place(chaser, _man.position.x - _dir * 3.5, 0.5)
			chaser.velocity = _man.velocity
			chaser.speed_scale = 0.9
			_man = chaser


func _place(player: Player, x: float, z: float) -> void:
	player.position = Vector3(x, 0.0, z)
	player.velocity = Vector3.ZERO
	player.facing = Vector3(_dir, 0.0, 0.0)
	player.frozen = false


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append("%s: %s" % [CASE_NAMES[_case], what])


func _finish() -> void:
	physics_frame.disconnect(_tick)
	if _failures.is_empty():
		print("JUMP DIVE CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("JUMP DIVE CHECK FAILED: %s" % failure)
		quit(1)
