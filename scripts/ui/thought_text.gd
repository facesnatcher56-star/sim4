class_name ThoughtText
extends RefCounted
## Adds variety to the most repeated thought balloons (and says what the Folk is about to do) without touching the data tables.
const VARIANTS := {
	"Hmm... what to do...": ["Hmm... what to do...", "Nothing pressing. I'll daydream a little.", "Let me just think for a moment."],
	"So sleepy...": ["So sleepy...", "I need to lie down soon.", "Time to get some sleep."],
	"I'm hungry...": ["I'm hungry...", "I could eat something.", "Time to find some food."],
	"I should find a toilet.": ["I should find a toilet.", "I need the bathroom soon."],
	"I could use a wash.": ["I could use a wash.", "A shower would be nice."],
	"I wish someone would talk to me.": ["I wish someone would talk to me.", "I'd love some company."],
	"I need something to do.": ["I need something to do.", "Restless... is anything fun around?"],
	"Let me play something.": ["Let me play something.", "Time for a little music.", "I'll play a tune."],
	"Scales, scales, scales.": ["Scales, scales, scales.", "Practice makes perfect."],
	"Time to freshen up.": ["Time to freshen up.", "A shower, then I'll feel human."],
	"I'll read for a while.": ["I'll read for a while.", "Let me find out what happens next."],
	"What's on?": ["What's on?", "Let's see what's on TV."],
	"I'm starving!": ["I'm starving!", "I really need to eat. Now."],
}
const REPEAT_BLOCK_SEC := 45.0

static func vary(text: String) -> String:
	if VARIANTS.has(text):
		var opts: Array = VARIANTS[text]
		return str(opts[randi() % opts.size()])
	return text
