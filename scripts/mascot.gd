class_name Mascot
extends Player
## A team's mascot as a footballer: the one who goes for the ball in the
## scramble that opens a half (see PlayController.line_up_scramble). It is the
## model from the sideline (Stadium.mascot_model) with that model's own clips,
## not a PlayerModel, so it has no PlayerAnimator. Every mascot has the same
## ratings: 50 in everything.

## Yards a second from which it is running, and the speed the run clip is made for.
const RUN_FROM: float = 0.8
const RUN_CLIP_SPEED: float = 7.0

var _clips: AnimationPlayer
var _clip: StringName = &""
## Where it carries the ball: this far in front of its middle, this high.
var _hold: Vector2 = Vector2(0.6, 1.2)


## The ratings every mascot has.
static func ratings_for(team: Team) -> PlayerRatings:
	var made: PlayerRatings = PlayerRatings.new()
	made.display_name = "%s Mascot" % team.team_name
	return made


func _setup_model() -> void:
	var holder: Node3D = Stadium.mascot_model(team.short_name)
	if holder == null:
		return
	holder.name = "Model"
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
		_clips.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func ball_anchor() -> Vector3:
	return position + facing * _hold.x + Vector3(0.0, _hold.y + air_height(), 0.0)


func _update_visual(delta: float, instant: bool) -> void:
	super(delta, instant)
	if _clips == null:
		return
	var clip: StringName = &"idle"
	var rate: float = 1.0
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var on_feet: bool = state == State.NORMAL or state == State.STIFF_ARM or state == State.DRAGGING
	if on_feet and speed > RUN_FROM:
		clip = &"run"
		rate = clampf(speed / RUN_CLIP_SPEED, 0.6, 2.0)
	elif play != null and play.ball_dead and play.result == PlayController.Result.TOUCHDOWN and on_feet:
		clip = &"cheer" if play.is_celebrating(self) else &"sulk"
	if not _clips.has_animation(clip):
		clip = &"idle"
	if clip != _clip and _clips.has_animation(clip):
		_clip = clip
		_clips.play(clip, 0.0 if instant else 0.15)
	_clips.speed_scale = rate
