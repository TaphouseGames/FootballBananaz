class_name ModelMotion
extends Node
## Keeps the PlayerModel it is a child of moving while it stands in a menu
## (see ModelStage): idling with its arms at its sides, or cheering, hopping
## with its fists in the air, as the mascots do on the team select. On the
## field PlayerAnimator moves the model and this is not there.
##
## A turn is given as seen from in front of the model's T-pose rest (left arm
## to +X, facing +Z) and is carried along by the bones above it.

## Seconds to go from idling to cheering or back.
const BLEND_TIME: float = 0.25
## Idle: how far down from straight out the arms hang and how much the elbows
## are bent, in radians, and how fast he breathes and looks about.
const IDLE_ARM_DROP: float = 1.2
const IDLE_ELBOW: float = 0.25
const IDLE_BREATH_SPEED: float = 1.9
const IDLE_LOOK_SPEED: float = 0.6
## Cheer: hops a second, how high in metres, how far over straight out the
## arms go up and how far each pump takes them, and the bend of the elbows.
const CHEER_HOP_SPEED: float = 2.4
const CHEER_HOP_HEIGHT: float = 0.14
const CHEER_ARM_RAISE: float = 0.85
const CHEER_ARM_PUMP: float = 0.3
const CHEER_ELBOW: float = 0.9
const CHEER_KNEE: float = 0.3

const BONES: PackedStringArray = [
	"Waist", "Spine02", "Head",
	"L_Upperarm", "L_Forearm", "R_Upperarm", "R_Forearm",
	"L_Thigh", "L_Calf", "R_Thigh", "R_Calf",
]

var cheering: bool = false
## Where in the motions he starts, so that a row of them is not in step.
var phase: float = 0.0

var _skeleton: Skeleton3D
var _clock: float = 0.0
## 0 idling, 1 cheering.
var _cheer: float = 0.0
## Per bone of BONES: its place in the skeleton, and what takes a turn seen
## from in front to its own pose ([what goes before, what goes after]).
var _index: Dictionary[String, int] = {}
var _frames: Dictionary[String, Array] = {}


func _process(delta: float) -> void:
	var model: PlayerModel = get_parent() as PlayerModel
	if model == null or model.skeleton == null:
		return
	if model.skeleton != _skeleton:
		_learn(model.skeleton)
	_clock += delta
	_cheer = move_toward(_cheer, 1.0 if cheering else 0.0, delta / BLEND_TIME)
	var w: float = smoothstep(0.0, 1.0, _cheer)
	var t: float = _clock + phase

	# How far off the ground the hop has him (0..1), and how near the ground.
	var hop: float = absf(sin(t * CHEER_HOP_SPEED * PI)) * w
	var landed: float = (1.0 - absf(sin(t * CHEER_HOP_SPEED * PI))) * w
	model.rig.position.y = hop * CHEER_HOP_HEIGHT

	var breath: float = sin(t * IDLE_BREATH_SPEED)
	var look: float = sin(t * IDLE_LOOK_SPEED) * (1.0 - w)
	_turn("Waist", Basis(Vector3.BACK, sin(t * IDLE_LOOK_SPEED * 0.7) * 0.03 * (1.0 - w)))
	_turn("Spine02", Basis(Vector3.RIGHT, breath * 0.025 - 0.12 * w))
	_turn("Head", Basis(Vector3.UP, look * 0.3) * Basis(Vector3.RIGHT, -0.15 * w))

	for side: String in ["L_", "R_"]:
		# The left arm lies to +X: up is a turn about +Z for it, about -Z for the right.
		var out: float = 1.0 if side == "L_" else -1.0
		var pump: float = sin(t * CHEER_HOP_SPEED * TAU + (0.0 if side == "L_" else phase * 3.0))
		var idle_arm: float = -IDLE_ARM_DROP + breath * 0.03
		var cheer_arm: float = CHEER_ARM_RAISE + pump * CHEER_ARM_PUMP
		_turn(side + "Upperarm", Basis(Vector3.BACK, out * lerpf(idle_arm, cheer_arm, w)))
		# Idling the elbow bends forward, cheering it bends up.
		_turn(side + "Forearm", Basis(Vector3.BACK, out * CHEER_ELBOW * w) * Basis(Vector3.UP, -out * IDLE_ELBOW * (1.0 - w)))
		# The knees give as he lands.
		_turn(side + "Thigh", Basis(Vector3.RIGHT, -landed * CHEER_KNEE))
		_turn(side + "Calf", Basis(Vector3.RIGHT, landed * CHEER_KNEE * 2.0))


## Finds the bones in a body the model has just been given.
func _learn(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_index.clear()
	_frames.clear()
	for bone_name: String in BONES:
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var parent: int = skeleton.get_bone_parent(bone)
		var parent_basis: Basis = skeleton.get_bone_global_rest(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		_index[bone_name] = bone
		_frames[bone_name] = [parent_basis.inverse(), skeleton.get_bone_global_rest(bone).basis.orthonormalized()]


func _turn(bone_name: String, turn: Basis) -> void:
	if not _index.has(bone_name):
		return
	var before: Basis = _frames[bone_name][0]
	var after: Basis = _frames[bone_name][1]
	_skeleton.set_bone_pose_rotation(_index[bone_name], (before * turn * after).get_rotation_quaternion())
