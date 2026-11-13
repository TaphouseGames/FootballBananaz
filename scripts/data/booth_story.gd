class_name BoothStory
extends RefCounted
## The stories Jim and Tony tell without meaning to. Each is a thread of
## chapters that come out in order, a chapter at a time in the huddle, and the
## game remembers how far the person has got in each from one session to the
## next. The threads run side by side:
##
## - `carol`: eleven years in the booth, Jim's wife Carol, and what Tony seems
##   to know about her. Nothing in it is ever confirmed (see docs/booth.md).
## - `commissioner`: the league commissioner is missing. For the first few
##   matches that is all the league says; once the Carol thread is over he
##   turns out to be in the booth's supply closet, and it ends with an apology
##   and a fine of fourteen dollars.
##
## Each chapter has an `id` (unlike any other, in any thread), who speaks
## `first`, and its `lines`, which the two say turn about. The lines are
## recorded as `assets/audio/story_<id>_<n>.ogg`; a thread waits at a chapter
## without a recording of every line. A chapter with `after` also waits until
## that other thread has been told to the end. The noises from the closet are
## part of the recordings, and are written here in brackets.
##
## To add a chapter: a row in its thread, in its place, and its files. To add
## a thread: its chapters, a name in THREADS, and its rows in chapters() and
## PER_MATCH.

const JIM: StringName = &"jim"
const TONY: StringName = &"tony"
const CAROL: StringName = &"carol"
const COMMISSIONER: StringName = &"commissioner"
const SECTION: String = "story"
## The key the Carol thread was saved under when it was the only one.
const KEY_OLD: String = "heard"

## The threads, in the order they get their turn in a match, and the most
## chapters of each that one match may bring.
const THREADS: Array[StringName] = [CAROL, COMMISSIONER]
const PER_MATCH: Dictionary[StringName, int] = {CAROL: 2, COMMISSIONER: 1}
## The commissioner can be heard in the closet once the first of these
## chapters has been told and until the second has.
const CAPTIVE_FROM: StringName = &"closet"
const CAPTIVE_UNTIL: StringName = &"caught"

const CAROL_CHAPTERS: Array[Dictionary] = [
	# First of all, who Carol is: nothing Tony lets slip means anything before it.
	{&"id": &"lunch", &"first": JIM, &"lines": [
		"My wife, Carol, packed my lunch today, Tony. Twenty-six years married, and she still writes a little note.",
		"What's it SAY, Jim?",
		"It says \"no mayonnaise.\"",
		"She GETS you, Jim!"]},
	{&"id": &"years", &"first": JIM, &"lines": [
		"Eleven years in this booth together, Tony.",
		"ELEVEN YEARS, Jim! And you've never ONCE come to my place!",
		"You've never invited me.",
		"It's a STUDIO, Jim! There's only room for me and Car... I mean BISCUIT!"]},
	{&"id": &"met", &"first": JIM, &"lines": [
		"My wife Carol and I met at a game just like this one, Tony. She was selling programs.",
		"That's BEAUTIFUL, Jim! Did you BUY one?",
		"I bought forty."]},
	{&"id": &"photo", &"first": TONY, &"lines": [
		"Is that a picture of your WIFE on the desk, Jim?",
		"That's Carol. I bring it to every broadcast.",
		"She looks GREAT, Jim! I mean... she looks like a great WIFE! For YOU!",
		"Thank you, Tony."]},
	{&"id": &"thursday", &"first": TONY, &"lines": [
		"Thursday is my FAVORITE day, Jim!",
		"What happens on Thursday?",
		"NOTHING! Nothing happens on Thursday! LOOK at that defense!"]},
	{&"id": &"book_club", &"first": JIM, &"lines": [
		"Carol has her book club on Thursdays, Tony. She comes home in a wonderful mood.",
		"That's GREAT, Jim! Good for CAROL!",
		"I've never seen her bring home a book.",
		"It's an AUDIO book club, Jim!"]},
	{&"id": &"couch", &"first": TONY, &"lines": [
		"How's the new couch, Jim? COMFY, right?",
		"I never told you we got a new couch.",
		"Lucky GUESS! Everybody's getting couches! It's COUCH SEASON, Jim!"]},
	{&"id": &"mayo_carol", &"first": JIM, &"lines": [
		"Carol has never once bought mayonnaise, Tony. That's love.",
		"She keeps a jar at... she PROBABLY doesn't! Great point, Jim!"]},
	{&"id": &"biscuit", &"first": TONY, &"lines": [
		"Biscuit LOVES Carol, Jim!",
		"When did Biscuit meet Carol?",
		"He's a very SOCIAL dog, Jim! He gets AROUND!",
		"Apparently."]},
	{&"id": &"deserve", &"first": JIM, &"lines": [
		"For the record, Tony, there's nobody I'd rather call a game with.",
		"JIM! That's the nicest thing you've EVER said to me!",
		"It won't happen again.",
		"I don't DESERVE you, Jim! I REALLY don't!"]},
	{&"id": &"anniversary", &"first": JIM, &"lines": [
		"It's our anniversary Saturday, Tony. I'm taking Carol to that Italian place.",
		"She HATES that place, Jim! Take her for SEAFOOD!",
		"How do you know what she...",
		"TOUCHDOWN! Was that a touchdown? It FELT like a touchdown!"]},
	{&"id": &"sweater", &"first": JIM, &"lines": [
		"Tony, that looks like my sweater.",
		"LOTS of people have this sweater, Jim!",
		"Carol knitted it.",
		"She's VERY productive, Jim!"]},
	{&"id": &"dinner", &"first": JIM, &"lines": [
		"Tony, Carol wants to have you over for dinner Thursday.",
		"THURSDAY? But Thursday is when I... YES! I'd LOVE to, Jim!",
		"She said you'd know the way.",
		"I have a GREAT sense of direction, Jim!"]},
]

const COMMISSIONER_CHAPTERS: Array[Dictionary] = [
	{&"id": &"missing", &"first": JIM, &"lines": [
		"We interrupt this broadcast with a statement from the league office. Quote: this morning, the commissioner of football did not arrive at work. His whereabouts are unknown. Anyone with information should contact the league at once. End quote.",
		"WEIRD, Jim! Nobody knows where he is! ESPECIALLY not us!",
		"Especially... not us."]},
	{&"id": &"day_two", &"first": JIM, &"lines": [
		"A statement from the league office. Quote: the commissioner remains missing. We are very worried. End quote.",
		"TERRIBLE, Jim! Just TERRIBLE! Anyway, how about this WEATHER?"]},
	{&"id": &"reward", &"first": JIM, &"lines": [
		"The league is now offering a reward for the commissioner's return, Tony. Five hundred dollars.",
		"FIVE HUNDRED? That's IT? For a whole COMMISSIONER?",
		"You sound disappointed, Tony.",
		"I'm sad for HIM, Jim!"]},
	{&"id": &"description", &"first": JIM, &"lines": [
		"The league has released a description, Tony. The commissioner was last seen wearing a gray suit and one shoe.",
		"ONE shoe? Where's the OTHER... I mean, what a MYSTERY!"]},
	{&"id": &"witness", &"first": JIM, &"lines": [
		"Police say the commissioner was last seen near this stadium, Tony. Getting into a car with two men in headsets.",
		"Could be ANYBODY, Jim!",
		"Lots of people wear headsets.",
		"It's a HEADSET town!"]},
	{&"id": &"closet", &"after": CAROL, &"first": TONY, &"lines": [
		"(muffled yelling) Did you hear something, Jim?",
		"I did not. (a thud)"]},
	{&"id": &"demands", &"first": JIM, &"lines": [
		"The league has received a list of demands, Tony. Two million dollars, and nachos in every booth.",
		"Who would ASK for that, Jim?",
		"And no mayonnaise within a mile of the stadium.",
		"MONSTERS!"]},
	{&"id": &"statement", &"first": JIM, &"lines": [
		"The league says, quote, we do not negotiate. Also, quote, please, he has our parking passes.",
		"(muffled shouting) QUIET, you! I mean... GO TEAM! (a thud)"]},
	{&"id": &"counter", &"first": JIM, &"lines": [
		"The league has countered with forty dollars and a gift basket, Tony.",
		"TAKE IT, Jim!",
		"We know nothing about it, Tony.",
		"RIGHT! Somebody ELSE should take it!"]},
	{&"id": &"snack", &"first": TONY, &"lines": [
		"Jim, can a commissioner eat NACHOS? Asking for a FRIEND!",
		"Through the gag, Tony?",
		"I'll make them SMALL!"]},
	{&"id": &"caught", &"first": JIM, &"lines": [
		"Tony, there are police officers at the booth door.",
		"Tell them we're ON THE AIR, Jim!",
		"They can hear the closet, Tony. (muffled cheering)"]},
	{&"id": &"apology", &"first": JIM, &"lines": [
		"The league has asked us to read the following. We are sorry we kidnapped the commissioner.",
		"VERY sorry! He was a DELIGHT!",
		"We have each been fined fourteen dollars.",
		"FOURTEEN? Jim, can you spot me?"]},
]

## Where the progress is kept. A test points this somewhere else.
static var save_path: String = "user://booth_story.cfg":
	set(value):
		save_path = value
		_loaded = false

## Chapters heard so far in each thread, once the file has been read.
static var _progress: Dictionary[StringName, int] = {}
static var _loaded: bool = false


## The chapters of `thread`, in order.
static func chapters(thread: StringName) -> Array[Dictionary]:
	match thread:
		CAROL:
			return CAROL_CHAPTERS
		COMMISSIONER:
			return COMMISSIONER_CHAPTERS
	push_warning("BoothStory: no thread called '%s'" % thread)
	return []


## Every chapter of every thread.
static func all_chapters() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for thread: StringName in THREADS:
		all.append_array(chapters(thread))
	return all


## How many chapters of `thread` the person has heard, from the first.
static func heard(thread: StringName) -> int:
	if not _loaded:
		_loaded = true
		_progress.clear()
		var file: ConfigFile = ConfigFile.new()
		var found: bool = file.load(save_path) == OK
		for id: StringName in THREADS:
			var count: int = 0
			if found:
				var old: int = int(file.get_value(SECTION, KEY_OLD, 0)) if id == CAROL else 0
				count = int(file.get_value(SECTION, id, old))
			_progress[id] = clampi(count, 0, chapters(id).size())
	return _progress.get(thread, 0)


## `thread` has been told to the end.
static func finished(thread: StringName) -> bool:
	return heard(thread) >= chapters(thread).size()


## The chapter of `thread` that comes next: nothing once it has been told, or
## while the chapter is waiting for another thread to end.
static func next(thread: StringName) -> Dictionary:
	if finished(thread):
		return {}
	var chapter: Dictionary = chapters(thread)[heard(thread)]
	if chapter.has(&"after") and not finished(chapter[&"after"]):
		return {}
	return chapter


## The thread whose next chapter is `id`, or none.
static func thread_of_next(id: StringName) -> StringName:
	for thread: StringName in THREADS:
		var chapter: Dictionary = next(thread)
		if not chapter.is_empty() and chapter[&"id"] == id:
			return thread
	return &""


## Chapter `id` has been heard to its last line. Only one that was next in
## its thread moves the story on.
static func mark_heard(id: StringName) -> void:
	var thread: StringName = thread_of_next(id)
	if thread == &"":
		return
	_progress[thread] += 1
	_save()


## The commissioner is in the closet, as far as the person has heard.
static func captive() -> bool:
	var told: int = heard(COMMISSIONER)
	var from: int = -1
	var until: int = -1
	var list: Array[Dictionary] = chapters(COMMISSIONER)
	for index: int in list.size():
		if list[index][&"id"] == CAPTIVE_FROM:
			from = index
		elif list[index][&"id"] == CAPTIVE_UNTIL:
			until = index
	return from >= 0 and told > from and told <= until


## Starts every thread over.
static func reset() -> void:
	_loaded = true
	for thread: StringName in THREADS:
		_progress[thread] = 0
	_save()


static func _save() -> void:
	var file: ConfigFile = ConfigFile.new()
	for thread: StringName in THREADS:
		file.set_value(SECTION, thread, _progress.get(thread, 0))
	var error: Error = file.save(save_path)
	if error != OK:
		push_warning("BoothStory: could not save to %s (%s)" % [save_path, error_string(error)])
