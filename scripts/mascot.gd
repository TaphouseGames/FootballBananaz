class_name Mascot
extends Player
## A team's mascot. It is not on the field during a play: hidden, and not one
## of PlayController.players. After a touchdown the scorer's one turns up out
## of the camera's sight and runs in to join the party round the scorer, as
## one of the team (PlayController._invite_mascot), until the next line-up
## sends it off again. It is Stadium.mascot_model with that
## model's own clips, not a PlayerModel, so it has no PlayerAnimator. Every
## mascot has the same ratings: 50 in everything.

## Yards a second from which it is running, and the speed the run clip is made for.
const RUN_FROM: float = 0.8
const RUN_CLIP_SPEED: float = 7.0
## Seconds a clip asked for with react() is held.
const ACT_TIME: float = 2.6
## Clips played once and held on their last frame; the others loop.
const ONE_SHOT: PackedStringArray = ["faint"]
## What a model without one of the newer clips does in its place.
const STAND_INS: Dictionary[String, String] = {"point": "cheer", "flex": "cheer", "faint": "sulk"}
## How fast a model with no clip for it goes over when it is knocked down.
const TIP_RATE: float = 9.0

var _clips: AnimationPlayer
var _clip: StringName = &""
## Where it carries the ball: this far in front of its middle, this high.
var _hold: Vector2 = Vector2(0.6, 1.2)
## The clip asked for with react() and the seconds it has left.
var _act: StringName = &""
var _act_left: float = 0.0
var _model: Node3D
## How far over it is (0 standing, 1 flat on its back), for a model that has
## no clip for being knocked down.
var _tip: float = 0.0


## The ratings every mascot has.
static func ratings_for(team: Team) -> PlayerRatings:
	var made: PlayerRatings = PlayerRatings.new()
	made.display_name = "%s Mascot" % team.team_name
	return made


## Something for it to act out where it stands: "point", "flex", "faint" or any
## other clip of the model. A model without it plays its stand-in.
func react(clip: StringName, seconds: float = ACT_TIME) -> void:
	_act = clip
	_act_left = seconds
	# The same one twice running starts again.
	_clip = &""


func _setup_model() -> void:
	extra_radius = tuning.mascot_extra_radius
	var holder: Node3D = Stadium.mascot_model(team.short_name)
	if holder == null:
		return
	holder.name = "Model"
	_model = holder
	# The model faces +Z, a player at rest +X; Body is the height of a
	# footballer's middle above the turf.
	holder.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, -body.position.y, 0.0))
	body.add_child(holder)
	var size: Vector3 = holder.get_meta(&"size")
	_hold = Vector2(size.z * 0.5 + 0.2, size.y * 0.45)
	pass_icon.position.y = size.y + 1.0
	for node: Node in holder.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
	var found: Array[Node] = holder.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	_clips = found[0] as AnimationPlayer
	for clip: StringName in _clips.get_animation_list():
		_clips.get_animation(clip).loop_mode = Animation.LOOP_NONE if ONE_SHOT.has(String(clip)) else Animation.LOOP_LINEAR


func ball_anchor() -> Vector3:
	return position + facing * _hold.x + Vector3(0.0, _hold.y + air_height(), 0.0)


func _update_visual(delta: float, instant: bool) -> void:
	super(delta, instant)
	_act_left = maxf(_act_left - delta, 0.0)
	var down: bool = is_down()
	var falls: bool = _clips != null and _clips.has_animation(&"faint")
	if _model != null:
		# With no clip for it, the whole model goes over on its back.
		var tip_to: float = 1.0 if down and not falls else 0.0
		_tip = tip_to if instant else move_toward(_tip, tip_to, TIP_RATE * delta)
		_model.basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -_tip * PI * 0.5)
	if _clips == null:
		return
	var clip: StringName = &"idle"
	var rate: float = 1.0
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var on_feet: bool = state == State.NORMAL or state == State.STIFF_ARM or state == State.DRAGGING
	if down:
		clip = &"faint"
	elif on_feet and speed > RUN_FROM:
		clip = &"run"
		rate = clampf(speed / RUN_CLIP_SPEED, 0.6, 2.0)
	elif _act_left > 0.0:
		clip = _act
	elif play != null and play.ball_dead and play.result == PlayController.Result.TOUCHDOWN and on_feet:
		clip = &"cheer" if play.is_celebrating(self) else &"sulk"
	if not _clips.has_animation(clip):
		clip = StringName(STAND_INS.get(String(clip), "idle"))
	if clip != _clip and _clips.has_animation(clip):
		_clip = clip
		_clips.play(clip, 0.0 if instant else 0.15)
	_clips.speed_scale = rate
