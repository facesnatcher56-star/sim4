extends RefCounted
## Co-op stage 4: what a passive player can do while time cannot skip. Town stories (news log + public chronicle) reach the client as a diff-only
## "s" part of the delta; the waiting panel appears only when I have nothing to do, someone else is busy and time is neither skipping nor paused;
## the spectate camera follows the active player's folk and sends no orders.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

class FakeLotView extends Node:
	var focused: Array = []
	func focus_on(kind: String, id: int) -> void:
		focused.append([kind, id])

class FakeHud extends Node:
	var lot_view = null

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	if n is Button:
		s += (n as Button).text + "\n"
	for c in n.get_children():
		s += _all_text(c)
	return s

func run() -> Array:
	fails = []
	HoodKit.new_game("classic")
	StoryPacing.enabled = false
	Players.set_player(1, 1, "Hosty")
	HoodKit.run(5)
	var folk: Array = []
	for i in 2:
		var f2 := HouseholdSetup.random_folk("adult", "none", ["Zed", "Zoe"])
		f2["name"] = ["Zed", "Zoe"][i]
		folk.append(f2)
	var r := CoopHouseholds.join(2, "Ann", {"name": "Newcomers", "folk": folk}, "")
	_check(r["ok"], "guest joined")
	if not r["ok"]:
		HoodKit.teardown()
		return fails
	# stories: news log + public chronicle only
	Story.news.clear()
	ChronicleHook.reset()
	Story._log("The bakery opened.")
	ChronicleHook.note("birth", "A baby was born on Elm Street.", [], "", 2, true)
	ChronicleHook.note("secret", "A private matter.", [], "", 3, false)
	var lines := CoopStories.lines_for(2)
	var text := JSON.stringify(lines)
	_check(text.contains("bakery") and text.contains("baby") and not text.contains("private"), "stories: news and public chronicle, not private notes (%s)" % text)
	for i in 30:
		Story._log("Gossip number %d." % i)
	_check(CoopStories.lines_for(2).size() == CoopStories.MAX_LINES, "at most %d lines" % CoopStories.MAX_LINES)
	# the delta carries them once, then only when they change
	var live := CoopLive.new()
	var st := live.new_peer()
	var d := live.build(st, 2, 10.0)
	_check(d.has("s") and (d["s"] as Array).size() == CoopStories.MAX_LINES, "first delta carries the stories")
	HoodKit.run(1)
	var d2 := live.build(st, 2, 11.0)
	_check(not d2.has("s"), "an unchanged story list is not sent again")
	Story._log("Something new happened.")
	HoodKit.run(1)
	var d3 := live.build(st, 2, 12.0)
	_check(d3.has("s") and JSON.stringify(d3["s"]).contains("Something new"), "a new story is sent")
	CoopStories.reset()
	CoopView.apply(CoopLive.decode(live.encode(d3)))
	_check(CoopStories.feed.size() == CoopStories.MAX_LINES and JSON.stringify(CoopStories.feed).contains("Something new"), "the client keeps the feed")
	CoopStories.apply("junk")
	_check(CoopStories.feed.is_empty(), "garbage feed is ignored")
	CoopStories.apply([[3, "x".repeat(500)], [1], "no", [2, "ok"]])
	_check(CoopStories.feed.size() == 2 and str(CoopStories.feed[0][1]).length() <= CoopStories.MAX_TEXT, "feed is bounded and plain")
	# when is a player waiting?
	for g in WorldIface.all_folk():
		if int(g.household_id) == int(r["hid"]):
			g.set_meta("away", "work")                 # the guest's household is away
	var st_run := {"skip": false, "paused": false}
	_check(CoopWaiting.waiting(st_run, 2), "guest away, host busy, no skip: the guest waits")
	_check(not CoopWaiting.waiting(st_run, 1), "the busy host does not wait")
	_check(not CoopWaiting.waiting({"skip": true, "paused": false}, 2), "while time skips nobody waits")
	_check(not CoopWaiting.waiting({"skip": false, "paused": true}, 2), "nor while paused")
	_check(CoopWaiting.active_players(2) == [1], "the host is the active player")
	var rows := CoopWaiting.folk_lines(1, 2)
	_check(rows.size() >= 3 and str(rows[0]["text"]).contains(":"), "the guest can watch the host's folk (%d rows)" % rows.size())
	# the panel: stories first, spectate follows the host's folk, no commands
	var hud := FakeHud.new()
	var lv := FakeLotView.new()
	hud.lot_view = lv
	var panel := CoopWaiting.new()
	panel.hud = hud
	var root: Window = Engine.get_main_loop().root
	root.add_child(hud)
	root.add_child(panel)
	var prev_local := Players.local_id
	Players.local_id = 2
	panel.update_state(st_run)
	_check(panel.visible and _all_text(panel).contains("Something new") and _all_text(panel).contains("Watch Hosty"), "the panel shows the town stories and a watch tab")
	panel._set_mode("watch:1")
	_check(lv.focused.size() == 1 and lv.focused[0][0] == "folk" and int(rows[0]["id"]) == lv.focused[0][1], "watching moves the camera to the active player's folk")
	_check(_all_text(panel).contains("Back to my household"), "and offers a way back")
	panel.update_state({"skip": true, "paused": false})
	_check(not panel.visible, "the panel hides when time skips")
	Players.local_id = prev_local
	panel.queue_free()
	hud.queue_free()
	HoodKit.teardown()
	return fails
