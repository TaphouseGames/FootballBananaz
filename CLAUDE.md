# Football Bananaz

## Controller rumble

The gamepad rumbles with what happens to the person's player (`scripts/rumble.gd`,
reached as `game.rumble`).

When you add or change a mechanic the person would feel in their hands (a hit, a
catch, a timing window, a new move, a score), give it rumble as part of the same work:

1. Add a preset to `Rumble.PRESETS`: weak motor, strong motor, seconds, delay. The weak
   motor is for ticks and clicks, the strong one for bodies and thuds. Match the strength
   to presets of similar weight already in the table.
2. Play it next to the mechanic's sound or `game.impact(...)` call:
   - `play_mine(preset, a, b)` when only the person's own player should feel it,
   - `play_for(preset, a, b)` when others' hits should come through faintly,
   - `play_team(preset, team)` for something that happens to their team,
   - `play(preset)` for the whole game (a score, a buzzer).

   With two people playing each has their own pad: `play_mine` and `play_for` go by whose
   player it is, `play_team` by whose team, and `play` shakes both.
3. Run `tests/rumble_check.gd`: it fails on a preset nobody plays and on a name that is
   no preset.

Leave it out where it would be noise: menus, anything continuous (sprinting), and the
start of a move whose landing or hit already rumbles.
