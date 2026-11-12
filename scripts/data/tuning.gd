class_name Tuning
extends Resource
## Every gameplay-feel number in one place. Edit resources/tuning.tres in the inspector.
## Distances are yards (1 unit = 1 yard), times are seconds, speeds are yards/second.

@export_group("Field")
@export var field_length: float = 100.0
@export var end_zone_depth: float = 10.0
@export var field_width: float = 40.0
## Yard line (from own goal) where a new drive starts.
@export var drive_start_yard: float = 25.0
@export var touchback_yard: float = 20.0

@export_group("Rules")
@export var downs_per_series: int = 4
@export var yards_to_gain: float = 30.0
## Game clock in seconds, played as two halves. Only runs while the ball is live.
@export var game_length: float = 360.0
@export var touchdown_points: int = 6
@export var safety_points: int = 2
## After a touchdown: one untimed play from this many yards out, worth this much.
@export var conversion_points: int = 2
@export var conversion_distance: float = 3.0

@export_group("Kickoff")
## Yard line (from the kicking team's own goal) the ball is kicked from.
@export var kickoff_yard: float = 35.0
## The kick comes down between these two, in yards from the receiving team's
## goal line (negative = in its end zone)...
@export var kickoff_land_min: float = -5.0
@export var kickoff_land_max: float = 20.0
## ...and within this share of the field's width, around the middle.
@export var kickoff_land_width: float = 0.6
## Seconds the kick is in the air.
@export var kickoff_hang_time: float = 3.4
## Seconds between the line-up and the kick.
@export var kickoff_delay: float = 1.5
## The kicking team lines up this far behind the ball.
@export var kickoff_run_up: float = 2.0
@export var halftime_banner_time: float = 4.0

@export_group("Movement")
@export var run_speed: float = 7.6
@export var acceleration: float = 42.0
@export var deceleration: float = 55.0
@export var line_speed_scale: float = 0.86
## Pass rushers lined up within this many yards of the ball count as linemen.
@export var line_depth: float = 1.25
## Near the goal line the defense is squeezed up so that its deepest man and
## zone stay this many yards inside the back of the end zone.
@export var def_back_margin: float = 1.5
@export var carrier_speed_scale: float = 0.97
@export var player_radius: float = 0.5
## Opponents who are not blocking each other keep this much room each, so they
## can brush shoulders but never stand in the same spot.
@export var body_radius: float = 0.4
## Share of the speed two such opponents run into each other with that turns
## into sliding past each other.
@export var body_slip: float = 1.0

@export_group("Turbo")
@export var turbo_speed_multiplier: float = 1.35
## Meter is 0..1. Units per second while held.
@export var turbo_drain: float = 0.42
@export var turbo_refill: float = 0.16
## After emptying the meter it must refill to this before turbo works again.
@export var turbo_restart_threshold: float = 0.2

@export_group("Actions")
@export var dive_speed: float = 13.5
@export var dive_time: float = 0.28
@export var dive_recover_time: float = 0.75
## Human defender: a dive auto-aims at the carrier (or late-hit victim) inside this range.
@export var dive_trigger_range: float = 6.5
@export var shove_radius: float = 2.0
## Minimum dot product between shove direction and the victim (cone width).
@export var shove_arc_dot: float = 0.15
@export var shove_time: float = 0.28
@export var shove_lunge_speed: float = 6.0
@export var shove_knockdown_impulse: float = 10.0
## Shared by spin and stiff arm: seconds before the next one of either kind.
@export var move_cooldown: float = 0.9
## A spin keeps the running line and cannot be steered. Started with the stick
## leaned to one side it also sidesteps that way (spin_juke_distance).
@export var spin_time: float = 0.4
## Yards a juking spin carries him sideways.
@export var spin_juke_distance: float = 2.0
## Window in which tackles against a spinning carrier mostly slide off.
@export var spin_evade_time: float = 0.45
@export var spin_speed_scale: float = 0.85
## How long the arm stays out. The carrier can still steer.
@export var stiff_arm_time: float = 0.5
@export var stiff_arm_speed_scale: float = 0.9
@export var knockdown_time: float = 1.1
@export var knockdown_friction: float = 16.0

@export_group("Jump")
@export var jump_time: float = 0.45
@export var jump_height: float = 1.3
## Seconds after landing before the next jump.
@export var jump_cooldown: float = 0.35
## Catch and interception radius multiplier for a player in the air.
@export var jump_catch_radius_scale: float = 1.5
## A jump for a pass that comes down within this many yards carries the player
## toward it.
@export var jump_ball_range: float = 3.5

@export_group("Diving catch")
## Catch and interception radius multiplier for a player diving at the ball.
@export var dive_catch_radius_scale: float = 2.2
## Seconds after hitting the turf that a dive still counts for the catch.
@export var dive_catch_grace: float = 0.2
## A dive at a pass that comes down within this many yards is aimed at it.
@export var dive_ball_range: float = 6.0
## Slowest such dive: a short lunge at a ball that is close.
@export var dive_ball_min_speed: float = 5.0

@export_group("Passing")
## Pass power runs from 0 (lob) to 1 (bullet) and sets the flat speed between
## these two. Gravity is fixed, so a slower pass flies longer and arcs higher.
@export var pass_lob_speed: float = 16.0
@export var pass_bullet_speed: float = 32.0
## Holding a pass button this long or less is a tap: power 0.
@export var pass_tap_time: float = 0.12
## Holding this long is full power; the ball is thrown without waiting for release.
@export var pass_charge_time: float = 0.45
@export var pass_gravity: float = 22.0
@export var pass_release_height: float = 1.9
@export var pass_catch_height: float = 1.3
@export var pass_max_lead_time: float = 2.6
## Throwing on the run (turbo held): the pass can miss by up to this many yards
## per yard thrown.
@export var pass_scramble_error: float = 0.18
## Seconds after letting go of turbo before the QB's feet are set again. 0 = at once.
@export var pass_set_feet_time: float = 0.25
## Chance that a pass to a receiver on the move is led too far, and by how many
## yards past the furthest he could sprint to. He has to jump or dive to get
## there.
@export var pass_overlead_chance: float = 0.15
@export var pass_overlead_min: float = 2.0
@export var pass_overlead_max: float = 5.0
## Lead pass: the ball goes further along the receiver's run, by this share of
## the ground he can make up by sprinting while it is in the air plus `base`
## yards, and never more than `max`. He has to speed up to get there.
@export var pass_lead_share: float = 0.5
@export var pass_lead_base: float = 0.3
@export var pass_lead_max: float = 5.0
## A lead pass multiplies pass_overlead_chance by this, and can miss long or
## short by up to this share of the extra lead (long twice as far as short).
@export var pass_lead_overlead_scale: float = 2.6
@export var pass_lead_error: float = 0.6
## Underthrown pass: whatever his route, the ball comes down short of where the
## receiver is as it is thrown, on the line from him to the quarterback, by this
## share of the ground he could cover while it is in the air: at least `min`
## yards, never more than `max`. He has to stop and come back for it.
@export var pass_under_share: float = 0.3
@export var pass_under_min: float = 2.0
@export var pass_under_max: float = 4.0
## An underthrown pass can come up shorter still, by up to this share of that.
@export var pass_under_error: float = 0.4
## A lead looks at the nearest defender within `range` yards of the receiver:
## one ahead of him on his run shortens it by up to this share, one trailing
## him lengthens it.
@export var pass_place_cover_range: float = 5.0
@export var pass_place_cover_scale: float = 0.35
## Reach of a receiver on his feet. Jumping and diving reach further.
@export var catch_radius: float = 1.6
## Over the last part of its flight the ball bends toward the hands of whoever
## is about to make a play on it. Looks only: the catch is decided as before.
@export var catch_guide_time: float = 0.3
## Seconds the hands take to bring a caught ball in.
@export var catch_blend_time: float = 0.18
@export var catch_base_chance: float = 0.96
## Defenders closer than this to the receiver reduce the catch chance.
@export var cover_radius: float = 3.0
## Chance removed by one defender standing right on the receiver.
@export var cover_penalty: float = 0.65
## Share of that penalty a receiver takes off by shielding the ball: he is
## standing still or coming back to it, and the defender is behind him.
@export var cover_shield: float = 0.4
@export var catch_min_chance: float = 0.12
@export var defender_catch_radius: float = 1.7
## Interception chance when the receiver fails the catch and a defender is at the ball.
@export var interception_chance: float = 0.18
## Interception chance when no receiver is near the ball at all.
@export var interception_chance_open: float = 0.5
## Chance removed by each defender in the air within reach of the ball.
@export var contest_penalty: float = 0.15
## A pass nobody held on to stays in the air, and live, until it lands. Dropped
## by the receiver it keeps this share of its flat speed and pops up a little...
@export var tip_drop_speed_share: float = 0.25
@export var tip_drop_up_min: float = 2.5
@export var tip_drop_up_max: float = 4.5
## ...batted by a defender it goes up higher, and anywhere.
@export var tip_bat_speed_min: float = 2.0
@export var tip_bat_speed_max: float = 6.0
@export var tip_bat_up_min: float = 4.0
@export var tip_bat_up_max: float = 7.0
## Chance that a man within reach of a tipped ball comes down with it (on the
## offense, on the defense), and how high it can be for a man on his feet to
## get a hand on it. One try a team.
@export var tip_catch_chance: float = 0.35
@export var tip_intercept_chance: float = 0.12
@export var tip_catch_height: float = 2.2
## Seconds after a tip before anyone can get a hand on it again.
@export var tip_retry_time: float = 0.3
## How many of each team go for a tipped ball.
@export var ai_tip_chasers: int = 2

## Run plays: a runner within `handoff_reach` yards of the quarterback is handed
## the ball, which takes `handoff_time` seconds to change hands. Further away it
## is tossed to him at `toss_speed`, on an arc `toss_height` yards high for
## every yard it travels.
@export var handoff_reach: float = 1.8
@export var handoff_time: float = 0.12
@export var toss_speed: float = 13.0
@export var toss_height: float = 0.12

@export_group("Tackling")
@export var tackle_radius: float = 1.1
@export var dive_tackle_radius: float = 1.5
@export var tackle_base_chance: float = 0.74
@export var dive_tackle_bonus: float = 0.2
@export var tackle_retry_time: float = 0.6
## Tackle chance multiplier for a defender who is tied up by a blocker.
@export var blocked_tackle_scale: float = 0.5
@export var broken_tackle_stun: float = 0.75
@export var tackle_knockdown_impulse: float = 8.0

@export_group("Ratings")
## Each pair is the value for a player rated 0 and one rated 100; ratings in
## between blend linearly, so 50 sits halfway.
## Run speed multiplier.
@export var speed_scale_low: float = 0.88
@export var speed_scale_high: float = 1.12
## Turbo drain multiplier.
@export var endurance_drain_low: float = 1.5
@export var endurance_drain_high: float = 0.5
## Catch chance multiplier (interception chance too).
@export var catch_scale_low: float = 0.8
@export var catch_scale_high: float = 1.1
## Tackle chance multiplier while the carrier's spin window is active (juke rating).
## A little weaker than the stiff arm: the spin works on every side and can juke.
@export var spin_tackle_scale_low: float = 0.7
@export var spin_tackle_scale_high: float = 0.16
## Tackle chance multiplier for a tackler who runs into a stiff arm (strength rating).
@export var stiff_arm_tackle_scale_low: float = 0.6
@export var stiff_arm_tackle_scale_high: float = 0.1
## Chance that a carrier in the air clears a diving tackler.
@export var hurdle_chance_low: float = 0.6
@export var hurdle_chance_high: float = 1.0
## Longest throw in yards. A pass aimed further comes up short.
@export var pass_range_low: float = 28.0
@export var pass_range_high: float = 62.0
## Bullet pass speed multiplier.
@export var pass_speed_scale_low: float = 0.85
@export var pass_speed_scale_high: float = 1.15
## Yards a pass can miss by per yard thrown, even with the feet set.
@export var accuracy_error_low: float = 0.08
@export var accuracy_error_high: float = 0.0
## Multiplies pass_overlead_chance.
@export var accuracy_overlead_scale_low: float = 1.5
@export var accuracy_overlead_scale_high: float = 0.5
## Multiplies pass_scramble_error and pass_set_feet_time.
@export var agility_scale_low: float = 1.6
@export var agility_scale_high: float = 0.4
## Tackle chance multiplier from the carrier's strength.
@export var strength_tackle_scale_low: float = 1.1
@export var strength_tackle_scale_high: float = 0.9
## Tackle chance multiplier from the tackler's tackling rating.
@export var tackling_scale_low: float = 0.85
@export var tackling_scale_high: float = 1.15
## Multiplies the time it takes to shed a block: the blocker's blocking rating...
@export var blocking_shed_scale_low: float = 0.7
@export var blocking_shed_scale_high: float = 1.3
## ...and the strength of the man being blocked.
@export var strength_shed_scale_low: float = 1.3
@export var strength_shed_scale_high: float = 0.7
## Multiply block_pancake_chance: the blocker's blocking rating and the strength
## of the man he is blocking.
@export var pancake_blocking_scale_low: float = 0.4
@export var pancake_blocking_scale_high: float = 1.6
@export var pancake_strength_scale_low: float = 1.6
@export var pancake_strength_scale_high: float = 0.4
## Multiplies ai_move_mistime_chance and ai_move_wrong_side_chance (juke rating).
@export var move_mistime_scale_low: float = 1.6
@export var move_mistime_scale_high: float = 0.4
## Speed multiplier for a quarterback running with the ball tucked or past the
## line: he is not built like a running back.
@export var qb_run_speed_scale: float = 0.94
## A CPU quarterback's taste for running, from the average of his speed and
## agility: multiplies ai_qb_keeper_chance. A pocket passer
## hardly ever goes; a quick one goes often. Below zero counts as never.
@export var qb_mobility_scale_low: float = -1.0
@export var qb_mobility_scale_high: float = 3.0
## Multiply ai_cover_lag and ai_cover_cut_slow: the defender's coverage rating...
@export var coverage_scale_low: float = 1.4
@export var coverage_scale_high: float = 0.6
## ...and the get-open rating of the receiver he is covering.
@export var get_open_scale_low: float = 0.7
@export var get_open_scale_high: float = 1.3
## Multiply ai_cover_bust_chance: the receiver's get-open rating and the
## defender's coverage rating.
@export var bust_get_open_scale_low: float = 0.4
@export var bust_get_open_scale_high: float = 1.6
@export var bust_coverage_scale_low: float = 1.6
@export var bust_coverage_scale_high: float = 0.4
## A receiver working open after his route: seconds between looks for a better
## spot, yards of error in judging each spot, and his speed multiplier.
@export var get_open_rethink_low: float = 1.0
@export var get_open_rethink_high: float = 0.3
@export var get_open_noise_low: float = 3.0
@export var get_open_noise_high: float = 0.0
@export var get_open_speed_scale_low: float = 0.7
@export var get_open_speed_scale_high: float = 1.0
## Seconds a wrapped-up carrier drags his tackler before going down. Negative
## counts as none, so only carriers stronger than average drag anyone.
@export var drag_time_low: float = -0.9
@export var drag_time_high: float = 0.9
## Chance that the drag ends with the tackler shaken off instead.
@export var shake_off_chance_low: float = -0.35
@export var shake_off_chance_high: float = 0.35

## Chance that a tackle knocks the ball loose.
@export var fumble_chance_low: float = 0.17
@export var fumble_chance_high: float = 0.03

@export_group("Fumbles")
## Multiplies the fumble chance on a dive or shove tackle.
@export var fumble_big_hit_scale: float = 1.5
## Flat speed the ball leaves the carrier at, and how fast it pops upward.
@export var fumble_pop_speed_min: float = 3.0
@export var fumble_pop_speed_max: float = 8.0
@export var fumble_pop_up_min: float = 2.5
@export var fumble_pop_up_max: float = 6.0
## How much of the carrier's own speed the ball keeps.
@export var fumble_carry_share: float = 0.5
## Degrees either side of the direction of the hit the ball can come out at: a
## standing big hit, a diving one, and a ball that comes out as he is wrestled
## down.
@export var fumble_spread_high: float = 70.0
@export var fumble_spread_low: float = 35.0
@export var fumble_spread_wrap: float = 150.0
## Nobody can get hold of the ball for this long after it comes out or is
## bobbled, nor while it is higher off the turf than this.
@export var fumble_pickup_delay: float = 0.3
@export var fumble_pickup_height: float = 1.4
## How close a player on his feet has to be to scoop it up, and one diving to
## fall on it.
@export var fumble_scoop_radius: float = 1.0
@export var fumble_dive_radius: float = 1.6
## Chance that a scoop comes off (times his catching), less this much for every
## yard per second the ball is moving. Falling on it is surer.
@export var fumble_scoop_chance: float = 0.6
@export var fumble_scoop_speed_penalty: float = 0.05
@export var fumble_dive_chance: float = 0.85
## A miss knocks the ball away at up to this speed, and he cannot try again for
## this long.
@export var fumble_bobble_speed: float = 5.0
@export var fumble_retry_time: float = 0.5
## A ball nobody has got hold of after this long is whistled dead where it lies.
@export var fumble_dead_time: float = 8.0
## Seconds before a CPU player right there and looking at it sees the ball is
## out...
@export var ai_fumble_notice_min: float = 0.1
@export var ai_fumble_notice_max: float = 0.35
## ...plus up to this much for one who is ai_fumble_notice_range yards away or
## has his back to it.
@export var ai_fumble_notice_far: float = 1.2
@export var ai_fumble_notice_range: float = 20.0
## Chance that he has no idea (more likely with his back to it), and how much
## longer it then takes him.
@export var ai_fumble_clueless_chance: float = 0.3
@export var ai_fumble_clueless_time_min: float = 1.2
@export var ai_fumble_clueless_time_max: float = 2.8
## A ball this close in front of him he sees whatever else he was doing.
@export var ai_fumble_wake_range: float = 3.5
## How many on each team go for the ball; the rest who have seen it come over
## and block.
@export var ai_fumble_chasers: int = 3
## This close to the ball he decides once whether to dive on it: the chance with
## room to pick it up, and with an opponent as close as ai_fumble_contest_range.
@export var ai_fumble_dive_range: float = 2.4
@export var ai_fumble_dive_chance: float = 0.3
@export var ai_fumble_dive_contested: float = 0.6
@export var ai_fumble_contest_range: float = 3.5

@export_group("Dragging")
## Drags shorter than this do not happen: the carrier just goes down.
@export var drag_min_time: float = 0.2
## Multiplies the drag time after a dive or a shove.
@export var drag_big_hit_scale: float = 0.5
## Carrier speed multiplier with a tackler hanging on.
@export var drag_speed_scale: float = 0.38
## How far behind the carrier the tackler hangs.
@export var drag_hold_distance: float = 0.8

@export_group("Blocking")
## Speed multiplier for a defender tied up by a blocker.
@export var block_slow_factor: float = 0.22
@export var block_shed_time_min: float = 1.3
@export var block_shed_time_max: float = 3.0
## How long a beaten blocker stays on the ground.
@export var block_beaten_time: float = 0.9
@export var block_immune_time: float = 1.2
## Run plays only: chance, each time a block is made, that the blocker puts his
## man on the ground (before ratings), how far into the block it happens, and
## how long the defender stays down.
@export var block_pancake_chance: float = 0.1
@export var block_pancake_time_min: float = 0.2
@export var block_pancake_time_max: float = 0.7
@export var block_pancake_down_time: float = 2.5

@export_group("Impact Feel")
## Real-time seconds of hit-stop on a tackle.
@export var hit_stop_time: float = 0.09
@export var hit_stop_time_scale: float = 0.05
## Camera trauma (0..1) added per event.
@export var tackle_shake: float = 0.75
@export var shove_shake: float = 0.4
@export var shake_decay: float = 2.2
@export var shake_max_offset: float = 1.1
## A player flashes for a moment when he gets the ball (white) and when he
## loses it (red): seconds it lasts and how strong it starts, 0..1.
@export var flash_time: float = 0.4
@export var possession_flash: float = 0.4
@export var fumble_flash: float = 0.55

@export_group("Audio")
## Off silences everything (the calls still count, for the tests).
@export var audio_enabled: bool = true
## Bus levels in dB: everything, hits and whooshes, the crowd, the quarterback
## and the huddle, and the menu blips.
@export var audio_master_db: float = 0.0
@export var audio_sfx_db: float = 0.0
@export var audio_crowd_db: float = -5.0
@export var audio_voice_db: float = -2.0
@export var audio_ui_db: float = -14.0
## Linear volume (0..1) of the steady crowd murmur, of the roar at full
## excitement, of a chant and of the huddle's muttering.
@export var audio_crowd_bed_level: float = 0.45
@export var audio_crowd_roar_level: float = 0.9
@export var audio_chant_level: float = 0.7
@export var audio_huddle_level: float = 0.6
## Linear volume of the announcer.
@export var audio_announcer_level: float = 1.0
## The announcer's remarks on a play ("What a catch!"): real seconds he waits
## between two of them, and a scale on how often he makes one (0 = never).
@export var audio_remark_gap: float = 8.0
@export var audio_remark_scale: float = 1.0
## The color commentator: her linear volume, the real seconds she waits between
## two quips and before saying the same line again, a scale on how often she
## has one (0 = never), and the chance of idle chatter while a play is picked.
@export var audio_color_level: float = 1.0
@export var audio_color_gap: float = 12.0
@export var audio_color_repeat_gap: float = 120.0
@export var audio_color_scale: float = 1.0
@export var audio_color_idle_chance: float = 0.12
## A touchdown is a walk-in when no defender on his feet is within this many
## yards of the scorer, and a long one when the play gained at least this many.
@export var audio_walk_in_yards: float = 6.0
@export var audio_long_score_yards: float = 25.0
## A completed pass play gaining at least this many yards lights the defense up.
@export var audio_hot_pass_yards: float = 20.0
## A completion thrown at least this far past the line is a great throw.
@export var audio_deep_throw_yards: float = 25.0
## Crowd excitement lost per second once nothing is happening.
@export var audio_crowd_decay: float = 0.22
## Chance the crowd starts a chant while a play is being picked.
@export var audio_chant_chance: float = 0.35

@export_group("Turf FX")
@export var blood_enabled: bool = true
## Drops sprayed by a tackle, and by a shove or dive that flattens someone.
@export var blood_drops_tackle: int = 22
@export var blood_drops_knockdown: int = 10
## Splats and marks kept on the field; the oldest is reused past this.
@export var max_blood_splats: int = 900
@export var max_footprints: int = 6000
## Distance run between cleat prints.
@export var footprint_stride: float = 0.9

@export_group("Play Flow")
@export var pre_snap_delay: float = 0.5
@export var cpu_snap_delay_min: float = 1.0
@export var cpu_snap_delay_max: float = 1.8
## Seconds after the whistle during which late hits are allowed.
@export var late_hit_window: float = 1.6
@export var scored_banner_time: float = 5.0
@export var turnover_banner_time: float = 2.2

@export_group("Celebration")
## The scorer's teammates gather on a ring this far from him.
@export var celebration_ring_radius: float = 2.4
## Seconds after the whistle that the scorer spikes the ball.
@export var celebration_spike_time: float = 0.5
## Chance per score that one of the beaten team takes a run at a celebrating
## player, how long he stews first, how close to the scorer he has to be at
## the whistle to be the one, and how far out he leaves his feet.
@export var cheap_shot_chance: float = 0.3
@export var cheap_shot_delay_min: float = 1.2
@export var cheap_shot_delay_max: float = 2.4
@export var cheap_shot_range: float = 18.0
@export var cheap_shot_dive_range: float = 3.2

@export_group("AI")
@export var ai_qb_min_time: float = 0.9
@export var ai_qb_max_time: float = 3.0
## Receiver counts as open when the nearest defender is at least this far away.
@export var ai_qb_open_distance: float = 2.6
@export var ai_qb_pressure_radius: float = 3.0
## Until this many seconds after the snap the CPU quarterback only looks at
## receivers at least `ai_qb_min_depth` yards downfield; after that (or under
## pressure) he will take a checkdown.
@export var ai_qb_checkdown_time: float = 2.0
@export var ai_qb_min_depth: float = 3.0
## Out of time with every receiver covered this tightly, the CPU quarterback
## tucks the ball and runs instead of forcing a throw.
@export var ai_qb_scramble_open: float = 2.0
## Chance (before his mobility) that a CPU quarterback keeps the ball by design
## on a pass play: between `time_min` and `time_max` seconds after the snap he
## runs around one side, `width` yards out before he turns upfield, going
## `forward` yards upfield for every yard across on the way.
@export var ai_qb_keeper_chance: float = 0.08
@export var ai_qb_keeper_time_min: float = 0.4
@export var ai_qb_keeper_time_max: float = 0.8
@export var ai_qb_keeper_width: float = 9.0
@export var ai_qb_keeper_forward: float = 0.35
## Running behind the line, he still pulls up and throws to a receiver this open.
@export var ai_qb_run_throw_open: float = 6.0
## An open receiver at least this far away gets a lob to run under.
@export var ai_qb_lob_distance: float = 22.0
## ...as long as he is running downfield at least this fast and no defender
## within `ai_qb_lob_clear` yards of him is deeper than he is.
@export var ai_qb_lob_min_speed: float = 3.0
@export var ai_qb_lob_clear: float = 9.0
## Pass power the CPU uses for a lob, a regular pass and a bullet.
@export var ai_qb_lob_power: float = 0.0
@export var ai_qb_normal_power: float = 0.55
@export var ai_qb_bullet_power: float = 1.0
## Pass power for a long throw that is not safe to lob.
@export var ai_qb_drive_power: float = 0.85
## The CPU quarterback leads or underthrows a receiver only when that spot looks
## at least this many yards more open than the regular one. His judgment of
## each spot is off by up to `noise` yards (before his accuracy rating), so he
## is sometimes wrong.
@export var ai_qb_lead_margin: float = 1.6
@export var ai_qb_under_margin: float = 1.5
@export var ai_qb_placement_noise: float = 0.8
## A lead also needs the receiver to have this much turbo left.
@export var ai_qb_lead_min_turbo: float = 0.3
## An underthrow brings the receiver back to the ball with his man behind him.
## The CPU quarterback throws one only at least this many yards long, with the
## nearest defender on the far side of the receiver, and with nobody within
## `lane` yards of the path of the ball or the spot it comes down. Even then he
## thinks of it only this share of the time (the sharper CPU team: `ai_edge_under_chance`).
@export var ai_qb_under_min_distance: float = 8.0
@export var ai_qb_under_lane: float = 4.5
@export var ai_qb_under_chance: float = 0.3
## Seconds after the snap before pass rushers start using turbo.
@export var ai_rush_turbo_delay: float = 0.7
## Seconds a coverage defender takes to read a change in his receiver's movement.
@export var ai_cover_lag: float = 0.42
## Share of his speed a coverage defender loses for a moment when his receiver
## makes a full change of direction (less for a gentler cut).
@export var ai_cover_cut_slow: float = 0.8
## Seconds ahead of the receiver a coverage defender aims.
@export var ai_cover_lead: float = 0.15
## Yards a coverage defender stays on the deep side of his receiver.
@export var ai_cover_cushion: float = 1.2
@export var ai_cover_speed_scale: float = 1.0
## A defender uses turbo to recover once his receiver is this far past him,
## or this far away in any direction.
@export var ai_cover_beaten_depth: float = 1.0
@export var ai_cover_beaten_gap: float = 4.0
## Chance that a coverage defender bites on a sharp cut by his receiver, before
## the ratings of the two are applied.
@export var ai_cover_bust_chance: float = 0.2
## Seconds he chases the wrong way, and his speed multiplier while he does.
@export var ai_cover_bust_time: float = 1.0
@export var ai_cover_bust_speed: float = 0.6
## How sharp a cut has to be to count (1 = a full stop or start, 2 = a full
## turnaround), seconds before the same defender can be fooled again, and
## seconds after the snap before anyone can be.
@export var ai_cover_bust_surprise: float = 0.8
@export var ai_cover_bust_cooldown: float = 1.2
@export var ai_cover_bust_min_time: float = 0.6
## Seconds a receiver waits at the end of his route before he goes looking for
## open space (each receiver rolls his own), and how far away he looks.
@export var ai_get_open_delay_min: float = 0.3
@export var ai_get_open_delay_max: float = 1.1
@export var ai_get_open_radius: float = 5.0
## With the nearest defender at least this far away he is in no hurry to leave:
## the wait runs down at `stay_scale` of its normal speed and he holds his spot.
@export var ai_get_open_stay_distance: float = 5.0
@export var ai_get_open_stay_scale: float = 0.35
## A receiver calls for the ball once the nearest defender is this much further
## away than `ai_qb_open_distance`, and stops once he is this much closer.
@export var ai_call_open_margin: float = 0.4
@export var ai_call_close_margin: float = 0.3
## He keeps this far from other receivers, and avoids spots with a defender
## within `lane_width` yards of the line from the quarterback.
@export var ai_get_open_spacing: float = 6.0
@export var ai_get_open_lane_width: float = 1.5
@export var ai_get_open_lane_penalty: float = 2.0
## Zone defenders judge receivers by where they will be this many seconds on.
@export var ai_zone_anticipate: float = 0.5
## How far from the middle of his zone a defender goes to sit on a receiver (0..1).
@export var ai_zone_tightness: float = 0.85
## With the zone empty, how far he leans toward the nearest receiver (share of radius).
@export var ai_zone_lean: float = 0.35
## Yards a deep-zone defender stays behind the deepest receiver.
@export var ai_deep_cushion: float = 3.5
## A deep-zone defender comes no shallower than this share of his radius in
## front of the middle of his zone, however short the receivers stay.
@export var ai_deep_step_up: float = 0.4
## A receiver thrown to this many times in the last few passes is "hot": zone
## defenders pick him up from further away and prefer him over others.
@export var ai_hot_targets: int = 3
@export var ai_hot_memory: int = 5
@export var ai_hot_zone_scale: float = 1.5
@export var ai_hot_bonus: float = 6.0
## How much the defense makes of what it has seen the offense do (0 = nothing,
## 1 = normal): recognising a play it keeps seeing, and spying a quarterback who
## keeps running. See Scout. Only a defense the CPU calls the plays for adjusts.
@export var ai_scout_strength: float = 1.0
## Recognised play: multiplies how late and slow the defender covering its
## favourite receiver is on his cuts (fully recognised; less in between).
@export var ai_scout_cover_scale: float = 0.45
## Recognised play: chance (when fully recognised) that a second defender leaves
## his own job to sit in front of the favourite receiver. Whoever he left is
## open.
@export var ai_scout_bracket_chance: float = 0.6
## Recognised play: share of ai_ball_react_time and ai_run_read_time the defense
## saves.
@export var ai_scout_react_saving: float = 0.7
## A spy waits this many yards past the line, across from the quarterback, and
## goes for him once he has tucked the ball for `react_time` seconds or comes
## within `trigger_depth` yards of the line.
@export var ai_spy_depth: float = 4.5
@export var ai_spy_react_time: float = 0.2
@export var ai_spy_trigger_depth: float = 1.5
## Underneath zone defenders come up for a quarterback who has had the ball
## tucked this long and is running at the line, within this many yards of them.
@export var ai_scramble_read_time: float = 0.45
@export var ai_scramble_read_range: float = 14.0
## Chance per coverage defender (before his coverage rating) that he blows his
## assignment at the snap: for a random time between the two below he stands
## flat-footed, then has to catch up. About one play in ten has one.
@export var ai_blown_coverage_chance: float = 0.04
@export var ai_blown_coverage_time_min: float = 1.3
@export var ai_blown_coverage_time_max: float = 2.2
## Seconds coverage defenders keep covering after a handoff before they read run.
@export var ai_run_read_time: float = 0.4
## Play action: chance per coverage defender (before his coverage rating, how
## much the offense has been running and how well the play is recognised) that
## he comes up for the faked handoff. A deep zone bites `deep_scale` as often.
## He keeps coming for a random time between the two below after the fake ends.
@export var ai_play_action_bite_chance: float = 0.2
@export var ai_play_action_deep_scale: float = 0.2
@export var ai_play_action_bite_time_min: float = 0.2
@export var ai_play_action_bite_time_max: float = 0.5
## Play action: the bite chance is multiplied by `low` for an offense that never
## runs and `high` for one that only runs.
@export var ai_play_action_run_scale_low: float = 0.3
@export var ai_play_action_run_scale_high: float = 1.5
## Delay before defenders break on a thrown ball.
@export var ai_ball_react_time: float = 0.25
@export var ai_ball_react_radius: float = 14.0
## The closest few defenders who are within `radius` of the landing spot, and can
## get within `margin` yards of it in time, go for the ball; the rest run to cut
## off the catch.
@export var ai_ball_breakers: int = 2
@export var ai_ball_break_margin: float = 3.0
@export var ai_ball_break_radius: float = 9.0
## Yards downfield of the landing spot the others aim for.
@export var ai_ball_cut_off: float = 4.0
## The defender covering the intended receiver plays a short ball tighter: on a
## pass this many yards short of the receiver's run he aims ai_cover_cushion
## yards past the landing spot instead (in between for less).
@export var ai_ball_short_full: float = 3.0
## A defender this close to the landing spot, this long before the ball arrives,
## may jump for it.
@export var ai_contest_range: float = 2.6
@export var ai_contest_time: float = 0.3
@export var ai_contest_chance: float = 0.6
## Chance that a CPU player who cannot reach the ball on his feet jumps or dives
## for it. Decided once per pass, this long before the ball arrives.
@export var ai_catch_effort_chance: float = 0.4
## Multiplies that chance on the person's team: there the jump and the dive are
## mostly left to the person.
@export var ai_catch_effort_human_scale: float = 0.6
## Shorter than dive_time, so a dive is still in the air when the ball gets there.
@export var ai_catch_effort_time: float = 0.26
## Max seconds ahead of the carrier a pursuer aims.
@export var ai_pursuit_max_lead: float = 1.5
@export var ai_turbo_range: float = 9.0
@export var ai_dive_range: float = 2.3
@export var ai_dive_chance: float = 0.6
## Chance that a CPU carrier answers a tackler straight ahead with a spin.
@export var ai_spin_chance: float = 0.45
## Chance that a CPU carrier stiff-arms a tackler closing from the side.
@export var ai_stiff_arm_chance: float = 0.45
## How far to the side the tackler must be (0 = straight ahead, 1 = level with him).
@export var ai_stiff_arm_side_dot: float = 0.6
## A CPU carrier starts a well-timed move this many seconds before the tackler
## gets to him, and never looks at a tackler further away than `range`.
@export var ai_move_lead: float = 0.2
@export var ai_move_range: float = 7.0
## Chance (before his juke rating) that he gets the timing wrong: half the time
## too early, by starting this many seconds before contact, so the move is over
## when the tackler arrives; half the time too late, by this many seconds.
@export var ai_move_mistime_chance: float = 0.4
@export var ai_move_early_min: float = 0.55
@export var ai_move_early_max: float = 0.95
@export var ai_move_late_min: float = 0.15
@export var ai_move_late_max: float = 0.4
## Chance (before his juke rating) that a stiff arm goes out on the wrong side.
@export var ai_move_wrong_side_chance: float = 0.12
## A CPU carrier dives when the goal line or the first-down marker is this close
## and a defender is nearer than the matching pressure distance.
@export var ai_dive_reach: float = 3.0
@export var ai_dive_goal_pressure: float = 2.6
@export var ai_dive_marker_pressure: float = 1.8
@export var ai_carrier_avoid_radius: float = 9.0
## Chance per second that a CPU player takes a cheap shot after the whistle.
@export var ai_late_hit_chance: float = 0.1

@export_group("CPU edge")
## How much sharper the team playing against the person is than the person's
## own CPU teammates (0 = no different, 1 = everything below in full). With no
## person playing, both teams get it. See PlayController.cpu_edge().
@export_range(0.0, 1.0) var cpu_skill: float = 1.0
## At full edge these take the place of ai_catch_effort_chance,
## ai_contest_chance, ai_qb_keeper_chance, ai_rush_turbo_delay and
## ai_ball_react_time.
@export var ai_edge_catch_effort_chance: float = 0.9
@export var ai_edge_contest_chance: float = 0.9
@export var ai_edge_keeper_chance: float = 0.28
@export var ai_edge_rush_turbo_delay: float = 0.35
@export var ai_edge_ball_react_time: float = 0.15
## In place of ai_qb_under_chance.
@export var ai_edge_under_chance: float = 0.6
## Defenders going for a pass in the air, in place of ai_ball_breakers.
@export var ai_edge_ball_breakers: int = 3
## A quarterback with nobody open and an unblocked defender within
## `escape_range` yards leaves the pocket round the other side, as on a keeper,
## with this chance (times his mobility, at full edge). Rolled once per play.
@export var ai_edge_escape_chance: float = 0.85
@export var ai_edge_escape_range: float = 5.5
## Out of the pocket like that, he throws to the first man who comes open, and
## gets rid of the ball once a rusher is this close again.
@export var ai_edge_escape_dump_range: float = 3.0
## From this long after the snap a quarterback with nobody open looks at both
## sides of the line: with no unblocked defender on one of them, up to
## `lane_depth` yards ahead of him and `lane_width` yards out, he goes round
## it, with this chance (times his mobility, at full edge). Rolled once per
## play. Out of time with nobody open he goes round the emptier side anyway.
@export var ai_edge_lane_time: float = 1.0
@export var ai_edge_lane_depth: float = 10.0
@export var ai_edge_lane_width: float = 11.0
@export var ai_edge_lane_chance: float = 0.6
## He takes the empty side unless a receiver is at least this open, and looks
## again this many seconds after deciding against it.
@export var ai_edge_lane_open: float = 4.0
@export var ai_edge_lane_retry: float = 0.5
## Nobody open and no empty side either: from this long after the snap he
## breaks out round the emptier one, with this chance (times his mobility, at
## full edge). Rolled once per play.
@export var ai_edge_bail_time: float = 2.0
@export var ai_edge_bail_chance: float = 0.5
## The least mobility a quarterback's taste for running is worked out from at
## full edge, so that a pocket passer runs now and then too.
@export var ai_edge_mobility_floor: float = 0.6
## At full edge these take the place of ai_move_mistime_chance and
## ai_move_wrong_side_chance, of both ai_spin_chance and ai_stiff_arm_chance,
## and of ai_dive_chance (a dive tackle is a big hit: it knocks the ball loose
## more often than wrapping up does).
@export var ai_edge_move_mistime_chance: float = 0.1
@export var ai_edge_move_wrong_side_chance: float = 0.02
@export var ai_edge_move_chance: float = 0.85
@export var ai_edge_dive_chance: float = 0.95
## A carrier jumps over a tackler who dives at him from within this range,
## with this chance (at full edge).
@export var ai_edge_hurdle_range: float = 3.5
@export var ai_edge_hurdle_chance: float = 0.4
## At full edge these multiply ai_cover_bust_chance and ai_blown_coverage_chance.
@export var ai_edge_bust_scale: float = 0.6
@export var ai_edge_blown_scale: float = 0.5
## Chance per play (at full edge) that one coverage defender means to flatten
## a receiver or the back before the ball is thrown, and that a second one
## does too. He goes this long after the snap: from `takeout_close_range`
## yards he runs at the man, from `takeout_range` he dives, and he gives it up
## `takeout_give_up` seconds after the snap.
@export var ai_takeout_chance: float = 0.45
@export var ai_takeout_second_chance: float = 0.25
@export var ai_takeout_close_range: float = 7.0
@export var ai_takeout_time_min: float = 0.5
@export var ai_takeout_time_max: float = 1.6
@export var ai_takeout_range: float = 2.3
@export var ai_takeout_give_up: float = 3.0

@export_group("CPU play calling")
## The clock only runs while the ball is live, so the time left is really a
## number of plays: the clock divided by how long a play lasts. This is the
## starting guess, in seconds; the play caller corrects it as the game goes.
@export var ai_call_play_time: float = 5.0
## An offense that needs points before the clock runs out compares the yards it
## needs per play it has left with a normal gain (yards_to_gain over
## downs_per_series). Below `calm_pace` times normal it calls plays as usual;
## at `urgent_pace` times normal it throws downfield almost every down.
@export var ai_call_calm_pace: float = 0.6
@export var ai_call_urgent_pace: float = 2.0
## Share of that hurry a team keeps at the end of the first half when it leads.
@export var ai_call_half_urgency_leading: float = 0.5
## A team leading in the second half starts running the clock down with this
## many plays left, more and more as they run out.
@export var ai_call_kill_plays: float = 12.0
## With no more than this many plays' worth of clock left, the play counts as
## the last one. On it, a team that needs a touchdown from further out than
## `heave_distance` calls its deepest pass and the quarterback heaves it.
@export var ai_call_last_play: float = 1.2
@export var ai_call_heave_distance: float = 15.0
## How much each yard downfield is worth to a CPU quarterback choosing a
## receiver (in yards of openness): normally, and when fully in a hurry.
@export var ai_qb_depth_bonus: float = 0.08
@export var ai_qb_urgent_depth_bonus: float = 0.25
## A heave is thrown at the latest this long after the snap, or once it would
## come down within `heave_range_margin` yards of the end of his range.
@export var ai_qb_heave_max_time: float = 5.0
@export var ai_qb_heave_range_margin: float = 4.0

@export_group("Camera")
## The camera sits behind the followed player: this high and this far back.
@export var camera_height: float = 19.5
@export var camera_distance: float = 24.7
@export var camera_fov: float = 50.0
@export var camera_follow_speed: float = 5.0
## Yards in front of the followed player the camera aims at.
@export var camera_look_ahead: float = 9.0
## How much of the player's sideways position the camera follows (0..1).
@export var camera_z_follow: float = 0.85
## Seconds the camera takes to circle round behind the other team when the ball
## changes sides in the middle of a play.
@export var camera_swing_time: float = 0.8


func half_width() -> float:
	return field_width * 0.5


## X of the goal line a team attacking in `dir` is trying to reach.
func goal_x(dir: int) -> float:
	return field_length if dir > 0 else 0.0


## X of the goal line a team attacking in `dir` defends.
func own_goal_x(dir: int) -> float:
	return 0.0 if dir > 0 else field_length


## World X for "own N yard line" of a team attacking in `dir`.
func yard_to_x(dir: int, yard: float) -> float:
	return yard if dir > 0 else field_length - yard
