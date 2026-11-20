class_name PreSnapShift
extends RefCounted
## The walk to a new line-up after an audible: everybody whose spot changed
## goes from where he stood to where the new play puts him. Owned by
## PlayController.
##
## Before the snap every player is frozen and nothing is simulated, so (like
## PreSnapMotion) this steers the ones who move and calls their integrate().

## Closer than this to his spot, a man is on it.
const ARRIVE: float = 0.15
## A man moved less than this is put on his spot at once.
const SHIFT_MIN: float = 0.3

var pc: PlayController
var tuning: Tuning
## Who is still walking, and the way each of them faces once he is set.
var _walkers: Dictionary[Player, Vector3] = {}
## Men who have got there: they turn to face the ball and get in their stance.
var _settled: Array[Player] = []


func _init(p_pc: PlayController) -> void:
	pc = p_pc
	tuning = pc.tuning


func reset() -> void:
	_walkers.clear()
	_settled.clear()


## Somebody (of `team`, or of either team) is still on his way.
func active(team: Team = null) -> bool:
	for player: Player in _walkers:
		if team == null or player.team == team:
			return true
	return false


## The teams have just been lined up for a new play. `from` is where each man
## stood before that: he goes back there and walks to his new spot.
func start(from: Dictionary[Player, Vector3]) -> void:
	reset()
	for player: Player in from:
		var spot: Vector3 = player.brain.start_point
		var was: Vector3 = from[player]
		if Vector2(was.x - spot.x, was.z - spot.z).length() < SHIFT_MIN:
			continue
		_walkers[player] = player.facing
		player.position = Vector3(was.x, 0.0, was.z)
		player.frozen = false


## One tick before the snap.
func tick(delta: float) -> void:
	for player: Player in _walkers.keys():
		var spot: Vector3 = player.brain.start_point
		if Vector2(player.position.x - spot.x, player.position.z - spot.z).length() < ARRIVE:
			PreSnapMotion.plant(player, spot, _walkers[player])
			_walkers.erase(player)
			_settled.append(player)
			continue
		player.ai_speed_scale = tuning.motion_jog_scale
		player.wants_turbo = false
		PreSnapMotion.steer(player, spot, true)
		player.integrate(delta)
	for player: Player in _settled:
		player.integrate(delta)


## The snap: whoever is still walking plays from where he is.
func finish() -> void:
	for player: Player in _walkers:
		player.ai_speed_scale = 1.0
		player.move_input = Vector3.ZERO
	reset()
