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

The person gets to know the two of them by playing. The stories are threads
of chapters in `scripts/data/booth_story.gd` (`BoothStory`). Each thread is
told in its own order, a chapter being an exchange of two to four lines in
the huddle, and the threads run side by side:

- `carol` (13 chapters, up to 2 a match): the booth, Carol, and Tony's slips.
- `commissioner` (12 chapters, 1 a match): the league commissioner is
  missing. Match 1 brings the league's statement (`missing`), and the next
  four matches a word each that he is still missing (`day_two`, `reward`,
  `description`, `witness`), with Jim and Tony sounding as guilty as they
  are. `closet` and what follows wait until the Carol thread is over
  (`after`): he is in the booth's supply closet, the league negotiates, the
  police come, and the two apologise on the air and are fined fourteen
  dollars each.

How they are paced:

- At most `Tuning.story_per_match` chapters a match in all (3) and each
  thread's own share (`BoothStory.PER_MATCH`); the first no sooner than
  huddle `story_first_huddle` (4), the next `story_huddle_gap` (8) huddles
  later, and `story_chance` of the time in a huddle where one may come. The
  thread that has had least of its share goes first: Carol, the
  commissioner, Carol. Fourth and twenty and the end of a half come first.
- The place in each thread is kept in `user://booth_story.cfg`, so it
  carries on from one session to the next. A chapter cut short by a call has
  not been heard and comes again.
- A thread waits at a chapter that has no recording of every line.
- Once a thread's last chapter has been heard, its chapters join the idle
  chatter.
- Off with the CPU playing both teams. `tests/story_check.gd` checks it.

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
| `menu_<moment>_<t\|j><k>_<part>` | Main menu and team select. Same shape as `chat_`; a set with one part is a solo line. |

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

## Script

The text of the lines recorded on 2026-11-13. The earlier lines (about 250) are
only in the flow, where a node shows the first few words of its prompt.

### In the game

`announcer_hit` (Jim, a big hit)

- 7: That one left a mark.
- 8: He will feel that tomorrow.
- 9: Oh, my. That was unnecessary.

`color_lawn_chair` (Tony, a big hit)

- 6: He just got hit into NEXT TUESDAY!
- 7: BISCUIT felt that one, Jim, and he's at HOME!
- 8: Somebody check his SHOES! I think he left them back there!
- 9: That man just met his ANCESTORS!

`chat_lawn_chair_t2`: Did you SEE that hit, Jim?! / I heard it. / My FILLINGS heard it!

`chat_lawn_chair_j2` (nobody in this game wears a helmet): And THAT is why they wear the helmets! / Jim, they're not WEARING helmets! / They're NOT? Oh, no! Somebody get a DOCTOR down there! Get ALL the doctors! / (sobbing) They're so BRAVE, Jim! They're so BRAVE!

`announcer_break` (Jim, a broken tackle)

- 6: He shrugs him off.
- 7: Not today, says the ball carrier.
- 8: One man is not going to be enough.
- 9: He simply declined to be tackled.

`color_dog` (Tony, a broken tackle)

- 5: He bounced off him like a SCREEN DOOR!
- 6: You can't tackle a man with your FEELINGS, Jim!
- 7: That's how Biscuit gets away at BATH TIME!
- 8: He's got BUTTER on his jersey! Somebody check!

`chat_dog_j1`: Nobody can bring him down, Tony. / Have they tried ASKING NICELY?

`announcer_tackle` (Jim, a plain wrap-up tackle; most tackles are dives, which are hits)

- 1: Down he goes.
- 2: That'll do it.
- 3: Wrapped up and brought down.
- 4: A sensible tackle.

`color_tackle` (Tony, an ordinary tackle)

- 1: And he is DOWN, Jim! Gravity wins AGAIN!
- 2: That's a tackle! I KNOW that one!
- 3: Right in the GRASS! That's where they keep the ground!
- 4: Textbook! I assume! I never read the textbook!

`announcer_spin` (Jim, a spin beats the tackler)

- 1: A spin, and he's free.
- 2: He spins away from the tackle.
- 3: Around he goes. Nobody home.

`color_spin` (Tony)

- 1: He's a CEILING FAN, Jim!
- 2: ROUND AND ROUND! I'm getting dizzy up HERE!
- 3: That's the same move Biscuit does before he lies down!

`announcer_stiff_arm` (Jim, a stiff arm beats the tackler)

- 1: A stiff arm, and he keeps going.
- 2: He holds him off with one hand.
- 3: Kept at arm's length. Literally.

`color_stiff_arm` (Tony)

- 1: TALK TO THE HAND, Jim!
- 2: He just told that man NO with his whole ARM!
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
- j7: You started a quarterback on his bye week, Tony. / He seemed RESTED!
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

The closet, only while the commissioner is in it (the noise is part of the
recording):

- `color_idle_captive_1`: (muffled yelling) That's the AIR CONDITIONING, folks!
- `color_idle_captive_2`: (muffled shouting) QUIET in there! I mean... GREAT crowd tonight!
- `chat_idle_captive_j1`: Tony, the closet is making noise again. / (a thud) FIXED it, Jim!
- `chat_idle_captive_t1`: (muffled yelling) Does anybody else hear a GHOST, Jim? / There are no ghosts, Tony. Only consequences.

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
- t1: Ooh, I LIKE these guys!
- t2: THOSE are my guys! I have NO idea who they are!
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
