"""Writes the offensive play .tres files and the offense playbook from one table.
Run from the project root."""
import os

Q, R, B, RUN = 0, 1, 2, 3
I_FORM, SINGLEBACK, HEAVY, GUN_SPREAD, GUN_TRIPS, GOAL_LINE = range(6)
CAT_RUN, SHORT, DEEP = range(3)

LINE = [("C", (-0.6, 0)), ("G", (-0.9, -1.7)), ("G", (-0.9, 1.7))]
# Per formation: quarterback's spot, then the four skill players in roster
# order (receiver, receiver, back, tight end / fullback).
FORMATIONS = {
    I_FORM: ((-4, 0), [("WR", (-0.6, -18.4)), ("WR", (-0.6, 18.4)), ("RB", (-6.5, 0.4)), ("FB", (-4.5, 1.8))]),
    # The wideout outside a tight end stands a step off the line, so the tight end is not covered up.
    SINGLEBACK: ((-4, 0), [("WR", (-0.6, -18.4)), ("WR", (-1.2, 18.4)), ("RB", (-6.5, 0.4)), ("TE", (-0.6, 3.4))]),
    HEAVY: ((-4, 0), [("TE", (-0.6, -3.4)), ("WR", (-1.2, 18.4)), ("RB", (-6.5, 0.4)), ("TE", (-0.6, 3.4))]),
    GUN_SPREAD: ((-7, 0), [("WR", (-0.6, -18.4)), ("WR", (-0.6, 18.4)), ("RB", (-7, 2.5)), ("SL", (-1.2, -8.3))]),
    GUN_TRIPS: ((-7, 0), [("SL", (-0.6, 11.2)), ("WR", (-0.6, 19.9)), ("RB", (-7, -2.5)), ("HB", (-1.5, 5.4))]),
    GOAL_LINE: ((-4, 0), [("TE", (-0.6, -3.4)), ("TE", (-0.6, 3.4)), ("RB", (-6.5, 0.4)), ("FB", (-4.5, 1.8))]),
}

blk = (B, [])


def rt(*route, settle=False, bt=0.0):
    return (R, list(route), settle, bt)


def run(*route):
    return (RUN, list(route))


def lead(*route):
    return (B, list(route))


GO = rt(40, 0)

# file, name, description, formation, category, flags, qb route, four skill jobs
PLAYS = [
    # ---- I-FORM ------------------------------------------------------------
    ("iso_lead", "Iso Lead", "Fullback hits the gap left of the center and takes on the first man there. Back follows him through.",
     I_FORM, CAT_RUN, dict(is_run=True, handoff_delay=0.4), [],
     [blk, blk, run(3.5, -1.3, 9, -1.5, 16, -1.5), lead(3.5, -2.9, 8, -2.9)]),
    ("fb_dive", "FB Dive", "Quick handoff to the fullback straight up the middle. Back fakes the sweep to the left.",
     I_FORM, CAT_RUN, dict(is_run=True, handoff_delay=0.3), [],
     [blk, blk, rt(1, -7, 4, -14), run(2.5, -1.4, 9, -1.6)]),
    ("lead_toss", "Lead Toss", "Quick pitch to the back running wide to the right, the fullback out in front of him.",
     I_FORM, CAT_RUN, dict(is_run=True, handoff_delay=0.25), [],
     [blk, blk, run(1, 8, 5.5, 13.5, 12.5, 15.5), lead(3.5, 5, 8.5, 8)]),
    ("quick_slants", "Quick Slants", "Both wideouts cut inside. Back leaks out to the right and turns upfield. Fullback blocks, then sits down over the middle.",
     I_FORM, SHORT, {}, [-3, 0],
     [rt(4, 0, 16, 15.4), rt(4, 0, 16, -15.4), rt(1.5, 8, 5.5, 16, 10.5, 19), rt(9, -1.3, settle=True, bt=0.7)]),
    ("fb_wheel", "FB Wheel", "Fullback swings out to the right and turns up the sideline. Right wideout slants inside to clear it, left wideout curls. Back stays in to block.",
     I_FORM, SHORT, {}, [-3, 0],
     [rt(12, 0, 11, 2.2, settle=True), rt(3, 0, 10, -10), blk, rt(0.5, 7, 4.5, 13.5, 30, 13.5)]),
    ("texas", "Texas", "Both wideouts run the coverage off deep. Back starts for the left flat, then angles back inside behind the linebackers. Fullback blocks, then breaks out to the right.",
     I_FORM, SHORT, {}, [-3, 0],
     [GO, rt(12, 0, 40, -14.4), rt(3, -9.5, 5.5, -12.3, 9, -4.4), rt(8.9, 1.6, 9.4, 8.6, bt=0.6)]),
    ("pa_post", "PA Post", "Fake the dive up the middle, then a deep post and a go route behind the defenders who come up.",
     I_FORM, DEEP, dict(play_action=True, handoff_delay=0.42), [-1.5, 0],
     [GO, rt(16, 0, 40, -18.4), run(3.5, 0.2, 14, 0.2), blk]),
    ("sluggo", "Sluggo", "Slant and go on the right: sell the slant, then straight up the field. Deep in on the left, back sits down underneath it.",
     I_FORM, DEEP, {}, [-4, 0],
     [rt(13, 0, 15, 20.4), rt(3, 0, 7, -7.2, 40, -10.1), rt(2.5, -6, 6.5, -10, settle=True), blk]),
    ("flea_flicker", "Flea Flicker", "Dive to the back, who stops and pitches it back to the quarterback. Go route on the left, deep crosser from the right.",
     I_FORM, DEEP, dict(flea_flicker=True, handoff_delay=0.42, flick_delay=0.5, cpu_weight=0.4), [-3, 0],
     [GO, rt(13, 0, 27, -25.3), run(3.3, 0, 5, -5.2, 8.5, -11), blk]),

    # ---- SINGLEBACK --------------------------------------------------------
    ("off_tackle", "Off Tackle", "Handoff round the outside of the tight end on the right. Everyone blocks.",
     SINGLEBACK, CAT_RUN, dict(is_run=True, handoff_delay=0.4), [],
     [blk, blk, run(2.8, 1.5, 5.5, 4.6, 10, 6.5), blk]),
    ("counter", "Counter", "Back steps right, then cuts back to the left side away from the tight end.",
     SINGLEBACK, CAT_RUN, dict(is_run=True, handoff_delay=0.6), [],
     [blk, blk, run(0.3, 2.3, 2.5, -5, 7, -11.8), blk]),
    ("draw", "Draw", "Looks like a pass: wideouts run deep, the quarterback drops, then a delayed handoff up the middle.",
     SINGLEBACK, CAT_RUN, dict(is_run=True), [-1.5, 0],
     [GO, GO, run(0.2, 0, 8, -0.6, 15, -0.6), blk]),
    ("curl_flat", "Curl Flat", "Wideouts stop and turn back at twelve yards. Back swings out to the right and turns upfield.",
     SINGLEBACK, SHORT, {}, [-3, 0],
     [rt(13, 0, 11, 2.2, settle=True), rt(13, 0, 11, -2.2, settle=True), rt(2.5, 10.8, 5.5, 18, 10.5, 20.9), blk]),
    ("mesh", "Mesh", "Wideouts cross over the middle 8 yards deep. Back angles in underneath. Tight end blocks, then slips to the right flat.",
     SINGLEBACK, SHORT, {}, [-3, 0],
     [rt(8, 0, 12, 31), rt(8, 0, 13.5, -31), rt(2.5, -8, 6.5, -11, 10.5, -4.5), rt(1.5, 2, 2.5, 10, bt=0.8)]),
    ("hb_screen", "HB Screen", "Wideouts clear out deep. Dump it to the back behind the line on the left.",
     SINGLEBACK, SHORT, {}, [-4, 0],
     [GO, rt(12, 0, 40, -11.6), rt(2, -8.7, 2, -14.5, settle=True), blk]),
    ("bootleg", "Bootleg", "Fake the sweep left and roll out right. Tight end in the flat in front of the quarterback, right wideout comes back to him, left wideout drags across.",
     SINGLEBACK, SHORT, dict(play_action=True, handoff_delay=0.6), [-2.5, 5],
     [rt(2, 0, 3, 28.2), rt(9, 0, 8, 4, settle=True), run(1.5, -2.4, 3, -8.7, 8, -14.5), rt(2, 0, 3, 9)]),
    ("crossfire", "Crossfire", "Two crossers at different depths. Back wheels up the right sideline.",
     SINGLEBACK, DEEP, {}, [-4, 0],
     [rt(7, 0, 13, 34), rt(3, 0, 7, -34), rt(2.5, 13.7, 7.5, 20.9, 41.5, 20.9), blk]),
    ("flood", "Flood", "Three levels on the right side: wideout deep, tight end to the sideline at fourteen yards, back in the flat. Left wideout breaks in behind them.",
     SINGLEBACK, DEEP, {}, [-4, 0],
     [rt(12, 0, 13, 14), GO, rt(2.5, 10.8, 5.5, 18), rt(8, 0, 14, 10)]),

    # ---- HEAVY -------------------------------------------------------------
    ("double_tight_power", "Double Tight Power", "A tight end on each side of the line. Handoff off the right guard, everyone blocks.",
     HEAVY, CAT_RUN, dict(is_run=True, handoff_delay=0.4), [],
     [blk, blk, run(2.8, 0.5, 5.5, 2.2, 10, 3), blk]),
    ("hb_dive", "HB Dive", "Quick handoff straight up the middle behind two tight ends.",
     HEAVY, CAT_RUN, dict(is_run=True, handoff_delay=0.35), [],
     [blk, blk, run(3.5, -0.2, 9, -0.2), blk]),
    ("power_sweep", "Power Sweep", "Handoff to the back running wide to the right behind the tight end and the wideout. Everyone blocks.",
     HEAVY, CAT_RUN, dict(is_run=True, handoff_delay=0.45), [],
     [blk, blk, run(1, 6, 6, 14, 13, 16), blk]),
    ("te_delay", "TE Delay", "Wideout runs the coverage off deep, back to the right flat. Left tight end blocks, then slips out over the middle.",
     HEAVY, SHORT, {}, [-3, 0],
     [rt(4, 0, 6, 5, settle=True, bt=0.9), GO, rt(2.5, 9, 5.5, 16), blk]),
    ("te_flat", "TE Flat", "Fake the dive. Right tight end slips into the flat behind it, wideout clears out deep, left tight end breaks in.",
     HEAVY, SHORT, dict(play_action=True, handoff_delay=0.35), [-1.5, 2],
     [rt(8, 0, 9, 10), GO, run(3.5, -0.4, 6, -4.8), rt(2, 0, 3, 9)]),
    ("te_corner", "TE Corner", "Wideout slants inside, right tight end breaks to the corner behind him. Left tight end drags across, back in the right flat.",
     HEAVY, SHORT, {}, [-3, 0],
     [rt(2, 0, 3.5, 12), rt(3, 0, 9, -9), rt(2.5, 10, 4.5, 17), rt(8, 0, 14, 9)]),
    ("te_cross", "TE Cross", "Right tight end crosses the field twelve yards deep, wideout runs the post over him. Left tight end in the left flat, back sits down on the right.",
     HEAVY, SHORT, {}, [-4, 0],
     [rt(2, -1.5, 3, -9), rt(12, 0, 40, -14), rt(2.5, 8, 5, 13, settle=True), rt(6, 0, 13, -20)]),
    ("te_seam", "TE Seam", "All four out. Right tight end straight up the seam, left tight end to the corner, wideout curls, back in the left flat.",
     HEAVY, DEEP, {}, [-4, 0],
     [rt(10, 0, 26, -10), rt(14, 0, 13, -2.2, settle=True), rt(2.5, -9, 5.5, -16), rt(12, 0, 40, -2)]),
    ("max_protect", "Max Protect", "Both tight ends stay in to block. Wideout alone runs the deep post. Back blocks, then sits down on the left.",
     HEAVY, DEEP, {}, [-4.5, 0],
     [blk, rt(14, 0, 40, -15), rt(2, -7, 5, -12, settle=True, bt=1.2), blk]),

    # ---- GUN SPREAD --------------------------------------------------------
    ("gun_draw", "Gun Draw", "Shotgun. Everyone runs deep, the quarterback waits, then hands it to the back up the middle.",
     GUN_SPREAD, CAT_RUN, dict(is_run=True, handoff_delay=0.55), [],
     [GO, GO, run(0.8, -2.2, 9, -3, 16, -3), rt(40, 1.4)]),
    ("gun_counter", "Gun Counter", "Shotgun. Back steps right, then crosses in front of the quarterback, takes the ball and cuts up the left side.",
     GUN_SPREAD, CAT_RUN, dict(is_run=True, handoff_delay=0.6), [],
     [blk, blk, run(0.3, 1.8, 1.5, -4, 7, -8.5, 14, -10.5), blk]),
    ("gun_stick", "Gun Stick", "Shotgun. Slot sits down six yards deep, left wideout fades behind him. Right wideout slants, back swings to the right flat.",
     GUN_SPREAD, SHORT, {}, [-0.5, 0],
     [rt(10, 0, 24, -2.5), rt(3, 0, 10, -10.1), rt(1, 6.6, 4, 15.2), rt(6.6, 0, 6.1, 1.5, settle=True)]),
    ("drive", "Drive", "Shotgun. Left wideout drags shallow across the field, right wideout breaks in behind him ten yards deep. Slot sits down, back in the right flat.",
     GUN_SPREAD, SHORT, {}, [-0.5, 0],
     [rt(2, 0, 4, 31.1), rt(10, 0, 11, -22.4), rt(1, 6.6, 4, 15.2), rt(6.7, 0, 6.2, -2, settle=True)]),
    ("gun_outs", "Gun Outs", "Shotgun. Both wideouts break to the sideline six yards deep, slot up the seam to hold the safety. Back stays in to block.",
     GUN_SPREAD, SHORT, {}, [-0.5, 0],
     [rt(6, 0, 7, -5.5), rt(6, 0, 7, 5.5), blk, rt(12, 0, 40, 3)]),
    ("gun_verts", "Gun Verts", "Shotgun. Both wideouts straight up the field, slot up the seam between the safeties. Back in the right flat.",
     GUN_SPREAD, DEEP, {}, [-1, 0],
     [GO, GO, rt(1, 6.6, 4, 15.2), rt(12, 0, 40, 5.5)]),
    ("dagger", "Dagger", "Shotgun. Slot runs the seam to pull the safety away, left wideout breaks in behind it thirteen yards deep. Right wideout comes back, back stays in to block.",
     GUN_SPREAD, DEEP, {}, [-1, 0],
     [rt(13, 0, 14, 20.4), rt(14, 0, 12.5, 2.5, settle=True), blk, rt(40, 1.4)]),
    ("gun_flea_flicker", "Gun Flea Flicker", "Shotgun. Toss to the back swinging right, who throws it straight back to the quarterback. Go route on the left, deep crosser from the right, slot sits down underneath.",
     GUN_SPREAD, DEEP, dict(flea_flicker=True, handoff_delay=0.25, flick_delay=0.35, cpu_weight=0.4), [-1, 0],
     [GO, rt(14, 0, 26, -28.2), run(1, 5.8, 3, 10.9, 6, 13.8), rt(6.6, 0, 6.1, 2, settle=True)]),
    ("hail_mary", "Hail Mary", "Everyone goes deep. Throw it up and pray.",
     GUN_SPREAD, DEEP, dict(heave_only=True), [-2, 0],
     [rt(20, 0, 45, 11), rt(20, 0, 45, -11), rt(8, -1.5, 50, -1.5), rt(13, 0, 45, 6)]),

    # ---- GUN TRIPS ---------------------------------------------------------
    ("gun_stretch", "Gun Stretch", "Shotgun, three on the right. Back crosses in front of the quarterback, takes the ball and runs wide to the right behind them.",
     GUN_TRIPS, CAT_RUN, dict(is_run=True, handoff_delay=0.4), [],
     [blk, blk, run(0.8, 2.5, 3, 8.7, 7, 13, 14, 15.9), blk]),
    ("gun_dive", "Gun Dive", "Shotgun, three on the right. Quick handoff to the back straight ahead, left of the center.",
     GUN_TRIPS, CAT_RUN, dict(is_run=True, handoff_delay=0.35), [],
     [blk, blk, run(1.5, 1.2, 8, 1.6, 16, 1.6), blk]),
    ("bubble_screen", "Bubble Screen", "Shotgun, three on the right. Slot steps back and out for a quick throw behind the line, the two men beside him block. Back swings left.",
     GUN_TRIPS, SHORT, {}, [-0.3, 0],
     [rt(-1.2, 3.5, settle=True), blk, rt(1, -6.6, 4, -15.2), blk]),
    ("smash", "Smash", "Shotgun, three on the right. Wideout stops at six yards, slot breaks to the corner over the top of him. Inside man hooks up in the middle, back in the left flat.",
     GUN_TRIPS, SHORT, {}, [-0.5, 0],
     [rt(7, 0, 15, 9.5), rt(6, 0, 5.5, -1.5, settle=True), rt(1, -6.6, 4, -15.2), rt(7.5, 0, 7, -2, settle=True)]),
    ("gun_levels", "Gun Levels", "Shotgun, three on the right. Wideout breaks in at five yards, slot at twelve. Inside man in the right flat, back swings left.",
     GUN_TRIPS, SHORT, {}, [-0.5, 0],
     [rt(12, 0, 13, -18), rt(5, 0, 6, -22), rt(1, -6.6, 4, -15.2), rt(2, 3, 3, 13)]),
    ("gun_boot", "Gun Boot", "Shotgun, three on the right. Fake the stretch right and roll out left. Inside man drags across with the quarterback, slot crosses deeper behind him, wideout goes deep.",
     GUN_TRIPS, SHORT, dict(play_action=True, handoff_delay=0.4), [-1, -6],
     [rt(10, 0, 14, -24), GO, run(0.8, 2.5, 3, 8.7, 6, 12), rt(2.5, 0, 4, -18)]),
    ("gun_trips_flood", "Trips Flood", "Shotgun, three on the right. Wideout straight up the field, slot out at twelve yards, inside man to the flat. Back stays in to block.",
     GUN_TRIPS, DEEP, {}, [-1, 0],
     [rt(12, 0, 13.5, 11.6), GO, blk, rt(2, 2.9, 3, 13)]),
    ("scissors", "Scissors", "Shotgun, three on the right. Wideout runs the post, slot crosses under him to the corner. Inside man drags left, back swings left.",
     GUN_TRIPS, DEEP, {}, [-1.5, 0],
     [rt(10, 0, 24, 11), rt(12, 0, 40, -14), rt(1, -6.6, 4, -15.2), rt(3, 0, 4, -10)]),
    ("da_bomb", "Da Bomb", "Shotgun, three on the right, everyone deep. Wideout straight up the field, slot on the deep post, inside man jabs left and runs a second post under it. Back stays in to block.",
     GUN_TRIPS, DEEP, dict(shot_play=True), [-3, 0],
     [rt(4.5, 0, 40, -20), GO, blk, rt(0.3, -1.8, 3.5, -1.8, 30, -20)]),

    # ---- GOAL LINE ---------------------------------------------------------
    ("gl_dive", "Goal Line Dive", "Two tight ends, everyone blocks down. Quick handoff straight ahead behind the fullback.",
     GOAL_LINE, CAT_RUN, dict(is_run=True, handoff_delay=0.3), [],
     [blk, blk, run(3.5, 0, 9, 0), lead(3.5, -0.9, 8, -0.9)]),
    ("gl_power", "Goal Line Power", "Two tight ends. Fullback leads round the right guard, back follows him in.",
     GOAL_LINE, CAT_RUN, dict(is_run=True, handoff_delay=0.4), [],
     [blk, blk, run(2.8, 0.9, 5.5, 3.6, 10, 4.6), lead(3.5, 1.7, 8, 2.6)]),
    ("gl_toss", "Goal Line Toss", "Two tight ends block down. Quick pitch to the back running for the right corner behind the fullback.",
     GOAL_LINE, CAT_RUN, dict(is_run=True, handoff_delay=0.25), [],
     [blk, blk, run(1, 7.5, 5, 14, 10, 16.5), lead(3.5, 4.5, 8.5, 7)]),
    ("gl_fb_dive", "Goal Line Wedge", "Quick handoff to the fullback left of the center. Back fakes the toss to the right.",
     GOAL_LINE, CAT_RUN, dict(is_run=True, handoff_delay=0.25), [],
     [blk, blk, rt(1, 7.5, 5, 14), run(2.5, -2.6, 9, -2.8)]),
    ("gl_boot", "Goal Line Boot", "Fake the dive and roll out right. Tight end in the flat in front of the quarterback, the other one crossing to the back corner.",
     GOAL_LINE, SHORT, dict(play_action=True, handoff_delay=0.35), [-2, 5.4],
     [rt(4, 0, 8, 14), rt(2, 0, 3, 12.7), run(3.5, -0.4, 6, -6.4), blk]),
    ("gl_corner", "Goal Line Corner", "Right tight end breaks to the back corner, left tight end sits down in the middle, back in the right flat.",
     GOAL_LINE, SHORT, {}, [-3, 0],
     [rt(4, 1, settle=True), rt(4, 0, 9, 8.4), rt(2, 5.9, 5, 14.6), blk]),
    ("gl_fb_flat", "Goal Line Flat", "Fullback slips straight out to the right flat. Right tight end slants inside to clear it, left tight end fades to the corner. Back stays in to block.",
     GOAL_LINE, SHORT, {}, [-2, 0],
     [rt(4, 0, 8, -7), rt(3, 0, 7, -4), blk, rt(2.5, 5, 5.5, 10)]),
    ("gl_te_pop", "Goal Line Pop", "Fake the dive. Right tight end runs straight up the middle behind the linebackers who come up, left tight end fades to the corner.",
     GOAL_LINE, SHORT, dict(play_action=True, handoff_delay=0.3), [-1, 0],
     [rt(3, 0, 6, -8), rt(5, 0, 9, -1.5), run(3.5, 0, 6, -5), blk]),
    ("gl_mesh", "Goal Line Mesh", "The tight ends cross right behind the line. Back to the left flat. Fullback blocks, then sits down in the middle.",
     GOAL_LINE, SHORT, {}, [-3, 0],
     [rt(2, 0, 3, 12), rt(3.5, 0, 4.5, -12), rt(2, -6, 5, -13), rt(9, -1.8, settle=True, bt=0.5)]),
]

# ---- Motion before the snap ------------------------------------------------
# The motion man is the receiver off the line (and not in the backfield) who
# is nearest the ball: see scripts/motion_rules.gd, and pick() below, which
# has to agree with it. I-Form and Goal Line have nobody like that.
ZIP, ACROSS, JET, ORBIT, RETURN = 1, 2, 3, 4, 5
# Where he ends up, per formation's motion man. He never moves toward the
# line, so a spot is never further up than the path that leads to it.
Z_ZIP, Z_RETURN = (-1.5, 8.5), (-1.2, 13.5)                                         # Singleback, Heavy: the flanker
# All the way across to the left slot, between the line and the quarterback
# under center: 27 yards, three and a half seconds of the play clock.
Z_ACROSS = (-2.4, -9)
SL_ACROSS, SL_ORBIT, SL_JET, SL_RETURN = (-2.2, 8.3), (-7, -2.5), (-5.5, 8.3), (-1.2, -4.5)   # Gun Spread: the slot
W_ACROSS, W_ORBIT, W_JET, W_RETURN = (-2.2, -6), (-7, 2.5), (-5.5, -6), (-1.5, 9)   # Gun Trips: the wing
# A jet crosses in front of the quarterback at the depth of the spot it ends
# on: a yard and a half in front of him for a handoff (shotgun: 5.5 back,
# under center: 2.4), further up when the ball does not go to the jet man.
Z_JET = (-2.4, -9)        # Under center: the flanker, all the way across
W_JET_HIGH = (-4.6, -6)   # Gun Trips: in front of the back who fakes the other way


def mo(kind, to, job=None, handoff=False, late=None):
    """`late` (JET): his job once he has gone past the quarterback or has set,
    from the spot he sets on. Without one he blocks."""
    return (kind, to, job, handoff, late)


# file -> motion, target spot, his job from there (routes relative to the new
# spot; JET: relative to the point in front of the quarterback, for a snap
# while he runs, and `late` for one after that). RETURN keeps the job
# the play draws. A play that is not here has no motion.
MOTIONS = {
    # Singleback
    # A flanker who comes in tight to block has a path to the point of the run
    # and takes the first free man there (a crack block). Just standing in
    # tight he brings his own man to the run and helps nobody.
    "off_tackle": mo(ZIP, Z_ZIP, lead(3, -2, 5.5, -3)),
    "counter": mo(RETURN, Z_RETURN),
    # The draw wants the defense spread out: with him across the formation it
    # lost three yards a carry, so he comes back to where he was.
    "draw": mo(RETURN, Z_RETURN),
    "curl_flat": mo(ZIP, Z_ZIP, rt(12, 0, 10.5, -2, settle=True)),
    "mesh": mo(ZIP, Z_ZIP, rt(8, 0, 12.5, -26)),
    "hb_screen": mo(RETURN, Z_RETURN),
    "bootleg": mo(RETURN, Z_RETURN),
    "crossfire": mo(ZIP, Z_ZIP, rt(3, 0, 6, -24)),
    # The deep level of the flood comes from the far slot: a post to the middle.
    "flood": mo(ACROSS, Z_ACROSS, rt(13, 0, 41, 9)),
    # Heavy
    "double_tight_power": mo(ZIP, Z_ZIP, lead(2.5, -4.5, 5, -5.5)),
    # A jet under center: the flanker takes the ball in front of the
    # quarterback at a sprint and cuts up between the left guard and the
    # tight end, where the line opens a hole for him. Round the end nobody
    # blocks the corner (2 yards a carry, against nearly 5 through the hole).
    "hb_dive": mo(JET, Z_JET, run(1, -2.4, 4, -2.8, 12, -3), handoff=True),
    "power_sweep": mo(ZIP, Z_ZIP, lead(2.5, -2.5, 5, -1.5)),
    # Runs the coverage off on the left: the right is empty for the back's flat.
    "te_delay": mo(ACROSS, Z_ACROSS, rt(41, 0)),
    "te_flat": mo(RETURN, Z_RETURN),
    "te_corner": mo(ZIP, Z_ZIP, rt(5, 0, 4.5, 1, settle=True)),
    "te_cross": mo(ZIP, Z_ZIP, rt(12, 0, 40, -8)),
    # Curls between the left tight end's corner route and the back's flat.
    "te_seam": mo(ACROSS, Z_ACROSS, rt(13, 0, 11.5, 1.5, settle=True)),
    "max_protect": mo(RETURN, Z_RETURN),
    # Gun Spread
    "gun_draw": mo(JET, SL_JET, rt(0, 8, 3, 15, 12, 19)),
    # The jet sweep: it goes to the side with a wideout to block the corner,
    # and the back, who steps that way anyway, leads it.
    "gun_counter": mo(JET, SL_JET, run(0.5, 5, 5.5, 9, 13, 11), handoff=True),
    "gun_stick": mo(ACROSS, SL_ACROSS, rt(7.6, 0, 7.1, -1.5, settle=True)),
    # Into the backfield and out to the left flat the drag has just left.
    "drive": mo(ORBIT, SL_ORBIT, rt(1, -6.6, 4, -15.2)),
    "gun_outs": mo(ACROSS, SL_ACROSS, rt(13, 0, 41, -3)),
    # Four verticals want two men on each side of the field.
    "gun_verts": mo(RETURN, SL_RETURN),
    "dagger": mo(RETURN, SL_RETURN),
    "gun_flea_flicker": mo(RETURN, SL_RETURN),
    # Gun Trips
    "gun_stretch": mo(ORBIT, W_ORBIT, lead(3.5, 5.5, 8, 9.5)),
    # Not a jet sweep away from the three receivers: nobody is out there to
    # block for it. The wing comes into the backfield and leads the dive.
    "gun_dive": mo(ORBIT, W_ORBIT, lead(6, -3, 11, -3.4)),
    "bubble_screen": mo(RETURN, W_RETURN),
    "smash": mo(ACROSS, W_ACROSS, rt(8.2, 0, 7.7, 2, settle=True)),
    # A corner route on the left, over the back's swing: the two in-breakers
    # come across underneath it.
    "gun_levels": mo(ACROSS, W_ACROSS, rt(10, 0, 18, -9)),
    # A jet on a pass: he is in the left flat at a sprint as the quarterback
    # rolls out that way. Snapped late he runs the same flat from a standstill.
    "gun_boot": mo(JET, W_JET_HIGH, rt(1.6, -6, 6.6, -15), late=rt(5.5, -2, 7.5, -10)),
    # Still the flat level of the flood, swinging out of the backfield.
    "gun_trips_flood": mo(ORBIT, W_ORBIT, rt(1, 6.6, 4, 15.2)),
    "scissors": mo(ORBIT, W_ORBIT, rt(1, 6.6, 4, 15.2)),
    "da_bomb": mo(RETURN, W_RETURN),
}


def pick(skill):
    """The motion man's place among the four skill players, or -1."""
    best = -1
    for i, (_label, (x, y)) in enumerate(skill):
        if x > -1.0 or x < -2.5:
            continue
        if best < 0 or abs(y) < abs(skill[best][1][1]):
            best = i
    return best


REMOVED = ["deep_bomb", "end_around", "wildcat_jet", "wildcat_pass", "crack_toss", "fb_belly", "hb_slot_out",
           "mismatch_go", "gun_empty_slants", "gl_fade", "gl_empty", "gl_rub", "gl_pa",
           "hb_toss"]


def num(value):
    return ("%.2f" % value).rstrip("0").rstrip(".") if value != int(value) else str(int(value))


def vec(point):
    return "Vector2(%s, %s)" % (num(point[0]), num(point[1]))


def sub(ident, label, job, start, route=(), settle=False, bt=0.0):
    lines = ['[sub_resource type="Resource" id="%s"]' % ident, 'script = ExtResource("2_assign")', 'label = "%s"' % label]
    if job != R:
        lines.append("job = %d" % job)
    lines.append("start = %s" % vec(start))
    if route:
        lines.append("route = PackedVector2Array(%s)" % ", ".join(num(v) for v in route))
    if settle:
        lines.append("settle = true")
    if bt:
        lines.append("block_time = %s" % num(bt))
    return "\n".join(lines) + "\n"


def write_play(spec):
    file, name, desc, formation, category, flags, qb_route, jobs = spec
    qb_start, skill = FORMATIONS[formation]
    out = ['[gd_resource type="Resource" script_class="OffensePlay" format=3]\n',
           '[ext_resource type="Script" path="res://scripts/data/offense_play.gd" id="1_play"]\n'
           '[ext_resource type="Script" path="res://scripts/data/offense_assignment.gd" id="2_assign"]\n']
    ids = ["qb", "c", "lg", "rg", "x", "z", "back", "y"]
    out.append(sub("qb", "QB", Q, qb_start, qb_route))
    for i, (label, start) in enumerate(LINE):
        out.append(sub(ids[1 + i], label, B, start))
    for i, ((label, start), job) in enumerate(zip(skill, jobs)):
        kind, route = job[0], job[1]
        settle = job[2] if len(job) > 2 else False
        bt = job[3] if len(job) > 3 else 0.0
        out.append(sub(ids[4 + i], label, kind, start, route, settle, bt))
    motion = MOTIONS.get(file)
    if motion:
        kind, to, job, handoff, late = motion
        man = pick(skill)
        assert man >= 0, "%s: nobody may go in motion" % file
        assert (job is None) == (kind == RETURN), file
        assert late is None or kind == JET, file
        if job:
            # A jet man's job starts at the point in front of the quarterback.
            start = (to[0], 0) if kind == JET else to
            settle = job[2] if len(job) > 2 else False
            bt = job[3] if len(job) > 3 else 0.0
            out.append(sub("motion", skill[man][0], job[0], start, job[1], settle, bt))
        if late:
            settle = late[2] if len(late) > 2 else False
            bt = late[3] if len(late) > 3 else 0.0
            out.append(sub("motion_set", skill[man][0], late[0], to, late[1], settle, bt))
    res = ["[resource]", 'script = ExtResource("1_play")', 'play_name = "%s"' % name, 'description = "%s"' % desc]
    if category != SHORT:
        res.append("category = %d" % category)
    if formation != 0:
        res.append("group = %d" % formation)
    order = ["heave_only", "shot_play", "is_run", "handoff_delay", "play_action", "flea_flicker", "flick_delay", "cpu_weight"]
    for key in order:
        if key in flags:
            value = flags[key]
            res.append("%s = %s" % (key, "true" if value is True else num(value)))
    if formation == GOAL_LINE:
        res.append("goal_line = true")
    res.append('assignments = Array[ExtResource("2_assign")]([%s])' % ", ".join('SubResource("%s")' % i for i in ids))
    if motion:
        res.append("motion = %d" % motion[0])
        res.append("motion_to = %s" % vec(motion[1]))
        if motion[2]:
            res.append('motion_assignment = SubResource("motion")')
        if motion[4]:
            res.append('motion_set_assignment = SubResource("motion_set")')
        if motion[3]:
            res.append("motion_handoff = true")
    out.append("\n".join(res) + "\n")
    with open("resources/plays/offense/%s.tres" % file, "w", newline="\n") as handle:
        handle.write("\n".join(out))


assert len(PLAYS) == 54, len(PLAYS)
assert len({p[0] for p in PLAYS}) == 54
assert set(MOTIONS) <= {p[0] for p in PLAYS}, set(MOTIONS) - {p[0] for p in PLAYS}
for formation in range(6):
    assert sum(1 for p in PLAYS if p[3] == formation) == 9, formation
for play in PLAYS:
    assert len(play[7]) == 4, play[0]
    write_play(play)
for name in REMOVED:
    path = "resources/plays/offense/%s.tres" % name
    assert name not in {p[0] for p in PLAYS}
    if os.path.exists(path):
        os.remove(path)
        print("removed", path)

book = ['[gd_resource type="Resource" script_class="OffensePlaybook" format=3]\n',
        '[ext_resource type="Script" path="res://scripts/data/offense_playbook.gd" id="1_book"]',
        '[ext_resource type="Script" path="res://scripts/data/offense_play.gd" id="2_play"]']
refs = []
for i, play in enumerate(PLAYS):
    ident = "%d_%s" % (i + 3, play[0])
    book.append('[ext_resource type="Resource" path="res://resources/plays/offense/%s.tres" id="%s"]' % (play[0], ident))
    refs.append('ExtResource("%s")' % ident)
book.append("\n[resource]")
book.append('script = ExtResource("1_book")')
book.append('plays = Array[ExtResource("2_play")]([%s])' % ", ".join(refs))
with open("resources/playbook_offense.tres", "w", newline="\n") as handle:
    handle.write("\n".join(book) + "\n")
print("wrote", len(PLAYS), "plays")
