# The booth: Jim and Tony

Who the two voices are, what they may and may not say, how a line gets recorded,
and the text of the lines. Read this before writing a new one.

## Jim (play-by-play)

- Dry and conservative in what he says: short sentences, understatement. He has
  called a thousand of these and nothing surprises him.
- The dryness is in the words, never in the voice. He is a sportscaster on the
  air: energetic and glad to be there, with a calm enthusiasm. He does not
  yell the way Tony does, and he never sounds bored, flat or quiet.
- Hates mayonnaise. Hates the phrase "Live, laugh, love" more. He will not say
  why, and the hatred is out of all proportion.
- Married to Carol for twenty-six years. Speaks of her rarely and fondly.
- Eleven years in the booth with Tony.
- Takes the fantasy league seriously: spreadsheets, waiver wire, the lot.
  Carol joined it this year and is beating him.
- He is fond of Tony and would never admit it. His weapon is the pause.

## Tony (color)

- A lovable idiot. Loud, delighted by everything, wrong with total confidence.
  He is never mean and never sarcastic: he means every word.
- Says weird things: bad metaphors, questions nobody asked, facts that are not
  facts.
- Loves nachos. Loves his dog, Biscuit, more. Biscuit comes up as proof of
  almost anything. The two of them live in a studio; Biscuit gets the bed.
- Believes ridiculous conspiracy theories, each with total conviction and
  no malice (the ball is full of bees). They are never about real people,
  real events or anything a person could be hurt by.
- Thursday is his favorite day. He will not say why.
- In the same fantasy league as Jim and terrible at it. Happy in last place.
- Calls Jim by name constantly.

## Carol

Tony may or may not be seeing Jim's wife. It is never confirmed and never
denied. Tony lets slip things he should not know (what Carol said, where she
was on Thursday, the new couch) and changes the subject at the top of his
voice. Jim almost notices, then moves on. No line ever settles it, and Tony is
never smug about it: he does not seem to realise what he is giving away.

## The stories

The stories are told in the games of a season only, never in an exhibition
match, and they start over with every new season (`Season.start()`).

The person gets to know the two of them by playing. The stories are threads
of chapters in `scripts/data/booth_story.gd` (`BoothStory`). Each thread is
told in its own order, a chapter being an exchange of two to four lines in
the huddle, and the threads run side by side:

- `carol` (13 chapters, up to 2 a match): the booth, Carol, and Tony's slips.
- `commissioner` (12 chapters, 1 a match, up to 3 once the Carol thread is
  over, so the closet is opened inside a ten-game season): the league
  commissioner is
  missing. Match 1 brings the league's statement (`missing`), and the next
  four matches a word each that he is still missing (`day_two`, `reward`,
  `description`, `witness`), with Jim and Tony sounding as guilty as they
  are. `closet` and what follows wait until the Carol thread is over
  (`after`): he is in the booth's supply closet, the league negotiates, the
  police come, and the two apologise on the air and are fined fourteen
  dollars each.

How they are paced:

- At most `Tuning.story_per_match` chapters a match in all (3) and each
  thread's own share (`BoothStory.share()`); the first no sooner than
  huddle `story_first_huddle` (4), the next `story_huddle_gap` (8) huddles
  later, and `story_chance` of the time in a huddle where one may come. The
  thread that has had least of its share goes first: Carol, the
  commissioner, Carol. Fourth and twenty and the end of a half come first.
- The place in each thread is kept in `user://booth_story.cfg`, so it
  carries on from one session to the next.
- A chapter interrupted by a call (a touchdown, a sack, a turnover, the
  warning) is held, not lost. At the next huddle whoever had the last word
  says "as I was saying" (`announcer_resume` for Jim, `color_resume` for
  Tony), says that line again, and the chapter carries on. Nothing new
  starts while one is held. A chapter still held when the half or the match
  ends has not been heard, and comes again from the start.
- A thread waits at a chapter that has no recording of every line.
- Once a thread's last chapter has been heard, its chapters join the idle
  chatter.
- Off in an exhibition match and with the CPU playing both teams.
  `tests/story_check.gd` checks it.

A chapter may build on the ones before it in its thread (Thursday is set up
in `thursday` and `book_club` and pays off in `dinner`). Lines outside the
stories may not: they come in any order.

### The closet

While the commissioner is in the closet (from `closet` heard until `caught`
heard, `BoothStory.captive()`), `Tuning.story_captive_chance` of the idle
chatter is a noise from the closet and one of them covering for it: the
lines of `color_idle_captive` and `chat_idle_captive_*`.

The commissioner has no voice of his own. His muffled yelling and the kick
that quiets him are four sound effects (`eleven_text_to_sound_v2`, in the
booth flow), mixed into the recording of the line before or after them at a
third of the voices' level, so a chapter is still Jim and Tony turn about.
Tony and Jim when guilty: `[nervous] [shouting]` for Tony, `[excited]
[nervous]` for Jim; the league's statements are `[excited] [urgent]`.

## The season

The lines for Season mode, recorded on 2026-11-13 (152 lines, one take
each). None names a team, since any
team can be in any game, and none leans on another having been heard. None
states how many games, teams or playoff places there are, or who plays whom
in the playoffs: all of that is still changing (see "Rules").

The championship game is the Fruit Cup. Tony is never sure whether it is a
trophy or a cup of fruit.

A moment's lines for a game of the season are files under the moment's own
name with `_season`, `_playoff` (the semifinal) or `_cup` (the final) after
it; `AudioDirector._season_take()` picks them, and falls back on the usual
lines. A week of the season opens with one of the `_season` openings
`Tuning.season_intro_chance` of the time, a playoff game always with its
own; `Tuning.season_idle_chance` of the idle chatter in such a game is
about the season.

### Before the game

`chat_intro_season` (a week of the regular season)

- j1: Another week of the season, Tony. / Every game COUNTS, Jim! / They do keep a table, yes.
- j2: Another game in the books after today, Tony. / There are BOOKS, Jim? / It's an expression. / I'd READ them!
- j3: The road to the Fruit Cup runs through today, Tony. / There's a ROAD, Jim? I took the BUS!
- t1: I've been studying the STANDINGS, Jim! / And? / They're in ORDER! Somebody put them in ORDER!
- t2: It's a LONG season, Jim! / It is not long, Tony. / I can only count to NINE, Jim! This is NEW for me!
- t3: You know what this season is all about, Jim? The FRUIT CUP! / It is. / I hope it's PEACHES!

`chat_intro_playoff` (the semifinal)

- j1: Welcome to the playoffs. Win, and you play for the Fruit Cup. Lose, and you go home. / No PRESSURE, Jim! / There is considerable pressure, Tony.
- t1: It's the PLAYOFFS, Jim! I wore my LUCKY socks! / You wear those every week, Tony. / And we're STILL HERE!
- t2: WIN OR GO HOME, Jim! / That's right, Tony. / What if they LIVE here?

`chat_intro_cup` (the final)

- j1: This is it. The championship. One game for the Fruit Cup. / I've got GOOSEBUMPS, Jim! / So have I, Tony. Don't tell anyone.
- t1: THE FRUIT CUP, Jim! The biggest prize in FOOTBALL! / It's the only prize in football, Tony. / That's what makes it the BIGGEST!
- t2: Jim, is there real FRUIT in the Fruit Cup? / It's a trophy, Tony. / So that's a MAYBE!

### Between plays

`color_idle_season` (Tony, a week of the regular season)

- 1: Every game COUNTS in a season, Jim! I've been counting them! I LOST COUNT!
- 2: Only the BEST teams make the playoffs, Jim! The rest of us watch from HOME! Like ME!
- 3: Somebody's going to WIN this whole season, Jim! And it's NOT going to be me!
- 4: I love the STANDINGS, Jim! It's like a MENU, but for TEAMS!
- 5: Biscuit's been following the season, Jim! He's got a FAVORITE team! He won't say WHICH!

`chat_idle_season`

- j1: The standings are tight this year, Tony. / TIGHT, Jim! Like my pants after NACHO night!
- j2: A win today matters in the playoff race, Tony. / And a LOSS, Jim? / Also matters. / It ALL matters! I can't SLEEP!
- j3: Carol asked who I like for the Fruit Cup this year, Tony. / What did you SAY, Jim? / I said it's a long season. / That's what she told ME! I mean... GOOD answer!
- t1: Jim, what do they WIN at the end of the season? / The Fruit Cup, Tony. / A WHOLE cup? Of FRUIT? / It's a trophy. / Even BETTER! It KEEPS!
- t2: My fantasy season is going GREAT, Jim! / You're in last place, Tony. / But I'm FIRST in my heart!

`color_idle_playoff` (Tony, the semifinal)

- 1: It's the PLAYOFFS, Jim! Everything is the SAME, but it MATTERS more!
- 2: There's no NEXT WEEK for the loser, Jim! I mean there IS, but they're not INVITED!
- 3: I can SMELL the Fruit Cup from here, Jim! Or that's my NACHOS!

`chat_idle_playoff`

- j1: Nobody wants their season to end today, Tony. / Then they should BOTH win, Jim! / That's not possible. / Not with THAT attitude!
- t1: PLAYOFF football, Jim! You can feel it in the AIR! / That's the nacho machine, Tony. / It's BOTH!

`color_idle_cup` (Tony, the final)

- 1: One of these teams is taking home the FRUIT CUP, Jim! I hope they SHARE!
- 2: This is the LAST game of the season, Jim! What do we do TOMORROW?

`chat_idle_cup`

- j1: The Fruit Cup is sitting right there on the sideline, Tony. / It's so SHINY, Jim! Can I touch it? / No. / Can BISCUIT touch it?
- t1: I've waited all SEASON for this game, Jim! / So has everybody, Tony. / But I waited the HARDEST!

### Halftime

In `scripts/data/halftime_exchanges.gd`, conditions `season`, `playoff`, `cup`:
`show_season_race`, `show_season_long`, `show_playoff_half`,
`show_playoff_nerves`, `show_cup_half`, `show_cup_fruit`.

### The final whistle

`announcer_final_playoff` (Jim, the semifinal is over)

- 1: That's the game! One season goes on. One is over.
- 2: It's over! Their season is still alive!

`color_final_playoff` (Tony)

- 1: THEY'RE STILL IN IT, Jim! Somebody tell their MOTHERS!
- 2: And the other team goes HOME, Jim! I hope home is NICE!

`announcer_final_cup` (Jim, the final is over)

- 1: It's over! We have a champion! The Fruit Cup has a new home!
- 2: That's it! Champions of the league, and winners of the Fruit Cup!

`color_final_cup` (Tony)

- 1: CHAMPIONS, Jim! CHAMPIONS! Somebody fill that cup with FRUIT!
- 2: THEY DID IT, Jim! THE FRUIT CUP! I'm not crying! YOU'RE crying!

`chat_final_cup_j1`: What a season, Tony. / What a SEASON, Jim! Can we do it AGAIN? / Next season, Tony. / Is that TOMORROW?

### Sudden death

Any match, exhibition included: a second half that ends level goes to
sudden death, a scramble for the ball and the first score wins.

`announcer_overtime` (Jim, as it starts)

- 1: We are level at the end of the second half. Overtime! The next score wins it.
- 2: Nobody ties in this league. Sudden death! First score wins.

`color_overtime` (Tony)

- 1: SUDDEN DEATH, Jim! Nobody actually DIES, right?
- 2: FREE FOOTBALL, Jim! We didn't even pay for the FIRST football!
- 3: NEXT SCORE WINS! I can't feel my LEGS, Jim!

`chat_overtime_t1`: OVERTIME, Jim! How long does it go? / Until somebody scores, Tony. / What if NOBODY scores? / Then we live here now.

### On the season's screen

Played by `MenuBooth`, asked for by `MainMenu` and `SeasonHub`.

`menu_season` (SEASON highlighted)

- j1: The season. Then the playoffs. Then the Fruit Cup.
- t1: SEASON! That's where the FRUIT CUP is!
- t2: A whole SEASON, Jim! With STANDINGS!

`menu_season_pick` (a new season: the choice of a team, and the team chosen)

- j1: A new season. Pick your team.
- j2: Choose wisely. You're stuck with them all season.
- t1: NEW SEASON! Everybody's in FIRST PLACE, Jim!

`menu_season_open` (SEASON pressed with a season on)

- j1: Back to the season.
- t1: The season's still GOING, Jim! I CHECKED!

`menu_standings` (the STANDINGS page)

- j1: The standings. The top of it is the place to be.
- t1: LOOK at all those NUMBERS, Jim!
- t2: Jim, which way is UP on this thing? / The top, Tony.

`menu_stats` (TEAM STATS, PLAYER STATS)

- j1: The numbers don't lie.
- t1: STATS, Jim! I don't know what ANY of these mean!

`menu_season_win` (back from a game of the season, won)

- j1: A win. That helps in the standings.
- t1: A WIN, Jim! Put it on the BOARD!
- t2: They WON, Jim! I KNEW they would! / You picked the other team, Tony.

`menu_season_loss` (lost)

- j1: A loss. There's always next week.
- t1: They LOST, Jim! But they looked GOOD doing it!
- t2: It's FINE, Jim! Nobody remembers the losses! / The standings do, Tony.

`menu_bye` (a playoff round went by with the person's team on its week off)

- j1: A week off. Well earned.
- t1: A week OFF, Jim! What do we do? / We wait, Tony. / I'm BAD at that!

`menu_playoffs` (the playoffs go on with the person still in them)

- j1: The playoffs. Win, or the season is over.
- t1: PLAYOFFS, Jim! PLAYOFFS!

`menu_eliminated` (the person's season is over)

- j1: The season is over for this team. There's always next year.
- t1: We can still WATCH, Jim! I LOVE watching!

`menu_champion` (the person's team won the Fruit Cup)

- j1: Champions. The Fruit Cup is theirs.
- t1: CHAMPIONS, Jim! Can I hold the CUP? / No, Tony.
- t2: THE FRUIT CUP, Jim! It's even BIGGER up close!

`menu_season_over` (somebody else won it)

- j1: The season is over. A new one is one button away.
- t1: It's OVER, Jim! Let's do ANOTHER one!

## Rules

- The game has no punts and no kicks. Nothing either of them says may imply
  that punting or kicking was an option.
- Both of them are excited about what they are saying, always. Tony yells;
  Jim is the steady professional with the same energy under control. A joke
  is never delivered deadpan, by either of them: Jim's understatement is funny
  because he says it brightly.
- A joke about a moment plays at that moment (the big-hit line on a big hit).
- The running gags (nachos, Biscuit, the fantasy league, Carol, mayonnaise,
  "Live, laugh, love") are seasoning: about one line in five. Most lines are
  about the football.
- A line said during a live play is one short sentence. Exchanges only start
  with the ball dead, and run two to four lines.
- No real people, teams, networks or brands.
- Nothing that is going to change. The game is early in development, so no
  line states the number of games, weeks, teams or playoff places, which seed
  plays which, who has the week off, or how long a half is. "The season",
  "the playoffs", "the standings", "the Fruit Cup" and "win or go home" are
  safe. A number is fine only in a joke that is true whatever the format
  (Tony can only count to nine).
- No "he" or "she" for a player: the players are men and women. A line about
  a player says "they", "the runner", "the quarterback", "that one",
  "somebody", or has no subject at all ("Down they go", "Shrugs it off").
  No "his", "him", "her", "that man", "these guys" or "son" either. Jim,
  Tony, Carol, the commissioner and Biscuit keep their own. The older lines
  that broke this were recorded again (see 'Without "he" or "him"').
- The players wear no helmets. A line may only mention helmets as a joke about that.

## File names

Everything is `assets/audio/<name>_<n>.ogg`; `AudioDirector` and `MenuBooth`
find the files by name, so adding a line is adding a file.

| Files | What |
|---|---|
| `announcer_<moment>_<n>` | Jim, one line. Every `n` is another line for that moment. |
| `color_<moment>_<n>` | Tony, one line. |
| `chat_<moment>_<t\|j><k>_<part>` | Exchange `k` of `color_<moment>`; the letter is who speaks first, the parts alternate. |
| `show_<id>_<part>` | Halftime report; text and conditions in `scripts/data/halftime_exchanges.gd`. |
| `story_<id>_<part>` | Chapter `id` of the story; text and order in `scripts/data/booth_story.gd`. |
| `menu_<moment>_<t\|j><k>_<part>` | Main menu, team select and the season's screen. Same shape as `chat_`; a set with one part is a solo line. |
| `<moment>_season\|_playoff\|_cup_...` | A moment's lines for a game of the season, a playoff game, the final (see "The season"). |

## Recording

- ElevenLabs flow "Tony and Jim booth" (`LzwEkf4e5N3rDFizXQ88`), model
  `eleven_v4`, one node per line, 2 takes.
- Tony: "Ryan - Event VOG / Announcer". Prompt `[excited] [shouting] ...`, or
  `[screaming]` when he panics. Exclamation marks, CAPS on the stressed words.
- Jim: "David - Sports Arena Announcer". Prompt `[excited] ...` with an
  exclamation mark, and CAPS on one word at most. Never `[calm]` or
  `[deadpan]`: with this voice both come out as a disinterested near-whisper
  at a third of his usual pitch (tried on 2026-11-13, and every line had to be
  recorded again). `[warm] [upbeat]` and no tag at all come out low as well.
- One take goes into the game, trimmed of silence and levelled to RMS 0.2. The
  two takes of a line come out within a tenth of a second of each other, so
  nothing picks between them by ear: listen to a new batch once, and swap in
  the other take from the flow where a line lands badly.

## The quarterback

Not the booth, but recorded the same way: flow "Arcade football SFX"
(`tNUiyj1Oo2WBOsJHqy3V`), voice "Damyen — Gravel & Velvet", `eleven_v4`,
prompt `[shouting] ...`, one take, levelled to the `qb_cadence` files (RMS
0.134). Both teams' quarterbacks share the lines.

- `qb_cadence_<n>`: the cadence as the teams line up. `qb_hut_<n>`: the snap.
- `qb_call_<n>`: one more shout each time the person presses (B) before the
  snap. Short, and real enough to pass for football.
- `qb_silly_<n>`: said in place of a shout or of the opening cadence now and
  then (`Tuning.qb_silly_chance`, `qb_silly_open_chance`). A CPU quarterback
  holds the snap for one, up to `cpu_silly_hold_max` seconds, so keep them
  under four seconds.

`qb_call` (2026-11-13): Blue forty-two! · Ohio! Ohio! · Hut! Hut! · Set! Set! ·
Omaha! Omaha! · Red nineteen! Red nineteen! · Green eighty! Green eighty! ·
Ready! Ready! · Easy! Easy! · Watch the blitz! Watch the blitz! · Fifty-four
is the Mike! Fifty-four! · Kill! Kill! Kill! · Check, check! Check, check! ·
Alaska! Alaska! · Tango twenty-two! Tango twenty-two! · On me! On me!

`qb_silly` (2026-11-13): Banana! Banana! · Blue forty-two! ...no wait,
forty-three! · Lasagna! Lasagna! · Does anybody remember the play?! · Mom! I'm
on TV! · Hut! Hut! GOOSE! · I left the oven on! · Spaghetti twenty-two!
Spaghetti twenty-two! · Nobody tackle me, okay?! · Is it Tuesday? TUESDAY! ·
Wi-fi password! Wi-fi password! · My hands are cold! Hurry up! · Purple!
Seven... teen... ish! · Who ordered the nachos?! Who ordered the nachos?! ·
Ohio! No, the OTHER Ohio! · I forgot the snap count!

## Script

The text of the lines recorded on 2026-11-13. The earlier lines (about 250) are
only in the flow, where a node shows the first few words of its prompt.

### In the game

`announcer_hit` (Jim, a big hit)

- 7: That one left a mark.
- 8: That will be felt tomorrow.
- 9: Oh, my. That was unnecessary.

`color_lawn_chair` (Tony, a big hit)

- 6: Just got hit into NEXT TUESDAY!
- 7: BISCUIT felt that one, Jim, and he's at HOME!
- 8: Somebody check for SHOES! I think they got left back there!
- 9: Somebody just met their ANCESTORS!

`chat_lawn_chair_t2`: Did you SEE that hit, Jim?! / I heard it. / My FILLINGS heard it!

`chat_lawn_chair_j2` (nobody in this game wears a helmet): And THAT is why they wear the helmets! / Jim, they're not WEARING helmets! / They're NOT? Oh, no! Somebody get a DOCTOR down there! Get ALL the doctors! / (sobbing) They're so BRAVE, Jim! They're so BRAVE!

`announcer_break` (Jim, a broken tackle)

- 6: Shrugs off the tackle.
- 7: Not today, says the ball carrier.
- 8: One tackler is not going to be enough.
- 9: Simply declined to be tackled.

`color_dog` (Tony, a broken tackle)

- 5: Bounced off like a SCREEN DOOR!
- 6: You can't tackle somebody with your FEELINGS, Jim!
- 7: That's how Biscuit gets away at BATH TIME!
- 8: There's BUTTER on that jersey! Somebody check!

`chat_dog_j1`: Nobody can make the tackle, Tony. / Have they tried ASKING NICELY?

`announcer_tackle` (Jim, a plain wrap-up tackle; most tackles are dives, which are hits)

- 1: Down they go.
- 2: That'll do it.
- 3: Wrapped up and brought down.
- 4: A sensible tackle.

`color_tackle` (Tony, an ordinary tackle)

- 1: DOWN, Jim! Gravity wins AGAIN!
- 2: That's a tackle! I KNOW that one!
- 3: Right in the GRASS! That's where they keep the ground!
- 4: Textbook! I assume! I never read the textbook!

`announcer_spin` (Jim, a spin beats the tackler)

- 1: A spin, and free.
- 2: Spins away from the tackle.
- 3: Round they go. Nobody home.

`color_spin` (Tony)

- 1: It's a CEILING FAN, Jim!
- 2: ROUND AND ROUND! I'm getting dizzy up HERE!
- 3: That's the same move Biscuit does before he lies down!

`announcer_stiff_arm` (Jim, a stiff arm beats the tackler)

- 1: A stiff arm, and still going.
- 2: Held off with one hand.
- 3: Kept at arm's length. Literally.

`color_stiff_arm` (Tony)

- 1: TALK TO THE HAND, Jim!
- 2: Just told that tackler NO with a whole ARM!
- 3: That's how I keep people away from my NACHOS!

`color_blaze` (fourth and twenty, in the huddle, after Jim's "Fourth down. Twenty to go."; said every time)

- 1: FOURTH and TWENTY, Jim! FOUR-TWENTY! BLAZE IT!
- 2: FOUR-TWENTY! No WONDER this drive went up in SMOKE!

`chat_blaze`

- j1: Fourth and twenty. DON'T say it, Tony! / BLAZE IT, JIM! / He said it!
- t1: FOUR-TWENTY, Jim! The whole stadium just got the MUNCHIES! / That explains the NACHO line!

`color_idle` (Tony, between plays)

- 24: Jim, if you put nachos ON nachos, is that still one nacho?
- 25: My dog Biscuit is watching at home, Jim! Hi, BISCUIT!
- 26: I named my fantasy team after Biscuit, Jim! We are in LAST PLACE and we are HAPPY!
- 27: The nachos here come in a HELMET, Jim! I've had THREE helmets!
- 28: Biscuit can catch a tennis ball from forty yards, Jim! SIGN HIM UP!
- 29: I set my fantasy lineup with my EYES CLOSED, Jim! It's called TRUSTING THE PROCESS!
- 30: Is cheese a sauce or a TOPPING, Jim? Don't answer! It's a LIFESTYLE!
- 31: I taught Biscuit to high five, Jim! He only does it for HAM!

`chat_idle` (between plays)

- t7: They had a sign at the hotel, Jim! Live, laugh... / Don't. / LOVE! / I'm going to need a minute.
- t8: Carol says you SNORE, Jim! / When did Carol say that? / WHAT A GAME we've got today!
- t9: You know what's GREAT on nachos, Jim? MAYONNAISE! / I will leave this booth, Tony.
- j7: You started a quarterback on a bye week, Tony. / They seemed RESTED!
- j8: Somebody put mayonnaise on my sandwich, Tony. / Is that BAD? / I've called the police.

Added with the story (one take each; a slip of Tony's is prompted
`[panicked] [shouting]`):

- `color_idle_32`: Biscuit and I live in a STUDIO, Jim! He gets the BED!
- `color_idle_33`: Jim is my EMERGENCY CONTACT, everybody! He doesn't KNOW!
- `chat_idle_blowout_t1` (a rout): With this score, Jim, you could be HOME by eight! Carol's making POT ROAST! / How do you know what Carol's making? / It's a POT ROAST kind of night, Jim!
- `chat_idle_close_j1` (a tight second half): My heart can't take this, Tony. Carol says I should retire. / DON'T, Jim! Who would I SIT with?
- `show_carol_phone` (halftime): Tony, your phone keeps lighting up. It says Carol. / DIFFERENT Carol, Jim! There are DOZENS of them! / I see.

Tony's conspiracy theories, and the booth off the air on the menu (one take
each):

- `color_idle_34`: The first down line is REAL, Jim! The players can SEE it! They just won't ADMIT it!
- `color_idle_35`: I don't trust the scoreboard, Jim! Who's telling IT the score?
- `color_idle_36`: Halftime isn't real, Jim! They just TURN US OFF!
- `color_idle_37`: Mayonnaise is just COLD GRAVY, Jim! They don't want you to KNOW!
- `chat_idle_t10`: There is no other team, Jim! It's the SAME team in different SHIRTS! / They're tackling each other, Tony. / That's how DEEP it goes!
- `chat_idle_t11`: The coin toss is RIGGED, Jim! That coin has TWO SIDES! / Every coin has two sides, Tony. / And who PROFITS?
- `chat_idle_j9`: Tony, why is there foil on your headset? / So the OTHER booth can't hear my thoughts, Jim! / There is no other booth. / That's what the foil is FOR!
- `show_locker_room` (halftime): Where do the players GO at halftime, Jim? Nobody KNOWS! / The locker room, Tony. / Have you SEEN it?
- `menu_options_t3`: DON'T press options! That's how they TRACK you!
- `menu_welcome_t3`: Sorry I'm late, Jim! THURSDAY traffic! / It's Sunday, Tony.
- `menu_idle_j3` (Jim is on the phone): Yes, dear. No, he's here. I'll ask him. / Ask me WHAT, Jim? / Carol says hello. / HI, CAROL! I mean, hello, Jim's wife!

The fantasy league, which Carol is in too (one take each):

- `color_idle_38`: My fantasy team is ZERO and NINE, Jim! That's called CONSISTENCY!
- `color_idle_39`: Carol's in our fantasy league now, Jim! She's in FIRST PLACE! I helped her DRAFT!
- `chat_idle_j10`: Carol joined our fantasy league this year, Tony. She's beating me. / She's beating EVERYBODY, Jim! She's RUTHLESS! / She named her team "Sorry, Jim."
- `chat_idle_t12`: Jim, I need a running back for my fantasy team! What'll you take for YOURS? / Nothing you have, Tony. / I've got NACHOS! / ...Go on.
- `chat_idle_t13`: Carol and I made a fantasy TRADE last night, Jim! / Last night? I was home last night. / It was a very QUIET trade, Jim!

The closet, only while the commissioner is in it (the noise is part of the
recording):

- `color_idle_captive_1`: (muffled yelling) That's the AIR CONDITIONING, folks!
- `color_idle_captive_2`: (muffled shouting) QUIET in there! I mean... GREAT crowd tonight!
- `chat_idle_captive_j1`: Tony, the closet is making noise again. / (a thud) FIXED it, Jim!
- `chat_idle_captive_t1`: (muffled yelling) Does anybody else hear a GHOST, Jim? / There are no ghosts, Tony. Only consequences.

### Without "he" or "him"

Every recorded line that called a player "he", "him", "that man" or "these
guys" was written again and recorded again on 2026-11-13 (97 lines, found by
transcribing the clips; one take each), since the players are men and women.
The files kept their names (two of them, `menu_team_t1` and `_t2`, are
listed with the menu lines). Lines 1-5 of the older sets are only here and in
the flow:

- `announcer_break_3`: They will not go down, Tony!
- `announcer_break_4`: Nobody can make the tackle, Tony! Still going!
- `announcer_break_5`: Bounced right off! Look at this, Tony!
- `announcer_break_6`: Shrugs off the tackle!
- `announcer_break_8`: One tackler is not going to be enough!
- `announcer_break_9`: Simply declined to be tackled!
- `announcer_catch_3`: How do you hold on to that?
- `announcer_catch_5`: Oh, what a grab! Tony, how do you hang on to that?
- `announcer_catch_6`: What a catch, Tony! No business coming down with that!
- `announcer_hit_5`: That one got rocked, Tony! Somebody send help!
- `announcer_hit_8`: That will be felt tomorrow!
- `announcer_hurdle_2`: Over the top! Tony, that was a HURDLE!
- `announcer_pancake_2`: Flattened, Tony! Flat as a pancake!
- `announcer_pancake_3`: Flat on the back! Tony, that's a big body down!
- `announcer_room_2`: This could go all the way!
- `announcer_room_3`: Tony! There's room! Nothing but grass!
- `announcer_room_4`: Loose, Tony! On the LOOSE!
- `announcer_room_5`: Look at that, Tony! Somebody better catch up!
- `announcer_spin_1`: A SPIN! And free!
- `announcer_spin_2`: Spins away from the tackle!
- `announcer_spin_3`: Round they go! Nobody home!
- `announcer_stiff_arm_1`: A stiff arm, and still going!
- `announcer_stiff_arm_2`: Held off with one hand!
- `announcer_tackle_1`: Down they go!
- `announcer_throw_4`: Tony! Dropped that one in a bucket!
- `color_bad_throw_5`: That one went to the HOT DOG stand, Jim!
- `color_breakaway_1`: Look at that one GO! Slowest getaway since that white BRONCO!
- `color_catch_1`: Jim! Caught that with the FINGERNAILS!
- `color_catch_3`: That's a GROWN-UP catch, Jim! Left the GROUND for that one!
- `color_confused_3`: DROPPED it, Jim! You're not supposed to DROP it!
- `color_confused_5`: Jim! Jim! ONE job! Hold the BALL!
- `color_dog_1`: They've got that DOG in them! Possibly SEVERAL dogs!
- `color_dog_2`: REFUSES to go down, Jim! Got somewhere to BE!
- `color_dog_3`: Jim, you could hit that one with a TRUCK and it wouldn't MATTER!
- `color_dog_4`: Still on their FEET! How, Jim? HOW?
- `color_dog_5`: Bounced off like a SCREEN DOOR!
- `color_dog_6`: You can't tackle somebody with your FEELINGS, Jim!
- `color_dog_8`: There's BUTTER on that jersey! Somebody check!
- `color_drop_1`: Tried to catch it, but the glove did NOT fit!
- `color_fourth_8`: Do or DIE, Jim! Well, do, or give the other team the ball! Still BAD!
- `color_hot_1`: ABSOLUTELY lighting up this defense!
- `color_hot_4`: WIDE OPEN! Jim, that was so open, I got SUSPICIOUS!
- `color_hurdle_1`: Jumped over a whole PERSON, Jim! That's illegal in most states!
- `color_hurdle_2`: They can FLY! Jim, did you know they could FLY?
- `color_hurdle_3`: Right over the TOP, Jim! Like a deer over a FENCE!
- `color_idle_1`: You know, Jim, the key to winning football games is scoring more points than the other TEAM!
- `color_idle_11`: These are PROFESSIONALS, Jim! I'm assuming! Nobody's shown me any PAPERWORK!
- `color_idle_3`: The quarterback is the one who THROWS the ball, Jim! Unless it's a HANDOFF!
- `color_interception_1`: That's the OTHER team!
- `color_interception_2`: Great catch, Jim! Wrong TEAM, but great catch!
- `color_interception_3`: NOOOOO! Jim! That went to the wrong COLOR!
- `color_interception_4`: You're supposed to throw it to YOUR team, Jim! I'm pretty sure that's in the RULES!
- `color_interception_5`: Gave it to them, Jim! As a GIFT!
- `color_late_half_2`: Hurry it up, EVERYBODY! The halftime snacks are getting COLD!
- `color_lawn_chair_1`: Absolutely FOLDED like a lawn chair!
- `color_lawn_chair_3`: They're going to feel that one on TUESDAY, Jim! And WEDNESDAY!
- `color_lawn_chair_4`: Somebody just got hit into NEXT WEEK, Jim!
- `color_lawn_chair_5`: JIM! FOLDED! Like a LAWN CHAIR!
- `color_lawn_chair_6`: Just got hit into NEXT TUESDAY!
- `color_lawn_chair_8`: Somebody check for SHOES! I think they got left back there!
- `color_lawn_chair_9`: Somebody just met their ANCESTORS!
- `color_qb_run_1`: Using the LEGS!
- `color_qb_run_2`: The quarterback is RUNNING, Jim! Is that ALLOWED?
- `color_qb_run_3`: RUN! RUN! Nobody can hear me, Jim, but I'm HELPING!
- `color_qb_run_4`: Nobody's open, so the quarterback said FINE! I'll do it MYSELF!
- `color_sack_1`: Never saw it COMING, Jim! I saw it! I just didn't SAY anything!
- `color_sack_4`: The line let that rusher right THROUGH, Jim! They held the DOOR!
- `color_spin_1`: It's a CEILING FAN, Jim!
- `color_stiff_arm_2`: Just told that tackler NO with a whole ARM!
- `color_tackle_1`: DOWN, Jim! Gravity wins AGAIN!
- `color_td_4`: In the END ZONE, Jim! That's where the points LIVE!
- `color_td_long_2`: Jim! STILL running! Somebody say it's okay to STOP!
- `color_td_long_3`: That was so FAR, Jim! I got tired just WATCHING!
- `color_td_long_4`: GOODBYE! Send a postcard, Jim, because that one is GONE!
- `color_td_walk_1`: Just WALKED into the end zone like they owned the place!
- `color_td_walk_2`: Nobody within a MILE, Jim! There was time to stop for a SANDWICH!
- `color_td_walk_5`: Strolled in, Jim! That was a STROLL! A leisurely stroll!
- `chat_bad_throw_j1_1`: Tony, not the best throw!
- `chat_bad_throw_j1_2`: Not the BEST, Jim? My nephew throws better, and he's a TODDLER!
- `chat_dog_j1_1`: Nobody can make the tackle, Tony!
- `chat_idle_j7_1`: You started a quarterback on a bye week, Tony!
- `chat_idle_j7_2`: They seemed RESTED!
- `chat_interception_j1_1`: Tony, what was the quarterback looking at there?
- `chat_intro_j3_2`: Score POINTS, Jim! As many as possible! Ideally more than the other TEAM!
- `chat_lawn_chair_j1_2`: That's going to hurt TOMORROW, Jim! I felt it NOW!
- `chat_lawn_chair_t1_1`: Jim, is that one OKAY? Are they OKAY?
- `chat_lawn_chair_t1_2`: Back on their feet, Tony!
- `chat_lawn_chair_t1_3`: TOUGHER than me, Jim! I'd have gone HOME!
- `chat_td_j2_2`: Sure, Jim! Had the ball, and then: END ZONE! That's the whole thing!
- `chat_td_walk_j1_1`: Nobody anywhere near, Tony!
- `show_star_1_1`: One player is doing EVERYTHING out there, Jim!
- `show_star_1_3`: Somebody give that player a RAISE!
- `show_star_2_2`: The rest of the team should send a FRUIT BASKET!
- `show_long_run_2`: STILL running, Jim! Somebody check the PARKING LOT!
- `show_dives_1`: Everybody is diving ALL OVER the place, Jim!

### The stories

The text of the chapters is in `scripts/data/booth_story.gd`, in order.
`carol`: `lunch`, `years`, `met`, `photo`, `thursday`, `book_club`, `couch`, `mayo_carol`,
`biscuit`, `deserve`, `anniversary`, `sweater`, `dinner`. `commissioner`:
`missing`, `day_two`, `reward`, `description`, `witness`, `closet`,
`demands`, `statement`, `counter`, `snack`, `caught`, `apology`.

### On the main menu

`menu_welcome` (the menu comes up for the first time)

- j1: Welcome to Blue 42. / The most REALISTIC football simulator EVER MADE, Jim! / It says that on the box, yes.
- j2: Good evening, and welcome to Blue 42. I'm Jim. / And I'm TONY! And I brought NACHOS!
- t1: WELCOME to Blue 42, everybody! / Press start whenever you're ready. / Or DON'T! We get paid EITHER WAY!
- t2: Jim! JIM! Somebody's HERE! / Then let's look professional, Tony.

`menu_welcome_back` (back from a match)

- j1: And we're back. / Did we WIN, Jim? / We're the announcers, Tony.
- j2: Welcome back to Blue 42.
- t1: They came BACK, Jim! I TOLD you they'd come back! / You said no such thing.

`menu_start` (START GAME highlighted)

- j1: Start game. A fine choice.
- j2: Whenever you're ready.
- t1: START GAME! That's the GOOD one!
- t2: PRESS IT! PRESS IT! PRESS IT!

`menu_options` (OPTIONS highlighted)

- j1: Options. There aren't any.
- j2: The options menu. Still under construction.
- t1: OPTIONS! I love having options, Jim!
- t2: Ooh, what's in THERE?

`menu_exit` (EXIT highlighted)

- j1: Let them go, Tony.
- t1: NO NO NO! DON'T DO IT!
- t2: NOT THE EXIT! ANYTHING but the exit!
- t3: Jim, they're LEAVING! SAY SOMETHING! / Goodbye.
- t4: I'll give you my NACHOS! Okay, HALF my nachos!
- t5: Think about BISCUIT! He'd want you to STAY!
- t6: WAIT WAIT WAIT! We haven't even PLAYED yet!

`menu_start_pick` (START GAME pressed)

- j1: Let's pick the teams.
- t1: HERE WE GO!
- t2: FOOTBALL TIME, Jim!

`menu_options_pick` (OPTIONS pressed)

- j1: There's nothing in there yet. / I looked! TWICE!
- j2: Nothing to set. Carry on.
- t1: It's EMPTY, Jim! Like my fantasy trophy case!

`menu_exit_pick` (EXIT pressed; the game quits when the line ends)

- j1: Good night, everybody.
- j2: Thanks for stopping by.
- t1: NOOOOO!

`menu_team` (team select: another team)

- j1: A solid football team.
- j2: Interesting choice.
- t1: Ooh, I LIKE this team!
- t2: THAT'S my team! I have NO idea who they are!
- t3: Biscuit could beat THIS team, Jim!

`menu_side` (team select: the controller changes side)

- j1: Switching sides.
- j2: Make up your mind. No rush.
- t1: The OTHER side! BOLD!

`menu_back` (team select: back to the menu)

- j1: Back to the menu.
- t1: Cold feet! I GET it!
- t2: Where are we GOING?

`menu_go` (team select: the match starts)

- j1: Here we go. Stay with us.
- t1: LET'S PLAY SOME FOOTBALL!
- t2: TO THE BOOTH, Jim!

`menu_idle` (nothing pressed for a while)

- j1: We're still here.
- j2: No hurry. The field isn't going anywhere.
- t1: Take your time! I've got NACHOS!
- t2: Jim, are they still THERE? / I believe so, Tony.
