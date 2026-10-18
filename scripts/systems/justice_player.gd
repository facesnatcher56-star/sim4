class_name JusticePlayer
extends RefCounted
## Everything where the PLAYER's folk meets the justice system: clear prompts with choices (robbery reaction, a dangerous grudge, a plea,
## a lawyer, testimony) and being held away from the lot (custody, court, jail, prison, community service) through Away, like the hospital.
##   JusticePlayer.ask(folk_id, title, text, [{id,label}], on_choice(choice_id), default_id)
##       shows the case prompt (CasePrompt registers `ask_fn`); without a UI (tests, headless, non-player folk) the default is chosen at once.
##   JusticePlayer.hold(folk, minutes, reason, label)   Away.send with a label; the folk is hidden on the map and sees a status chip.
##   JusticePlayer.status_chips(folk)                    [{text, color, tip}] for the folk panel

static var ask_fn: Callable = Callable()       # set by the UI: (folk_id, title, text, options, on_choice, default_id)
static var auto: String = ""                   # tests: force this choice id when it is among the options
static var log: Array = []                     # last prompts [{pid, title, text, options, choice}] (tests and the case board)

static func reset() -> void:
	auto = ""
	log.clear()

static func ask(pid: int, title: String, text: String, options: Array, on_choice: Callable, default_id: String) -> void:
	var entry: Dictionary = {"pid": pid, "title": title, "text": text, "options": options.map(func(o): return str(o["id"])), "choice": ""}
	log.append(entry)
	while log.size() > 30:
		log.pop_front()
	if not CrimePerson.is_player(pid):
		entry["choice"] = default_id
		on_choice.call(default_id)
		return
	if auto != "" and (entry["options"] as Array).has(auto):
		entry["choice"] = auto
		on_choice.call(auto)
		return
	if ask_fn.is_valid():
		var wrapped: Callable = func(choice):
			entry["choice"] = str(choice)
			on_choice.call(choice)
		ask_fn.call(pid, title, text, options, wrapped, default_id)
		return
	entry["choice"] = default_id
	on_choice.call(default_id)

## A one-button information screen (verdict, sentence). Never blocks: the effect already happened.
static func tell(pid: int, title: String, text: String) -> void:
	ask(pid, title, text, [{"id": "ok", "label": "OK"}], func(_c): pass, "ok")

## Send a player folk away for `minutes` (custody, court, jail ...). Returns false for non-residents or when already away.
static func hold(f, minutes: float, reason: String, label: String) -> bool:
	if f == null or not SysUtil.is_resident(f):
		return false
	if Away.is_away(int(f.id)):
		var why: String = str(Away.info(int(f.id)).get("reason", ""))
		if why in ["work", "school", "party", "travel"]:
			Away.recall(int(f.id), "arrested")
		elif why == "hospital":
			Hospital.discharge(int(f.id))
		else:
			Away.recall(int(f.id), "arrested")
	for q in f.queue.duplicate():
		if (q as Interaction).def_id == Away.IID:
			f.queue.erase(q)
	Away.pending.erase(int(f.id))
	f.clear_queue()
	f.cancel_current("arrested")
	f.add_buff("in_custody")
	return Away.send(f, maxf(minutes, 2.0), reason, {"label": label})

static func release(f) -> void:
	if f == null:
		return
	f.remove_buff("in_custody")
	if Away.is_away(int(f.id)) and str(Away.info(int(f.id)).get("reason", "")) in ["custody", "jail", "prison", "court", "service"]:
		Away.recall(int(f.id), "released")
	else:
		for q in f.queue.duplicate():
			if (q as Interaction).def_id == Away.IID:
				f.queue.erase(q)
		Away.pending.erase(int(f.id))

static func status_chips(f) -> Array:
	var out: Array = []
	var pid: int = int(f.id)
	if JusticeState.inmates.has(pid):
		var ins: Dictionary = JusticeState.inmates[pid]
		var until: String = "for a long time" if int(ins["until"]) >= 100000 else "until day %d" % (int(ins["until"]) + 1)
		var kind: String = str(ins["kind"])
		out.append({"text": {"custody": "In custody", "remand": "Held for trial", "jail": "In jail", "prison": "In prison"}.get(kind, "In custody"),
			"color": Color("#8a5cf6"), "tip": "Away from home %s. Friends and family can visit." % until})
	if JusticeState.probation.has(pid) and int(JusticeState.probation[pid]) >= SysUtil.day():
		out.append({"text": "On probation", "color": Color("#c9b037"), "tip": "Any new crime is punished harder until day %d." % (int(JusticeState.probation[pid]) + 1)})
	if JusticeState.service.has(pid):
		out.append({"text": "Community service", "color": Color("#4aa3a2"), "tip": "%d days of service left." % int(JusticeState.service[pid]["days_left"])})
	return out
