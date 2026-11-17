# Play audit: offense (54 plays) and defense (36 plays)

Audit of both playbooks against the four rules, with the fixes made, Da Bomb added, and a check that keeps the problems from coming back.

## Summary

| Rule | Found | Now |
|---|---|---|
| 1. Offense must not give itself away | 50 different line-ups for 54 plays; no line-up had 4 plays; the quarterback stood a yard deeper on passes than on runs | 6 formations with 9 plays each, every one with runs and passes; the tabs of the play-select screen are the formations |
| 2. No mirrors or near-duplicates | 1 exact mirror pair and 8 groups of plays that were one idea drawn again; 4 near-duplicate pairs on defense | 14 offensive plays and 1 defensive play replaced, 3 defensive plays redrawn; none within the duplicate measure |
| Da Bomb | Not in the book | In Gun Trips, in place of Deep Bomb; the CPU calls it on under 1% of ordinary first downs and on 6 to 15% of calls in long yardage, with the half running out or two scores behind |
| 3. Defense lines up on the offense | Partly true: man defenders followed their man, every zone defender, spy and blitzer stood on a fixed spot | Every defender has an alignment rule; zone corners, walked-out linebackers and safeties move with the formation |
| 4. Balance | See section 5 | Every open-field play has a defense that holds it to 2 yards or less and one it gains 8 or more against, and the other way round for every defense |

Three things did not come out as asked or need a decision from you:

1. **Da Bomb does not clearly beat single-high man coverage.** In the simulation it beats the two-deep coverages (the post splits the safeties) and loses to Cover 3, Prevent and the quick blitzes, as wanted. Against Man Cover 1 it gains 1 to 6 yards a snap depending on the run. Section 5 has the numbers and the reason.
2. **`situation_check.gd` fails on two points.** One fails on the last commit too. The other is new: the CPU defense now answers a last-play heave with a blitz, so those throws are aimed 22 yards downfield where the test wants 25. Section 8.
3. **Three plays are weak or misnamed and were left alone:** Run Stuff is the worst open-field defense against the run, Overload gives up 15 yards a pass (it did before), Goal Line Boot is sacked on 39% of snaps. Section 6.

### Decisions made without asking

- **54 and 36 plays kept**, not the "about 36 and 24" of the brief: you confirmed this, and that the tabs become formations.
- **No motion and no quarterback run plays.** The game has neither, and both would be new mechanics. Da Bomb's green arrow is a jab step: the inside man's first two yards go left.
- **Wildcat Jet, Wildcat Pass and End Around were dropped**, not rebuilt: each needs a line-up of its own, which is exactly what Rule 1 forbids. The two flea flickers stay as the trick plays.
- **Da Bomb's eighth player** (the diagram has seven) is the back beside the quarterback, in pass protection.
- **The CPU's fit values for the defenses were measured again** from the matrix in section 6 and written into the play files, since the alignment change moves what every defense is good at.
- **Goal Line Press was replaced** (by Goal Line TE Double) because it was Run Stuff again; the other near-duplicates on defense were redrawn, not replaced.
- **Offensive plays are generated** from `tools/gen_offense_plays.py`. Editing a `.tres` by hand still works, and the check catches a play that leaves its formation.

## 1. What was there (inventory before any change)

Where the plays live and what uses them:

| What | Where |
|---|---|
| A play | One `.tres` per play in `resources/plays/offense/` and `resources/plays/defense/` (`OffensePlay`, `DefensePlay`, one assignment per player) |
| The playbooks | `resources/playbook_offense.tres` and `resources/playbook_defense.tres` list the play files; `scenes/main.tscn` loads both |
| Line-up | `PlayController.line_up` in `scripts/play_controller.gd` puts every player on his spot |
| Play select | `scripts/state/play_select_state.gd` and `scripts/hud.gd`: one tab per `group`, nine cards a tab |
| Play diagrams | `scripts/play_diagram.gd` draws the card from the play file |
| CPU play calling | `scripts/play_caller.gd` (by `category`, `cpu_weight`, `goal_line`, `heave_only`, and the defense's `run_fit / short_fit / deep_fit`) |
| Defense's memory | `scripts/scout.gd` remembers play resources during a game; nothing is saved to disk |
| Tests that name plays | `tests/coverage_check.gd` ("curl flat", "quick slants", "gun verts"); the others take plays by flag or by position in the book |

The game is 8-on-8: a quarterback, three linemen (center and two guards) and four skill players a side. There is no pre-snap motion. A play can be flipped left to right on the play-select screen, and the CPU flips its own plays.

All coordinates below are in yards: the first number is past the line of scrimmage (negative is the backfield), the second to the offense's right of the ball.

### Offense before: 54 plays

| Play | File | Tab | Type | Skill players (x past the line, y right of the ball) | What it does |
|---|---|---|---|---|---|
| HB Dive | hb_dive | RUN | run | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 17.0), RB (-6.5, 0.6), TE (-0.6, 3.4) | Quick handoff straight up the middle. Tight end on the right. |
| Power Sweep | power_sweep | RUN | run | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 11.2), RB (-6.0, -2.0), TE (-0.6, 3.4) | Handoff to the back running wide behind the tight end. Everyone blocks. |
| Counter | counter | RUN | run | QB (-4.0, 0.0), WR (-0.6, -11.2), WR (-0.6, 17.0), RB (-6.0, 2.0), TE (-0.6, -3.4) | Back steps right, then cuts back to the left side behind the tight end. |
| Quick Slants | quick_slants | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, -3.4) | Both wideouts cut inside. Back leaks out and turns upfield. Tight end blocks, then sits down over the middle. |
| Curl Flat | curl_flat | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, -3.4) | Wideouts stop and turn back at twelve yards. Back swings out and turns upfield. |
| HB Screen | hb_screen | SHORT PASS | screen | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), RB (-5.0, -3.0), TE (-0.6, -3.4) | Wideouts clear out deep. Dump it to the back behind the line. |
| Crossfire | crossfire | DEEP PASS | deep pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, 3.4) | Two crossers at different depths. Back wheels up the sideline. |
| Flood | flood | DEEP PASS | deep pass | QB (-5.0, 0.0), WR (-0.6, -9.8), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, -3.4) | Three levels on the right side: deep, middle and flat. Tight end blocks, then leaks out to the left. |
| Deep Bomb | deep_bomb | DEEP PASS | deep pass | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), SL (-0.6, 8.3), FB (-5.5, 2.5) | Go route and a deep post. Slot crosses underneath. |
| Off Tackle | off_tackle | RUN | run | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 5.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Handoff through the gap outside the right guard. The tight end and the tight wideout seal the edge. |
| HB Toss | hb_toss | RUN | run | QB (-4.0, 0.0), WR (-0.6, -11.2), WR (-0.6, 17.0), RB (-6.0, -2.5), FB (-4.5, -2.0) | Quick pitch to the back, already running wide to the left. Fullback leads him round the end. |
| Draw | draw | RUN | run | QB (-4.5, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.5, 0.6), TE (-0.6, 3.4) | Looks like a pass: wideouts run deep, then a delayed handoff up the middle. |
| End Around | end_around | RUN | run | QB (-4.0, 0.0), WR (-3.5, -4.0), WR (-0.6, 15.6), RB (-5.0, 3.0), TE (-0.6, 3.4) | Left wideout takes the ball behind the quarterback and runs around the right end. Back leads the way. |
| PA Post | pa_post | DEEP PASS | play-action | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.6), FB (-4.5, 2.0) | Fake the dive up the middle, then a deep post and a go route behind the defenders who come up. |
| Bootleg | bootleg | SHORT PASS | play-action | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 18.4), RB (-5.5, 2.0), TE (-0.6, -3.4) | Fake the sweep left and roll out right. Out route and a drag come with the quarterback. |
| Mesh | mesh | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 15.6), RB (-5.0, 3.0), TE (-0.6, -3.4) | Wideouts cross over the middle 8 yards deep. Back angles in underneath. Tight end blocks, then slips to the left flat. |
| Smash | smash | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-1.2, 9.8), WR (-0.6, 19.9), RB (-5.0, -3.0), TE (-0.6, 3.4) | Hitch outside with a corner route over the top of it. Tight end hooks up in the middle, back in the far flat. |
| Sluggo | sluggo | DEEP PASS | deep pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, -3.0), TE (-0.6, 3.4) | Slant and go on the right: sell the slant, then straight up the field. Deep in on the left. |
| Gun Verts | gun_verts | SHOTGUN | deep pass | QB (-7.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), SL (-0.6, 6.9), FB (-7.0, -2.5) | Shotgun. Both wideouts straight up the field, slot up the seam between the safeties. |
| Gun Stick | gun_stick | SHOTGUN | short pass | QB (-7.0, 0.0), SL (-0.6, 8.3), WR (-0.6, 18.4), RB (-7.0, 2.5), TE (-0.6, -3.4) | Shotgun. Slot sits down six yards deep, wideout fades behind him, back swings to the flat. Tight end breaks out on the other side. |
| Gun Stretch | gun_stretch | SHOTGUN | run | QB (-7.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 9.8), RB (-7.0, -2.5), TE (-0.6, 3.4) | Shotgun. Back crosses in front of the quarterback, takes the ball and runs wide to the right. |
| Goal Line Fade | gl_fade | GOAL LINE | short pass | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 15.6), RB (-6.5, 0.6), TE (-0.6, -3.4) | Both wideouts fade to the back corners. Back slips out to the right flat. Tight end blocks, then sits down in the middle. |
| Goal Line Rub | gl_rub | GOAL LINE | short pass | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 11.2), SL (-1.5, 7.6), TE (-0.6, -3.4) | Two stacked on the right: the outside man slants in, the inside man breaks to the flat under him. Tight end drags across, left wideout fades to the corner. |
| Goal Line Corner | gl_corner | GOAL LINE | short pass | QB (-5.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-5.5, -2.5) | Right tight end breaks to the back corner, left tight end sits down in the middle, back in the flat. |
| Goal Line Dive | gl_dive | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-4.5, 1.8) | Two tight ends, everyone blocks down. Quick handoff straight ahead behind the fullback. |
| Goal Line Power | gl_power | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 2.0) | Two tight ends. Fullback leads off the right guard, back follows him in. |
| Goal Line PA | gl_pa | GOAL LINE | play-action | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-4.5, 2.0) | Fake the goal line dive. Right tight end slips to the back corner, left one drags, back leaks to the left flat. |
| Crack Toss | crack_toss | RUN | run | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 8.3), RB (-6.0, 2.5), TE (-0.6, 3.4) | Quick pitch to the back running wide to the right. Right wideout lines up tight and blocks down inside. |
| Wildcat Jet | wildcat_jet | RUN | run | QB (-0.6, 18.4), WR (-3.0, -5.4), WR (-0.6, 9.8), RB (-5.0, 0.0), TE (-0.6, 3.4) | Direct snap to the back. Left wideout comes across in front of him, takes the ball and runs around the right end. Quarterback is split wide to block. |
| HB Slot Out | hb_slot_out | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 18.4), RB (-1.5, 8.3), FB (-5.5, 2.5) | Back lines up in the right slot and breaks to the sideline four yards deep. Both wideouts slant inside. |
| Texas | texas | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, -3.0), TE (-0.6, 3.4) | Both wideouts run the coverage off deep. Back starts for the left flat, then angles back inside behind the linebackers. Tight end blocks, then breaks out to the right. |
| Drive | drive | SHORT PASS | short pass | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 17.0), RB (-1.5, -7.6), TE (-0.6, 3.4) | Left wideout drags shallow across the field, right wideout breaks in behind him ten yards deep. Back sits down from the left slot. |
| Flea Flicker | flea_flicker | DEEP PASS | trick | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.6), TE (-0.6, 3.4) | Dive to the back, who stops and pitches it back to the quarterback. Go route on the left, deep crosser from the right. |
| Mismatch Go | mismatch_go | DEEP PASS | deep pass | QB (-5.0, 0.0), SL (-1.5, -9.8), WR (-0.6, 18.4), RB (-0.6, -19.9), TE (-0.6, 3.4) | Back splits out wide left and runs straight up the field on a linebacker. Slot breaks in under him, right wideout runs the post. Tight end blocks, then leaks to the right flat. |
| Dagger | dagger | DEEP PASS | deep pass | QB (-5.0, 0.0), WR (-0.6, -18.4), SL (-0.6, -8.3), RB (-5.0, 3.0), TE (-0.6, -3.4) | Slot runs the seam to pull the safety away, left wideout breaks in behind it thirteen yards deep. Back to the right flat. |
| Gun Empty Slants | gun_empty_slants | SHOTGUN | short pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-1.5, -8.3), TE (-0.6, 3.4) | Shotgun, nobody in the backfield. Back in the left slot: three quick slants. |
| Gun Trips Flood | gun_trips_flood | SHOTGUN | deep pass | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-1.5, 5.4), FB (-7.0, -2.5) | Shotgun, three on the right. Wideout straight up the field, slot out at twelve yards, back to the flat. |
| Gun Flea Flicker | gun_flea_flicker | SHOTGUN | trick | QB (-7.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), RB (-7.0, 2.5), TE (-0.6, -3.4) | Shotgun. Toss to the back swinging right, who throws it straight back to the quarterback. Go route on the left, deep crosser from the right. |
| Gun Draw | gun_draw | SHOTGUN | run | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), FB (-7.0, -2.5) | Shotgun. Wideouts run deep, the quarterback waits, then hands it to the back up the middle behind the fullback. |
| Wildcat Pass | wildcat_pass | SHOTGUN | short pass | QB (-0.6, -18.4), SL (-1.5, 9.8), WR (-0.6, 18.4), RB (-6.0, 0.0), TE (-0.6, 3.4) | Direct snap to the back, who rolls right to throw: slot in the flat, wideout curling at ten. Quarterback is split left and runs deep. |
| Gun Levels | gun_levels | SHOTGUN | short pass | QB (-7.0, 0.0), WR (-0.6, -18.4), SL (-0.6, -8.3), RB (-7.0, 2.5), TE (-0.6, 3.4) | Shotgun. Two men break in from the left, at five yards and at twelve. Back swings to the right flat. Tight end blocks, then sits down in the middle. |
| Goal Line Toss | gl_toss | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.0, 1.5), FB (-4.5, 2.0) | Two tight ends block down. Quick pitch to the back running for the right corner behind the fullback. |
| Goal Line Empty | gl_empty | GOAL LINE | short pass | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 15.6), RB (-1.5, 7.6), TE (-0.6, -3.4) | Back lines up in the right slot and slants inside, wideout fades to the corner behind him. Tight end breaks to the left flat under the left wideout's slant. |
| Goal Line Boot | gl_boot | GOAL LINE | play-action | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-4.5, -2.0) | Fake the dive and roll out right. Tight end in the flat in front of the quarterback, the other one crossing to the back corner. |
| Hail Mary | hail_mary | DEEP PASS | deep pass | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), SL (-0.6, 8.3), TE (-0.6, -8.3) | Everyone goes deep. Throw it up and pray. |
| FB Dive | fb_dive | HEAVY | run | QB (-4.0, 0.0), WR (-0.6, -17.0), TE (-0.6, 3.4), RB (-6.5, -1.6), FB (-5.6, 1.0) | Quick handoff to the fullback straight up the middle, the right wideout in tight to block. Back fakes the sweep to the left. |
| FB Belly | fb_belly | HEAVY | run | QB (-4.0, 0.0), WR (-0.6, -5.4), WR (-0.6, 17.0), RB (-6.5, 0.6), FB (-4.5, -1.8) | Fullback takes it off the left guard, the tight wideout seals the edge. Back fakes the sweep to the right. |
| Iso Lead | iso_lead | HEAVY | run | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 17.0), RB (-6.5, -0.4), FB (-4.5, -1.8) | Fullback hits the gap left of the center and takes on the first man there. Back follows him through. |
| Lead Toss | lead_toss | HEAVY | run | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 11.2), RB (-6.0, 2.5), FB (-4.5, 2.2) | Quick pitch to the back running wide to the right, the fullback out in front of him. |
| Double Tight Power | double_tight_power | HEAVY | run | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-0.6, 17.0), RB (-6.5, 0.4), TE (-0.6, 3.4) | A tight end on each side of the line. Handoff off the right guard, everyone blocks. |
| TE Delay | te_delay | HEAVY | short pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, -3.4) | Wideouts run the coverage off deep, back to the right flat. Tight end blocks, then slips out over the middle. |
| TE Flat | te_flat | HEAVY | play-action | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.6), TE (-0.6, 3.4) | Fake the dive. Tight end slips into the right flat behind it, right wideout clears out deep, left wideout breaks in. |
| FB Wheel | fb_wheel | HEAVY | short pass | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), FB (-5.0, -3.0) | Fullback swings out to the left and turns up the sideline. Left wideout slants inside to clear it, right wideout curls. Back stays in to block. |
| TE Seam | te_seam | HEAVY | deep pass | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), RB (-5.0, -3.0), TE (-0.6, 3.4) | All four out. Tight end straight up the seam, left wideout up the sideline, right wideout curls, back in the left flat. |

### Formation groups before: 50 line-ups for 54 plays, 54 plays in a group of fewer than 4

The three linemen stood on the same spots in every play. The four skill players and the quarterback did not: wideouts at 15.6, 17, 18.4 or 19.9 yards, slots at 5.4, 6.9, 8.3, 9.8 or 11.2, the back in a dozen places, and the quarterback at 4 yards on runs and play action but at 5 on drop-back passes. So the quarterback's depth alone told the defense run or pass, and nearly every play had a line-up of its own. No group reached four plays.

| Plays | Runs | Passes | Skill players | Plays in it |
|---|---|---|---|---|
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 17.0), RB (-6.5, 0.6), TE (-0.6, 3.4) | HB Dive |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 11.2), RB (-6.0, -2.0), TE (-0.6, 3.4) | Power Sweep |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -11.2), WR (-0.6, 17.0), RB (-6.0, 2.0), TE (-0.6, -3.4) | Counter |
| 3 | 0 | 3 | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, -3.4) | Quick Slants, Curl Flat, TE Delay |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), RB (-5.0, -3.0), TE (-0.6, -3.4) | HB Screen |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, 3.4) | Crossfire |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -9.8), WR (-0.6, 18.4), RB (-5.0, 3.0), TE (-0.6, -3.4) | Flood |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), SL (-0.6, 8.3), FB (-5.5, 2.5) | Deep Bomb |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 5.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Off Tackle |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -11.2), WR (-0.6, 17.0), RB (-6.0, -2.5), FB (-4.5, -2.0) | HB Toss |
| 1 | 1 | 0 | QB (-4.5, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.5, 0.6), TE (-0.6, 3.4) | Draw |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-3.5, -4.0), WR (-0.6, 15.6), RB (-5.0, 3.0), TE (-0.6, 3.4) | End Around |
| 1 | 0 | 1 | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.6), FB (-4.5, 2.0) | PA Post |
| 1 | 0 | 1 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 18.4), RB (-5.5, 2.0), TE (-0.6, -3.4) | Bootleg |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 15.6), RB (-5.0, 3.0), TE (-0.6, -3.4) | Mesh |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-1.2, 9.8), WR (-0.6, 19.9), RB (-5.0, -3.0), TE (-0.6, 3.4) | Smash |
| 2 | 0 | 2 | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, -3.0), TE (-0.6, 3.4) | Sluggo, Texas |
| 1 | 0 | 1 | QB (-7.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), SL (-0.6, 6.9), FB (-7.0, -2.5) | Gun Verts |
| 1 | 0 | 1 | QB (-7.0, 0.0), SL (-0.6, 8.3), WR (-0.6, 18.4), RB (-7.0, 2.5), TE (-0.6, -3.4) | Gun Stick |
| 1 | 1 | 0 | QB (-7.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 9.8), RB (-7.0, -2.5), TE (-0.6, 3.4) | Gun Stretch |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 15.6), RB (-6.5, 0.6), TE (-0.6, -3.4) | Goal Line Fade |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 11.2), SL (-1.5, 7.6), TE (-0.6, -3.4) | Goal Line Rub |
| 1 | 0 | 1 | QB (-5.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-5.5, -2.5) | Goal Line Corner |
| 1 | 1 | 0 | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-4.5, 1.8) | Goal Line Dive |
| 1 | 1 | 0 | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 2.0) | Goal Line Power |
| 1 | 0 | 1 | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-4.5, 2.0) | Goal Line PA |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 8.3), RB (-6.0, 2.5), TE (-0.6, 3.4) | Crack Toss |
| 1 | 1 | 0 | QB (-0.6, 18.4), WR (-3.0, -5.4), WR (-0.6, 9.8), RB (-5.0, 0.0), TE (-0.6, 3.4) | Wildcat Jet |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 18.4), RB (-1.5, 8.3), FB (-5.5, 2.5) | HB Slot Out |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 17.0), RB (-1.5, -7.6), TE (-0.6, 3.4) | Drive |
| 2 | 0 | 2 | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.6), TE (-0.6, 3.4) | Flea Flicker, TE Flat |
| 1 | 0 | 1 | QB (-5.0, 0.0), SL (-1.5, -9.8), WR (-0.6, 18.4), RB (-0.6, -19.9), TE (-0.6, 3.4) | Mismatch Go |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -18.4), SL (-0.6, -8.3), RB (-5.0, 3.0), TE (-0.6, -3.4) | Dagger |
| 1 | 0 | 1 | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-1.5, -8.3), TE (-0.6, 3.4) | Gun Empty Slants |
| 1 | 0 | 1 | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-1.5, 5.4), FB (-7.0, -2.5) | Gun Trips Flood |
| 1 | 0 | 1 | QB (-7.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), RB (-7.0, 2.5), TE (-0.6, -3.4) | Gun Flea Flicker |
| 1 | 1 | 0 | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), FB (-7.0, -2.5) | Gun Draw |
| 1 | 0 | 1 | QB (-0.6, -18.4), SL (-1.5, 9.8), WR (-0.6, 18.4), RB (-6.0, 0.0), TE (-0.6, 3.4) | Wildcat Pass |
| 1 | 0 | 1 | QB (-7.0, 0.0), WR (-0.6, -18.4), SL (-0.6, -8.3), RB (-7.0, 2.5), TE (-0.6, 3.4) | Gun Levels |
| 1 | 1 | 0 | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.0, 1.5), FB (-4.5, 2.0) | Goal Line Toss |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -15.6), WR (-0.6, 15.6), RB (-1.5, 7.6), TE (-0.6, -3.4) | Goal Line Empty |
| 1 | 0 | 1 | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.6), FB (-4.5, -2.0) | Goal Line Boot |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), SL (-0.6, 8.3), TE (-0.6, -8.3) | Hail Mary |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), TE (-0.6, 3.4), RB (-6.5, -1.6), FB (-5.6, 1.0) | FB Dive |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -5.4), WR (-0.6, 17.0), RB (-6.5, 0.6), FB (-4.5, -1.8) | FB Belly |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 17.0), RB (-6.5, -0.4), FB (-4.5, -1.8) | Iso Lead |
| 1 | 1 | 0 | QB (-4.0, 0.0), WR (-0.6, -17.0), WR (-0.6, 11.2), RB (-6.0, 2.5), FB (-4.5, 2.2) | Lead Toss |
| 1 | 1 | 0 | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-0.6, 17.0), RB (-6.5, 0.4), TE (-0.6, 3.4) | Double Tight Power |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-5.0, 3.0), FB (-5.0, -3.0) | FB Wheel |
| 1 | 0 | 1 | QB (-5.0, 0.0), WR (-0.6, -19.9), WR (-0.6, 19.9), RB (-5.0, -3.0), TE (-0.6, 3.4) | TE Seam |

### Mirrors and near-duplicates before

Measured by `tests/playbook_probe.gd`: two plays are the same play when they line up within 1.5 yards of each other and no player's path differs by more than 2.5 yards over its first 25 yards, compared as drawn and with one of them mirrored.

- HB Toss / Lead Toss: mirror, 0.8 yd apart

Only one pair was a mirror by that measure, because the plays hardly ever shared a line-up. Read as football, more of them were one idea drawn again:

| Plays | Why they are one play |
|---|---|
| HB Toss, Lead Toss, Crack Toss, Goal Line Toss | The same pitch to the same back behind the same lead block: left, right, right with the wideout tight, right from two tight ends |
| Off Tackle, Double Tight Power, Goal Line Power | The back on the same path off the right guard |
| FB Dive, FB Belly | Fullback up the middle, one gap apart |
| Deep Bomb, Gun Verts, Hail Mary | Go routes outside and one man up the middle |
| Flea Flicker, Gun Flea Flicker | Same routes; only the hand-off differs |
| TE Delay, Texas | The same two clear-out routes with a late man underneath |
| Quick Slants, Gun Empty Slants, HB Slot Out | Slants from both wideouts |
| Goal Line PA, Goal Line Corner, Goal Line Boot | The same corner route by the right tight end |

### Defense before: 36 plays

| Play | File | Tab | Rush | Man | Zone (deep) | Spy | CPU fit run/short/deep | What it does |
|---|---|---|---|---|---|---|---|---|
| Man Cover 1 | man_cover | MAN | 3 | 4 | 1 (1) | 0 | 0.70 / 0.66 / 0.55 | Three rush, man on every receiver, one safety deep. |
| Man Robber | man_robber | MAN | 3 | 4 | 1 (0) | 0 | 0.78 / 0.44 / 0.57 | Three rush, man on every receiver, a robber in the short middle. Nobody deep. |
| Run Stuff | run_stuff | MAN | 3 | 4 | 1 (0) | 0 | 0.71 / 0.33 / 0.52 | Three rush, press man, linebackers tight on the back and the tight end, safety walked up. Nobody deep. |
| Zone Cover 2 | zone_cover | ZONE | 3 | 0 | 5 (2) | 0 | 0.67 / 0.50 / 0.39 | Three rush, two flats, two deep halves, one linebacker in the middle. |
| Cover 3 | cover_3 | ZONE | 3 | 0 | 5 (3) | 0 | 0.43 / 0.12 / 0.55 | Three rush, three deep thirds, two underneath. Flats are open. |
| Prevent | prevent | ZONE | 2 | 0 | 6 (4) | 0 | 0.61 / 0.39 / 0.55 | Two rush, four deep, two underneath. Gives up the short stuff. |
| All-Out Blitz | all_out_blitz | BLITZ | 4 | 4 | 0 (0) | 0 | 0.32 / 0.69 / 0.66 | Four rush, press man on every receiver. Nobody deep. |
| Zone Blitz | zone_blitz | BLITZ | 4 | 1 | 3 (1) | 0 | 0.66 / 0.62 / 0.43 | Four rush, zones outside, a man on the tight end, one safety deep. Open in the short middle. |
| Corner Blitz | corner_blitz | BLITZ | 4 | 4 | 0 (0) | 0 | 0.41 / 0.84 / 0.44 | Right corner comes off the edge. The safety picks up his man from deep. Nobody behind them. |
| Goal Line Stuff | gl_stuff | GOAL LINE | 5 | 3 | 0 (0) | 0 | 0.56 / 0.60 / 0.15 | Five rush, both linebackers off the edges, press man outside and on the tight end. Nobody on the back. |
| Goal Line Man | gl_man | GOAL LINE | 4 | 4 | 0 (0) | 0 | 0.47 / 0.84 / 0.20 | Four down linemen in the gaps, press man on every receiver. Nobody deep. |
| Goal Line Zone | gl_zone | GOAL LINE | 3 | 0 | 5 (0) | 0 | 0.49 / 0.39 / 0.10 | Three rush, five short zones across the goal line. Soft against the run. |
| 2 Man Under | two_man | MAN | 2 | 4 | 2 (2) | 0 | 0.50 / 0.61 / 0.51 | Two rush, man underneath every receiver, two safeties over the top. Light against the run. |
| Bracket | bracket | MAN | 3 | 5 | 0 (0) | 0 | 0.25 / 0.44 / 0.55 | Three rush, man on every receiver, a second man underneath the left wideout. Nobody deep. |
| Cover 1 Spy | cover_1_spy | MAN | 2 | 4 | 1 (1) | 1 | 0.64 / 0.75 / 0.65 | Two rush, man on every receiver, a spy on the quarterback, one safety deep. |
| Safety Blitz | safety_blitz | BLITZ | 4 | 4 | 0 (0) | 0 | 0.43 / 0.57 / 0.71 | Three rush and the safety comes from deep up the middle. Man on every receiver, nobody behind them. |
| Mike Blitz | mike_blitz | BLITZ | 4 | 3 | 1 (1) | 0 | 0.51 / 0.53 / 0.58 | Linebacker shoots the middle gap. Man on the wideouts and the tight end, one safety deep. The back is free. |
| Overload | overload | BLITZ | 5 | 0 | 3 (0) | 0 | 0.61 / 0.37 / 0.10 | Five rush, two extra off the right edge. Three zones behind them, nobody deep. |
| Press Man | press_man | MAN | 3 | 4 | 1 (1) | 0 | 0.65 / 0.60 / 0.43 | Three rush, corners up in the receivers' faces, linebackers on the back and the tight end. The safety sits only ten yards deep. |
| Double Wide | double_wide | MAN | 2 | 6 | 0 (0) | 0 | 0.35 / 0.55 / 0.58 | Two rush. Both wideouts get a man underneath and a man over the top. One linebacker has the back, the other the tight end. |
| Man Lurk | man_lurk | MAN | 2 | 4 | 2 (1) | 0 | 0.50 / 0.65 / 0.61 | Two rush, man on every receiver, a lurker in the short middle and one safety deep. |
| Cover 4 | cover_4 | ZONE | 3 | 0 | 5 (4) | 0 | 0.45 / 0.15 / 0.47 | Three rush, four deep quarters across the field. Only one linebacker underneath. |
| Cover 6 | cover_6 | ZONE | 3 | 0 | 5 (3) | 0 | 0.50 / 0.30 / 0.42 | Three rush. Two deep quarters on the left; a deep half with a corner in the flat under it on the right. One linebacker in the short middle. |
| Tampa 2 | tampa_2 | ZONE | 2 | 0 | 6 (3) | 0 | 0.50 / 0.45 / 0.61 | Two rush, corners in the flats, two deep halves, and the middle linebacker runs back to take the deep seam. The other one stays underneath. |
| Cover 2 Sink | cover_2_sink | ZONE | 3 | 0 | 5 (2) | 0 | 0.55 / 0.30 / 0.34 | Three rush, two deep halves, a linebacker in the middle. Corners drop to ten yards under the corner routes and leave the flats alone. |
| Cloud Flats | cloud_flats | ZONE | 2 | 0 | 6 (1) | 0 | 0.60 / 0.60 / 0.44 | Two rush, four men across underneath and one in the hole behind them, one safety deep. Takes away the short stuff. |
| Zone Spy | zone_spy | ZONE | 2 | 0 | 5 (2) | 1 | 0.60 / 0.45 / 0.55 | Two rush, two flats, one in the middle, two deep halves, and a spy who goes when the quarterback runs. |
| Edge Blitz | edge_blitz | BLITZ | 4 | 3 | 1 (1) | 0 | 0.60 / 0.50 / 0.84 | Two linebackers come off the edges with two linemen inside. Man on the wideouts and the tight end, one safety deep. The back is free. |
| Cross Dog | cross_dog | BLITZ | 5 | 3 | 0 (0) | 0 | 0.45 / 0.50 / 0.36 | Five rush: two linebackers through the middle behind the line. Man on the wideouts and the tight end, nobody deep and nobody on the back. |
| Fire Zone | fire_zone | BLITZ | 5 | 1 | 2 (2) | 0 | 0.60 / 0.30 / 0.20 | Five rush with two deep halves behind it and a man on the tight end. Everything else short is open if the ball gets out. |
| Goal Line Blitz | gl_blitz | GOAL LINE | 5 | 3 | 0 (0) | 0 | 0.55 / 0.55 / 0.15 | Four down linemen in the gaps and a linebacker behind them: five rush. Press man outside and on the tight end, nobody on the back. |
| Goal Line Pinch | gl_pinch | GOAL LINE | 5 | 0 | 3 (0) | 0 | 0.60 / 0.35 / 0.10 | Five across the front, one linebacker behind them. Corners sit in the flats. |
| Goal Line Press | gl_press | GOAL LINE | 3 | 4 | 1 (0) | 0 | 0.50 / 0.70 / 0.20 | Three rush, corners in the receivers' faces, linebackers on the back and the tight end and a man waiting in the short middle. |
| Goal Line Spy | gl_spy | GOAL LINE | 3 | 4 | 0 (0) | 1 | 0.50 / 0.70 / 0.20 | Three rush, man on every receiver, and a spy for the quarterback who rolls out or keeps it. |
| Goal Line Edge | gl_edge | GOAL LINE | 3 | 2 | 3 (0) | 0 | 0.55 / 0.50 / 0.15 | Three rush, a linebacker set wide on each side for the toss and one in the middle. Man on the wideouts. |
| Goal Line Double | gl_double | GOAL LINE | 3 | 4 | 1 (0) | 0 | 0.40 / 0.60 / 0.30 | Three rush, two men on each wideout: one in front, one behind. One man in the short middle, nobody on the back. |

### Defensive mirrors and near-duplicates before

Same measure: every defender's spot (for a man defender his depth and whom he covers, for a zone defender also the zone) within 2.5 yards of a defender of the other play with the same job.

- Man Robber / Run Stuff: same side, 2.0 yd apart
- Man Robber / Run Stuff: mirror, 2.0 yd apart
- Run Stuff / Goal Line Press: same side, 2.0 yd apart
- Run Stuff / Goal Line Press: mirror, 2.0 yd apart
- All-Out Blitz / Goal Line Man: same side, 1.4 yd apart
- All-Out Blitz / Goal Line Man: mirror, 1.4 yd apart
- Cross Dog / Goal Line Blitz: mirror, 2.1 yd apart

No defensive play was a left-right mirror of another by design (the pairs above match both ways round because the plays are symmetric). Four pairs were close to the same play: an open-field play and its goal line copy three times, and Man Robber next to Run Stuff.

## 2. Rule 3: does the defense ignore where the receivers are?

**Partly confirmed.** The defense did not bunch every man over the line: defenders in man coverage already slid sideways to stand across from their man. Everybody else stood on the spot the play file gave him, whatever the offense did:

- every zone defender, spy and blitzer was on the same spot against all six test formations (the "Fixed" column: 5 of 5, 6 of 6);
- zone corners stood at a fixed width of 12.7 to 18.4 yards. Against a wideout at 18.4 the Cover 2 corners were 5.7 yards inside him, against three receivers on one side the corner on the empty side covered grass, and against two tight ends both corners stood out wide over nobody;
- in man coverage the numbers in the play file meant "first, second, third receiver in the order the offensive play lists them", not "widest receiver". Against three on one side a corner covered the slot only because the play happened to list the slot first;
- the CPU flipped its defensive play on a coin toss, so an overload or a rolled coverage went to the strong side only by luck.

Test: every defensive play lined up against six formations (two wideouts and a tight end; three receivers on one side; four wide; an empty backfield with three and one; a bunch; two tight ends and two backs). Each cell is "split receivers with no coverage defender within 5 yards across / split receivers".

Per formation: split receivers with no coverage defender within 5 yards across / split receivers. "Fixed": coverage defenders (not in man) who stand on the same spot against all six.

| Play | Fixed | 2-wide | trips | 4-wide | empty 3x1 | bunch | heavy |
|---|---|---|---|---|---|---|---|
| Man Cover 1 | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Man Robber | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Run Stuff | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Zone Cover 2 | 5 of 5 | 2 / 2 | 1 / 3 | 2 / 4 | 2 / 4 | 0 / 3 | 0 / 0 |
| Cover 3 | 5 of 5 | 0 / 2 | 2 / 3 | 1 / 4 | 1 / 4 | 2 / 3 | 0 / 0 |
| Prevent | 6 of 6 | 0 / 2 | 1 / 3 | 0 / 4 | 1 / 4 | 1 / 3 | 0 / 0 |
| All-Out Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Zone Blitz | 4 of 4 | 0 / 2 | 1 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Corner Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Stuff | 2 of 2 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Man | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Zone | 5 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 1 / 3 | 0 / 0 |
| 2 Man Under | 2 of 2 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Bracket | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 1 Spy | 2 of 2 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Safety Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Mike Blitz | 2 of 2 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Overload | 5 of 5 | 2 / 2 | 2 / 3 | 2 / 4 | 3 / 4 | 1 / 3 | 0 / 0 |
| Press Man | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Double Wide | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Man Lurk | 2 of 2 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 4 | 5 of 5 | 0 / 2 | 1 / 3 | 0 / 4 | 1 / 4 | 1 / 3 | 0 / 0 |
| Cover 6 | 5 of 5 | 0 / 2 | 1 / 3 | 0 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Tampa 2 | 6 of 6 | 0 / 2 | 2 / 3 | 0 / 4 | 2 / 4 | 0 / 3 | 0 / 0 |
| Cover 2 Sink | 5 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cloud Flats | 6 of 6 | 0 / 2 | 1 / 3 | 0 / 4 | 0 / 4 | 1 / 3 | 0 / 0 |
| Zone Spy | 6 of 6 | 2 / 2 | 1 / 3 | 2 / 4 | 2 / 4 | 0 / 3 | 0 / 0 |
| Edge Blitz | 3 of 3 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Cross Dog | 2 of 2 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Fire Zone | 4 of 4 | 0 / 2 | 1 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Pinch | 3 of 3 | 0 / 2 | 2 / 3 | 2 / 4 | 2 / 4 | 1 / 3 | 0 / 0 |
| Goal Line Press | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Spy | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Edge | 3 of 3 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Double | 1 of 1 | 0 / 2 | 1 / 3 | 2 / 4 | 2 / 4 | 0 / 3 | 0 / 0 |

Three of the 36, with every defender's spot (`tests/play_audit_dump.gd -- lineups` prints all of them):

| Play | Against | Defenders (yards past the line, yards to the offense's right) |
|---|---|---|
| Man Cover 1 | 2-wide | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB man (5.0, -18.4), CB man (5.0, 18.4), LB man (5.0, 0.4), LB man (5.0, 3.4) |
| Man Cover 1 | trips | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB man (5.0, 11.2), CB man (5.0, 19.9), LB man (5.0, -2.5), LB man (5.0, 5.4) |
| Man Cover 1 | heavy | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB man (5.0, -3.4), CB man (5.0, 3.4), LB man (5.0, 0.4), LB man (6.5, 1.8) |
| Zone Cover 2 | 2-wide | S zone (14.0, -9.8), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (6.0, -12.7), CB zone (6.0, 12.7), S zone (14.0, 9.8), LB zone (5.0, 0.0) |
| Zone Cover 2 | trips | S zone (14.0, -9.8), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (6.0, -12.7), CB zone (6.0, 12.7), S zone (14.0, 9.8), LB zone (5.0, 0.0) |
| Zone Cover 2 | heavy | S zone (14.0, -9.8), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (6.0, -12.7), CB zone (6.0, 12.7), S zone (14.0, 9.8), LB zone (5.0, 0.0) |
| Cover 3 | 2-wide | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (9.0, -17.0), CB zone (9.0, 17.0), LB zone (5.0, 0.0), LB zone (5.0, -6.0) |
| Cover 3 | trips | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (9.0, -17.0), CB zone (9.0, 17.0), LB zone (5.0, 0.0), LB zone (5.0, -6.0) |
| Cover 3 | heavy | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (9.0, -17.0), CB zone (9.0, 17.0), LB zone (5.0, 0.0), LB zone (5.0, -6.0) |

## 3. Offense after: six formations, nine plays each

The tabs of the play-select screen are now the formations. Every play of a formation has all eight players on exactly the same spots, the quarterback included (under center he is at 4 yards for runs and passes alike; in the shotgun at 7).

| Tab | Quarterback | Skill players | Runs | Short | Deep | Play action, screens, tricks |
|---|---|---|---|---|---|---|
| I-FORM | under center | wideout each side, back, fullback | Iso Lead, FB Dive, Lead Toss | Quick Slants, FB Wheel, Texas | PA Post, Sluggo, Flea Flicker | PA Post (play action), Flea Flicker (trick) |
| SINGLEBACK | under center | wideout each side, back, tight end right | Off Tackle, Counter, Draw | Curl Flat, Mesh, HB Screen, Bootleg | Crossfire, Flood | Bootleg (play action), HB Screen (screen), Draw |
| HEAVY | under center | tight end each side, wideout right, back | Double Tight Power, HB Dive, Power Sweep | TE Delay, TE Flat, TE Corner, TE Cross | TE Seam, Max Protect | TE Flat (play action) |
| GUN SPREAD | shotgun | wideout each side, slot left, back beside the quarterback | Gun Draw, Gun Counter | Gun Stick, Drive, Gun Outs | Gun Verts, Dagger, Gun Flea Flicker, Hail Mary | Gun Flea Flicker (trick), Gun Draw |
| GUN TRIPS | shotgun | wideout, slot and a wing on the right, back beside the quarterback | Gun Stretch, Gun Dive | Bubble Screen, Smash, Gun Levels, Gun Boot | Trips Flood, Scissors, Da Bomb | Gun Boot (play action), Bubble Screen (screen) |
| GOAL LINE | under center | tight end each side, back, fullback | Dive, Power, Toss, Wedge | Boot, Corner, Flat, Pop, Mesh | none | Boot and Pop (play action) |

The roster order decides who stands where (two receivers, the back, then the tight end or fullback), so in a formation the same man is on the same spot in every play.

The plays are written by `tools/gen_offense_plays.py` from one table (a formation's spots are in it once), which is the easy way to add a play without breaking a formation. What each play is for is on its card and in the table below; what stops it and what it beats is in section 6.

### Formation groups after: 6 line-ups for 54 plays, 0 plays in a group of fewer than 4

| Plays | Runs | Passes | Skill players | Plays in it |
|---|---|---|---|---|
| 9 | 3 | 6 | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Iso Lead, FB Dive, Lead Toss, Quick Slants, FB Wheel, Texas, PA Post, Sluggo, Flea Flicker |
| 9 | 3 | 6 | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Off Tackle, Counter, Draw, Curl Flat, Mesh, HB Screen, Bootleg, Crossfire, Flood |
| 9 | 3 | 6 | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Double Tight Power, HB Dive, Power Sweep, TE Delay, TE Flat, TE Corner, TE Cross, TE Seam, Max Protect |
| 9 | 2 | 7 | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Gun Draw, Gun Counter, Gun Stick, Drive, Gun Outs, Gun Verts, Dagger, Gun Flea Flicker, Hail Mary |
| 9 | 2 | 7 | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Gun Stretch, Gun Dive, Bubble Screen, Smash, Gun Levels, Gun Boot, Trips Flood, Scissors, Da Bomb |
| 9 | 4 | 5 | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Goal Line Dive, Goal Line Power, Goal Line Toss, Goal Line Wedge, Goal Line Boot, Goal Line Corner, Goal Line Flat, Goal Line Pop, Goal Line Mesh |

### Offense after: 54 plays

| Play | File | Tab | Type | Skill players (x past the line, y right of the ball) | What it does |
|---|---|---|---|---|---|
| Iso Lead | iso_lead | I-FORM | run | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Fullback hits the gap left of the center and takes on the first man there. Back follows him through. |
| FB Dive | fb_dive | I-FORM | run | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Quick handoff to the fullback straight up the middle. Back fakes the sweep to the left. |
| Lead Toss | lead_toss | I-FORM | run | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Quick pitch to the back running wide to the right, the fullback out in front of him. |
| Quick Slants | quick_slants | I-FORM | short pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Both wideouts cut inside. Back leaks out to the right and turns upfield. Fullback blocks, then sits down over the middle. |
| FB Wheel | fb_wheel | I-FORM | short pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Fullback swings out to the right and turns up the sideline. Right wideout slants inside to clear it, left wideout curls. Back stays in to block. |
| Texas | texas | I-FORM | short pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Both wideouts run the coverage off deep. Back starts for the left flat, then angles back inside behind the linebackers. Fullback blocks, then breaks out to the right. |
| PA Post | pa_post | I-FORM | play-action | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Fake the dive up the middle, then a deep post and a go route behind the defenders who come up. |
| Sluggo | sluggo | I-FORM | deep pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Slant and go on the right: sell the slant, then straight up the field. Deep in on the left, back sits down underneath it. |
| Flea Flicker | flea_flicker | I-FORM | trick | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Dive to the back, who stops and pitches it back to the quarterback. Go route on the left, deep crosser from the right. |
| Off Tackle | off_tackle | SINGLEBACK | run | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Handoff round the outside of the tight end on the right. Everyone blocks. |
| Counter | counter | SINGLEBACK | run | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Back steps right, then cuts back to the left side away from the tight end. |
| Draw | draw | SINGLEBACK | run | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Looks like a pass: wideouts run deep, the quarterback drops, then a delayed handoff up the middle. |
| Curl Flat | curl_flat | SINGLEBACK | short pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Wideouts stop and turn back at twelve yards. Back swings out to the right and turns upfield. |
| Mesh | mesh | SINGLEBACK | short pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Wideouts cross over the middle 8 yards deep. Back angles in underneath. Tight end blocks, then slips to the right flat. |
| HB Screen | hb_screen | SINGLEBACK | screen | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Wideouts clear out deep. Dump it to the back behind the line on the left. |
| Bootleg | bootleg | SINGLEBACK | play-action | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Fake the sweep left and roll out right. Tight end in the flat in front of the quarterback, right wideout comes back to him, left wideout drags across. |
| Crossfire | crossfire | SINGLEBACK | deep pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Two crossers at different depths. Back wheels up the right sideline. |
| Flood | flood | SINGLEBACK | deep pass | QB (-4.0, 0.0), WR (-0.6, -18.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Three levels on the right side: wideout deep, tight end to the sideline at fourteen yards, back in the flat. Left wideout breaks in behind them. |
| Double Tight Power | double_tight_power | HEAVY | run | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | A tight end on each side of the line. Handoff off the right guard, everyone blocks. |
| HB Dive | hb_dive | HEAVY | run | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Quick handoff straight up the middle behind two tight ends. |
| Power Sweep | power_sweep | HEAVY | run | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Handoff to the back running wide to the right behind the tight end and the wideout. Everyone blocks. |
| TE Delay | te_delay | HEAVY | short pass | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Wideout runs the coverage off deep, back to the right flat. Left tight end blocks, then slips out over the middle. |
| TE Flat | te_flat | HEAVY | play-action | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Fake the dive. Right tight end slips into the flat behind it, wideout clears out deep, left tight end breaks in. |
| TE Corner | te_corner | HEAVY | short pass | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Wideout slants inside, right tight end breaks to the corner behind him. Left tight end drags across, back in the right flat. |
| TE Cross | te_cross | HEAVY | screen | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Right tight end crosses the field twelve yards deep, wideout runs the post over him. Left tight end in the left flat, back sits down on the right. |
| TE Seam | te_seam | HEAVY | deep pass | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | All four out. Right tight end straight up the seam, left tight end to the corner, wideout curls, back in the left flat. |
| Max Protect | max_protect | HEAVY | screen | QB (-4.0, 0.0), TE (-0.6, -3.4), WR (-1.2, 18.4), RB (-6.5, 0.4), TE (-0.6, 3.4) | Both tight ends stay in to block. Wideout alone runs the deep post. Back blocks, then sits down on the left. |
| Gun Draw | gun_draw | GUN SPREAD | run | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Everyone runs deep, the quarterback waits, then hands it to the back up the middle. |
| Gun Counter | gun_counter | GUN SPREAD | run | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Back steps right, then crosses in front of the quarterback, takes the ball and cuts up the left side. |
| Gun Stick | gun_stick | GUN SPREAD | short pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Slot sits down six yards deep, left wideout fades behind him. Right wideout slants, back swings to the right flat. |
| Drive | drive | GUN SPREAD | short pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Left wideout drags shallow across the field, right wideout breaks in behind him ten yards deep. Slot sits down, back in the right flat. |
| Gun Outs | gun_outs | GUN SPREAD | short pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Both wideouts break to the sideline six yards deep, slot up the seam to hold the safety. Back stays in to block. |
| Gun Verts | gun_verts | GUN SPREAD | deep pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Both wideouts straight up the field, slot up the seam between the safeties. Back in the right flat. |
| Dagger | dagger | GUN SPREAD | deep pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Slot runs the seam to pull the safety away, left wideout breaks in behind it thirteen yards deep. Right wideout comes back, back stays in to block. |
| Gun Flea Flicker | gun_flea_flicker | GUN SPREAD | trick | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Shotgun. Toss to the back swinging right, who throws it straight back to the quarterback. Go route on the left, deep crosser from the right, slot sits down underneath. |
| Hail Mary | hail_mary | GUN SPREAD | deep pass | QB (-7.0, 0.0), WR (-0.6, -18.4), WR (-0.6, 18.4), RB (-7.0, 2.5), SL (-1.2, -8.3) | Everyone goes deep. Throw it up and pray. |
| Gun Stretch | gun_stretch | GUN TRIPS | run | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Back crosses in front of the quarterback, takes the ball and runs wide to the right behind them. |
| Gun Dive | gun_dive | GUN TRIPS | run | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Quick handoff to the back straight ahead, left of the center. |
| Bubble Screen | bubble_screen | GUN TRIPS | screen | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Slot steps back and out for a quick throw behind the line, the two men beside him block. Back swings left. |
| Smash | smash | GUN TRIPS | short pass | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Wideout stops at six yards, slot breaks to the corner over the top of him. Inside man hooks up in the middle, back in the left flat. |
| Gun Levels | gun_levels | GUN TRIPS | short pass | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Wideout breaks in at five yards, slot at twelve. Inside man in the right flat, back swings left. |
| Gun Boot | gun_boot | GUN TRIPS | play-action | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Fake the stretch right and roll out left. Inside man drags across with the quarterback, slot crosses deeper behind him, wideout goes deep. |
| Trips Flood | gun_trips_flood | GUN TRIPS | deep pass | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Wideout straight up the field, slot out at twelve yards, inside man to the flat. Back stays in to block. |
| Scissors | scissors | GUN TRIPS | deep pass | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right. Wideout runs the post, slot crosses under him to the corner. Inside man drags left, back swings left. |
| Da Bomb | da_bomb | GUN TRIPS | deep pass | QB (-7.0, 0.0), SL (-0.6, 11.2), WR (-0.6, 19.9), RB (-7.0, -2.5), HB (-1.5, 5.4) | Shotgun, three on the right, everyone deep. Wideout straight up the field, slot on the deep post, inside man jabs left and runs a second post under it. Back stays in to block. |
| Goal Line Dive | gl_dive | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Two tight ends, everyone blocks down. Quick handoff straight ahead behind the fullback. |
| Goal Line Power | gl_power | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Two tight ends. Fullback leads round the right guard, back follows him in. |
| Goal Line Toss | gl_toss | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Two tight ends block down. Quick pitch to the back running for the right corner behind the fullback. |
| Goal Line Wedge | gl_fb_dive | GOAL LINE | run | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Quick handoff to the fullback left of the center. Back fakes the toss to the right. |
| Goal Line Boot | gl_boot | GOAL LINE | play-action | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Fake the dive and roll out right. Tight end in the flat in front of the quarterback, the other one crossing to the back corner. |
| Goal Line Corner | gl_corner | GOAL LINE | short pass | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Right tight end breaks to the back corner, left tight end sits down in the middle, back in the right flat. |
| Goal Line Flat | gl_fb_flat | GOAL LINE | short pass | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Fullback slips straight out to the right flat. Right tight end slants inside to clear it, left tight end fades to the corner. Back stays in to block. |
| Goal Line Pop | gl_te_pop | GOAL LINE | play-action | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | Fake the dive. Right tight end runs straight up the middle behind the linebackers who come up, left tight end fades to the corner. |
| Goal Line Mesh | gl_mesh | GOAL LINE | short pass | QB (-4.0, 0.0), TE (-0.6, -3.4), TE (-0.6, 3.4), RB (-6.5, 0.4), FB (-4.5, 1.8) | The tight ends cross right behind the line. Back to the left flat. Fullback blocks, then sits down in the middle. |

## 4. Defense after: line-up by rule

`scripts/defense_aligner.gd` (new) reads the formation from where the offense stands, never from what its play is going to be, and `PlayController.line_up` asks it for every defender's spot. The play file still gives each defender his job, his depth and his side; the aligner sets how wide he stands.

**Reading the formation.** A player 4.6 yards or more from the ball and not deep in the backfield is split out (wideout, slot, wing). Per side they are numbered from the outside in. The strong side is the one with more split receivers; with as many on each, the side with a tight end.

**Rules** (`DefenseAssignment.align`, set on every defender in every play file):

| Rule | Who | What he does |
|---|---|---|
| man coverage | every defender whose job is a man | Stands across from his man. Target 0 is the widest receiver on the left, 1 the widest on the right, 2 the back, 3 whoever is left (tight end, fullback, a slot). With nobody split out on his side a corner goes to the next widest man, so against three on one side both corners are over there |
| OUTSIDE | zone corners, blitzing corners | Out with the widest receiver of his side, 1.5 yards inside him to see the quarterback (a blitzing corner cheats 2.5 in). With nobody split out on his side he comes in to 3 yards outside the last man on the line |
| SLOT | linebackers and safeties in underneath zones | Whoever is nearest walks out over a slot or wing that nobody has, 60% of the way from the box to him (80% over a wideout a blitzing corner has left). Only on his own side, unless he is drawn in the middle. Otherwise he slides toward the strong side |
| STRENGTH | deep safeties, the deep middle | Slides toward the strong side: 1.5 yards for every receiver it has more (a yard underneath), 3 at the most |
| SPOT | the line, blitzers in the box, spies | Where the play draws him |

Zones themselves stay where the play draws them; only the starting spot moves. Two defenders who would stand in each other are staggered in depth (a stack or a bunch). The whole line-up is still squeezed toward the line near the goal line, as before.

**Edge cases.** Empty backfield: without a back, man target 2 is the inside receiver on the right. Three on one side: both corners and the walked-out linebacker go there, the safeties slide. Bunch and stack: defenders stagger. Unbalanced lines: the rules read receivers, not linemen, so a tight end only moves the strong side. Motion: the game has none; `line_up` is the only place players are put on their spots, and a motion feature would call the aligner again from there.

**CPU flip.** `DefensePlay.strength_side` says where a one-sided play belongs: Overload and Zone Spy toward the strong side; Corner Blitz, Cover 6, Cover 3, Tampa 2 and Prevent the other way round. The CPU flips those to fit the formation and still tosses a coin for the rest. The person's own flip is untouched.

**Shared shells (disguise).** Zone Cover 2, Cover 2 Sink, Zone Spy, Cover 4, Cover 6, Tampa 2 and 2 Man Under all start with two safeties at 14 yards, 8.5 either side. Man Cover 1, Man Lurk, Cover 1 Spy, Cover 3, Cloud Flats, Edge Blitz, Mike Blitz and Zone Blitz start with one safety at 15 in the middle. The corners' depth can still give a hint, as it does in real football.

**The same test after the change:**

Per formation: split receivers with no coverage defender within 5 yards across / split receivers. "Fixed": coverage defenders (not in man) who stand on the same spot against all six.

| Play | Fixed | 2-wide | trips | 4-wide | empty 3x1 | bunch | heavy |
|---|---|---|---|---|---|---|---|
| Man Cover 1 | 0 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Man Robber | 0 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Run Stuff | 0 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Zone Cover 2 | 0 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 3 | 0 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Prevent | 0 of 6 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| All-Out Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Zone Blitz | 1 of 4 | 0 / 2 | 1 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Corner Blitz | 0 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Stuff | 2 of 2 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Man | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Zone | 0 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| 2 Man Under | 0 of 2 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Bracket | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 1 Spy | 1 of 2 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Safety Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Mike Blitz | 1 of 2 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Overload | 1 of 5 | 1 / 2 | 1 / 3 | 1 / 4 | 1 / 4 | 1 / 3 | 0 / 0 |
| Press Man | 0 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Double Wide | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Man Lurk | 0 of 2 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 4 | 0 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 6 | 0 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Tampa 2 | 0 of 6 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cover 2 Sink | 0 of 5 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Cloud Flats | 0 of 6 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Zone Spy | 1 of 6 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Edge Blitz | 2 of 3 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Cross Dog | 2 of 2 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Fire Zone | 2 of 4 | 0 / 2 | 1 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Blitz | 1 of 1 | 0 / 2 | 0 / 3 | 1 / 4 | 1 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Pinch | 0 of 3 | 0 / 2 | 0 / 3 | 1 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line TE Double | 0 of 0 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Spy | 1 of 1 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Edge | 0 of 3 | 0 / 2 | 0 / 3 | 0 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |
| Goal Line Double | 0 of 1 | 0 / 2 | 0 / 3 | 1 / 4 | 0 / 4 | 0 / 3 | 0 / 0 |

The cells that are not zero are blitzes and goal line fronts with fewer men in coverage than the offense has split receivers. "Fixed" now only counts spies and blitzers in the box.

| Play | Against | Defenders (yards past the line, yards to the offense's right) |
|---|---|---|
| Man Cover 1 | 2-wide | S zone (15.0, 0.8), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB man (5.0, -18.4), CB man (5.0, 18.4), LB man (5.0, 0.4), LB man (5.0, 3.4) |
| Man Cover 1 | trips | S zone (15.0, 3.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB man (5.0, 11.2), CB man (5.0, 19.9), LB man (5.0, -2.5), LB man (5.0, 5.4) |
| Man Cover 1 | heavy | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB man (5.0, -3.4), CB man (5.0, 3.4), LB man (5.0, 0.4), LB man (5.0, 1.8) |
| Zone Cover 2 | 2-wide | S zone (14.0, -7.8), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (6.0, -16.9), CB zone (6.0, 16.9), S zone (14.0, 9.3), LB zone (5.0, 0.5) |
| Zone Cover 2 | trips | S zone (14.0, -5.5), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (6.0, -4.7), CB zone (6.0, 18.4), S zone (14.0, 11.5), LB zone (5.0, 7.7) |
| Zone Cover 2 | heavy | S zone (14.0, -8.5), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (6.0, -6.4), CB zone (6.0, 6.4), S zone (14.0, 8.5), LB zone (5.0, 0.0) |
| Cover 3 | 2-wide | S zone (15.0, 0.8), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (9.0, -16.9), CB zone (9.0, 16.9), LB zone (5.0, 0.5), LB zone (5.0, -5.5) |
| Cover 3 | trips | S zone (15.0, 3.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (9.0, -4.7), CB zone (9.0, 18.4), LB zone (5.0, 7.7), LB zone (5.0, -4.0) |
| Cover 3 | heavy | S zone (15.0, 0.0), DL rush (1.0, -1.9), DL rush (1.0, 0.0), DL rush (1.0, 1.9), CB zone (9.0, -6.4), CB zone (9.0, 6.4), LB zone (5.0, 0.0), LB zone (5.0, -6.0) |

### Defense after: 36 plays

| Play | File | Tab | Rush | Man | Zone (deep) | Spy | CPU fit run/short/deep | What it does |
|---|---|---|---|---|---|---|---|---|
| Man Cover 1 | man_cover | MAN | 3 | 4 | 1 (1) | 0 | 0.41 / 0.42 / 0.46 | Three rush, man on every receiver, one safety deep. |
| Man Robber | man_robber | MAN | 3 | 4 | 1 (0) | 0 | 0.42 / 0.46 / 0.43 | Three rush, man on every receiver, a robber nine yards deep in the middle. Nobody behind him. |
| Run Stuff | run_stuff | MAN | 3 | 4 | 1 (0) | 0 | 0.30 / 0.45 / 0.39 | Three rush, press man, linebackers tight on the back and the tight end, safety walked up. Nobody deep. |
| Zone Cover 2 | zone_cover | ZONE | 3 | 0 | 5 (2) | 0 | 0.64 / 0.45 / 0.34 | Three rush, two flats, two deep halves, one linebacker in the middle. |
| Cover 3 | cover_3 | ZONE | 3 | 0 | 5 (3) | 0 | 0.39 / 0.43 / 0.52 | Three rush, three deep thirds, two underneath. Flats are open. |
| Prevent | prevent | ZONE | 2 | 0 | 6 (4) | 0 | 0.59 / 0.41 / 0.56 | Two rush, four deep, two underneath. Gives up the short stuff. |
| All-Out Blitz | all_out_blitz | BLITZ | 4 | 4 | 0 (0) | 0 | 0.24 / 0.60 / 0.68 | Three linemen and a linebacker off the left edge, press man on every receiver. Nobody deep. |
| Zone Blitz | zone_blitz | BLITZ | 4 | 1 | 3 (1) | 0 | 0.54 / 0.52 / 0.56 | Four rush, zones outside, a man on the tight end, one safety deep. Open in the short middle. |
| Corner Blitz | corner_blitz | BLITZ | 4 | 4 | 0 (0) | 0 | 0.61 / 0.39 / 0.37 | Right corner comes off the edge. The safety picks up his man from deep. Nobody behind them. |
| Goal Line Stuff | gl_stuff | GOAL LINE | 5 | 3 | 0 (0) | 0 | 0.42 / 0.81 / 0.15 | Five rush, both linebackers off the edges, press man outside and on the tight end. Nobody on the back. |
| Goal Line Man | gl_man | GOAL LINE | 4 | 4 | 0 (0) | 0 | 0.49 / 0.52 / 0.20 | Four down linemen in the gaps, press man on every receiver. Nobody deep. |
| Goal Line Zone | gl_zone | GOAL LINE | 3 | 0 | 5 (0) | 0 | 0.45 / 0.34 / 0.10 | Three rush, five short zones across the goal line. Soft against the run. |
| 2 Man Under | two_man | MAN | 2 | 4 | 2 (2) | 0 | 0.49 / 0.59 / 0.51 | Two rush, man underneath every receiver, two safeties over the top. Light against the run. |
| Bracket | bracket | MAN | 3 | 5 | 0 (0) | 0 | 0.24 / 0.50 / 0.52 | Three rush, man on every receiver, a second man underneath the left wideout. Nobody deep. |
| Cover 1 Spy | cover_1_spy | MAN | 2 | 4 | 1 (1) | 1 | 0.60 / 0.70 / 0.57 | Two rush, man on every receiver, a spy on the quarterback, one safety deep. |
| Safety Blitz | safety_blitz | BLITZ | 4 | 4 | 0 (0) | 0 | 0.41 / 0.71 / 0.64 | Three rush and the safety comes from deep up the middle. Man on every receiver, nobody behind them. |
| Mike Blitz | mike_blitz | BLITZ | 4 | 3 | 1 (1) | 0 | 0.36 / 0.67 / 0.61 | Linebacker shoots the middle gap. Man on the wideouts and the tight end, one safety deep. The back is free. |
| Overload | overload | BLITZ | 5 | 0 | 3 (0) | 0 | 0.73 / 0.10 / 0.10 | Five rush, two extra off the right edge. Three zones behind them, nobody deep. |
| Press Man | press_man | MAN | 3 | 4 | 1 (1) | 0 | 0.43 / 0.31 / 0.41 | Three rush, corners up in the receivers' faces, linebackers on the back and the tight end. The safety sits only ten yards deep. |
| Double Wide | double_wide | MAN | 2 | 6 | 0 (0) | 0 | 0.36 / 0.46 / 0.56 | Two rush. Both wideouts get a man underneath and a man over the top. One linebacker has the back, the other the tight end. |
| Man Lurk | man_lurk | MAN | 2 | 4 | 2 (1) | 0 | 0.51 / 0.56 / 0.45 | Two rush, man on every receiver, a lurker in the short middle and one safety deep. |
| Cover 4 | cover_4 | ZONE | 3 | 0 | 5 (4) | 0 | 0.44 / 0.49 / 0.46 | Three rush, four deep quarters across the field. Only one linebacker underneath. |
| Cover 6 | cover_6 | ZONE | 3 | 0 | 5 (3) | 0 | 0.59 / 0.49 / 0.44 | Three rush. Two deep quarters on the left; a deep half with a corner in the flat under it on the right. One linebacker in the short middle. |
| Tampa 2 | tampa_2 | ZONE | 2 | 0 | 6 (3) | 0 | 0.71 / 0.53 / 0.54 | Two rush, corners in the flats, two deep halves, and the middle linebacker runs back to take the deep seam. The other one stays underneath. |
| Cover 2 Sink | cover_2_sink | ZONE | 3 | 0 | 5 (2) | 0 | 0.41 / 0.50 / 0.43 | Three rush, two deep halves, a linebacker in the middle. Corners drop to ten yards under the corner routes and leave the flats alone. |
| Cloud Flats | cloud_flats | ZONE | 2 | 0 | 6 (1) | 0 | 0.75 / 0.66 / 0.39 | Two rush, four men across underneath and one in the hole behind them, one safety deep. Takes away the short stuff. |
| Zone Spy | zone_spy | ZONE | 2 | 0 | 5 (2) | 1 | 0.78 / 0.60 / 0.59 | Two rush, two flats, one in the middle, two deep halves, and a spy who goes when the quarterback runs. |
| Edge Blitz | edge_blitz | BLITZ | 4 | 3 | 1 (1) | 0 | 0.67 / 0.57 / 0.87 | Two linebackers come off the edges with two linemen inside. Man on the wideouts and the tight end, one safety deep. The back is free. |
| Cross Dog | cross_dog | BLITZ | 5 | 3 | 0 (0) | 0 | 0.44 / 0.68 / 0.63 | Five rush: two linebackers from depth through the middle behind the line. Man on the wideouts and the tight end, nobody deep and nobody on the back. |
| Fire Zone | fire_zone | BLITZ | 5 | 1 | 2 (2) | 0 | 0.42 / 0.41 / 0.59 | Five rush with two deep halves behind it and a man on the tight end. Everything else short is open if the ball gets out. |
| Goal Line Blitz | gl_blitz | GOAL LINE | 5 | 3 | 0 (0) | 0 | 0.49 / 0.47 / 0.15 | Four down linemen in the gaps and a linebacker behind them: five rush. Press man outside and on the tight end, nobody on the back. |
| Goal Line Pinch | gl_pinch | GOAL LINE | 5 | 0 | 3 (0) | 0 | 0.48 / 0.67 / 0.10 | Five across the front, one linebacker behind them. Corners sit in the flats. |
| Goal Line TE Double | gl_te_double | GOAL LINE | 3 | 5 | 0 (0) | 0 | 0.56 / 0.43 / 0.20 | Three rush, corners in the receivers' faces, a linebacker on the back, and two men on the tight end: one behind him, one in front. |
| Goal Line Spy | gl_spy | GOAL LINE | 3 | 4 | 0 (0) | 1 | 0.82 / 0.48 / 0.20 | Three rush, man on every receiver, and a spy for the quarterback who rolls out or keeps it. |
| Goal Line Edge | gl_edge | GOAL LINE | 3 | 2 | 3 (0) | 0 | 0.56 / 0.49 / 0.15 | Three rush, a linebacker set wide on each side for the toss and one in the middle. Man on the wideouts. |
| Goal Line Double | gl_double | GOAL LINE | 3 | 4 | 1 (0) | 0 | 0.22 / 0.28 / 0.30 | Three rush, two men on each wideout: one in front, one behind. One man in the short middle, nobody on the back. |

## 5. Da Bomb

File `resources/plays/offense/da_bomb.tres`, tab GUN TRIPS, in place of Deep Bomb (the first passing play removed). The tab with its card: [docs/play_audit/offense_tab_4_gun_trips.png](docs/play_audit/offense_tab_4_gun_trips.png).

| Diagram | In the game |
|---|---|
| 3 linemen, left of the receivers | Center and two guards on the ball, as in every play |
| 2 receivers on the line to the right, a gap between them | Slot at 11.2 yards, wideout at 19.9, both on the line |
| 1 receiver just behind the line, between the line and the receivers | The wing at 5.4 yards, 1.5 behind the line |
| Quarterback in the backfield | Shotgun, 7 yards deep; drops 3 more |
| (seven players) | The eighth, the back, stands beside the quarterback on the left and blocks |
| Outside receiver: go route | Straight up the field |
| Inside receiver: up 3 to 5 yards, then deep toward the left | Up 4.5 yards, then a post that ends 20 yards further left |
| Backfield receiver: short move left, then deep left under the other post | Jabs 2 yards left, releases, then a second post inside and under the first |

The same nine players' spots are used by Gun Stretch and Gun Dive (runs), Bubble Screen, Smash, Gun Levels, Gun Boot (play action), Trips Flood and Scissors, so lining up in it says nothing. There is no mirrored copy: the flip button does that.

**CPU calls** (`OffensePlay.shot_play`, `PlayCaller._shot_scale`): the play's weight is multiplied by 0.2 on an ordinary down and by up to 3 as the yards needed per down go past normal, as the clock forces the offense downfield, or as the deficit in the second half grows. Measured by `tests/play_groups_check.gd` over 3000 calls each: 0.4% of calls on first down with the score level, 9.6% on third and long, 15.3% with the half running out, 6.3% two scores behind (a second run gave 0.8, 15.2, 14.9 and 11.9%; it depends on which team has the ball). On a last-play heave it is one of the deep plays the CPU picks from.

**What it does against the defenses** (yards a snap, 40 snaps each; a turnover counts as 12 lost):

| Defense | Yards | As asked? |
|---|---|---|
| Two deep, nobody in the deep middle: Zone Spy 14.6, Zone Cover 2 11.1, Cover 6 10.7, 2 Man Under 10.0, Cloud Flats 9.2, Cover 2 Sink 6.6 | 6.6 to 14.6 | Not in the brief, but right: the posts split two safeties |
| Deep zones: Cover 3 2.9, Prevent 3.6, Tampa 2 4.3, Cover 4 5.4 | 2.9 to 5.4 | Yes, it loses |
| Quick blitzes: Mike Blitz 0.1, All-Out Blitz 0.9, Edge Blitz 3.3, Safety Blitz 3.2 | 0.1 to 3.3 | Yes, it loses (sacked on about 40% of snaps against All-Out Blitz) |
| Slow or zone blitzes: Corner Blitz 6.3, Cross Dog 6.5, Fire Zone 7.6, Zone Blitz 9.1, Overload 27.2 | 6.3 to 27.2 | It beats the ones that leave the deep middle open |
| Single-high man: Man Cover 1 0.9, Man Robber 4.2, Cover 1 Spy 5.0, Run Stuff 5.5, Man Lurk 5.6, Press Man 6.2 | 0.9 to 6.2 | **No.** It was meant to beat these |

Why not, and what I tried: against Man Cover 1 over 100 snaps the play is completed 39% of the time, turned over 16% and sacked 22%, and goes for 20 yards or more on 18% of snaps (13% against Cover 3, 9% against All-Out Blitz). So it does hit its home runs most often against man, but the average stays low: the routes need more than three seconds, the back's man rushes when the back stays in to block, and the single safety plays over the top of the deepest route with a zone wide enough to reach both posts. Flatter posts, steeper posts and a shallower second post all came out the same or worse (2.9 to 3.4 yards against Man Cover 1); the deeper drop was the one change that helped against man and hurt against the blitz, and it is in. Making it a true man-beater needs a change to how man defenders play deep routes or how far a deep safety reaches, which is game mechanics and was not touched.

## 6. Balance (Rule 4)

### Offense mix

| Kind | Plays |
|---|---|
| Inside runs | Iso Lead, FB Dive, HB Dive, Double Tight Power, Gun Dive, Goal Line Dive, Goal Line Wedge |
| Outside runs | Lead Toss, Off Tackle, Power Sweep, Gun Stretch, Goal Line Power, Goal Line Toss |
| Misdirection and draws | Counter, Gun Counter, Draw, Gun Draw |
| Quick passes | Quick Slants, Gun Stick, Gun Outs, Smash, Goal Line Flat, Goal Line Mesh |
| Intermediate | Curl Flat, Mesh, Texas, FB Wheel, Drive, Gun Levels, TE Delay, TE Corner, TE Cross, Goal Line Corner |
| Deep | Sluggo, Crossfire, Flood, TE Seam, Max Protect, Gun Verts, Dagger, Trips Flood, Scissors, Da Bomb, Hail Mary |
| Screens | HB Screen, Bubble Screen |
| Play action | PA Post, Bootleg, TE Flat, Gun Boot, Goal Line Boot, Goal Line Pop |
| Trick plays | Flea Flicker, Gun Flea Flicker |

For the CPU: 17 runs, 22 short passes, 15 deep passes (one of them the heave-only Hail Mary).

### Defense mix

| Kind | Plays |
|---|---|
| Base zones | Zone Cover 2, Cover 2 Sink, Tampa 2, Cover 3, Cover 4, Cover 6, Cloud Flats, Zone Spy |
| Man with a deep safety | Man Cover 1, Man Lurk, Cover 1 Spy, Press Man, 2 Man Under |
| Man with nobody deep | Man Robber, Run Stuff, Bracket, Double Wide |
| Zone blitzes | Zone Blitz, Fire Zone, Overload |
| Man blitzes | All-Out Blitz, Safety Blitz, Corner Blitz, Mike Blitz, Edge Blitz, Cross Dog |
| Prevent | Prevent |
| Goal line | Stuff, Man, Zone, Blitz, Pinch, TE Double, Spy, Edge, Double |

### Gaps that remain

- **No quarterback run** (sneak, keeper, option). A run play needs a runner other than the quarterback; this is a mechanic, not a play file.
- **No motion**, so no jet sweep or end around. End Around was removed because it needed its own line-up.
- **No deep pass at the goal line**, by design: there is no room.

### Flagged as unrealistic or broken

| What | Detail | Done |
|---|---|---|
| Quarterback depth gave run or pass away | 4 yards on runs, 5 on passes | Fixed: one depth per formation |
| A tight end covered up by a wideout on the line | Singleback and Heavy, right side | Fixed: that wideout stands a step off the line |
| Gun Trips: slot and wideout both on the line | By real rules the wideout covers the slot up; the diagram asks for both on the line and the game has no eligibility rule | Left as drawn |
| Men on the line | 8-man football asks for 5: every formation has 5 | Nothing to do (the 7 of the brief is the 11-man rule) |
| Routes leaving the field or players lining up in each other | None; the new check tests both | Nothing to do |
| Defenders without a job | None. A man defender always has a man: with 4 skill players there is one for each target | Nothing to do |
| Two men on one receiver while another is free, with no zone behind | None; Double Wide and Bracket cover all four, the blitzes that leave the back free say so on the card | The new check tests it |
| Man coverage against two tight ends | The corners cover the tight ends and the linebackers the backs | Left: it is "widest man", and a goal line offense has no wideouts |
| **Run Stuff does not stop the run** | 10.7 yards a run play, the third worst of the open-field defenses (after Bracket and All-Out Blitz, 11.9). Man defenders follow their blockers away from the ball | Left; its CPU fit against the run is now 0.30 (was 0.71), so the CPU stops calling it for that |
| **Overload** | 15.1 yards a short pass, 16.3 a deep one. On the last commit it gave up 16 to Quick Slants and 25 to Gun Verts, so this is not new | Left; fit 0.10 against passes |
| **Goal Line Boot** | Sacked on 39% of snaps, loses a yard a snap on average | Left |
| Flea Flicker | A pass follows the pitch-back on 13 of 30 snaps (16 of 30 on the last commit; the check wants 12) | Left; it is close to its own check's limit |
| Zone coverage is now stronger against deep passes | Gun Verts made 12.3 yards a snap on the last commit and makes 7.5 now: zone corners used to stand up to 6 yards inside the wideouts | Intended, but it is the biggest shift in balance from this change |

### Counter matrix

Every offensive play was run against every defensive play in the headless simulation (`tests/balance_matrix.gd`, CPU quarterback, the defense's memory of earlier plays off): 54 x 36 cells, 12 snaps a cell, Da Bomb 40. The number is yards a snap with a gain capped at 30 and a turnover counted as 12 yards lost. Open-field plays start on the own 25, goal line plays on the 6. With 12 snaps a single cell is good to about 4 yards either way; a play's mean over 27 defenses to about 1.

Goal line plays are set against the nine goal line defenses and the others against the 27 open-field defenses. The full grid is in the appendix.

**Every offensive play: what stops it, what it beats.**

| Offense | Tab | Mean | Stopped by (yards a snap) | Beats (yards a snap) | Comp % | Sack % | Turnover % |
|---|---|---|---|---|---|---|---|
| Iso Lead | I-Form | 8.4 | Zone Blitz (-0.8), Cloud Flats (-0.1), Prevent (0.7) | Corner Blitz (23.7), Mike Blitz (17.0), Double Wide (16.6) | 0 | 0 | 3 |
| FB Dive | I-Form | 1.6 | Zone Spy (-2.2), Overload (-2.1), Cross Dog (-1.9) | Run Stuff (12.8), Cover 1 Spy (5.9), Bracket (5.7) | 0 | 0 | 5 |
| Lead Toss | I-Form | 9.8 | Corner Blitz (-1.5), Zone Spy (1.5), Tampa 2 (1.6) | Run Stuff (23.1), Cross Dog (22.3), Bracket (18.0) | 0 | 0 | 4 |
| Quick Slants | I-Form | 7.1 | Safety Blitz (-3.9), Man Robber (0.5), Cross Dog (1.2) | Fire Zone (19.4), Overload (16.7), Press Man (12.8) | 50 | 16 | 9 |
| FB Wheel | I-Form | 4.5 | Cloud Flats (-5.1), Edge Blitz (-2.0), All-Out Blitz (-0.6) | Overload (13.9), Cover 6 (10.5), Cover 1 Spy (10.1) | 37 | 22 | 11 |
| Texas | I-Form | 7.1 | Fire Zone (-0.5), Man Robber (0.4), Cloud Flats (1.3) | Overload (21.7), Edge Blitz (12.9), Man Cover 1 (11.8) | 44 | 20 | 8 |
| PA Post | I-Form | 10.6 | Edge Blitz (-0.7), Bracket (2.5), All-Out Blitz (2.8) | Zone Cover 2 (26.1), Overload (24.9), Cover 2 Sink (19.9) | 47 | 19 | 8 |
| Sluggo | I-Form | 3.6 | Safety Blitz (-1.4), Cross Dog (-0.5), Cover 1 Spy (-0.3) | Man Lurk (13.6), Man Robber (8.3), Prevent (8.1) | 36 | 23 | 11 |
| Flea Flicker | I-Form | 6.5 | Edge Blitz (-4.3), All-Out Blitz (-2.6), 2 Man Under (2.2) | Corner Blitz (14.6), Zone Blitz (14.4), Cloud Flats (13.4) | 37 | 30 | 9 |
| Off Tackle | Singleback | 10.8 | Cloud Flats (0.5), Overload (1.2), Cover 1 Spy (2.2) | Bracket (21.6), Safety Blitz (21.5), Run Stuff (21.0) | 0 | 0 | 4 |
| Counter | Singleback | 8.2 | Overload (-2.9), Corner Blitz (-2.3), Cloud Flats (-1.5) | Fire Zone (23.0), Cross Dog (20.4), Man Cover 1 (19.5) | 0 | 0 | 5 |
| Draw | Singleback | 6.2 | Cross Dog (-1.2), Overload (-0.6), Edge Blitz (-0.2) | All-Out Blitz (15.7), Man Cover 1 (14.9), Zone Blitz (12.7) | 0 | 0 | 3 |
| Curl Flat | Singleback | 6.1 | Cloud Flats (-3.7), Cover 1 Spy (0.3), Cross Dog (0.7) | Press Man (16.0), Bracket (12.4), Overload (12.1) | 41 | 21 | 11 |
| Mesh | Singleback | 6.4 | Cloud Flats (-0.1), All-Out Blitz (1.2), Safety Blitz (1.2) | Overload (22.1), Edge Blitz (10.3), Man Robber (10.2) | 49 | 14 | 10 |
| HB Screen | Singleback | 5.3 | Edge Blitz (-4.9), Zone Blitz (-4.2), Cover 2 Sink (-2.9) | Man Cover 1 (20.2), Prevent (16.5), Overload (11.8) | 38 | 26 | 9 |
| Bootleg | Singleback | 5.4 | Safety Blitz (0.6), Edge Blitz (0.7), Zone Spy (1.8) | Double Wide (17.9), Man Lurk (8.7), 2 Man Under (8.5) | 42 | 25 | 7 |
| Crossfire | Singleback | 3.5 | Edge Blitz (-7.2), Cover 1 Spy (-2.4), All-Out Blitz (-1.8) | Run Stuff (12.8), Cross Dog (9.8), Man Lurk (8.4) | 40 | 24 | 12 |
| Flood | Singleback | 7.5 | Edge Blitz (-2.4), Cross Dog (-1.4), Safety Blitz (-0.3) | Overload (27.6), Run Stuff (16.0), Corner Blitz (15.4) | 44 | 19 | 11 |
| Double Tight Power | Heavy | 7.1 | Edge Blitz (-2.6), Zone Cover 2 (-0.9), Cloud Flats (0.8) | All-Out Blitz (16.7), Cover 3 (16.2), Cover 4 (14.1) | 0 | 0 | 7 |
| HB Dive | Heavy | 4.2 | Man Robber (-2.3), Cross Dog (-1.7), Overload (-1.5) | Run Stuff (14.2), All-Out Blitz (13.2), Bracket (13.1) | 0 | 0 | 4 |
| Power Sweep | Heavy | 10.0 | Zone Spy (-0.4), Corner Blitz (3.1), Tampa 2 (3.7) | Man Cover 1 (20.5), Fire Zone (19.4), All-Out Blitz (17.8) | 0 | 0 | 5 |
| TE Delay | Heavy | 7.3 | Mike Blitz (-2.2), Cover 4 (-0.8), Corner Blitz (1.1) | Overload (27.5), Tampa 2 (13.8), Zone Blitz (12.7) | 41 | 26 | 9 |
| TE Flat | Heavy | 7.2 | 2 Man Under (-4.0), Fire Zone (-4.0), Edge Blitz (-2.6) | Zone Blitz (19.4), Zone Cover 2 (14.8), Cover 6 (13.5) | 42 | 23 | 11 |
| TE Corner | Heavy | 7.5 | Man Lurk (1.5), Mike Blitz (1.9), Cloud Flats (2.0) | Press Man (22.1), Double Wide (18.1), Man Robber (14.8) | 43 | 16 | 8 |
| TE Cross | Heavy | 8.4 | Edge Blitz (-1.6), Zone Blitz (-1.4), 2 Man Under (0.3) | Overload (22.7), Press Man (18.9), Run Stuff (18.1) | 45 | 22 | 7 |
| TE Seam | Heavy | 7.8 | Edge Blitz (-4.7), Fire Zone (-0.4), Corner Blitz (2.1) | Overload (19.7), 2 Man Under (15.6), Press Man (15.3) | 46 | 13 | 10 |
| Max Protect | Heavy | 3.5 | Zone Spy (-2.8), Tampa 2 (-2.2), Cloud Flats (-1.4) | Man Lurk (12.7), Corner Blitz (12.3), Overload (12.1) | 30 | 28 | 10 |
| Gun Draw | Gun Spread | 4.9 | Prevent (-3.0), Cross Dog (-1.0), Mike Blitz (0.1) | Press Man (15.4), Man Robber (11.8), Zone Blitz (11.0) | 0 | 0 | 5 |
| Gun Counter | Gun Spread | 6.5 | Overload (-1.1), Cloud Flats (-0.8), Edge Blitz (-0.2) | Mike Blitz (19.3), Cross Dog (17.7), All-Out Blitz (15.6) | 0 | 0 | 3 |
| Gun Stick | Gun Spread | 6.2 | Cover 1 Spy (-2.3), Mike Blitz (-0.3), Cross Dog (0.2) | Overload (23.0), All-Out Blitz (14.2), Man Lurk (11.3) | 47 | 17 | 11 |
| Drive | Gun Spread | 5.3 | Mike Blitz (-4.9), Safety Blitz (-0.2), Bracket (0.1) | Corner Blitz (13.9), Zone Cover 2 (11.4), Cover 3 (11.0) | 40 | 20 | 9 |
| Gun Outs | Gun Spread | 3.1 | Cover 1 Spy (-2.9), Man Cover 1 (-1.3), Press Man (-0.8) | Cover 3 (10.8), Overload (7.8), Cover 2 Sink (6.9) | 45 | 19 | 13 |
| Gun Verts | Gun Spread | 7.5 | Edge Blitz (-3.6), Cross Dog (1.0), All-Out Blitz (1.5) | Overload (25.4), Cloud Flats (15.8), Run Stuff (15.3) | 47 | 16 | 12 |
| Dagger | Gun Spread | 4.4 | Zone Spy (-4.5), Edge Blitz (-4.0), Cross Dog (-2.2) | Man Cover 1 (11.7), Cover 4 (11.6), Cover 6 (9.9) | 36 | 22 | 13 |
| Gun Flea Flicker | Gun Spread | 6.9 | Fire Zone (-9.5), Edge Blitz (-5.3), Zone Blitz (-3.1) | Corner Blitz (19.0), Cloud Flats (16.1), Cover 2 Sink (14.9) | 38 | 32 | 7 |
| Hail Mary | Gun Spread | 8.0 | Safety Blitz (-1.7), All-Out Blitz (-0.8), Edge Blitz (1.0) | Overload (26.5), Cross Dog (17.6), Cover 2 Sink (17.3) | 48 | 11 | 16 |
| Gun Stretch | Gun Trips | 3.5 | Cross Dog (-2.9), Fire Zone (-1.7), Run Stuff (-1.5) | All-Out Blitz (13.5), Safety Blitz (10.1), Press Man (8.5) | 0 | 0 | 4 |
| Gun Dive | Gun Trips | 6.2 | Zone Blitz (-2.6), Fire Zone (-1.3), Tampa 2 (0.5) | Mike Blitz (19.5), 2 Man Under (18.0), Run Stuff (12.7) | 0 | 0 | 5 |
| Bubble Screen | Gun Trips | 3.8 | Zone Cover 2 (-4.2), Safety Blitz (-3.0), Cloud Flats (-2.8) | Fire Zone (16.9), Edge Blitz (15.0), Double Wide (9.8) | 28 | 29 | 10 |
| Smash | Gun Trips | 5.5 | Zone Spy (-4.6), Cover 1 Spy (-4.3), Safety Blitz (-0.8) | Overload (17.8), Cover 3 (14.3), Fire Zone (11.7) | 43 | 17 | 14 |
| Gun Levels | Gun Trips | 5.8 | Cover 1 Spy (-1.3), Prevent (0.2), Cloud Flats (1.0) | Man Cover 1 (11.5), Zone Cover 2 (11.4), Edge Blitz (10.9) | 41 | 17 | 10 |
| Gun Boot | Gun Trips | 8.7 | Edge Blitz (-3.2), All-Out Blitz (0.6), 2 Man Under (2.7) | Overload (30.0), Corner Blitz (21.1), Zone Spy (14.0) | 52 | 9 | 14 |
| Trips Flood | Gun Trips | 5.0 | Run Stuff (-4.6), Safety Blitz (-2.0), Cross Dog (0.2) | Overload (24.6), Fire Zone (15.4), Corner Blitz (9.0) | 35 | 23 | 13 |
| Scissors | Gun Trips | 5.7 | Cross Dog (-0.8), All-Out Blitz (0.4), Man Lurk (0.6) | Overload (28.2), Tampa 2 (13.2), Cover 6 (11.6) | 39 | 17 | 12 |
| Da Bomb | Gun Trips | 6.6 | Mike Blitz (0.1), Man Cover 1 (0.9), All-Out Blitz (0.9) | Overload (27.2), Zone Spy (14.6), Zone Cover 2 (11.1) | 44 | 17 | 14 |
| Goal Line Dive | Goal Line | 0.1 | Goal Line Spy (-2.7), Goal Line TE Double (-1.0), Goal Line Blitz (-0.9) | Goal Line Stuff (2.1), Goal Line Double (1.8), Goal Line Pinch (1.7) | 0 | 0 | 4 |
| Goal Line Power | Goal Line | 3.0 | Goal Line Spy (-0.8), Goal Line TE Double (0.4), Goal Line Zone (1.6) | Goal Line Double (5.6), Goal Line Stuff (5.4), Goal Line Blitz (4.5) | 0 | 0 | 3 |
| Goal Line Toss | Goal Line | 4.3 | Goal Line Edge (0.9), Goal Line Pinch (2.6), Goal Line Stuff (2.8) | Goal Line Double (6.4), Goal Line TE Double (6.1), Goal Line Man (5.7) | 0 | 0 | 2 |
| Goal Line Wedge | Goal Line | -0.7 | Goal Line Spy (-3.5), Goal Line Man (-2.1), Goal Line Stuff (-1.4) | Goal Line Pinch (0.9), Goal Line Double (0.4), Goal Line Zone (0.2) | 0 | 0 | 4 |
| Goal Line Boot | Goal Line | -0.9 | Goal Line Stuff (-5.5), Goal Line Blitz (-2.9), Goal Line Man (-2.5) | Goal Line Spy (2.2), Goal Line Double (1.5), Goal Line Zone (0.6) | 25 | 39 | 8 |
| Goal Line Corner | Goal Line | 1.2 | Goal Line Blitz (-2.8), Goal Line Stuff (-1.9), Goal Line Man (-0.5) | Goal Line Pinch (4.7), Goal Line Double (3.4), Goal Line Zone (3.3) | 36 | 22 | 6 |
| Goal Line Flat | Goal Line | 0.7 | Goal Line Pinch (-3.4), Goal Line Stuff (-3.3), Goal Line Edge (-0.8) | Goal Line Double (5.6), Goal Line Blitz (3.2), Goal Line TE Double (2.0) | 32 | 25 | 10 |
| Goal Line Pop | Goal Line | 2.3 | Goal Line Double (-0.7), Goal Line Stuff (-0.3), Goal Line Spy (1.0) | Goal Line Zone (5.9), Goal Line Blitz (4.0), Goal Line Man (3.8) | 35 | 28 | 8 |
| Goal Line Mesh | Goal Line | 1.4 | Goal Line Pinch (-5.6), Goal Line Zone (0.3), Goal Line Spy (0.3) | Goal Line Double (4.8), Goal Line Blitz (4.5), Goal Line Edge (2.5) | 43 | 22 | 8 |

**Every defensive play: what it stops, what beats it** (Hail Mary left out).

| Defense | Mean allowed | Stops (yards a snap) | Beaten by (yards a snap) |
|---|---|---|---|
| Man Cover 1 | 7.6 | Gun Outs (-1.3), FB Dive (-0.7), Da Bomb (0.9) | Power Sweep (20.5), HB Screen (20.2), Counter (19.5) |
| Man Robber | 7.4 | HB Dive (-2.3), FB Dive (-1.2), Texas (0.4) | Off Tackle (17.6), Lead Toss (15.1), TE Corner (14.8) |
| Run Stuff | 8.5 | Trips Flood (-4.6), Gun Stretch (-1.5), Draw (1.0) | Lead Toss (23.1), Off Tackle (21.0), PA Post (19.0) |
| Zone Cover 2 | 6.7 | Bubble Screen (-4.2), Double Tight Power (-0.9), Smash (-0.2) | PA Post (26.1), TE Flat (14.8), TE Cross (14.4) |
| Cover 3 | 7.3 | FB Dive (-0.4), Max Protect (0.2), Bubble Screen (0.3) | Off Tackle (20.7), Double Tight Power (16.2), Power Sweep (16.1) |
| Prevent | 5.9 | Gun Draw (-3.0), FB Dive (0.2), Gun Levels (0.2) | HB Screen (16.5), TE Corner (11.6), Power Sweep (11.4) |
| All-Out Blitz | 6.1 | Flea Flicker (-2.6), Crossfire (-1.8), FB Wheel (-0.6) | Off Tackle (19.2), Power Sweep (17.8), Double Tight Power (16.7) |
| Zone Blitz | 5.6 | HB Screen (-4.2), Gun Flea Flicker (-3.1), Gun Dive (-2.6) | TE Flat (19.4), Flea Flicker (14.4), TE Delay (12.7) |
| Corner Blitz | 7.1 | Counter (-2.3), Lead Toss (-1.5), Gun Counter (0.8) | Iso Lead (23.7), Gun Boot (21.1), Gun Flea Flicker (19.0) |
| Goal Line Stuff | -0.0 | Goal Line Boot (-5.5), Goal Line Flat (-3.3), Goal Line Corner (-1.9) | Goal Line Power (5.4), Goal Line Toss (2.8), Goal Line Dive (2.1) |
| Goal Line Man | 1.2 | Goal Line Boot (-2.5), Goal Line Wedge (-2.1), Goal Line Dive (-0.7) | Goal Line Toss (5.7), Goal Line Power (4.2), Goal Line Pop (3.8) |
| Goal Line Zone | 2.2 | Goal Line Wedge (0.2), Goal Line Mesh (0.3), Goal Line Boot (0.6) | Goal Line Pop (5.9), Goal Line Toss (5.2), Goal Line Corner (3.3) |
| 2 Man Under | 5.7 | TE Flat (-4.0), TE Cross (0.3), Dagger (0.5) | Gun Dive (18.0), TE Seam (15.6), Iso Lead (10.5) |
| Bracket | 7.7 | Max Protect (-0.1), Drive (0.1), Gun Outs (0.1) | Off Tackle (21.6), Counter (18.0), Lead Toss (18.0) |
| Cover 1 Spy | 4.0 | Smash (-4.3), Gun Outs (-2.9), Crossfire (-2.4) | PA Post (14.0), Flood (13.4), Gun Flea Flicker (12.3) |
| Safety Blitz | 4.6 | Quick Slants (-3.9), Bubble Screen (-3.0), Trips Flood (-2.0) | Off Tackle (21.5), Power Sweep (13.5), Lead Toss (12.8) |
| Mike Blitz | 5.4 | Drive (-4.9), TE Delay (-2.2), Gun Outs (-0.7) | Gun Dive (19.5), Gun Counter (19.3), Iso Lead (17.0) |
| Overload | 11.6 | Counter (-2.9), FB Dive (-2.1), HB Dive (-1.5) | Gun Boot (30.0), Scissors (28.2), Flood (27.6) |
| Press Man | 8.5 | Gun Outs (-0.8), FB Dive (-0.6), Dagger (-0.2) | TE Corner (22.1), TE Cross (18.9), Curl Flat (16.0) |
| Double Wide | 7.0 | HB Screen (-0.3), Gun Stretch (1.4), Mesh (1.9) | TE Corner (18.1), Bootleg (17.9), Iso Lead (16.6) |
| Man Lurk | 6.2 | Gun Stretch (-0.6), Gun Outs (0.4), Scissors (0.6) | PA Post (15.5), Lead Toss (13.8), Sluggo (13.6) |
| Cover 4 | 7.0 | TE Delay (-0.8), Draw (1.4), FB Dive (1.7) | Double Tight Power (14.1), Iso Lead (12.8), Gun Flea Flicker (12.3) |
| Cover 6 | 6.2 | Max Protect (0.8), Quick Slants (1.3), Bubble Screen (1.8) | TE Flat (13.5), TE Cross (12.6), Scissors (11.6) |
| Tampa 2 | 4.6 | Max Protect (-2.2), Counter (-0.9), FB Dive (-0.1) | TE Delay (13.8), Scissors (13.2), TE Seam (10.1) |
| Cover 2 Sink | 7.3 | HB Screen (-2.9), Drive (0.2), FB Wheel (1.5) | PA Post (19.9), Gun Flea Flicker (14.9), Gun Verts (13.5) |
| Cloud Flats | 4.4 | FB Wheel (-5.1), Curl Flat (-3.7), Bubble Screen (-2.8) | Gun Flea Flicker (16.1), Gun Verts (15.8), Flood (14.4) |
| Zone Spy | 3.5 | Smash (-4.6), Dagger (-4.5), Max Protect (-2.8) | Da Bomb (14.6), Gun Boot (14.0), Texas (9.4) |
| Edge Blitz | 2.7 | Crossfire (-7.2), Gun Flea Flicker (-5.3), HB Screen (-4.9) | Bubble Screen (15.0), Texas (12.9), Gun Levels (10.9) |
| Cross Dog | 4.7 | Gun Stretch (-2.9), Dagger (-2.2), FB Dive (-1.9) | Lead Toss (22.3), Counter (20.4), Gun Counter (17.7) |
| Fire Zone | 6.9 | Gun Flea Flicker (-9.5), TE Flat (-4.0), Gun Stretch (-1.7) | Counter (23.0), Power Sweep (19.4), Quick Slants (19.4) |
| Goal Line Blitz | 1.4 | Goal Line Boot (-2.9), Goal Line Corner (-2.8), Goal Line Dive (-0.9) | Goal Line Mesh (4.5), Goal Line Power (4.5), Goal Line Pop (4.0) |
| Goal Line Pinch | 0.5 | Goal Line Mesh (-5.6), Goal Line Flat (-3.4), Goal Line Boot (-1.0) | Goal Line Corner (4.7), Goal Line Toss (2.6), Goal Line Pop (2.4) |
| Goal Line TE Double | 1.5 | Goal Line Dive (-1.0), Goal Line Wedge (-0.3), Goal Line Boot (-0.1) | Goal Line Toss (6.1), Goal Line Pop (3.2), Goal Line Mesh (2.1) |
| Goal Line Spy | 0.4 | Goal Line Wedge (-3.5), Goal Line Dive (-2.7), Goal Line Power (-0.8) | Goal Line Toss (5.3), Goal Line Boot (2.2), Goal Line Corner (2.1) |
| Goal Line Edge | 1.1 | Goal Line Flat (-0.8), Goal Line Boot (-0.4), Goal Line Dive (-0.0) | Goal Line Power (4.2), Goal Line Mesh (2.5), Goal Line Corner (2.0) |
| Goal Line Double | 3.2 | Goal Line Pop (-0.7), Goal Line Wedge (0.4), Goal Line Boot (1.5) | Goal Line Toss (6.4), Goal Line Flat (5.6), Goal Line Power (5.6) |

Every open-field play has at least one defense that holds it to 2 yards or less and one it makes 8 or more against; every open-field defense has a play it holds to 2 or less and one that makes 8 or more against it. At the goal line, where 6 yards is a touchdown, every play has a defense that holds it under a yard and every defense gives up 2 or more to something.

The CPU's `run_fit`, `short_fit` and `deep_fit` of each defense are now set from these numbers: 0.5 for the average defense of its package against that kind of play, 0.15 more for every standard deviation fewer yards it gives up.

## 7. Before and after

### Offensive plays removed (14)

| Play | Why |
|---|---|
| Deep Bomb | The first passing play to go: go routes and a man up the middle, the same idea as Gun Verts. **Replaced by Da Bomb** |
| HB Toss | Mirror image of Lead Toss (0.8 yards apart) |
| Crack Toss | Lead Toss again with the wideout lined up tight, which announced it |
| FB Belly | FB Dive one gap over, with a wideout 5 yards from the ball as the tell |
| End Around | Needed its wideout 3.5 yards deep and 4 from the ball: a line-up no other play had |
| Wildcat Jet, Wildcat Pass | The quarterback split wide and the back taking the snap: two line-ups of their own, each used by one play |
| HB Slot Out | The back in the slot (own line-up); its slants are in Quick Slants |
| Mismatch Go | The back split wide (own line-up) |
| Gun Empty Slants | Empty backfield (own line-up), slants again |
| Goal Line Fade, Goal Line Empty, Goal Line Rub | Three different spread line-ups at the goal line, one play each |
| Goal Line PA | Same corner route as Goal Line Corner behind the same fake as Goal Line Boot |

### Offensive plays added (14)

| Play | Formation | What it adds |
|---|---|---|
| Da Bomb | Gun Trips | The home-run shot (section 5) |
| Scissors | Gun Trips | Post and corner crossing: beats quarters and man |
| Bubble Screen | Gun Trips | The receiver screen the book did not have |
| Gun Boot | Gun Trips | Play action away from the three receivers: punishes a defense that slides to them |
| Gun Dive | Gun Trips | A quick inside run, so three wide on one side is not a pass tell |
| Gun Counter | Gun Spread | Misdirection run from the shotgun |
| Gun Outs | Gun Spread | Quick outs: the answer to soft corners, which nothing else attacked |
| TE Corner | Heavy | Corner route behind a slant |
| TE Cross | Heavy | A deep crosser from a run formation |
| Max Protect | Heavy | Seven blockers and one deep route: the answer to an all-out blitz |
| Goal Line Wedge | Goal Line | Fullback carries; the back's fake is the toss |
| Goal Line Flat | Goal Line | The quick throw against a pinched front |
| Goal Line Pop | Goal Line | Play action over the linebackers who come up |
| Goal Line Mesh | Goal Line | Tight ends crossing: the rub against man coverage |

### Offensive plays kept and changed (40)

Every kept play was moved onto its formation's spots, and routes that started from the old spots were redrawn to end where they did. Beyond that:

| Play | Change |
|---|---|
| All under-center passes | Quarterback starts at 4 yards like on a run (was 5) and drops a yard further |
| HB Dive, Power Sweep | Moved to Heavy (two tight ends) |
| Off Tackle | Now runs outside the tight end; Double Tight Power keeps the path off the guard |
| FB Wheel | The wheel goes to the right, where the fullback lines up |
| Quick Slants, Texas, Sluggo, Flea Flicker, PA Post | Now from the I: the fullback has the job the tight end or second back had |
| Mesh, Curl Flat, HB Screen, Crossfire | Tight end on the right in all of them (was left or right by play) |
| Bootleg | The tight end is now the man in the flat in front of the quarterback |
| Flood | Rebuilt on the tight end: wideout deep, tight end to the sideline, back in the flat |
| Draw | The back starts from his normal spot, not a yard deeper |
| TE Delay, TE Flat, TE Seam | Two tight ends: the second one has the route a wideout had |
| Gun Stick, Drive, Dagger, Gun Verts, Gun Draw, Gun Flea Flicker, Hail Mary | All from Gun Spread (wideout each side, slot left, back right of the quarterback) |
| Smash, Gun Levels, Trips Flood (was Gun Trips Flood), Gun Stretch | All from Gun Trips; the back is beside the quarterback and the tight end is the wing |
| Goal Line Dive, Power, Toss, Boot, Corner | Fullback on one spot in all of them (he was on four) |
| Singleback and Heavy | The wideout outside a tight end stands a step off the line, so the tight end is not covered up |

### Defense

| Play | Change | Why |
|---|---|---|
| All 36 | Every defender has an alignment rule (section 4) | Rule 3 |
| All man coverages | Targets mean widest left, widest right, back, the fourth man | Corners on wideouts whatever the offense's play order |
| Every defender on the back (target 2) | Rushes when the back stays in to block, as the tight end's man already did | The back is now always target 2, also when he blocks; before, a blocker dropped to the end of the order and got the rushing defender |
| Seven two-high and eight one-high coverages | Safeties start from two shared shells | Disguise |
| Overload, Zone Spy, Corner Blitz, Cover 6, Cover 3, Tampa 2, Prevent | `strength_side` set | The CPU puts them on the right side of the formation |
| Man Robber | Robber at 9 yards (was 7) with a wider zone | Was Run Stuff with a deeper safety |
| All-Out Blitz | The linebacker comes from 3 yards off the left edge (was 2 yards deep in the gap) | Was Goal Line Man |
| Cross Dog | The two linebackers start 4.5 yards deep | Was Goal Line Blitz |
| Goal Line Press | **Removed**, replaced by **Goal Line TE Double**: press corners, a linebacker on the back, two men on the tight end | Was Run Stuff squeezed up; nothing at the goal line doubled the tight end, who is the main target there |
| CPU fit values | Measured again from the matrix in section 6 (the deep fit of the goal line plays is unchanged: there is no deep goal line pass to measure it with) | The CPU's counters should follow what the plays now do |

### Code

| File | Change |
|---|---|
| `scripts/defense_aligner.gd` | New: reads the formation, orders the man targets, places the defenders, decides the CPU's flip |
| `scripts/play_controller.gd` | `line_up` asks the aligner for the defense's spots and man targets |
| `scripts/data/defense_assignment.gd`, `defense_play.gd` | `align`, `strength_side` |
| `scripts/data/offense_play.gd` | Tabs are formations; `shot_play` |
| `scripts/play_caller.gd` | Shot plays by situation |
| `scripts/state/play_select_state.gd` | CPU flip by formation |
| `tools/gen_offense_plays.py` | New: writes the offensive plays and the playbook from one table |
| `tests/playbook_rules_check.gd`, `tests/playbook_probe.gd`, `tests/play_audit_dump.gd` | New: the automated check, its measures, and the dump this report is built from |
| `tests/play_groups_check.gd`, `balance_matrix.gd`, `playbook_gallery.gd`, `wave_gallery.gd` | Tab names, Da Bomb's calls, `tab=` filter, defensive line-up shots |

## 8. Checks run

Godot 4.7.2, headless, on the final state of the files.

| Check | Result |
|---|---|
| `--import` | No script errors |
| `tests/playbook_rules_check.gd` (new) | **Passed**: 54 plays in 6 formations; 36 defensive plays lined up against 12 formations both ways round, 864 line-ups |
| The same check with three rules broken on purpose (a wideout moved in Mesh, Gun Dive given Gun Stretch's path, a Cover 3 corner set to a fixed spot) | **Failed** as it should, naming each one; files restored |
| `tests/play_groups_check.gd` | **Passed**: 9 plays on every tab, one heave-only play, Da Bomb's calls by situation |
| `tests/toss_check.gd` | **Passed**: the ball changes hands without a jump on all 17 run plays |
| `tests/flea_flicker_check.gd` | **Passed** |
| `tests/coverage_check.gd` | **Passed** |
| `tests/smoke_test.gd -- games=2` | **Passed**: two full CPU games, no script errors |
| `tests/balance_matrix.gd` | Every one of the 1944 pairings ran (section 6) |
| `tests/situation_check.gd -- plays=60` | **Failed** on 2 points, see below |

`situation_check.gd`:

- "neutral mix moved" fails on the last commit as well. The test expects 30% runs and 30% deep passes on a neutral down; the home team's roster leans the calls to short passes (run 0.99, short 1.27, deep 0.79), which gives 30 / 49 / 21.
- "heaves were aimed only 22.1 yd downfield on average" (wanted 25) is new. It was 26.2 on the last commit and 27.6 with the new playbooks before the defenses' fit values were measured again. With the measured values the CPU defense calls a blitz on the last play (Edge Blitz and All-Out Blitz give up the least to deep passes), and a rushed quarterback throws shorter. Either the fit values stay and the test's limit comes down, or the last play gets a rule of its own (Prevent); I left it for you to choose.
- "defense did not play the run against a team killing the clock" failed on the last commit and passes now.

Not run: the tests that have nothing to do with plays (booth, stadium, season, menus), and nobody has played the new book by hand. The play-select screen was only looked at in the screenshots in `docs/play_audit/` (all six offense tabs, the four defense tabs, and Cover 3 and Zone Cover 2 lined up against Gun Trips; the kickoff banner is in the way in the last two).

### Running it again

```
godot --headless --path . --script res://tests/playbook_rules_check.gd
godot --headless --path . --script res://tests/play_audit_dump.gd -- lineups
godot --headless --fixed-fps 60 --path . --script res://tests/balance_matrix.gd -- mode=matrix snaps=12 "tab=gun trips"
godot --headless --fixed-fps 60 --path . --script res://tests/balance_matrix.gd -- mode=matrix snaps=40 "off=da bomb" "def=cover 3" detail
python tools/gen_offense_plays.py
```

The rules check fails when a formation has fewer than 4 plays or no run or no pass, when a formation is on two tabs, when two plays (offense or defense) are within 2.5 yards of each other as drawn or mirrored, when a zone defender has a fixed spot or a defender with an alignment rule does not move between formations, when a corner or a linebacker who could cover a split receiver leaves him alone, when two defenders stand in each other, when a man defender has no man, when a receiver is doubled while another is free with no zone behind, and when a route leaves the field.

## Appendix: the full matrix

Value per snap (yards, capped at 30, a turnover counts as 12 lost), 12 snaps a cell (Da Bomb 40). The first 45 rows are from the own 25; the goal line rows from the 6.

Columns: D1 Man Cover 1, D2 Man Robber, D3 Run Stuff, D4 Zone Cover 2, D5 Cover 3, D6 Prevent, D7 All-Out Blitz, D8 Zone Blitz, D9 Corner Blitz, D10 Goal Line Stuff, D11 Goal Line Man, D12 Goal Line Zone, D13 2 Man Under, D14 Bracket, D15 Cover 1 Spy, D16 Safety Blitz, D17 Mike Blitz, D18 Overload, D19 Press Man, D20 Double Wide, D21 Man Lurk, D22 Cover 4, D23 Cover 6, D24 Tampa 2, D25 Cover 2 Sink, D26 Cloud Flats, D27 Zone Spy, D28 Edge Blitz, D29 Cross Dog, D30 Fire Zone, D31 Goal Line Blitz, D32 Goal Line Pinch, D33 Goal Line TE Double, D34 Goal Line Spy, D35 Goal Line Edge, D36 Goal Line Double.

| Offense \ Defense | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 | D9 | D10 | D11 | D12 | D13 | D14 | D15 | D16 | D17 | D18 | D19 | D20 | D21 | D22 | D23 | D24 | D25 | D26 | D27 | D28 | D29 | D30 | D31 | D32 | D33 | D34 | D35 | D36 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Iso Lead | 14 | 14 | 15 | 3 | 1 | 1 | 11 | -1 | 24 | 19 | 23 | 3 | 10 | 10 | 6 | 9 | 17 | 5 | 8 | 17 | 8 | 13 | 5 | 1 | 9 | -0 | 1 | 7 | 11 | 8 | 11 | -4 | 21 | 22 | 10 | 14 |
| FB Dive | -1 | -1 | 13 | 0 | -0 | 0 | 1 | 2 | 1 | 0 | 5 | -1 | 3 | 6 | 6 | 1 | 2 | -2 | -1 | 2 | 3 | 2 | 3 | -0 | 3 | -1 | -2 | 4 | -2 | 2 | 3 | 4 | 4 | 2 | 0 | 4 |
| Lead Toss | 10 | 15 | 23 | 5 | 14 | 7 | 10 | 10 | -2 | 17 | 19 | 7 | 8 | 18 | 3 | 13 | 10 | 4 | 15 | 8 | 14 | 10 | 5 | 2 | 13 | 4 | 2 | 9 | 22 | 12 | 22 | 4 | 13 | 12 | 13 | 10 |
| Quick Slants | 7 | 0 | 6 | 4 | 8 | 8 | 2 | 7 | 12 | 3 | 5 | 12 | 3 | 9 | 9 | -4 | 7 | 17 | 13 | 5 | 5 | 6 | 1 | 10 | 12 | 6 | 8 | 10 | 1 | 19 | 9 | 4 | 14 | 12 | 5 | 5 |
| FB Wheel | 3 | 2 | 9 | 7 | 4 | 6 | -1 | -1 | 6 | -1 | 0 | 8 | 1 | 5 | 10 | 3 | 7 | 14 | 8 | 4 | 6 | 5 | 10 | 5 | 2 | -5 | 4 | -2 | 1 | 7 | -0 | 0 | 10 | 0 | 3 | 11 |
| Texas | 12 | 0 | 8 | 6 | 4 | 5 | 6 | 11 | 5 | -4 | 6 | 20 | 6 | 7 | 4 | 6 | 5 | 22 | 5 | 10 | 10 | 11 | 7 | 5 | 10 | 1 | 9 | 13 | 4 | -0 | 8 | 3 | 5 | 8 | -1 | 2 |
| PA Post | 8 | 15 | 19 | 26 | 7 | 8 | 3 | 10 | 12 | 3 | 11 | 19 | 4 | 2 | 14 | 8 | 8 | 25 | 14 | 3 | 16 | 5 | 9 | 5 | 20 | 11 | 8 | -1 | 11 | 15 | 21 | 14 | 10 | 7 | 9 | 3 |
| Sluggo | 3 | 8 | 3 | 4 | 5 | 8 | 3 | -0 | 1 | 5 | -2 | 6 | 8 | 4 | -0 | -1 | 0 | 0 | 7 | 6 | 14 | 5 | 7 | 1 | 5 | 1 | 0 | 0 | -0 | 6 | 6 | 4 | 9 | 9 | 6 | 3 |
| Flea Flicker | 4 | 12 | 7 | 8 | 10 | 6 | -3 | 14 | 15 | -1 | -0 | 19 | 2 | 7 | 5 | 7 | 2 | 5 | 9 | 4 | 5 | 8 | 9 | 7 | 9 | 13 | 7 | -4 | 3 | 3 | 1 | 1 | 13 | 3 | 13 | 6 |
| Off Tackle | 10 | 18 | 21 | 2 | 21 | 10 | 19 | 6 | 10 | 18 | 14 | 12 | 10 | 22 | 2 | 22 | 15 | 1 | 13 | 16 | 12 | 11 | 3 | 6 | 6 | 0 | 7 | 9 | 12 | 10 | 21 | 10 | 12 | 14 | 18 | 19 |
| Counter | 20 | 11 | 12 | 4 | 11 | 2 | 15 | 6 | -2 | 15 | 12 | 3 | 5 | 18 | 6 | 8 | 6 | -3 | 15 | 15 | 5 | 12 | 4 | -1 | 9 | -2 | 3 | -0 | 20 | 23 | 19 | 27 | 15 | 8 | 19 | 12 |
| Draw | 15 | 10 | 1 | 9 | 6 | 10 | 16 | 13 | 5 | 14 | 12 | 16 | 2 | 12 | 2 | 4 | 4 | -1 | 5 | 11 | 12 | 1 | 7 | 6 | 9 | 2 | 0 | -0 | -1 | 6 | 14 | 12 | 5 | 2 | 8 | 10 |
| Curl Flat | 6 | 10 | 11 | 9 | 6 | 5 | 2 | 5 | 3 | 6 | 8 | 6 | 7 | 12 | 0 | 3 | 5 | 12 | 16 | 3 | 4 | 8 | 6 | 10 | 7 | -4 | 4 | 5 | 1 | 9 | 8 | 7 | 11 | 8 | 2 | 7 |
| Mesh | 2 | 10 | 5 | 4 | 10 | 10 | 1 | 8 | 8 | 8 | 7 | 8 | 9 | 2 | 6 | 1 | 5 | 22 | 9 | 2 | 6 | 9 | 9 | 4 | 5 | -0 | 3 | 10 | 4 | 9 | 18 | 8 | 3 | 4 | 5 | 4 |
| HB Screen | 20 | 7 | 4 | 8 | 6 | 16 | 7 | -4 | 6 | 3 | 7 | 14 | 5 | 4 | 7 | 5 | 9 | 12 | 10 | -0 | 3 | 5 | 2 | 4 | -3 | 4 | 1 | -5 | 6 | 3 | 2 | 7 | 5 | 3 | 14 | -1 |
| Bootleg | 2 | 5 | 5 | 3 | 3 | 8 | 8 | 8 | 7 | 2 | 6 | 8 | 8 | 8 | 3 | 1 | 5 | 3 | 6 | 18 | 9 | 5 | 5 | 3 | 5 | 3 | 2 | 1 | 3 | 8 | 10 | 13 | 8 | 6 | 12 | 16 |
| Crossfire | 5 | 7 | 13 | 7 | 2 | 1 | -2 | 0 | 4 | -0 | 4 | 0 | 8 | 4 | -2 | -2 | 8 | 3 | 3 | 2 | 8 | 5 | 4 | 3 | 3 | 4 | -0 | -7 | 10 | 4 | 8 | -4 | 10 | 9 | 4 | 13 |
| Flood | 13 | 14 | 16 | 12 | 3 | 1 | 5 | 5 | 15 | 6 | 3 | 17 | 5 | 8 | 13 | -0 | 5 | 28 | 12 | 5 | 3 | 6 | 6 | 4 | 5 | 14 | 4 | -2 | -1 | 5 | 8 | 2 | 11 | 3 | 10 | 17 |
| Double Tight Power | 3 | 10 | 11 | -1 | 16 | 10 | 17 | 8 | 1 | 17 | 21 | 7 | 9 | 14 | 4 | 13 | 13 | 4 | 8 | 12 | 4 | 14 | 6 | 1 | 3 | 1 | 3 | -3 | 3 | 6 | 16 | 12 | 12 | 12 | 10 | 4 |
| HB Dive | 2 | -2 | 14 | 4 | 2 | 5 | 13 | 3 | 1 | 9 | 16 | 3 | 6 | 13 | -0 | 6 | 5 | -2 | 2 | 2 | 3 | 8 | 3 | 2 | 12 | 3 | 0 | 1 | -2 | 8 | 10 | 3 | 11 | 4 | 11 | 9 |
| Power Sweep | 20 | 13 | 8 | 6 | 16 | 11 | 18 | 11 | 3 | 16 | 13 | 7 | 6 | 12 | 8 | 14 | 9 | 8 | 8 | 12 | 5 | 9 | 5 | 4 | 11 | 7 | -0 | 10 | 17 | 19 | 14 | 11 | 15 | 14 | 6 | 6 |
| TE Delay | 6 | 6 | 5 | 6 | 6 | 8 | 10 | 13 | 1 | 6 | 8 | 16 | 9 | 3 | 9 | 10 | -2 | 28 | 9 | 4 | 7 | -1 | 4 | 14 | 9 | 12 | 7 | 3 | 2 | 10 | -1 | 10 | 14 | -2 | 4 | 7 |
| TE Flat | 9 | 7 | 8 | 15 | 13 | 9 | 5 | 19 | 8 | 5 | -4 | 18 | -4 | 13 | 7 | 7 | 7 | 5 | 6 | 7 | 7 | 7 | 14 | 8 | 10 | 11 | 5 | -3 | 1 | -4 | -4 | 17 | 9 | 10 | 12 | 9 |
| TE Corner | 13 | 15 | 8 | 6 | 6 | 12 | 11 | 5 | 10 | 1 | 5 | 19 | 3 | 14 | 2 | 2 | 2 | 12 | 22 | 18 | 2 | 3 | 3 | 2 | 6 | 2 | 6 | 2 | 4 | 8 | 1 | 18 | 25 | 7 | 13 | 6 |
| TE Cross | 4 | 9 | 18 | 14 | 4 | 9 | 3 | -1 | 14 | 4 | -2 | 17 | 0 | 8 | 1 | 6 | 2 | 23 | 19 | 4 | 10 | 11 | 13 | 9 | 13 | 12 | 5 | -2 | 7 | 12 | 12 | -3 | 10 | 5 | 7 | 7 |
| TE Seam | 10 | 6 | 9 | 12 | 3 | 8 | 12 | 5 | 2 | 6 | 8 | 20 | 16 | 12 | 2 | 11 | 3 | 20 | 15 | 6 | 10 | 10 | 7 | 10 | 3 | 10 | 9 | -5 | 5 | -0 | 10 | 9 | 14 | 1 | 16 | 19 |
| Max Protect | 5 | 4 | 7 | 0 | 0 | 3 | 1 | 1 | 12 | 0 | 12 | 8 | 9 | -0 | 2 | 4 | 0 | 12 | 5 | 7 | 13 | 4 | 1 | -2 | 3 | -1 | -3 | 4 | 4 | -1 | 11 | -3 | 12 | 11 | 18 | 10 |
| Gun Draw | 5 | 12 | 1 | 5 | 8 | -3 | 6 | 11 | 6 | 11 | 10 | 17 | 4 | 8 | 1 | 1 | 0 | 2 | 15 | 10 | 2 | 9 | 8 | 5 | 10 | 1 | 1 | 0 | -1 | 3 | -1 | -2 | 5 | 3 | 8 | 8 |
| Gun Counter | 4 | 3 | 9 | 2 | 13 | 8 | 16 | 11 | 1 | 2 | 4 | -2 | 4 | 8 | 5 | 2 | 19 | -1 | 4 | 4 | 8 | 6 | 6 | 1 | 11 | -1 | 0 | -0 | 18 | 15 | 0 | 1 | 4 | 4 | 12 | 12 |
| Gun Stick | 3 | 6 | 8 | 7 | 10 | 7 | 14 | 3 | 7 | -1 | -4 | 12 | 6 | 3 | -2 | 4 | -0 | 23 | 11 | 4 | 11 | 7 | 2 | 5 | 5 | 4 | 8 | 10 | 0 | 1 | 5 | 7 | 18 | 11 | 9 | 9 |
| Drive | 5 | 9 | 4 | 11 | 11 | 6 | 1 | 4 | 14 | 7 | -4 | 8 | 7 | 0 | 0 | -0 | -5 | 11 | 8 | 8 | 5 | 3 | 6 | 4 | 0 | 10 | 4 | 8 | 2 | 7 | 3 | 6 | 5 | -1 | 6 | 6 |
| Gun Outs | -1 | 7 | 4 | 4 | 11 | 5 | 3 | 1 | 1 | 7 | 6 | 18 | 6 | 0 | -3 | 1 | -1 | 8 | -1 | 4 | 0 | 3 | 5 | 6 | 7 | 2 | 2 | 4 | 1 | 4 | 4 | 9 | 0 | 0 | 15 | 14 |
| Gun Verts | 8 | 10 | 15 | 12 | 10 | 7 | 2 | 4 | 5 | -1 | -0 | 18 | 6 | 10 | 2 | 6 | 2 | 25 | 9 | 5 | 6 | 6 | 5 | 7 | 14 | 16 | 8 | -4 | 1 | 7 | 3 | 5 | 8 | 1 | 20 | 13 |
| Dagger | 12 | 2 | 3 | 10 | 10 | 3 | 4 | 8 | 4 | -0 | 4 | 13 | 0 | 3 | 4 | -0 | 6 | 8 | -0 | 8 | 6 | 12 | 10 | 6 | 3 | 5 | -4 | -4 | -2 | 4 | 2 | 12 | -0 | 2 | 9 | 14 |
| Gun Flea Flicker | 13 | 6 | 9 | 11 | 12 | 5 | 2 | -3 | 19 | 2 | -9 | 21 | 2 | 7 | 12 | 4 | 6 | 4 | 14 | 2 | 3 | 12 | 7 | 5 | 15 | 16 | 4 | -5 | 10 | -10 | -5 | -11 | 13 | 10 | 16 | 8 |
| Hail Mary | 4 | 15 | 9 | 10 | 11 | 7 | -1 | 8 | 7 | 5 | -4 | 17 | 4 | 10 | 8 | -2 | 2 | 26 | 10 | 3 | 3 | 4 | 5 | 10 | 17 | 6 | 11 | 1 | 18 | 6 | 4 | 18 | 12 | 10 | 18 | 16 |
| Gun Stretch | 4 | 5 | -2 | 4 | 2 | 1 | 14 | 0 | 4 | 6 | -3 | -1 | 5 | 5 | 6 | 10 | 6 | 5 | 8 | 1 | -1 | 6 | 3 | 5 | 6 | 0 | -1 | 2 | -3 | -2 | -1 | -2 | 5 | 7 | 12 | 1 |
| Gun Dive | 5 | 2 | 13 | 6 | 4 | 1 | 2 | -3 | 5 | 9 | 5 | 2 | 18 | 10 | 12 | 7 | 20 | 5 | 3 | 11 | 9 | 4 | 5 | 0 | 10 | 6 | 2 | 5 | 8 | -1 | 14 | 2 | 12 | 7 | 14 | 29 |
| Bubble Screen | 5 | 4 | 6 | -4 | 0 | 1 | 4 | 4 | 6 | 11 | 9 | 4 | 3 | 5 | -1 | -3 | 1 | 8 | 2 | 10 | 3 | 6 | 2 | 2 | 5 | -3 | 0 | 15 | 6 | 17 | 11 | -2 | 3 | 2 | 1 | 13 |
| Smash | 11 | 7 | 3 | -0 | 14 | 10 | 2 | 6 | 3 | 9 | 4 | 8 | 8 | 2 | -4 | -1 | 2 | 18 | 3 | 9 | 2 | 11 | 7 | 0 | 11 | 5 | -5 | 10 | -0 | 12 | 12 | 4 | 12 | 10 | -1 | 12 |
| Gun Levels | 12 | 10 | 6 | 11 | 9 | 0 | 2 | 9 | 10 | 8 | 4 | 8 | 5 | 8 | -1 | 1 | 8 | 5 | 9 | 4 | 2 | 7 | 10 | 4 | 2 | 1 | 5 | 11 | 5 | 2 | 13 | 9 | 6 | 3 | 12 | 10 |
| Gun Boot | 13 | 8 | 8 | 13 | 3 | 9 | 1 | 7 | 21 | 12 | 10 | 13 | 3 | 9 | 6 | 8 | 3 | 30 | 12 | 8 | 3 | 8 | 6 | 7 | 6 | 6 | 14 | -3 | 12 | 13 | 7 | 28 | 12 | 0 | 10 | 12 |
| Trips Flood | 3 | 2 | -5 | 5 | 5 | 5 | 6 | 1 | 9 | 2 | -2 | 14 | 2 | 7 | 2 | -2 | 5 | 25 | 4 | 6 | 4 | 6 | 7 | 4 | 6 | 4 | 6 | 2 | 0 | 15 | -1 | 16 | 6 | 1 | 11 | 18 |
| Scissors | 4 | 5 | 5 | 2 | 6 | 4 | 0 | 10 | 6 | 10 | -6 | 12 | 2 | 6 | 2 | 5 | 5 | 28 | 4 | 5 | 1 | 5 | 12 | 13 | 6 | 6 | 3 | 8 | -1 | 1 | -3 | 16 | 7 | -0 | 17 | 25 |
| Da Bomb | 1 | 4 | 6 | 11 | 3 | 4 | 1 | 9 | 6 | 4 | 3 | 6 | 10 | 3 | 5 | 3 | 0 | 27 | 6 | 6 | 6 | 5 | 11 | 4 | 7 | 9 | 15 | 3 | 6 | 8 | 4 | 16 | 3 | 9 | 12 | 13 |
| Goal Line Dive | 2 | -0 | 2 | -0 | 4 | 4 | 3 | 2 | 0 | 2 | -1 | 1 | 2 | 3 | -1 | 2 | -2 | -0 | 1 | 0 | -1 | 4 | -0 | -0 | 3 | 0 | -1 | -1 | 1 | -0 | -1 | 2 | -1 | -3 | -0 | 2 |
| Goal Line Power | 4 | 3 | 6 | 1 | 4 | 5 | 5 | 4 | 1 | 5 | 4 | 2 | 4 | 3 | 4 | 3 | 6 | -2 | 2 | 4 | 4 | 5 | 2 | 5 | 4 | 2 | 1 | 1 | 3 | 0 | 4 | 2 | 0 | -1 | 4 | 6 |
| Goal Line Toss | 6 | 5 | 3 | 3 | 6 | 5 | 5 | 3 | -0 | 3 | 6 | 5 | 5 | 6 | 5 | 3 | 5 | -1 | 4 | 2 | 4 | 5 | 3 | 0 | 2 | -1 | 0 | 2 | 2 | 3 | 4 | 3 | 6 | 5 | 1 | 6 |
| Goal Line Wedge | -2 | -1 | -2 | -0 | 2 | 0 | -1 | 1 | -2 | -1 | -2 | 0 | 1 | -2 | -1 | -2 | -2 | -3 | 1 | 1 | -1 | 3 | 0 | 1 | 2 | -3 | -1 | 0 | -2 | -0 | -0 | 1 | -0 | -4 | 0 | 0 |
| Goal Line Boot | 3 | 2 | 2 | 1 | 1 | 2 | -2 | -2 | -3 | -6 | -2 | 1 | -3 | 0 | -1 | -0 | -2 | -4 | 1 | -2 | 1 | 0 | 2 | 1 | 2 | 2 | -0 | -3 | 0 | -2 | -3 | -1 | -0 | 2 | -0 | 2 |
| Goal Line Corner | 6 | 3 | 4 | 2 | 3 | 1 | 0 | 5 | 2 | -2 | -0 | 3 | 3 | 4 | -0 | 3 | -2 | 6 | 3 | 1 | -0 | 5 | 1 | 5 | -0 | 1 | 1 | 0 | -3 | 2 | -3 | 5 | 1 | 2 | 2 | 3 |
| Goal Line Flat | -1 | 3 | 4 | 5 | 6 | 2 | -3 | -6 | 2 | -3 | 1 | 2 | 4 | 1 | -2 | -2 | 5 | 3 | 3 | 5 | 0 | 3 | -2 | 5 | 6 | 2 | -0 | -0 | -6 | -4 | 3 | -3 | 2 | -0 | -1 | 6 |
| Goal Line Pop | 1 | 1 | 2 | 2 | 4 | 4 | 0 | -2 | -1 | -0 | 4 | 6 | 3 | 4 | 2 | 1 | 2 | -3 | 3 | 2 | 1 | 2 | 0 | 2 | 1 | 0 | 4 | -3 | -0 | 2 | 4 | 2 | 3 | 1 | 2 | -1 |
| Goal Line Mesh | 4 | -0 | 3 | 4 | 4 | -2 | -2 | -5 | -1 | 2 | 2 | 0 | -0 | 4 | -5 | -1 | 1 | -4 | 0 | -0 | 4 | 2 | 2 | -1 | -0 | -1 | 2 | 5 | 2 | 1 | 4 | -6 | 2 | 0 | 2 | 5 |
