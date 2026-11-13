class_name PlayerAnimator
extends RefCounted
## Procedural animation for one Player. There are no animation clips: every tick
## a target pose is built from what the player is doing, and the skeleton eases
## toward it.
##
## Pose angles are in degrees, in skeleton space at rest: +X is the character's
## left, +Y up, +Z forward.
##   x: pitch. Positive leans the torso forward, swings a hanging limb back and
##      bends a knee.
##   y: yaw / twist. For a lowered arm it turns the elbow; on the forearm,
##      negative bends the elbow.
##   z: roll. Negative lowers the left arm from the T-pose and leans the torso left.
## Right-side bones are written as if they were the left one and mirrored on the
## way to the skeleton, so a symmetric pose uses the same numbers on both sides.

enum B {
	HIPS, SPINE, CHEST, NECK, HEAD,
	ARM_L, FORE_L, HAND_L, ARM_R, FORE_R, HAND_R,
	THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R,
	COUNT,
}

const BONE_NAMES: PackedStringArray = [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"UpperArm.L", "Forearm.L", "Hand.L", "UpperArm.R", "Forearm.R", "Hand.R",
	"Thigh.L", "Shin.L", "Foot.L", "Thigh.R", "Shin.R", "Foot.R",
]
const ARM_DOWN: float = -78.0
## Seconds before a pass arrives that the hands start following the ball itself.
const HANDS_TIME: float = 0.35
## Yards from a fumbled ball at which the hands start to go for it.
const LOOSE_REACH: float = 2.5
## Half the gap between the two hands on the ball, in metres.
const HANDS_APART: float = 0.11
## The hands never go for a ball further back than this far in front of the line
## of the shoulders, in metres.
const CHEST_CLEAR: float = 0.14
## Seconds before a handoff or toss that the back turns and gets his hands ready.
const HANDOFF_READY_TIME: float = 0.4
## A ball gripped to throw: how far from the wrist (0) to the palm point (1) its
## middle is, and how far off the palm, in metres.
const GRIP_ALONG: float = 1.0
## His body as far as his own arms are concerned, in skeleton units: a ball for
## the head (its middle this far above the head bone), a tube from hips to
## chest, and how thick an arm is. Celebrations keep the arms outside these.
const HEAD_RADIUS: float = 0.235
const HEAD_RISE: float = 0.18
const TORSO_RADIUS: float = 0.14
const ARM_RADIUS: float = 0.055
## The first pose branch that is a celebration.
const MODE_CELEBRATE: int = 30
const GRIP_OUT: float = 0.12
## A ball tucked under the arm: its middle this far from the elbow (0) to the
## palm (1), so one end is in the hand and the other in the crook of the elbow,
## and this far in from the forearm toward the chest, in metres, so it lies
## along the inside of the arm instead of through it.
const TUCK_ALONG: float = 0.5
const TUCK_IN: float = 0.15
## How many dances a scorer has, ways his teammates cheer and ways the other
## team sulks. The last sulk is the one who walks off.
const DANCES: int = 4
const CHEERS: int = 3
const SULKS: int = 5
const SULK_TRUDGE: int = 4
const SPIKE_TIME: float = 0.4
## Hands on hips, elbows out. The pose gets the elbows about right and the palms
## are then put on the hips: this far out to the side, up and forward of the
## hips bone, in skeleton units.
const HIP_ARM: Vector3 = Vector3(24.0, 0.0, -44.0)
const HIP_FORE: Vector3 = Vector3(0.0, -100.0, 0.0)
const HIP_HAND: Vector3 = Vector3(0.215, 0.03, 0.06)
## Pose branches for a block: waiting for someone, holding a man, being held.
const MODE_BLOCK_READY: int = 6
const MODE_BLOCK_HOLD: int = 8
const MODE_BLOCK_FIGHT: int = 9
## What the blocked man does with one arm when he changes side: over the top of
## the blocker's shoulder, or up through under his arm. Seconds each takes.
const MOVE_NONE: int = 0
const MOVE_SWIM: int = 1
const MOVE_RIP: int = 2
const MOVE_TIME: float = 0.38
## Yards between two men at which their hands are fully on each other, and at
## which they have let go.
const GRAB_NEAR: float = 1.3
const GRAB_FAR: float = 1.75
## Where a blocker's hands go on the other man's chest: this far either side of
## the middle and this far down from the line of the shoulders to the chest
## bone (0..1). Where the blocked man's go on a shoulder: this far up and
## forward of the joint. Skeleton units.
const GRAB_CHEST_APART: float = 0.09
const GRAB_CHEST_DOWN: float = 0.45
const GRAB_SHOULDER_UP: float = 0.05
const GRAB_SHOULDER_FRONT: float = 0.07

var player: Player
var skeleton: Skeleton3D

var _bone: PackedInt32Array = PackedInt32Array()
var _rest_local: Array[Quaternion] = []
var _rest_global: Array[Quaternion] = []
var _current: Array[Quaternion] = []
var _pose: PackedVector3Array = PackedVector3Array()
var _hips_rest: Vector3 = Vector3.ZERO
var _ankle_rest_y: float = 0.0
## Palm of each hand, in that hand bone's own space.
var _palm_l: Vector3 = Vector3(0.0, 0.15, 0.0)
var _palm_r: Vector3 = Vector3(0.0, 0.15, 0.0)
## The way each palm faces, in that hand bone's own space.
var _palm_out_l: Vector3 = Vector3.DOWN
var _palm_out_r: Vector3 = Vector3.DOWN
## The ball is gripped in one hand to throw, not clamped under the arm: it sits
## on the palm instead of round the fingers. `_grip_now` is the eased value.
var _grip: bool = false
var _grip_now: float = 0.0
## The ball is tucked between forearm and chest (see `_tuck_ball`); eased the
## same way.
var _tuck: bool = false
var _tuck_now: float = 0.0
## Middle of the head, in the head bone's own space.
var _head_centre: Vector3 = Vector3(0.0, HEAD_RISE, 0.0)
## How much each hand is resting on its hip this tick (0..1).
var _hip_l: float = 0.0
var _hip_r: float = 0.0
## How much the arms are being kept out of the body just now (0..1).
var _clear_now: float = 0.0
## "Up" in the space the hips bone is positioned in.
var _hips_up: Vector3 = Vector3.UP
var _ground: float = 1.0
var _ground_current: float = 1.0
var _rate: float = 14.0
var _phase: float = 0.0
var _clock: float = 0.0
var _throw_timer: float = 0.0
var _spike_timer: float = 0.0
var _was_thrower: bool = false
var _ball_hand: int = B.HAND_L
## Above 0 while both hands follow the ball (a pass coming in, or one just
## caught): how strongly, and the world position they go to.
var _hands_weight: float = 0.0
var _hands_target: Vector3 = Vector3.ZERO
## The same for the hand that does not end up carrying the ball: it lets go
## once the catch is made.
var _off_hand_weight: float = 0.0
## How far from the midpoint of the shoulders both palms can meet, in skeleton
## units.
var _hands_reach: float = 0.5
## Shoulder to palm with the arm straight, in skeleton units.
var _arm_length: float = 0.6
## Where the ball hand would be without that, in world space.
var _anchor_rest: Vector3 = Vector3.ZERO
## Which shoulder he has turned over to see a ball behind him (+1 left, -1
## right, 0 not turned), and whether he turned to anything this tick.
var _twist_side: float = 0.0
var _turned: bool = false
## "Forward" in the chest bone's own space.
var _chest_forward: Vector3 = Vector3.BACK

## Which pose branch is active; a change eases in instead of snapping.
var _mode: int = 0
var _mode_prev: int = 0
var _settle: float = 1.0
## Blend rate that keeps up with the stride cycle (0 when not running).
var _cycle_rate: float = 0.0
var _scratch: PackedVector3Array = PackedVector3Array()

# Gait
var _run: float = 0.0
var _sprint: float = 0.0
var _turbo: float = 0.0
var _leg_length: float = 0.9
var _hop: float = 0.0
var _hop_current: float = 0.0
var _vel_prev: Vector3 = Vector3.ZERO
var _acc_fwd: float = 0.0
var _acc_left: float = 0.0
var _punch: float = 0.0
var _punch_wait: float = 0.0
## How far into the "throw it to me" wave he is (0..1), and his own point in
## the swing so that two open receivers do not wave in step.
var _wave: float = 0.0
var _wave_offset: float = 0.0

# Locked up in a block. The man being blocked keeps trying one side and then
# the other; the blocker reads which and slides with him a beat late.
## How strongly each hand is to hold on to the other man this tick, the eased
## values, who that is, and whether the hands go on his chest (the blocker's)
## or on his shoulders (the blocked man's).
var _grab_l: float = 0.0
var _grab_r: float = 0.0
var _grab_l_now: float = 0.0
var _grab_r_now: float = 0.0
var _grab_with: Player = null
var _grab_chest: bool = false
## The side he is working to: +1 his own left, -1 his right. `_fight_now` is
## the eased value, which is what the pose leans by.
var _fight_side: float = 1.0
var _fight_now: float = 0.0
var _fight_wait: float = 0.0
## The arm move the blocked man is throwing, and how much of it is left.
var _move: int = MOVE_NONE
var _move_timer: float = 0.0

# Loose limbs: a damped spring per bone, kicked by hits and landings.
var _flop: PackedVector3Array = PackedVector3Array()
var _flop_vel: PackedVector3Array = PackedVector3Array()
var _flop_stiffness: float = 160.0
var _flop_damping: float = 15.0

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_player: Player, p_skeleton: Skeleton3D) -> void:
	player = p_player
	skeleton = p_skeleton
	_pose.resize(B.COUNT)
	_scratch.resize(B.COUNT)
	_flop.resize(B.COUNT)
	_flop_vel.resize(B.COUNT)
	for i: int in B.COUNT:
		var bone_name: String = BONE_NAMES[i]
		var idx: int = skeleton.find_bone(bone_name)
		if idx < 0:
			idx = skeleton.find_bone(bone_name.replace(".", "_"))
		if idx < 0:
			push_error("PlayerAnimator: bone '%s' is missing from the player model" % bone_name)
		_bone.append(idx)
		var local: Quaternion = Quaternion.IDENTITY
		var global: Quaternion = Quaternion.IDENTITY
		if idx >= 0:
			local = skeleton.get_bone_rest(idx).basis.orthonormalized().get_rotation_quaternion()
			global = skeleton.get_bone_global_rest(idx).basis.orthonormalized().get_rotation_quaternion()
		_rest_local.append(local)
		_rest_global.append(global)
		_current.append(Quaternion.IDENTITY)
	if _bone[B.HIPS] >= 0:
		_hips_rest = skeleton.get_bone_rest(_bone[B.HIPS]).origin
		var hips_parent: int = skeleton.get_bone_parent(_bone[B.HIPS])
		if hips_parent >= 0:
			_hips_up = skeleton.get_bone_global_rest(hips_parent).basis.inverse() * Vector3.UP
	if _bone[B.FOOT_L] >= 0:
		_ankle_rest_y = skeleton.get_bone_global_rest(_bone[B.FOOT_L]).origin.y
		if _bone[B.HIPS] >= 0:
			_leg_length = maxf(skeleton.get_bone_global_rest(_bone[B.HIPS]).origin.y - _ankle_rest_y, 0.1)
	if _bone[B.CHEST] >= 0:
		_chest_forward = skeleton.get_bone_global_rest(_bone[B.CHEST]).basis.orthonormalized().inverse() * Vector3.BACK
	_palm_l = _palm_offset(B.HAND_L, B.FORE_L, _palm_l)
	_palm_r = _palm_offset(B.HAND_R, B.FORE_R, _palm_r)
	if _bone[B.HEAD] >= 0:
		_head_centre = skeleton.get_bone_global_rest(_bone[B.HEAD]).basis.orthonormalized().inverse() * Vector3(0.0, HEAD_RISE, 0.0)
	# The model stands with its arms out and its palms to the turf.
	if _bone[B.HAND_L] >= 0:
		_palm_out_l = skeleton.get_bone_global_rest(_bone[B.HAND_L]).basis.orthonormalized().inverse() * Vector3.DOWN
	if _bone[B.HAND_R] >= 0:
		_palm_out_r = skeleton.get_bone_global_rest(_bone[B.HAND_R]).basis.orthonormalized().inverse() * Vector3.DOWN
	if _bone[B.ARM_L] >= 0 and _bone[B.ARM_R] >= 0 and _bone[B.FORE_L] >= 0 and _bone[B.HAND_L] >= 0:
		var shoulder: Vector3 = skeleton.get_bone_global_rest(_bone[B.ARM_L]).origin
		var elbow: Vector3 = skeleton.get_bone_global_rest(_bone[B.FORE_L]).origin
		var palm: Vector3 = skeleton.get_bone_global_rest(_bone[B.HAND_L]) * _palm_l
		var arm: float = shoulder.distance_to(elbow) + elbow.distance_to(palm)
		var half_width: float = shoulder.distance_to(skeleton.get_bone_global_rest(_bone[B.ARM_R]).origin) * 0.5
		# Each arm runs from its own shoulder, so the two meet a little short of
		# a full arm's length from the middle.
		_hands_reach = sqrt(maxf(arm * arm - half_width * half_width, 0.01)) * 0.9
		_arm_length = arm
	# Start each player at a different point of the idle sway.
	_clock = float(player.index) * 1.7 + (0.0 if player.team == null else float(player.team.attack_dir))
	_wave_offset = _rng.randf_range(0.0, TAU)
	_fight_side = 1.0 if _rng.randf() < 0.5 else -1.0


## The palm sits a little past the wrist, along the line of the forearm at rest.
## Worked out from the rest pose so it does not matter which way the hand bone's
## own axes point.
func _palm_offset(hand: int, fore: int, fallback: Vector3) -> Vector3:
	if _bone[hand] < 0 or _bone[fore] < 0:
		return fallback
	var hand_rest: Transform3D = skeleton.get_bone_global_rest(_bone[hand])
	var along: Vector3 = hand_rest.origin - skeleton.get_bone_global_rest(_bone[fore]).origin
	return hand_rest.basis.inverse() * (along * 0.45)


## World position of the hand that holds the ball. While the hands are following
## the ball this is where the hand is on its way to, so the ball is not chasing
## a hand that is chasing the ball.
func ball_anchor() -> Vector3:
	if _hands_weight > 0.0:
		return _anchor_rest
	return _palm_world()


## Midpoint between the shoulders, in world space, as he is posed now.
func shoulders() -> Vector3:
	if _bone[B.ARM_L] < 0 or _bone[B.ARM_R] < 0:
		return player.global_position + Vector3(0.0, 1.2, 0.0)
	var mid: Vector3 = (skeleton.get_bone_global_pose(_bone[B.ARM_L]).origin + skeleton.get_bone_global_pose(_bone[B.ARM_R]).origin) * 0.5
	return skeleton.global_transform * mid


## How far straight out from there he can get both hands on a ball, in metres.
func hands_reach() -> float:
	return _hands_reach * skeleton.global_basis.get_scale().x


## The spot nearest to `point` that both palms can get to, with his shoulders
## moved `shift` from where they are now. All in world space.
func nearest_reach(point: Vector3, shift: Vector3) -> Vector3:
	if _bone[B.ARM_L] < 0 or _bone[B.ARM_R] < 0:
		return point
	var to_world: Transform3D = skeleton.global_transform
	var left: Vector3 = to_world * skeleton.get_bone_global_pose(_bone[B.ARM_L]).origin + shift
	var right: Vector3 = to_world * skeleton.get_bone_global_pose(_bone[B.ARM_R]).origin + shift
	var arm: float = _arm_length * to_world.basis.get_scale().x * 0.92
	var result: Vector3 = point
	# Pulling it inside one arm's reach can push it out of the other's, so the
	# two take turns a few times.
	for i: int in 4:
		for shoulder: Vector3 in [left, right]:
			var to: Vector3 = result - shoulder
			if to.length() > arm:
				result = shoulder + to.normalized() * arm
	return result


func _palm_world() -> Vector3:
	var idx: int = _bone[_ball_hand]
	if idx < 0:
		return player.global_position + Vector3(0.0, 1.1, 0.0)
	var hand: Transform3D = skeleton.get_bone_global_pose(idx)
	var right: bool = _ball_hand == B.HAND_R
	var palm: Vector3 = hand * (_palm_r if right else _palm_l)
	if _grip_now > 0.0:
		# Back toward the heel of the hand and out off the palm by half the
		# ball's width, so the hand is round it and not through it.
		var out: Vector3 = (hand.basis.orthonormalized() * (_palm_out_r if right else _palm_out_l)).normalized()
		var held: Vector3 = hand.origin.lerp(palm, GRIP_ALONG) + out * (GRIP_OUT / skeleton.global_basis.get_scale().x)
		palm = palm.lerp(held, _grip_now)
	if _tuck_now > 0.0:
		palm = palm.lerp(_tuck_point(), _tuck_now)
	return skeleton.global_transform * palm


## Middle of a ball tucked under the carrying arm, in skeleton space: halfway
## down the forearm, pushed in off it toward the chest by about half the ball's
## width plus the arm's.
func _tuck_point() -> Vector3:
	var right: bool = _ball_hand == B.HAND_R
	var fore_idx: int = _bone[B.FORE_R if right else B.FORE_L]
	var hand_idx: int = _bone[_ball_hand]
	var chest_idx: int = _bone[B.CHEST]
	if fore_idx < 0 or hand_idx < 0 or chest_idx < 0:
		return skeleton.get_bone_global_pose(maxi(hand_idx, 0)).origin
	var elbow: Vector3 = skeleton.get_bone_global_pose(fore_idx).origin
	var palm: Vector3 = skeleton.get_bone_global_pose(hand_idx) * (_palm_r if right else _palm_l)
	var along: Vector3 = elbow.lerp(palm, TUCK_ALONG)
	var axis: Vector3 = (palm - elbow).normalized()
	var to_chest: Vector3 = skeleton.get_bone_global_pose(chest_idx).origin - along
	var inward: Vector3 = to_chest - axis * to_chest.dot(axis)
	if inward.length_squared() < 0.000001:
		return along
	return along + inward.normalized() * (TUCK_IN / skeleton.global_basis.get_scale().x)


## Which way the long axis of the carried ball points, in world space: along the
## forearm when it is tucked, otherwise ahead and a little up.
func ball_axis() -> Vector3:
	var dir: Vector3 = player.facing
	if not player.is_down():
		dir = dir + Vector3(0.0, 0.45, 0.0)
	dir = dir.normalized()
	if _tuck_now <= 0.0:
		return dir
	var right: bool = _ball_hand == B.HAND_R
	var fore_idx: int = _bone[B.FORE_R if right else B.FORE_L]
	var hand_idx: int = _bone[_ball_hand]
	if fore_idx < 0 or hand_idx < 0:
		return dir
	var elbow: Vector3 = skeleton.get_bone_global_pose(fore_idx).origin
	var palm: Vector3 = skeleton.get_bone_global_pose(hand_idx) * (_palm_r if right else _palm_l)
	var fore: Vector3 = skeleton.global_basis * (palm - elbow)
	if fore.length_squared() < 0.000001:
		return dir
	return dir.slerp(fore.normalized(), _tuck_now)


func update(delta: float, instant: bool) -> void:
	_clock += delta
	_throw_timer = maxf(_throw_timer - delta, 0.0)
	_spike_timer = maxf(_spike_timer - delta, 0.0)
	_ground = 1.0
	_rate = 14.0
	_cycle_rate = 0.0
	_hop = 0.0
	_flop_stiffness = 160.0
	_flop_damping = 15.0
	_hands_weight = 0.0
	_off_hand_weight = 0.0
	_grip = false
	_tuck = false
	_hip_l = 0.0
	_hip_r = 0.0
	_grab_l = 0.0
	_grab_r = 0.0
	if instant:
		_reset_dynamics()
	_track_momentum(delta)
	_watch_ball(delta)
	_turned = false
	_build_pose(delta)
	if not _turned:
		_twist_side = 0.0
	_update_flop(delta)

	# The stride must not be smoothed away, but a change of pose still eases in.
	if _mode != _mode_prev:
		_mode_prev = _mode
		_settle = 0.0
	_settle = minf(_settle + delta / 0.2, 1.0)
	var rate: float = _rate
	if _cycle_rate > rate:
		rate = lerpf(rate, _cycle_rate, _settle)

	var blend: float = 1.0 if instant else 1.0 - exp(-rate * delta)
	_grip_now = lerpf(_grip_now, 1.0 if _grip else 0.0, blend)
	_tuck_now = lerpf(_tuck_now, 1.0 if _tuck else 0.0, blend)
	_ground_current = lerpf(_ground_current, _ground, blend)
	_hop_current = lerpf(_hop_current, _hop, blend)
	for i: int in B.COUNT:
		var idx: int = _bone[i]
		if idx < 0:
			continue
		var e: Vector3 = _pose[i]
		if i == B.ARM_R or i == B.FORE_R or i == B.HAND_R or i == B.THIGH_R or i == B.SHIN_R or i == B.FOOT_R:
			e.y = -e.y
			e.z = -e.z
		var target: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(e.x)) \
			* Quaternion(Vector3.UP, deg_to_rad(e.y)) \
			* Quaternion(Vector3.BACK, deg_to_rad(e.z))
		_current[i] = _current[i].slerp(target, blend).normalized()
		var g: Quaternion = _rest_global[i]
		skeleton.set_bone_pose_rotation(idx, _rest_local[i] * (g.inverse() * _current[i] * g))
	_plant_feet()
	if _hands_weight > 0.0:
		_anchor_rest = _palm_world()
		var pc: PlayController = player.play
		if player.has_ball and pc != null:
			# Exactly where the ball will put itself this tick.
			_hands_target = pc.ball.settle_position(_anchor_rest, pc.ball.settle_share(delta))
		_reach_hands()
	if _hip_l > 0.0 or _hip_r > 0.0:
		_hands_to_hips()
	# A hand takes hold, and lets go for a swim or a rip, quicker than a pose eases.
	_grab_l_now = move_toward(_grab_l_now, _grab_l, delta / 0.09)
	_grab_r_now = move_toward(_grab_r_now, _grab_r, delta / 0.09)
	if _grab_l_now > 0.0 or _grab_r_now > 0.0:
		_grab_partner()
	_clear_now = lerpf(_clear_now, 1.0 if _mode >= MODE_CELEBRATE else 0.0, blend)
	if _clear_now > 0.01:
		_clear_arm(B.ARM_L, B.FORE_L, B.HAND_L, _palm_l)
		_clear_arm(B.ARM_R, B.FORE_R, B.HAND_R, _palm_r)


# --- Hands on another player -----------------------------------------------------

## The two places on him that a man he is locked up with puts his hands, in
## world space as he is posed now: either side of the front of his chest, or on
## top of his shoulders.
func grab_points(chest: bool) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if _bone[B.ARM_L] < 0 or _bone[B.ARM_R] < 0 or _bone[B.CHEST] < 0:
		var middle: Vector3 = player.global_position + Vector3(0.0, 1.2, 0.0)
		points.append(middle)
		points.append(middle)
		return points
	var left: Vector3 = skeleton.get_bone_global_pose(_bone[B.ARM_L]).origin
	var right: Vector3 = skeleton.get_bone_global_pose(_bone[B.ARM_R]).origin
	var chest_pose: Transform3D = skeleton.get_bone_global_pose(_bone[B.CHEST])
	var forward: Vector3 = (chest_pose.basis.orthonormalized() * _chest_forward).normalized()
	var to_world: Transform3D = skeleton.global_transform
	if chest:
		var across: Vector3 = (left - right).normalized()
		var plate: Vector3 = ((left + right) * 0.5).lerp(chest_pose.origin, GRAB_CHEST_DOWN) + forward * TORSO_RADIUS
		points.append(to_world * (plate + across * GRAB_CHEST_APART))
		points.append(to_world * (plate - across * GRAB_CHEST_APART))
	else:
		var lift: Vector3 = Vector3(0.0, GRAB_SHOULDER_UP, 0.0) + forward * GRAB_SHOULDER_FRONT
		points.append(to_world * (left + lift))
		points.append(to_world * (right + lift))
	return points


## Which way the man being blocked is trying to get round, in world space: no
## length when he is going straight at his blocker (or is not being blocked).
func fight_lean() -> Vector3:
	if _mode != MODE_BLOCK_FIGHT:
		return Vector3.ZERO
	return skeleton.global_basis.x.normalized() * _fight_now


## Where each palm is to go on the man he has hold of (left, then right), in
## his own skeleton space: each hand takes the place on its own side.
func _grab_targets() -> PackedVector3Array:
	var points: PackedVector3Array = _grab_with.animator.grab_points(_grab_chest)
	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse()
	var a: Vector3 = to_skeleton * points[0]
	var b: Vector3 = to_skeleton * points[1]
	return PackedVector3Array([a, b] if a.x >= b.x else [b, a])


## Puts the palms on the man he is locked up with. Runs after the pose has been
## written to the skeleton and works on the bones directly.
func _grab_partner() -> void:
	if _grab_with == null or not is_instance_valid(_grab_with) or _grab_with.animator == null or _hands_weight > 0.0:
		_grab_l_now = 0.0
		_grab_r_now = 0.0
		return
	var targets: PackedVector3Array = _grab_targets()
	_reach_arm(B.ARM_L, B.FORE_L, B.HAND_L, _palm_l, targets[0], _grab_l_now)
	_reach_arm(B.ARM_R, B.FORE_R, B.HAND_R, _palm_r, targets[1], _grab_r_now)


## How far each palm is from where it has hold of the other man (left, right),
## in metres, or -1 for a hand that has let go. For tests.
func grab_gaps() -> Vector2:
	var gaps: Vector2 = Vector2(-1.0, -1.0)
	if _grab_with == null or not is_instance_valid(_grab_with) or _grab_with.animator == null:
		return gaps
	var targets: PackedVector3Array = _grab_targets()
	var scale: float = skeleton.global_basis.get_scale().x
	if _grab_l_now >= 1.0:
		gaps.x = (skeleton.get_bone_global_pose(_bone[B.HAND_L]) * _palm_l).distance_to(targets[0]) * scale
	if _grab_r_now >= 1.0:
		gaps.y = (skeleton.get_bone_global_pose(_bone[B.HAND_R]) * _palm_r).distance_to(targets[1]) * scale
	return gaps


# --- Arms out of the body --------------------------------------------------------

## Rests the palms on the hips, wherever the dance has put the hips.
func _hands_to_hips() -> void:
	if _bone[B.HIPS] < 0:
		return
	var hips: Transform3D = skeleton.get_bone_global_pose(_bone[B.HIPS])
	var frame: Basis = hips.basis.orthonormalized() * Basis(_rest_global[B.HIPS].inverse())
	_reach_arm(B.ARM_L, B.FORE_L, B.HAND_L, _palm_l, hips.origin + frame * HIP_HAND, _hip_l)
	_reach_arm(B.ARM_R, B.FORE_R, B.HAND_R, _palm_r, hips.origin + frame * Vector3(-HIP_HAND.x, HIP_HAND.y, HIP_HAND.z), _hip_r)


## Where `point` has to be for an arm there to be outside his head and trunk
## (itself, if it already is). In skeleton space, as he is posed now.
func _outside_body(point: Vector3) -> Vector3:
	var result: Vector3 = point
	var low: Vector3 = skeleton.get_bone_global_pose(_bone[B.HIPS]).origin
	var high: Vector3 = skeleton.get_bone_global_pose(_bone[B.CHEST]).origin
	var along: Vector3 = high - low
	var nearest: Vector3 = low + along * clampf((result - low).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
	var off: Vector3 = result - nearest
	if off.length() < TORSO_RADIUS + ARM_RADIUS:
		# Dead centre there is no way out to prefer: forward will do.
		result = nearest + (off.normalized() if off.length_squared() > 0.000001 else Vector3.BACK) * (TORSO_RADIUS + ARM_RADIUS)
	var head: Vector3 = skeleton.get_bone_global_pose(_bone[B.HEAD]) * _head_centre
	off = result - head
	if off.length() < HEAD_RADIUS + ARM_RADIUS:
		result = head + (off.normalized() if off.length_squared() > 0.000001 else Vector3.BACK) * (HEAD_RADIUS + ARM_RADIUS)
	return result


## How far into his own head or trunk his arms are, in skeleton units: 0 when
## they are clear of it. For tests.
func arm_overlap() -> float:
	var worst: float = 0.0
	for arm: Array in [[B.ARM_L, B.FORE_L, B.HAND_L, _palm_l], [B.ARM_R, B.FORE_R, B.HAND_R, _palm_r]]:
		var fore_idx: int = _bone[arm[1]]
		var hand_idx: int = _bone[arm[2]]
		if fore_idx < 0 or hand_idx < 0:
			continue
		var elbow: Vector3 = skeleton.get_bone_global_pose(fore_idx).origin
		var hand: Transform3D = skeleton.get_bone_global_pose(hand_idx)
		var palm_local: Vector3 = arm[3]
		for point: Vector3 in [elbow, elbow.lerp(hand.origin, 0.5), hand.origin, hand * palm_local]:
			worst = maxf(worst, point.distance_to(_outside_body(point)))
	return worst


## Swings one arm clear of his head and trunk: the upper arm until the elbow is
## out, then the forearm until the wrist and palm are. Runs after the pose has
## been written to the skeleton and works on the bones directly.
func _clear_arm(upper: int, fore: int, hand: int, palm_local: Vector3) -> void:
	var upper_idx: int = _bone[upper]
	var fore_idx: int = _bone[fore]
	var hand_idx: int = _bone[hand]
	if upper_idx < 0 or fore_idx < 0 or hand_idx < 0 or _bone[B.HEAD] < 0 or _bone[B.HIPS] < 0 or _bone[B.CHEST] < 0:
		return
	# Moving the forearm out can bring it back in somewhere else, so a few times.
	for i: int in 4:
		var elbow: Vector3 = skeleton.get_bone_global_pose(fore_idx).origin
		_swing_bone(upper_idx, elbow, _outside_body(elbow))
		elbow = skeleton.get_bone_global_pose(fore_idx).origin
		var wrist: Transform3D = skeleton.get_bone_global_pose(hand_idx)
		# Whichever part of the forearm and hand is deepest in leads it out.
		var deepest: Vector3 = wrist.origin
		var deepest_to: Vector3 = deepest
		var depth: float = 0.0
		for point: Vector3 in [elbow.lerp(wrist.origin, 0.5), wrist.origin, wrist * palm_local]:
			var to: Vector3 = _outside_body(point)
			if point.distance_to(to) > depth:
				depth = point.distance_to(to)
				deepest = point
				deepest_to = to
		if depth > 0.0:
			_swing_bone(fore_idx, deepest, deepest_to)


## Turns a bone about its own joint so that `from`, a point that moves with it,
## comes onto the line to `to`. Skeleton space.
func _swing_bone(idx: int, from: Vector3, to: Vector3) -> void:
	var pose: Transform3D = skeleton.get_bone_global_pose(idx)
	var a: Vector3 = from - pose.origin
	var b: Vector3 = to - pose.origin
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001 or a.normalized().dot(b.normalized()) > 0.99999:
		return
	var turned: Basis = (Basis(Quaternion(a.normalized(), b.normalized())) * pose.basis).orthonormalized()
	var parent_idx: int = skeleton.get_bone_parent(idx)
	var parent_basis: Basis = Basis.IDENTITY
	if parent_idx >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent_idx).basis.orthonormalized()
	var local: Quaternion = (parent_basis.inverse() * turned).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx).slerp(local, _clear_now))


# --- Hands on the ball -----------------------------------------------------------

## Decides whether the hands follow the ball this tick: a pass he is about to
## make a play on, or one he has just caught and is bringing in.
func _watch_ball(delta: float) -> void:
	var pc: PlayController = player.play
	if pc == null or pc.ball == null:
		return
	var ball: Ball = pc.ball
	if player.has_ball:
		if player.catch_timer > 0.0:
			# The ball eases from where it was caught to where it is carried,
			# with the carrying hand on it all the way.
			_hands_target = ball.global_position
			_hands_weight = 1.0
			_off_hand_weight = smoothstep(0.0, 1.0, player.catch_timer / maxf(player.tuning.catch_blend_time, 0.01))
		return
	var tipped: bool = pc.phase == PlayController.Phase.TIPPED
	if not pc.ball_dead and (tipped or pc.phase == PlayController.Phase.LOOSE):
		# A fumble: anyone who has seen it and is nearly on it goes down for it.
		# A tipped pass: anyone near it reaches for it.
		if (player.is_down() and player.dive_reach_timer <= 0.0) or not (tipped or pc.sees_loose_ball(player)):
			return
		var to_ball: Vector3 = ball.global_position - player.position
		to_ball.y = 0.0
		var near: float = 1.0 - to_ball.length() / LOOSE_REACH
		if near > 0.0:
			_hands_target = ball.global_position
			_hands_weight = smoothstep(0.0, 1.0, near)
			_off_hand_weight = _hands_weight
		return
	if pc.ball_dead or ball.state != Ball.State.FLIGHT or ball.thrower == player:
		return
	# Flat on the turf he only reaches if he has just dived for it.
	if player.is_down() and player.dive_reach_timer <= 0.0:
		return
	var remaining: float = ball.flight_time - ball.flight_elapsed
	if remaining > HANDS_TIME:
		return
	var to_spot: Vector3 = ball.target_point - player.position
	to_spot.y = 0.0
	var off_feet: bool = player.state == Player.State.JUMPING or player.dive_reach_timer > 0.0
	if to_spot.length() > (5.0 if off_feet or ball.intended == player else 3.0):
		return
	# The ball moves once more before this pose is drawn.
	_hands_target = ball.next_flight_position(delta)
	_hands_weight = smoothstep(0.0, 1.0, 1.0 - remaining / HANDS_TIME)
	_off_hand_weight = _hands_weight


## Turns and leans the upper body toward the ball the hands are following.
func _turn_to_ball(amount: float) -> void:
	if _hands_weight > 0.0:
		_turn_toward(_hands_target, _hands_weight * amount)


## Twists him from the hips up to face `point` (world space), so that what his
## hands are doing happens in front of his chest and not behind his back. The
## feet keep going the way they were.
func _turn_toward(point: Vector3, weight: float) -> void:
	if weight <= 0.0:
		return
	_turned = true
	var local: Vector3 = skeleton.global_transform.affine_inverse() * point
	if local.x * local.x + local.z * local.z < 0.0004:
		return
	var angle: float = rad_to_deg(atan2(local.x, local.z))
	# Straight behind him either shoulder would do: he stays with the one he
	# has already turned over instead of whipping round to the other.
	if _twist_side != 0.0 and absf(angle) > 110.0 and signf(angle) != _twist_side:
		angle += 360.0 * _twist_side
	elif absf(angle) > 8.0:
		_twist_side = signf(angle)
	var turn: float = clampf(angle, -150.0, 150.0) * weight
	_pose[B.HIPS].y += turn * 0.1
	_pose[B.SPINE].y += turn * 0.27
	_pose[B.SPINE].z -= clampf(turn, -70.0, 70.0) * 0.2
	_pose[B.CHEST].y += turn * 0.3
	_pose[B.NECK].y += turn * 0.1
	_pose[B.HEAD].y += turn * 0.23


## Puts both palms on the ball, one either side of it. Runs after the pose has
## been written to the skeleton and works on the bones directly.
func _reach_hands() -> void:
	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse()
	var target: Vector3 = to_skeleton * _hands_target
	# Half the gap between the hands, in skeleton units. +X is his left.
	var apart: float = HANDS_APART * to_skeleton.basis.get_scale().x
	# Nobody's arms go back through his own body: a ball behind the line of his
	# shoulders is waited for just in front of it, until he has turned to it.
	if _bone[B.CHEST] >= 0 and _bone[B.ARM_L] >= 0 and _bone[B.ARM_R] >= 0:
		var forward: Vector3 = (skeleton.get_bone_global_pose(_bone[B.CHEST]).basis.orthonormalized() * _chest_forward).normalized()
		var mid: Vector3 = (skeleton.get_bone_global_pose(_bone[B.ARM_L]).origin + skeleton.get_bone_global_pose(_bone[B.ARM_R]).origin) * 0.5
		var ahead: float = (target - mid).dot(forward)
		var least: float = CHEST_CLEAR * to_skeleton.basis.get_scale().x
		if ahead < least:
			target += forward * (least - ahead)
	var carries_left: bool = _ball_hand == B.HAND_L
	_reach_arm(B.ARM_L, B.FORE_L, B.HAND_L, _palm_l, target + Vector3(apart, 0.0, 0.0), _hands_weight if carries_left else _off_hand_weight)
	_reach_arm(B.ARM_R, B.FORE_R, B.HAND_R, _palm_r, target - Vector3(apart, 0.0, 0.0), _off_hand_weight if carries_left else _hands_weight)


## Two-bone reach for one arm: bends the elbow until the palm is the right
## distance from the shoulder, then swings the whole arm onto the line to the
## target. Which way the elbow points is left to the pose underneath.
func _reach_arm(upper: int, fore: int, hand: int, palm_local: Vector3, target: Vector3, weight: float) -> void:
	if weight <= 0.0:
		return
	var upper_idx: int = _bone[upper]
	var fore_idx: int = _bone[fore]
	var hand_idx: int = _bone[hand]
	if upper_idx < 0 or fore_idx < 0 or hand_idx < 0:
		return
	var upper_pose: Transform3D = skeleton.get_bone_global_pose(upper_idx)
	var fore_pose: Transform3D = skeleton.get_bone_global_pose(fore_idx)
	var shoulder: Vector3 = upper_pose.origin
	var elbow: Vector3 = fore_pose.origin
	var palm: Vector3 = skeleton.get_bone_global_pose(hand_idx) * palm_local
	var upper_len: float = (elbow - shoulder).length()
	var fore_len: float = (palm - elbow).length()
	var to: Vector3 = target - shoulder
	if upper_len < 0.001 or fore_len < 0.001 or to.length_squared() < 0.000001:
		return
	# Never quite straight, so the elbow keeps a side to bend to.
	var dist: float = clampf(to.length(), absf(upper_len - fore_len) + 0.001, (upper_len + fore_len) * 0.98)

	var a: Vector3 = (shoulder - elbow) / upper_len
	var b: Vector3 = (palm - elbow) / fore_len
	var axis: Vector3 = a.cross(b)
	if axis.length_squared() < 0.0001:
		axis = a.cross(Vector3.UP)
	if axis.length_squared() < 0.0001:
		axis = a.cross(Vector3.RIGHT)
	axis = axis.normalized()
	var bend: float = acos(clampf((upper_len * upper_len + fore_len * fore_len - dist * dist) / (2.0 * upper_len * fore_len), -1.0, 1.0))
	var bend_turn: Basis = Basis(axis, bend - a.angle_to(b))
	var palm_bent: Vector3 = elbow + bend_turn * (palm - elbow)
	var swing: Basis = Basis(Quaternion((palm_bent - shoulder).normalized(), to.normalized()))

	var upper_basis: Basis = (swing * upper_pose.basis).orthonormalized()
	var fore_basis: Basis = (swing * bend_turn * fore_pose.basis).orthonormalized()
	var parent_idx: int = skeleton.get_bone_parent(upper_idx)
	var parent_basis: Basis = Basis.IDENTITY
	if parent_idx >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent_idx).basis.orthonormalized()
	var upper_local: Quaternion = (parent_basis.inverse() * upper_basis).get_rotation_quaternion()
	var fore_local: Quaternion = (upper_basis.inverse() * fore_basis).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(upper_idx, skeleton.get_bone_pose_rotation(upper_idx).slerp(upper_local, weight))
	skeleton.set_bone_pose_rotation(fore_idx, skeleton.get_bone_pose_rotation(fore_idx).slerp(fore_local, weight))


## Moves the hips so the lower foot rests on the turf: this is what makes a
## crouch sink and a run bob without any per-pose height numbers. The hop on
## top of it is the moment in a running stride when both feet are in the air.
func _plant_feet() -> void:
	var hips: int = _bone[B.HIPS]
	var foot_l: int = _bone[B.FOOT_L]
	var foot_r: int = _bone[B.FOOT_R]
	if hips < 0 or foot_l < 0 or foot_r < 0:
		return
	skeleton.set_bone_pose_position(hips, _hips_rest)
	var lowest: float = minf(skeleton.get_bone_global_pose(foot_l).origin.y, skeleton.get_bone_global_pose(foot_r).origin.y)
	var lift: float = (_ankle_rest_y - lowest) * _ground_current + _hop_current * _leg_length
	skeleton.set_bone_pose_position(hips, _hips_rest + _hips_up * lift)


# --- Momentum and loose limbs --------------------------------------------------------

func _reset_dynamics() -> void:
	_vel_prev = Vector3(player.velocity.x, 0.0, player.velocity.z)
	_acc_fwd = 0.0
	_acc_left = 0.0
	_turbo = 0.0
	_punch = 0.0
	_punch_wait = 0.0
	_grab_l_now = 0.0
	_grab_r_now = 0.0
	_grab_with = null
	_fight_now = 0.0
	_move = MOVE_NONE
	_move_timer = 0.0
	_wave = 0.0
	_hop_current = 0.0
	_settle = 1.0
	for i: int in B.COUNT:
		_flop[i] = Vector3.ZERO
		_flop_vel[i] = Vector3.ZERO


## Smoothed acceleration along and across the way the player faces. It leans
## him into a start, sits him back on a stop and banks him through a cut.
func _track_momentum(delta: float) -> void:
	if delta <= 0.0:
		return
	var flat: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var acc: Vector3 = (flat - _vel_prev) / delta
	_vel_prev = flat
	var forward: Vector3 = Vector3(player.facing.x, 0.0, player.facing.z)
	var left: Vector3 = Vector3.UP.cross(forward)
	var blend: float = 1.0 - exp(-9.0 * delta)
	_acc_fwd = lerpf(_acc_fwd, clampf(acc.dot(forward), -60.0, 60.0), blend)
	_acc_left = lerpf(_acc_left, clampf(acc.dot(left), -60.0, 60.0), blend)


## A hit along `world_dir` that the body has to absorb: the torso is shoved and
## the head and limbs lag behind, then swing back.
func jolt(world_dir: Vector3, strength: float) -> void:
	var local: Vector3 = skeleton.global_basis.inverse() * world_dir
	local.y = 0.0
	if local.length_squared() < 0.000001:
		return
	local = local.normalized()
	var kick: float = 700.0 * strength
	var torso: Vector3 = Vector3(-local.z, 0.0, local.x)
	_flop_vel[B.SPINE] += torso * kick * 0.35
	_flop_vel[B.CHEST] += torso * kick * 0.35
	_flop_vel[B.HEAD] += torso * kick * 0.6
	_flop_vel[B.ARM_L] += Vector3(local.z, 0.0, -local.x * 0.5) * kick
	_flop_vel[B.ARM_R] += Vector3(local.z, 0.0, local.x * 0.5) * kick
	_flop_vel[B.FORE_L].y += kick * 0.3 * absf(local.z)
	_flop_vel[B.FORE_R].y += kick * 0.3 * absf(local.z)
	_flop_vel[B.THIGH_L].x += local.z * kick * 0.3
	_flop_vel[B.THIGH_R].x += local.z * kick * 0.3


## Slamming into the turf throws every limb somewhere slightly different.
func _splat(strength: float) -> void:
	var kick: float = 420.0 * strength
	for i: int in [B.ARM_L, B.ARM_R, B.THIGH_L, B.THIGH_R]:
		_flop_vel[i] += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1.0, 1.0)) * kick
	for i: int in [B.FORE_L, B.FORE_R]:
		_flop_vel[i].y += _rng.randf_range(-1.0, 0.4) * kick
	for i: int in [B.SHIN_L, B.SHIN_R]:
		_flop_vel[i].x += _rng.randf_range(0.0, 1.0) * kick
	_flop_vel[B.HEAD] += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), 0.0) * kick * 0.5
	_flop_vel[B.SPINE].x += _rng.randf_range(-1.0, 1.0) * kick * 0.3


func _update_flop(delta: float) -> void:
	for i: int in B.COUNT:
		var offset: Vector3 = _flop[i]
		var vel: Vector3 = _flop_vel[i]
		vel += (-_flop_stiffness * offset - _flop_damping * vel) * delta
		offset = (offset + vel * delta).limit_length(75.0)
		_flop[i] = offset
		_flop_vel[i] = vel
		var weight: float = 1.0
		if player.has_ball and (i == B.ARM_L or i == B.FORE_L or i == B.ARM_R or i == B.FORE_R):
			# Whatever happens, he hangs on to the ball.
			weight = 0.15
		_pose[i] += offset * weight
	# Knees and elbows only bend one way.
	_pose[B.SHIN_L].x = maxf(_pose[B.SHIN_L].x, 0.0)
	_pose[B.SHIN_R].x = maxf(_pose[B.SHIN_R].x, 0.0)
	_pose[B.FORE_L].y = minf(_pose[B.FORE_L].y, 0.0)
	_pose[B.FORE_R].y = minf(_pose[B.FORE_R].y, 0.0)


func _stash() -> void:
	for i: int in B.COUNT:
		_scratch[i] = _pose[i]
		_pose[i] = Vector3.ZERO


## Mixes the stashed pose (weight 0) with the one built since (weight 1).
func _blend_from_stash(weight: float) -> void:
	for i: int in B.COUNT:
		_pose[i] = _scratch[i].lerp(_pose[i], weight)


## Swaps left and right.
func _mirror() -> void:
	for pair: Array in [[B.ARM_L, B.ARM_R], [B.FORE_L, B.FORE_R], [B.HAND_L, B.HAND_R], [B.THIGH_L, B.THIGH_R], [B.SHIN_L, B.SHIN_R], [B.FOOT_L, B.FOOT_R]]:
		var left: Vector3 = _pose[pair[0]]
		_pose[pair[0]] = _pose[pair[1]]
		_pose[pair[1]] = left
	for i: int in [B.HIPS, B.SPINE, B.CHEST, B.NECK, B.HEAD]:
		_pose[i] = Vector3(_pose[i].x, -_pose[i].y, -_pose[i].z)


# --- Pose building ----------------------------------------------------------------

func _build_pose(delta: float) -> void:
	for i: int in B.COUNT:
		_pose[i] = Vector3.ZERO
	var pc: PlayController = player.play
	var ball: Ball = pc.ball if pc != null else null
	_ball_hand = B.HAND_L

	if player.frozen:
		_mode = 20
		_stance()
		return

	match player.state:
		Player.State.DIVING:
			_mode = 11
			_dive()
			return
		Player.State.DOWN:
			_mode = 12
			_down()
			return
		Player.State.JUMPING:
			_mode = 13
			_jump()
			return
		Player.State.SHOVING:
			_mode = 14
			_shove()
			return
		Player.State.SPINNING:
			_mode = 18
			_locomotion(delta)
			_spin()
			return
		Player.State.STIFF_ARM:
			_mode = 19
			_locomotion(delta)
			_stiff_arm()
			return
		Player.State.DRAGGING:
			# Head down, driving the legs with a tackler on his back.
			_mode = 16
			_locomotion(delta)
			_tuck_ball()
			_pose[B.SPINE].x += 20.0
			_pose[B.HEAD].x -= 10.0
			return
		Player.State.HOLDING:
			_mode = 17
			_hold_on()
			return

	_mode = 0
	_locomotion(delta)
	if pc == null:
		return
	var waving: bool = false

	# The throw is noticed here, on the tick the ball leaves the hand.
	var is_thrower: bool = ball.state == Ball.State.FLIGHT and ball.thrower == player
	if is_thrower and not _was_thrower:
		_throw_timer = 0.32
	_was_thrower = is_thrower

	if pc.ball_dead and pc.result == PlayController.Result.TOUCHDOWN and pc.final_team != null:
		_wave = 0.0
		_after_score(pc)
		return

	if player.has_ball:
		# A quarterback sprinting on turbo tucks it until his feet are set again.
		if player == pc.qb and pc.faking() and not pc.ball_dead and not player.is_tucked():
			_mode = 4
			_fake_handoff()
		elif player == pc.qb and pc.phase == PlayController.Phase.POCKET and not pc.ball_dead and player.feet_set >= 1.0 and not player.is_tucked():
			_mode = 2
			_qb_cocked()
		else:
			_mode = 1
			_tuck_ball()
	elif _throw_timer > 0.0:
		_mode = 3
		_throw_follow_through()
	elif player == pc.runner and pc.selling_run():
		_mode = 5
		_fake_carry()
	elif pc.ball_dead:
		pass
	elif _awaits_handoff(pc, ball):
		_mode = 7
		_ready_for_handoff(pc, ball)
	elif ball.state == Ball.State.FLIGHT and _reach_for_pass(ball):
		pass
	elif player.is_blocking or player.block_slow_timer > 0.0:
		var partner: Player = player.block_partner
		if partner == null or partner.animator == null:
			_mode = MODE_BLOCK_READY
			_block_ready()
		elif player.is_blocking:
			_mode = MODE_BLOCK_HOLD
			_block_hold(delta, partner)
		else:
			_mode = MODE_BLOCK_FIGHT
			_block_fight(delta, partner)
	elif ball.carrier != null and ball.carrier.team != player.team:
		_close_in(ball.carrier)
	else:
		waving = player.calling_for_ball
	# The arms go up and come down over a moment; anything else he has to do
	# with them drops the wave at once.
	_wave = move_toward(_wave, 1.0, delta * 5.0) if waving else (move_toward(_wave, 0.0, delta * 5.0) if _mode == 0 else 0.0)
	if _wave > 0.0 and _mode == 0:
		_call_for_ball(pc)
	if not _turned:
		_turn_to_ball(1.0)


func _set_arms(arm: Vector3, fore: Vector3) -> void:
	_pose[B.ARM_L] = arm
	_pose[B.ARM_R] = arm
	_pose[B.FORE_L] = fore
	_pose[B.FORE_R] = fore


func _set_legs(thigh: float, shin: float) -> void:
	_pose[B.THIGH_L] = Vector3(thigh, 0.0, 0.0)
	_pose[B.THIGH_R] = Vector3(thigh, 0.0, 0.0)
	_pose[B.SHIN_L] = Vector3(shin, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(shin, 0.0, 0.0)
	# Keep the soles flat whatever the legs do.
	_pose[B.FOOT_L] = Vector3(-(thigh + shin), 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(-(thigh + shin), 0.0, 0.0)


## A number that differs between walking, running and sprinting.
func _gait(walk: float, run: float, sprint: float) -> float:
	return lerpf(lerpf(walk, run, _run), sprint, _sprint)


## Standing, walking, running and sprinting. Each gait has its own shape and
## they blend by speed. The stride phase advances with distance covered so the
## feet keep pace with the ground.
func _locomotion(delta: float) -> void:
	var flat: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var speed: float = flat.length()
	var run_speed: float = maxf(player.tuning.run_speed, 0.1)
	var move: float = clampf(speed / 1.2, 0.0, 1.0)
	# +1 running the way he faces, -1 backpedalling.
	var forwardness: float = 1.0
	if speed > 0.3:
		forwardness = flat.dot(Vector3(player.facing.x, 0.0, player.facing.z)) / speed
	var backward: float = clampf(-forwardness, 0.0, 1.0)

	_turbo = lerpf(_turbo, 1.0 if player.turbo_active else 0.0, 1.0 - exp(-10.0 * delta))
	_run = smoothstep(1.8, run_speed * 0.8, speed) * (1.0 - 0.45 * backward)
	_sprint = maxf(smoothstep(run_speed * 0.98, run_speed * 1.3, speed), _turbo * 0.7) * _run * (1.0 - backward)

	var step_length: float = _gait(0.8, 1.5, 1.72)
	var stride_dir: float = -1.0 if forwardness < -0.3 else 1.0
	_phase = fposmod(_phase + stride_dir * speed * delta / step_length * PI, TAU)
	var s: float = sin(_phase)
	var c: float = cos(_phase)
	var breath: float = sin(_clock * 2.1)
	_cycle_rate = lerpf(14.0, 46.0, move)

	# Lean: into the run, further into a start, back on a stop, sideways in a cut.
	var lean: float = _gait(5.0, 19.0, 31.0) * move * (1.0 - 1.3 * backward) + clampf(_acc_fwd * 0.4, -16.0, 14.0)
	var bank: float = -clampf(_acc_left * 0.55, -22.0, 22.0) * move
	var brake: float = clampf(-_acc_fwd / 40.0, 0.0, 1.0) * (1.0 - backward)

	_pose[B.HIPS] = Vector3(0.0, -_gait(4.0, 8.0, 11.0) * move * s, bank * 0.5)
	_pose[B.SPINE] = Vector3(3.0 + lean * 0.6, 0.0, bank * 0.5)
	_pose[B.CHEST] = Vector3(2.0 + lean * 0.4 + 1.5 * breath * (1.0 - move), _gait(6.0, 12.0, 16.0) * move * s, 0.0)
	_pose[B.HEAD] = Vector3(-(4.0 + lean * _gait(0.8, 0.7, 0.5)), -_gait(3.0, 5.0, 6.0) * move * s, -bank * 0.6)

	# Legs. The thigh swings between a knee drive in front and a push-off behind;
	# the knee folds as the leg comes through and gives a little under the weight.
	var front: float = _gait(-26.0, -66.0, -86.0) * move
	var behind: float = _gait(16.0, 26.0, 36.0) * move
	var mid: float = (front + behind) * 0.5 - 14.0 * brake
	var swing: float = (behind - front) * 0.5
	var fold: float = _gait(30.0, 100.0, 126.0) * move
	var give: float = _gait(4.0, 20.0, 24.0) * move
	var toe: float = _gait(8.0, 24.0, 34.0) * move
	var through: float = cos(_phase - 0.5 * stride_dir)
	var stand_l: float = maxf(-c * stride_dir, 0.0)
	var stand_r: float = maxf(c * stride_dir, 0.0)
	var thigh_l: float = mid - swing * s - give * 0.5 * stand_l
	var thigh_r: float = mid + swing * s - give * 0.5 * stand_r
	var shin_l: float = 6.0 * move + fold * maxf(through * stride_dir, 0.0) + give * stand_l + 24.0 * brake
	var shin_r: float = 6.0 * move + fold * maxf(-through * stride_dir, 0.0) + give * stand_r + 24.0 * brake
	_pose[B.THIGH_L] = Vector3(thigh_l, 0.0, -2.0)
	_pose[B.THIGH_R] = Vector3(thigh_r, 0.0, -2.0)
	_pose[B.SHIN_L] = Vector3(shin_l, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(shin_r, 0.0, 0.0)
	_pose[B.FOOT_L] = Vector3(clampf(-(thigh_l + shin_l) * 0.6, -25.0, 30.0) + toe * maxf(-s, 0.0), 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(clampf(-(thigh_r + shin_r) * 0.6, -25.0, 30.0) + toe * maxf(s, 0.0), 0.0, 0.0)
	# Both feet leave the ground when the legs are split widest.
	_hop = _gait(0.0, 0.09, 0.15) * move * pow(absf(s), 1.5)

	# Arms pump against the legs, elbows locked near a right angle at a run.
	var pump: float = _gait(16.0, 46.0, 64.0) * move
	var elbow: float = -(14.0 + _gait(14.0, 76.0, 86.0) * move)
	var reach: float = -8.0 * _sprint
	_pose[B.ARM_L] = Vector3(reach + pump * s, 0.0, ARM_DOWN + 2.0 * breath * (1.0 - move))
	_pose[B.ARM_R] = Vector3(reach - pump * s, 0.0, ARM_DOWN + 2.0 * breath * (1.0 - move))
	_pose[B.FORE_L] = Vector3(0.0, elbow + 14.0 * _run * s, 0.0)
	_pose[B.FORE_R] = Vector3(0.0, elbow - 14.0 * _run * s, 0.0)


## Lined up before the snap.
func _stance() -> void:
	_rate = 9.0
	var brain: PlayerBrain = player.brain
	var sway: float = sin(_clock * 1.8)
	var lineman: bool = false
	var quarterback: bool = false
	var defender: bool = false
	if brain != null and brain.off_assign != null:
		lineman = brain.off_assign.job == OffenseAssignment.Job.BLOCK
		quarterback = brain.off_assign.job == OffenseAssignment.Job.QB
	elif brain != null and brain.def_assign != null:
		lineman = brain.def_assign.job == DefenseAssignment.Job.RUSH
		defender = not lineman
	else:
		# No play called yet: just stand there.
		_locomotion(0.0)
		return

	if lineman:
		# Three-point stance: one hand on the turf, eyes up.
		_set_legs(-78.0, 100.0)
		_pose[B.SPINE] = Vector3(38.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(24.0 + sway, 0.0, 0.0)
		_pose[B.NECK] = Vector3(-25.0, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(-30.0, 0.0, 0.0)
		_pose[B.ARM_R] = Vector3(-62.0, 0.0, -84.0)
		_pose[B.FORE_R] = Vector3(0.0, -4.0, 0.0)
		_pose[B.ARM_L] = Vector3(-25.0, 0.0, -70.0)
		_pose[B.FORE_L] = Vector3(0.0, -95.0, 0.0)
	elif quarterback:
		# Under centre, hands out for the snap.
		_set_legs(-42.0, 62.0)
		_pose[B.SPINE] = Vector3(22.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(12.0 + sway, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(-22.0, 12.0 * sin(_clock * 0.9), 0.0)
		_set_arms(Vector3(-38.0, 0.0, -84.0), Vector3(0.0, -35.0, 0.0))
	elif defender:
		# Balanced, hands ready.
		_set_legs(-36.0, 56.0)
		_pose[B.THIGH_L].z = 8.0
		_pose[B.THIGH_R].z = 8.0
		_pose[B.SPINE] = Vector3(18.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(10.0 + sway, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(-18.0, 0.0, 0.0)
		_set_arms(Vector3(-22.0, 0.0, -62.0), Vector3(0.0, -75.0, 0.0))
	else:
		# Receiver / back: staggered two-point stance.
		_pose[B.THIGH_L] = Vector3(-44.0, 0.0, 0.0)
		_pose[B.SHIN_L] = Vector3(58.0, 0.0, 0.0)
		_pose[B.FOOT_L] = Vector3(-14.0, 0.0, 0.0)
		_pose[B.THIGH_R] = Vector3(4.0, 0.0, 0.0)
		_pose[B.SHIN_R] = Vector3(36.0, 0.0, 0.0)
		_pose[B.FOOT_R] = Vector3(-10.0, 0.0, 0.0)
		_pose[B.SPINE] = Vector3(24.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(12.0 + sway, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(-26.0, 0.0, 0.0)
		_pose[B.ARM_L] = Vector3(20.0, 0.0, ARM_DOWN)
		_pose[B.ARM_R] = Vector3(-25.0, 0.0, ARM_DOWN)
		_pose[B.FORE_L] = Vector3(0.0, -70.0, 0.0)
		_pose[B.FORE_R] = Vector3(0.0, -80.0, 0.0)


## Ball carrier: the ball is clamped in the left arm, the right arm keeps pumping.
func _tuck_ball() -> void:
	_ball_hand = B.HAND_L
	_tuck = true
	_pose[B.ARM_L] = Vector3(-18.0, -35.0, -72.0)
	_pose[B.FORE_L] = Vector3(0.0, -112.0, 0.0)
	# Wrist turned in so the fingers come over the front end of the ball.
	_pose[B.HAND_L] = Vector3(0.0, 0.0, -25.0)
	_pose[B.CHEST].y *= 0.4


## Play action, the quarterback: the ball held out low in front of him for the
## back to run over.
func _fake_handoff() -> void:
	_ball_hand = B.HAND_R
	_pose[B.SPINE].x = 14.0
	_pose[B.HEAD].x = -8.0
	_set_arms(Vector3(-42.0, 0.0, -78.0), Vector3(0.0, -38.0, 0.0))


## Play action, the back: both arms folded over a ball that is not there, head
## down for the hole.
func _fake_carry() -> void:
	_set_arms(Vector3(-18.0, -35.0, -72.0), Vector3(0.0, -112.0, 0.0))
	_pose[B.SPINE].x += 14.0
	_pose[B.HEAD].x -= 8.0
	_pose[B.CHEST].y *= 0.4


## The back on a run play, in the moment before the ball is his.
func _awaits_handoff(pc: PlayController, ball: Ball) -> bool:
	return player == pc.runner and pc.off_play != null and pc.off_play.is_run and not pc.handoff_done 			and pc.qb != null and ball.carrier == pc.qb 			and pc.live_time > pc.off_play.handoff_delay - HANDOFF_READY_TIME


## He looks round at the quarterback, shoulders turned to him, and makes a
## pocket for the ball with his arms: one forearm over, one under.
func _ready_for_handoff(pc: PlayController, ball: Ball) -> void:
	var w: float = smoothstep(0.0, 1.0, 1.0 - (pc.off_play.handoff_delay - pc.live_time) / HANDOFF_READY_TIME)
	_rate = 18.0
	_pose[B.ARM_L] = _pose[B.ARM_L].lerp(Vector3(-30.0, -20.0, -68.0), w)
	_pose[B.FORE_L] = _pose[B.FORE_L].lerp(Vector3(0.0, -85.0, 0.0), w)
	_pose[B.ARM_R] = _pose[B.ARM_R].lerp(Vector3(-48.0, -20.0, -60.0), w)
	_pose[B.FORE_R] = _pose[B.FORE_R].lerp(Vector3(0.0, -95.0, 0.0), w)
	_pose[B.CHEST].y *= 1.0 - 0.6 * w
	_turn_toward(ball.global_position, w)


## Quarterback in the pocket: ball up by the ear, front hand out for balance.
func _qb_cocked() -> void:
	_ball_hand = B.HAND_R
	_grip = true
	_pose[B.SPINE].x = 2.0
	_pose[B.CHEST] = Vector3(0.0, -22.0, 0.0)
	_pose[B.HEAD] = Vector3(-4.0, 20.0, 0.0)
	_pose[B.ARM_R] = Vector3(-95.0, 18.0, 8.0)
	_pose[B.FORE_R] = Vector3(0.0, -105.0, 0.0)
	# Wrist bent so the fingers come over the top of the ball.
	_pose[B.HAND_R] = Vector3(0.0, 0.0, -20.0)
	_pose[B.ARM_L] = Vector3(-55.0, 0.0, -62.0)
	_pose[B.FORE_L] = Vector3(0.0, -70.0, 0.0)


## Plays the arm coming down as the scorer spikes the ball.
func spike() -> void:
	_spike_timer = SPIKE_TIME


## Plays the throwing motion for a toss to the running back.
func toss() -> void:
	_throw_timer = 0.32


func _throw_follow_through() -> void:
	_rate = 26.0
	_pose[B.SPINE].x = 20.0
	_pose[B.CHEST] = Vector3(10.0, 30.0, 0.0)
	_pose[B.ARM_R] = Vector3(-62.0, 0.0, -66.0)
	_pose[B.FORE_R] = Vector3(0.0, -12.0, 0.0)
	_pose[B.ARM_L] = Vector3(25.0, 0.0, -66.0)
	_pose[B.FORE_L] = Vector3(0.0, -80.0, 0.0)


## Anyone near where a pass comes down turns to it and puts his hands up.
func _reach_for_pass(ball: Ball) -> bool:
	var remaining: float = ball.flight_time - ball.flight_elapsed
	var reach_time: float = 0.7 if ball.intended == player else 0.45
	if remaining > reach_time:
		return false
	var to_spot: Vector3 = ball.target_point - player.position
	to_spot.y = 0.0
	if ball.intended != player and to_spot.length() > 3.0:
		return false
	var weight: float = clampf(1.0 - remaining / reach_time, 0.0, 1.0)
	_rate = 18.0
	_pose[B.CHEST].y *= 1.0 - weight
	_pose[B.HEAD] = Vector3(-22.0 * weight, 0.0, 0.0)
	_turn_toward(ball.global_position, weight)
	var arm: Vector3 = Vector3(-135.0, 0.0, -80.0)
	var fore: Vector3 = Vector3(0.0, -28.0, 0.0)
	_pose[B.ARM_L] = _pose[B.ARM_L].lerp(arm, weight)
	_pose[B.ARM_R] = _pose[B.ARM_R].lerp(arm, weight)
	_pose[B.FORE_L] = _pose[B.FORE_L].lerp(fore, weight)
	_pose[B.FORE_R] = _pose[B.FORE_R].lerp(fore, weight)
	return true


## Open and wanting the ball: he looks back at the quarterback and waves. Both
## arms overhead when he is standing or drifting; at a run only one hand goes
## up and the other arm keeps pumping.
func _call_for_ball(pc: PlayController) -> void:
	var w: float = smoothstep(0.0, 1.0, _wave)
	var both: float = 1.0 - _run
	_rate = 20.0
	var swing: float = sin(_clock * 9.0 + _wave_offset)
	var local: Vector3 = skeleton.global_transform.affine_inverse() * pc.qb.global_position
	var yaw: float = clampf(rad_to_deg(atan2(local.x, local.z)), -80.0, 80.0) * w
	_pose[B.SPINE].y += yaw * 0.25 * both
	_pose[B.CHEST].y += yaw * 0.35 * both
	_pose[B.HEAD].y += yaw * 0.4
	_pose[B.HEAD].x -= 8.0 * w * both
	var sweep: float = lerpf(10.0, 20.0, both)
	# Arms out to the side and up into a V; the two swing the same way together.
	var up: float = lerpf(70.0, 62.0, both)
	var arm_l: Vector3 = Vector3(-15.0, 0.0, up + sweep * swing)
	var arm_r: Vector3 = Vector3(-15.0, 0.0, up - sweep * swing)
	var fore_l: Vector3 = Vector3(0.0, -22.0 + 15.0 * swing, 0.0)
	var fore_r: Vector3 = Vector3(0.0, -22.0 - 15.0 * swing, 0.0)
	_pose[B.ARM_L] = _pose[B.ARM_L].lerp(arm_l, w)
	_pose[B.FORE_L] = _pose[B.FORE_L].lerp(fore_l, w)
	_pose[B.ARM_R] = _pose[B.ARM_R].lerp(arm_r, w * both)
	_pose[B.FORE_R] = _pose[B.FORE_R].lerp(fore_r, w * both)


## Looking for someone to block: low base, hands up in front of the chest, and
## out to meet a man who is nearly on him.
func _block_ready() -> void:
	_pose[B.SPINE].x = 20.0
	_pose[B.CHEST].x = 8.0
	_pose[B.HEAD].x = -22.0
	_block_legs(22.0, 36.0, 9.0, 0.0, 0.0, 0.0)
	if _opponent_within(1.7):
		_set_arms(Vector3(-52.0, 0.0, -76.0), Vector3(0.0, -75.0, 0.0))
	else:
		_set_arms(Vector3(-35.0, 0.0, -72.0), Vector3(0.0, -95.0, 0.0))


## The legs of a man in a block, on top of whatever stride he has: sunk by
## `thigh` and `shin`, feet `spread` apart and wider still on the `side` he is
## working to (+1 his left), with short choppy steps of `chop` degrees at
## `speed`. `pitch` is how far the hips are tipped forward, for the feet.
func _block_legs(thigh: float, shin: float, spread: float, side: float, chop: float, speed: float, pitch: float = 0.0) -> void:
	var beat: float = sin(_clock * speed + float(player.index) * 1.3)
	var up_l: float = maxf(beat, 0.0)
	var up_r: float = maxf(-beat, 0.0)
	var thigh_l: float = _pose[B.THIGH_L].x - thigh - chop * up_l
	var thigh_r: float = _pose[B.THIGH_R].x - thigh - chop * up_r
	var shin_l: float = _pose[B.SHIN_L].x + shin + chop * 1.8 * up_l
	var shin_r: float = _pose[B.SHIN_R].x + shin + chop * 1.8 * up_r
	_pose[B.THIGH_L] = Vector3(thigh_l, 0.0, spread + 9.0 * maxf(side, 0.0))
	_pose[B.THIGH_R] = Vector3(thigh_r, 0.0, spread + 9.0 * maxf(-side, 0.0))
	_pose[B.SHIN_L].x = shin_l
	_pose[B.SHIN_R].x = shin_r
	# Soles flat on the turf, toes down a little on the foot that is in the air.
	_pose[B.FOOT_L] = Vector3(clampf(-(thigh_l + shin_l) - pitch, -40.0, 35.0) + 12.0 * up_l, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(clampf(-(thigh_r + shin_r) - pitch, -40.0, 35.0) + 12.0 * up_r, 0.0, 0.0)


## How much of a hold two men this far apart have on each other (0..1).
func _grab_weight(partner: Player) -> float:
	var gap: Vector3 = partner.position - player.position
	gap.y = 0.0
	return 1.0 - smoothstep(GRAB_NEAR, GRAB_FAR, gap.length())


## The blocker with a man in his hands: sat down low on a wide base, hands
## inside on the man's chest, sliding to whichever side he tries to get round.
func _block_hold(delta: float, partner: Player) -> void:
	_rate = 16.0
	var left: Vector3 = skeleton.global_basis.x.normalized()
	var forward: Vector3 = skeleton.global_basis.z.normalized()
	# He sees which way the man is going and follows a moment after.
	var want: float = clampf(partner.animator.fight_lean().dot(left), -1.0, 1.0)
	_fight_now = lerpf(_fight_now, want, 1.0 - exp(-8.0 * delta))
	var side: float = _fight_now
	# Every so often he resets his hands and jolts the man back.
	_punch = maxf(_punch - delta * 4.0, 0.0)
	_punch_wait -= delta
	if _punch_wait <= 0.0:
		_punch = 1.0
		_punch_wait = _rng.randf_range(0.7, 1.3)
		jolt(-forward, _rng.randf_range(0.1, 0.2))
		partner.animator.jolt(forward, _rng.randf_range(0.2, 0.35))
	_pose[B.SPINE].x = 17.0 - 7.0 * _punch
	_pose[B.SPINE].z -= 8.0 * side
	_pose[B.CHEST].x = 3.0
	_pose[B.NECK].x = -6.0
	_pose[B.HEAD].x = -8.0
	# His head goes to the other side of the man's from the way they lean.
	_pose[B.HEAD].z += 10.0 * side
	_block_legs(32.0, 56.0, 14.0, side, 9.0, 11.0)
	# Elbows in tight under the other man's arms.
	_set_arms(Vector3(-46.0, 0.0, -72.0), Vector3(0.0, -90.0, 0.0))
	_turn_toward(partner.global_position + Vector3(0.0, 1.2, 0.0), 0.8)
	var hold: float = _grab_weight(partner)
	_grab_with = partner
	_grab_chest = true
	_grab_l = hold
	_grab_r = hold


## The man being blocked: leaning in with his legs driving, hands on the
## blocker's shoulders, working to one side of him and then the other. Each
## change of side comes with a swim or a rip of the arm away from that side.
func _block_fight(delta: float, partner: Player) -> void:
	_rate = 16.0
	if _mode_prev != MODE_BLOCK_FIGHT:
		# Just locked up: a moment of pushing before the first move.
		_fight_wait = _rng.randf_range(0.25, 0.5)
		_move_timer = 0.0
	_fight_wait -= delta
	if _fight_wait <= 0.0:
		_fight_wait = _rng.randf_range(0.55, 0.95)
		_fight_side = -_fight_side
		_move = MOVE_SWIM if _rng.randf() < 0.5 else MOVE_RIP
		_move_timer = MOVE_TIME
		partner.animator.jolt(skeleton.global_basis.z.normalized() - skeleton.global_basis.x.normalized() * _fight_side, _rng.randf_range(0.12, 0.22))
	_move_timer = maxf(_move_timer - delta, 0.0)
	_fight_now = lerpf(_fight_now, _fight_side, 1.0 - exp(-7.0 * delta))
	var side: float = _fight_now

	# The whole body tipped into him, shoulder dipped to the side he is going.
	var pitch: float = 6.0
	_pose[B.HIPS].x = pitch
	_pose[B.SPINE].x = 12.0
	_pose[B.SPINE].z -= 13.0 * side
	_pose[B.CHEST].x = 4.0
	_pose[B.CHEST].y += 12.0 * side
	_pose[B.NECK].x = -6.0
	_pose[B.HEAD].x = -8.0
	_pose[B.HEAD].z -= 8.0 * side
	_block_legs(20.0, 34.0, 7.0, side, 16.0, 14.0, pitch)
	_set_arms(Vector3(-70.0, 0.0, -58.0), Vector3(0.0, -62.0, 0.0))
	_turn_toward(partner.global_position + Vector3(0.0, 1.2, 0.0), 0.8)
	# Eyes past the blocker, on where he wants to get to.
	_pose[B.HEAD].y += 20.0 * side

	var hold: float = _grab_weight(partner)
	_grab_with = partner
	_grab_chest = false
	_grab_l = hold
	_grab_r = hold
	if _move_timer <= 0.0:
		return
	# The arm away from the side he is going lets go and does the work.
	var u: float = 1.0 - _move_timer / MOVE_TIME
	var arc: float = sin(PI * u)
	var arm: Vector3
	var fore: Vector3
	if _move == MOVE_SWIM:
		# Up, over the top of the shoulder and down the far side of it.
		arm = Vector3(lerpf(-45.0, -100.0, u), 0.0, -35.0 + 85.0 * arc)
		fore = Vector3(0.0, -80.0 + 50.0 * arc, 0.0)
	else:
		# From low behind his own hip, up through under the blocker's arm.
		arm = Vector3(lerpf(30.0, -95.0, smoothstep(0.0, 1.0, u)), 0.0, -76.0)
		fore = Vector3(0.0, -105.0 + 25.0 * arc, 0.0)
	_rate = 26.0
	if _fight_side > 0.0:
		_pose[B.ARM_R] = arm
		_pose[B.FORE_R] = fore
		_grab_r = 0.0
	else:
		_pose[B.ARM_L] = arm
		_pose[B.FORE_L] = fore
		_grab_l = 0.0


## Defender bearing down on the ball carrier: arms come out for the tackle.
func _close_in(carrier: Player) -> void:
	var gap: Vector3 = carrier.position - player.position
	gap.y = 0.0
	var weight: float = clampf(1.0 - (gap.length() - 1.2) / 2.3, 0.0, 1.0)
	if weight <= 0.0:
		return
	_pose[B.SPINE].x += 16.0 * weight
	var arm: Vector3 = Vector3(-70.0, 0.0, -58.0)
	var fore: Vector3 = Vector3(0.0, -35.0, 0.0)
	_pose[B.ARM_L] = _pose[B.ARM_L].lerp(arm, weight)
	_pose[B.ARM_R] = _pose[B.ARM_R].lerp(arm, weight)
	_pose[B.FORE_L] = _pose[B.FORE_L].lerp(fore, weight)
	_pose[B.FORE_R] = _pose[B.FORE_R].lerp(fore, weight)


## Spinning out of a tackle: ball wrapped up, free arm in tight, shoulders low.
func _spin() -> void:
	_rate = 24.0
	_tuck_ball()
	_pose[B.SPINE].x += 16.0
	_pose[B.HEAD].x -= 8.0
	_pose[B.ARM_R] = Vector3(-20.0, 30.0, -70.0)
	_pose[B.FORE_R] = Vector3(0.0, -105.0, 0.0)


## Free arm straight out to the side, ball tucked in the other. Built for the
## right arm (ball in the left) and mirrored for the left.
func _stiff_arm() -> void:
	_rate = 26.0
	_tuck_ball()
	_pose[B.SPINE].z += 8.0
	_pose[B.CHEST].y += 18.0
	_pose[B.HEAD].y += 22.0
	_pose[B.ARM_R] = Vector3(-20.0, 0.0, -8.0)
	_pose[B.FORE_R] = Vector3(0.0, -4.0, 0.0)
	if player.move_side > 0.0:
		_mirror()
		_ball_hand = B.HAND_R


## Hanging on to a ball carrier who will not go down: arms wrapped around him,
## legs trailing behind.
func _hold_on() -> void:
	_rate = 24.0
	_pose[B.SPINE] = Vector3(40.0, 0.0, 0.0)
	_pose[B.CHEST] = Vector3(16.0, 0.0, 0.0)
	_pose[B.NECK] = Vector3(-20.0, 0.0, 0.0)
	_pose[B.HEAD] = Vector3(-26.0, 18.0, 0.0)
	_set_arms(Vector3(-84.0, 0.0, -62.0), Vector3(0.0, -55.0, 0.0))
	_pose[B.THIGH_L] = Vector3(22.0, 0.0, 4.0)
	_pose[B.THIGH_R] = Vector3(34.0, 0.0, 4.0)
	_pose[B.SHIN_L] = Vector3(30.0, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(44.0, 0.0, 0.0)
	_pose[B.FOOT_L] = Vector3(35.0, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(35.0, 0.0, 0.0)


func _shove() -> void:
	_rate = 30.0
	_pose[B.SPINE] = Vector3(22.0, 0.0, 0.0)
	_pose[B.CHEST] = Vector3(10.0, 0.0, 0.0)
	_pose[B.HEAD] = Vector3(-24.0, 0.0, 0.0)
	_set_arms(Vector3(-86.0, 0.0, -82.0), Vector3(0.0, -6.0, 0.0))
	_pose[B.THIGH_L] = Vector3(-46.0, 0.0, 0.0)
	_pose[B.SHIN_L] = Vector3(50.0, 0.0, 0.0)
	_pose[B.THIGH_R] = Vector3(26.0, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(22.0, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(30.0, 0.0, 0.0)


func _jump() -> void:
	_rate = 22.0
	_ground = 0.0
	_pose[B.SPINE] = Vector3(-6.0, 0.0, 0.0)
	_pose[B.HEAD] = Vector3(-24.0, 0.0, 0.0)
	_pose[B.THIGH_L] = Vector3(-48.0, 0.0, 0.0)
	_pose[B.SHIN_L] = Vector3(82.0, 0.0, 0.0)
	_pose[B.THIGH_R] = Vector3(-12.0, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(48.0, 0.0, 0.0)
	_pose[B.FOOT_L] = Vector3(30.0, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(30.0, 0.0, 0.0)
	_set_arms(Vector3(-168.0, 0.0, -82.0), Vector3(0.0, -12.0, 0.0))
	_turn_to_ball(1.0)
	if player.has_ball:
		var pc: PlayController = player.play
		if pc != null and player == pc.qb and pc.phase == PlayController.Phase.POCKET:
			# Jump pass: ball up in the throwing hand.
			_ball_hand = B.HAND_R
			_grip = true
			_pose[B.ARM_L] = Vector3(-60.0, 0.0, -60.0)
			_pose[B.FORE_L] = Vector3(0.0, -60.0, 0.0)
		else:
			_tuck_ball()


func _dive() -> void:
	_rate = 28.0
	_ground = 0.0
	_pose[B.SPINE] = Vector3(-8.0, 0.0, 0.0)
	_pose[B.NECK] = Vector3(-25.0, 0.0, 0.0)
	_pose[B.HEAD] = Vector3(-35.0, 0.0, 0.0)
	_set_arms(Vector3(-165.0, 0.0, -80.0), Vector3(0.0, -8.0, 0.0))
	_pose[B.THIGH_L] = Vector3(12.0, 0.0, 6.0)
	_pose[B.THIGH_R] = Vector3(4.0, 0.0, 6.0)
	_pose[B.SHIN_L] = Vector3(26.0, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(8.0, 0.0, 0.0)
	_pose[B.FOOT_L] = Vector3(40.0, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(40.0, 0.0, 0.0)
	_turn_to_ball(0.6)
	if player.has_ball:
		_pose[B.ARM_L] = Vector3(-150.0, -20.0, -80.0)


## Knocked down: limbs flung by the hit while the body tumbles, a sprawl once it
## lands, then gathering the arms and legs to get back up.
func _down() -> void:
	var fall: PlayerFall = player.fall
	_ground = fall.rise * fall.rise
	_rate = lerpf(18.0, 11.0, fall.settle)
	# Limp while falling, a little firmer on the turf, normal again when rising.
	_flop_stiffness = lerpf(lerpf(45.0, 100.0, fall.settle), 160.0, fall.rise)
	_flop_damping = lerpf(lerpf(5.0, 13.0, fall.settle), 15.0, fall.rise)
	if fall.impact > 0.0:
		_splat(fall.impact)
		fall.impact = 0.0

	_tumble(fall)
	if fall.settle > 0.0:
		_stash()
		_sprawl(fall.on_back, fall.variant)
		if fall.mirror:
			_mirror()
		_blend_from_stash(fall.settle)
	if fall.rise > 0.0:
		_stash()
		_set_arms(Vector3(0.0, 0.0, ARM_DOWN), Vector3(0.0, -14.0, 0.0))
		_blend_from_stash(fall.rise)
		_stash()
		_gather(fall.on_back)
		_blend_from_stash(sin(PI * fall.rise))
	if player.has_ball:
		_pose[B.ARM_L] = Vector3(-30.0, -35.0, -70.0)
		_pose[B.FORE_L] = Vector3(0.0, -112.0, 0.0)


## In the air after the hit. The body is thrown one way, so the head, arms and
## legs trail the other way.
func _tumble(fall: PlayerFall) -> void:
	# Hit direction in skeleton space: +Z forward, +X left.
	var push_fwd: float = fall.dir.x
	var push_left: float = -fall.dir.z
	var back: float = clampf(-push_fwd, 0.0, 1.0)
	var fwd: float = clampf(push_fwd, 0.0, 1.0)
	var asym: float = 1.0 if fall.variant % 2 == 0 else -1.0
	var hard: float = 0.5 + 0.5 * fall.power

	_pose[B.SPINE] = Vector3(28.0 * back - 18.0 * fwd, 0.0, 22.0 * push_left)
	_pose[B.CHEST] = Vector3(14.0 * back - 10.0 * fwd, 0.0, 0.0)
	_pose[B.HEAD] = Vector3(25.0 * back - 28.0 * fwd, 0.0, 15.0 * push_left)
	var arm_yaw: float = -15.0 - 55.0 * back * hard + 40.0 * fwd
	_pose[B.ARM_L] = Vector3(0.0, arm_yaw, -30.0 - 30.0 * push_left)
	_pose[B.ARM_R] = Vector3(0.0, arm_yaw, -30.0 + 30.0 * push_left)
	_pose[B.FORE_L] = Vector3(0.0, -25.0 - 30.0 * back, 0.0)
	_pose[B.FORE_R] = Vector3(0.0, -25.0 - 30.0 * back, 0.0)
	var thigh: float = -55.0 * back * hard + 18.0 * fwd
	var spread: float = 10.0 + 15.0 * absf(push_left)
	_pose[B.THIGH_L] = Vector3(thigh + 14.0 * asym, 0.0, spread)
	_pose[B.THIGH_R] = Vector3(thigh - 14.0 * asym, 0.0, spread)
	_pose[B.SHIN_L] = Vector3(25.0 + 45.0 * fwd, 0.0, 0.0)
	_pose[B.SHIN_R] = Vector3(25.0 + 45.0 * fwd + 20.0 * asym, 0.0, 0.0)
	_pose[B.FOOT_L] = Vector3(30.0, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(30.0, 0.0, 0.0)

	# Spinning throws the arms and legs outward.
	var fling: float = clampf(absf(fall.spin_speed) / 9.0, 0.0, 1.0)
	if fling > 0.0:
		_pose[B.ARM_L] = _pose[B.ARM_L].lerp(Vector3(0.0, 0.0, -5.0), fling)
		_pose[B.ARM_R] = _pose[B.ARM_R].lerp(Vector3(0.0, 0.0, -5.0), fling)
		_pose[B.THIGH_L].z += 22.0 * fling
		_pose[B.THIGH_R].z += 22.0 * fling

	if fall.flip:
		# Somersault: tucked into a ball.
		_pose[B.SPINE] = Vector3(40.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(20.0, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(30.0, 0.0, 0.0)
		_pose[B.THIGH_L] = Vector3(-100.0, 0.0, 8.0)
		_pose[B.THIGH_R] = Vector3(-80.0, 0.0, 8.0)
		_pose[B.SHIN_L] = Vector3(115.0, 0.0, 0.0)
		_pose[B.SHIN_R] = Vector3(95.0, 0.0, 0.0)
		_set_arms(Vector3(0.0, -50.0, -35.0), Vector3(0.0, -60.0, 0.0))
	elif fall.kind == PlayerFall.Kind.PANCAKE:
		# Going over backwards, arms windmilling for balance.
		var wheel: float = fall.elapsed * 16.0
		_pose[B.THIGH_L] = Vector3(-62.0, 0.0, 10.0)
		_pose[B.THIGH_R] = Vector3(-40.0, 0.0, 10.0)
		_pose[B.SHIN_L] = Vector3(70.0, 0.0, 0.0)
		_pose[B.SHIN_R] = Vector3(45.0, 0.0, 0.0)
		_pose[B.ARM_L] = Vector3(0.0, -30.0 + 45.0 * sin(wheel), -25.0 + 35.0 * cos(wheel))
		_pose[B.ARM_R] = Vector3(0.0, -30.0 - 45.0 * sin(wheel), -25.0 - 35.0 * cos(wheel))


## One of several ways to lie on the turf, written for one side; the caller
## mirrors it half the time.
func _sprawl(on_back: bool, variant: int) -> void:
	if on_back:
		match variant:
			0:
				# Starfish.
				_pose[B.HEAD] = Vector3(10.0, 25.0, 0.0)
				_pose[B.ARM_L] = Vector3(0.0, 0.0, -25.0)
				_pose[B.FORE_L] = Vector3(0.0, -15.0, 0.0)
				_pose[B.ARM_R] = Vector3(0.0, 0.0, -40.0)
				_pose[B.FORE_R] = Vector3(0.0, -30.0, 0.0)
				_pose[B.THIGH_L] = Vector3(-8.0, 0.0, 20.0)
				_pose[B.SHIN_L] = Vector3(12.0, 0.0, 0.0)
				_pose[B.THIGH_R] = Vector3(-20.0, 0.0, 14.0)
				_pose[B.SHIN_R] = Vector3(40.0, 0.0, 0.0)
			1:
				# One hand up by the helmet, one knee up.
				_pose[B.HEAD] = Vector3(5.0, -30.0, 0.0)
				_pose[B.ARM_L] = Vector3(-90.0, 0.0, -8.0)
				_pose[B.FORE_L] = Vector3(0.0, -85.0, 0.0)
				_pose[B.ARM_R] = Vector3(0.0, 0.0, -60.0)
				_pose[B.FORE_R] = Vector3(0.0, -20.0, 0.0)
				_pose[B.THIGH_L] = Vector3(-58.0, 0.0, 8.0)
				_pose[B.SHIN_L] = Vector3(100.0, 0.0, 0.0)
				_pose[B.THIGH_R] = Vector3(-4.0, 0.0, 16.0)
				_pose[B.SHIN_R] = Vector3(8.0, 0.0, 0.0)
			2:
				# Out cold: arms by the sides, head rolled over.
				_pose[B.SPINE] = Vector3(0.0, 12.0, 0.0)
				_pose[B.HEAD] = Vector3(20.0, 40.0, 0.0)
				_set_arms(Vector3(0.0, 0.0, -62.0), Vector3(0.0, -10.0, 0.0))
				_pose[B.THIGH_L] = Vector3(-6.0, 0.0, 10.0)
				_pose[B.SHIN_L] = Vector3(6.0, 0.0, 0.0)
				_pose[B.THIGH_R] = Vector3(-12.0, 0.0, 24.0)
				_pose[B.SHIN_R] = Vector3(30.0, 0.0, 0.0)
			_:
				# Curled up, one arm across the chest.
				_pose[B.CHEST] = Vector3(8.0, 10.0, 0.0)
				_pose[B.HEAD] = Vector3(22.0, 0.0, 0.0)
				_pose[B.ARM_L] = Vector3(-30.0, -40.0, -70.0)
				_pose[B.FORE_L] = Vector3(0.0, -110.0, 0.0)
				_pose[B.ARM_R] = Vector3(-90.0, 0.0, -20.0)
				_pose[B.FORE_R] = Vector3(0.0, -60.0, 0.0)
				_pose[B.THIGH_L] = Vector3(-50.0, 0.0, 5.0)
				_pose[B.SHIN_L] = Vector3(85.0, 0.0, 0.0)
				_pose[B.THIGH_R] = Vector3(-35.0, 0.0, 18.0)
				_pose[B.SHIN_R] = Vector3(70.0, 0.0, 0.0)
		return

	_pose[B.NECK] = Vector3(-12.0, 0.0, 0.0)
	_pose[B.FOOT_L] = Vector3(40.0, 0.0, 0.0)
	_pose[B.FOOT_R] = Vector3(40.0, 0.0, 0.0)
	match variant:
		0:
			# Hands up either side of the helmet.
			_pose[B.HEAD] = Vector3(-15.0, 50.0, 0.0)
			_pose[B.ARM_L] = Vector3(-90.0, 0.0, -12.0)
			_pose[B.FORE_L] = Vector3(0.0, -80.0, 0.0)
			_pose[B.ARM_R] = Vector3(-90.0, 0.0, -25.0)
			_pose[B.FORE_R] = Vector3(0.0, -60.0, 0.0)
			_pose[B.THIGH_L] = Vector3(4.0, 0.0, 12.0)
			_pose[B.SHIN_L] = Vector3(10.0, 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(6.0, 0.0, 20.0)
			_pose[B.SHIN_R] = Vector3(35.0, 0.0, 0.0)
		1:
			# One arm stretched out ahead, one leg kicked out wide.
			_pose[B.HEAD] = Vector3(-20.0, -40.0, 0.0)
			_pose[B.ARM_L] = Vector3(0.0, 0.0, 55.0)
			_pose[B.FORE_L] = Vector3(0.0, -10.0, 0.0)
			_pose[B.ARM_R] = Vector3(0.0, 0.0, -55.0)
			_pose[B.FORE_R] = Vector3(0.0, -15.0, 0.0)
			_pose[B.THIGH_L] = Vector3(8.0, 0.0, 6.0)
			_pose[B.SHIN_L] = Vector3(5.0, 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(0.0, 0.0, 35.0)
			_pose[B.SHIN_R] = Vector3(20.0, 0.0, 0.0)
		2:
			# Flat out, arms by the sides.
			_pose[B.HEAD] = Vector3(-10.0, -55.0, 0.0)
			_set_arms(Vector3(10.0, 0.0, -65.0), Vector3(0.0, -20.0, 0.0))
			_pose[B.THIGH_L] = Vector3(5.0, 0.0, 18.0)
			_pose[B.SHIN_L] = Vector3(8.0, 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(5.0, 0.0, 8.0)
			_pose[B.SHIN_R] = Vector3(22.0, 0.0, 0.0)
		_:
			# Twisted, one heel in the air.
			_pose[B.SPINE] = Vector3(0.0, -10.0, 0.0)
			_pose[B.HEAD] = Vector3(-20.0, 35.0, 0.0)
			_pose[B.ARM_L] = Vector3(-90.0, 0.0, -5.0)
			_pose[B.FORE_L] = Vector3(0.0, -95.0, 0.0)
			_pose[B.ARM_R] = Vector3(0.0, 0.0, -15.0)
			_pose[B.FORE_R] = Vector3(0.0, -10.0, 0.0)
			_pose[B.THIGH_L] = Vector3(6.0, 0.0, 5.0)
			_pose[B.SHIN_L] = Vector3(45.0, 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(4.0, 0.0, 22.0)
			_pose[B.SHIN_R] = Vector3(5.0, 0.0, 0.0)


## Halfway back to his feet: curled up from his back, or pushing up off his chest.
func _gather(on_back: bool) -> void:
	if on_back:
		_pose[B.SPINE] = Vector3(38.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(16.0, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(10.0, 0.0, 0.0)
		_set_legs(-95.0, 120.0)
		_set_arms(Vector3(-40.0, 0.0, -70.0), Vector3(0.0, -40.0, 0.0))
	else:
		_pose[B.SPINE] = Vector3(20.0, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(-30.0, 0.0, 0.0)
		_pose[B.THIGH_L] = Vector3(-90.0, 0.0, 6.0)
		_pose[B.SHIN_L] = Vector3(115.0, 0.0, 0.0)
		_pose[B.THIGH_R] = Vector3(-55.0, 0.0, 6.0)
		_pose[B.SHIN_R] = Vector3(95.0, 0.0, 0.0)
		_set_arms(Vector3(-60.0, 0.0, -70.0), Vector3(0.0, -55.0, 0.0))


## After a score: the scorer dances, his team celebrates round him, the other
## side takes it badly.
func _after_score(pc: PlayController) -> void:
	var flat: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	# All of it is done standing: on the move it gives way to the run.
	var still: float = 1.0 - smoothstep(0.8, 2.6, flat.length())
	if player.team != pc.final_team:
		_sulk(pc, still)
	elif player == pc.scorer:
		_scorer_dance(pc, still)
	else:
		_cheer(pc, still)


## The scorer: the ball held up, slammed down, then his dance.
func _scorer_dance(pc: PlayController, still: float) -> void:
	if player.has_ball:
		_mode = 30
		_tuck_ball()
		_stash()
		_rate = 16.0
		_pose[B.SPINE] = Vector3(-8.0, 0.0, 0.0)
		_pose[B.HEAD] = Vector3(-20.0, 0.0, 0.0)
		_pose[B.ARM_L] = Vector3(-168.0, 0.0, -80.0)
		_pose[B.FORE_L] = Vector3(0.0, -8.0, 0.0)
		_pose[B.ARM_R] = Vector3(-150.0, 0.0, -66.0)
		_pose[B.FORE_R] = Vector3(0.0, -70.0, 0.0)
		_blend_from_stash(still)
		return
	if _spike_timer > 0.0:
		# The arm that had the ball comes through hard, the body after it.
		_mode = 31
		_rate = 30.0
		_pose[B.SPINE] = Vector3(34.0, 0.0, 0.0)
		_pose[B.CHEST] = Vector3(14.0, 20.0, 0.0)
		_pose[B.HEAD] = Vector3(10.0, 0.0, 0.0)
		_pose[B.ARM_L] = Vector3(-28.0, 0.0, -76.0)
		_pose[B.FORE_L] = Vector3(0.0, -6.0, 0.0)
		_pose[B.ARM_R] = Vector3(40.0, 0.0, -60.0)
		_pose[B.FORE_R] = Vector3(0.0, -50.0, 0.0)
		_pose[B.THIGH_L] = Vector3(-40.0, 0.0, 0.0)
		_pose[B.SHIN_L] = Vector3(50.0, 0.0, 0.0)
		_pose[B.THIGH_R] = Vector3(10.0, 0.0, 0.0)
		_pose[B.SHIN_R] = Vector3(24.0, 0.0, 0.0)
		return

	var style: int = posmod(pc.celebration_style, DANCES)
	_mode = 32 + style
	_stash()
	_rate = 18.0
	var t: float = _clock
	match style:
		0:
			# Fists pumping overhead one after the other, hips going with them.
			var s: float = sin(t * 10.0)
			var bob: float = absf(s)
			_pose[B.HIPS] = Vector3(0.0, 10.0 * s, 5.0 * s)
			_pose[B.SPINE] = Vector3(-4.0, 0.0, -9.0 * s)
			_pose[B.HEAD] = Vector3(-14.0, 0.0, 6.0 * s)
			_pose[B.ARM_L] = Vector3(-150.0 + 30.0 * s, 0.0, -70.0)
			_pose[B.FORE_L] = Vector3(0.0, -45.0 - 30.0 * s, 0.0)
			_pose[B.ARM_R] = Vector3(-150.0 - 30.0 * s, 0.0, -70.0)
			_pose[B.FORE_R] = Vector3(0.0, -45.0 + 30.0 * s, 0.0)
			_set_legs(-20.0 * bob, 40.0 * bob)
			_hop = 0.05 * (1.0 - bob)
		1:
			# The chicken: hands in the armpits, elbows flapping, knees going
			# in and out, head pecking.
			var flap: float = sin(t * 14.0)
			var peck: float = sin(t * 7.0)
			_pose[B.SPINE] = Vector3(16.0, 0.0, 0.0)
			_pose[B.HEAD] = Vector3(-12.0 + 16.0 * peck, 0.0, 0.0)
			_set_arms(Vector3(10.0, -90.0, -30.0 + 24.0 * flap), Vector3(0.0, -140.0, 0.0))
			_set_legs(-38.0 - 8.0 * peck, 64.0 + 16.0 * peck)
			_pose[B.THIGH_L].z = 12.0 + 12.0 * flap
			_pose[B.THIGH_R].z = 12.0 + 12.0 * flap
		2:
			# Flexing both arms at the crowd and stamping from foot to foot.
			var s: float = sin(t * 8.0)
			_pose[B.SPINE] = Vector3(-8.0, 0.0, 0.0)
			_pose[B.CHEST] = Vector3(-4.0, 22.0 * sin(t * 4.0), 0.0)
			_pose[B.HEAD] = Vector3(-16.0, 0.0, 0.0)
			_set_arms(Vector3(-90.0, 0.0, -12.0), Vector3(0.0, -65.0 - 30.0 * absf(s), 0.0))
			var up_l: float = maxf(s, 0.0)
			var up_r: float = maxf(-s, 0.0)
			_pose[B.THIGH_L] = Vector3(-46.0 * up_l, 0.0, 8.0)
			_pose[B.SHIN_L] = Vector3(66.0 * up_l, 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(-46.0 * up_r, 0.0, 8.0)
			_pose[B.SHIN_R] = Vector3(66.0 * up_r, 0.0, 0.0)
		_:
			# One hand on the hip, the other pointing at the sky, swapping
			# sides on the beat.
			var p: float = clampf(sin(t * 5.0) * 3.0, -1.0, 1.0)
			var left: float = (p + 1.0) * 0.5
			var bob: float = absf(sin(t * 10.0))
			var sky: Vector3 = Vector3(-20.0, 0.0, 56.0)
			var sky_fore: Vector3 = Vector3(0.0, -6.0, 0.0)
			_pose[B.HIPS] = Vector3(0.0, 0.0, 8.0 * p)
			_pose[B.SPINE] = Vector3(-2.0, 12.0 * p, -7.0 * p)
			_pose[B.HEAD] = Vector3(-10.0, 20.0 * p, 0.0)
			_pose[B.ARM_L] = HIP_ARM.lerp(sky, left)
			_pose[B.FORE_L] = HIP_FORE.lerp(sky_fore, left)
			_pose[B.ARM_R] = HIP_ARM.lerp(sky, 1.0 - left)
			_pose[B.FORE_R] = HIP_FORE.lerp(sky_fore, 1.0 - left)
			_hip_l = (1.0 - left) * still
			_hip_r = left * still
			_set_legs(-16.0 * bob, 32.0 * bob)
	_cycle_rate = 40.0
	_blend_from_stash(still)


## The scorer's teammates, once they have got to him.
func _cheer(pc: PlayController, still: float) -> void:
	var variant: int = pc.celebration_variant(player, CHEERS)
	_mode = 40 + variant
	_stash()
	_rate = 18.0
	var pump: float = sin(_clock * 9.0 + float(player.index) * 1.7)
	var up: float = maxf(pump, 0.0)
	match variant:
		0:
			# Jumping up and down with both arms in the air.
			_pose[B.SPINE] = Vector3(-6.0, 0.0, 0.0)
			_pose[B.HEAD] = Vector3(-18.0, 0.0, 0.0)
			_set_arms(Vector3(-150.0 + 14.0 * pump, 0.0, -70.0), Vector3(0.0, -30.0 - 20.0 * pump, 0.0))
			_set_legs(-22.0 * (1.0 - up), 44.0 * (1.0 - up))
			_hop = 0.2 * up
		1:
			# Punching the air with one fist.
			_pose[B.SPINE] = Vector3(-4.0, 0.0, 0.0)
			_pose[B.CHEST] = Vector3(0.0, 14.0 * up, 0.0)
			_pose[B.HEAD] = Vector3(-14.0, 0.0, 0.0)
			_pose[B.ARM_L] = Vector3(-165.0, 0.0, -80.0)
			_pose[B.FORE_L] = Vector3(0.0, -80.0 + 70.0 * up, 0.0)
			_pose[B.ARM_R] = Vector3(-20.0, 0.0, -70.0)
			_pose[B.FORE_R] = Vector3(0.0, -95.0, 0.0)
			_set_legs(-14.0 * up, 28.0 * up)
			if player.index % 2 == 1:
				_mirror()
		_:
			# Pushing both palms at the sky.
			_pose[B.SPINE] = Vector3(-5.0, 0.0, 6.0 * pump)
			_pose[B.HEAD] = Vector3(-16.0, 0.0, 0.0)
			_set_arms(Vector3(-90.0 - 24.0 * up, 0.0, -12.0), Vector3(0.0, -90.0 + 45.0 * up, 0.0))
			_set_legs(-18.0 * (1.0 - up), 36.0 * (1.0 - up))
			_hop = 0.06 * up
	_cycle_rate = 36.0
	_blend_from_stash(still)


## The team that has just been scored on.
func _sulk(pc: PlayController, still: float) -> void:
	var variant: int = pc.celebration_variant(player, SULKS)
	_mode = 50 + variant
	var t: float = _clock + float(player.index) * 0.9
	if variant == SULK_TRUDGE:
		# Walking off, shoulders down, arms hanging: this one goes on top of
		# the walk, not in place of it.
		_pose[B.SPINE].x += 14.0
		_pose[B.CHEST].x += 8.0
		_pose[B.HEAD] = Vector3(28.0, 6.0 * sin(t * 1.3), 0.0)
		_pose[B.ARM_L] = Vector3(_pose[B.ARM_L].x * 0.3, 0.0, ARM_DOWN)
		_pose[B.ARM_R] = Vector3(_pose[B.ARM_R].x * 0.3, 0.0, ARM_DOWN)
		_pose[B.FORE_L] = Vector3(0.0, -8.0, 0.0)
		_pose[B.FORE_R] = Vector3(0.0, -8.0, 0.0)
		return
	_stash()
	_rate = 7.0
	match variant:
		0:
			# Hands on hips, shaking his head at the turf.
			_pose[B.SPINE] = Vector3(12.0, 0.0, 0.0)
			_pose[B.CHEST] = Vector3(8.0, 0.0, 0.0)
			_pose[B.HEAD] = Vector3(26.0, 22.0 * sin(t * 3.2), 0.0)
			_set_arms(HIP_ARM, HIP_FORE)
			_hip_l = still
			_hip_r = still
		1:
			# Hands on his helmet, staring at the sky.
			_pose[B.SPINE] = Vector3(-10.0, 0.0, 3.0 * sin(t * 1.1))
			_pose[B.HEAD] = Vector3(-24.0, 0.0, 0.0)
			_set_arms(Vector3(-96.0, 0.0, -4.0), Vector3(0.0, -118.0, 0.0))
		2:
			# Down on one knee, head bowed, a hand on the other knee.
			_pose[B.SPINE] = Vector3(22.0, 0.0, 0.0)
			_pose[B.CHEST] = Vector3(10.0, 0.0, 0.0)
			_pose[B.HEAD] = Vector3(30.0, 0.0, 0.0)
			_pose[B.THIGH_L] = Vector3(-88.0, 0.0, 0.0)
			_pose[B.SHIN_L] = Vector3(92.0, 0.0, 0.0)
			_pose[B.FOOT_L] = Vector3(-4.0, 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(8.0, 0.0, 0.0)
			_pose[B.SHIN_R] = Vector3(96.0, 0.0, 0.0)
			_pose[B.FOOT_R] = Vector3(45.0, 0.0, 0.0)
			_pose[B.ARM_L] = Vector3(-50.0, 0.0, -70.0)
			_pose[B.FORE_L] = Vector3(0.0, -30.0, 0.0)
			_pose[B.ARM_R] = Vector3(0.0, 0.0, ARM_DOWN)
			_pose[B.FORE_R] = Vector3(0.0, -10.0, 0.0)
			if player.index % 2 == 1:
				_mirror()
		_:
			# A tantrum: stamping his feet and throwing his arms down.
			_rate = 20.0
			_cycle_rate = 36.0
			var u: float = sin(t * 11.0)
			var slam: float = absf(u)
			_pose[B.SPINE] = Vector3(16.0, 0.0, 0.0)
			_pose[B.HEAD] = Vector3(18.0, 16.0 * sin(t * 5.0), 0.0)
			_set_arms(Vector3(-55.0 + 75.0 * slam, 0.0, -62.0), Vector3(0.0, -75.0 + 60.0 * slam, 0.0))
			_pose[B.THIGH_L] = Vector3(-55.0 * maxf(u, 0.0), 0.0, 0.0)
			_pose[B.SHIN_L] = Vector3(80.0 * maxf(u, 0.0), 0.0, 0.0)
			_pose[B.THIGH_R] = Vector3(-55.0 * maxf(-u, 0.0), 0.0, 0.0)
			_pose[B.SHIN_R] = Vector3(80.0 * maxf(-u, 0.0), 0.0, 0.0)
	_blend_from_stash(still)


func _opponent_within(radius: float) -> bool:
	if player.team == null or player.team.opponent == null:
		return false
	for other: Player in player.team.opponent.players:
		if other.is_down():
			continue
		var gap: Vector3 = other.position - player.position
		gap.y = 0.0
		if gap.length_squared() < radius * radius:
			return true
	return false
