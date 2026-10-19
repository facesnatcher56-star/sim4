class_name CoopAlerts
extends RefCounted
## Turns big game events into CoopTime alerts (stop a skip, tell the right player(s)). Host only. Listens to `Events.game_event`.
## Any system can raise one itself: `SysUtil.game_event("coop_alert", {alert_players: [ids], text, folk_id})`; an `alert_players` list in
## any listed payload overrides the automatic choice. Automatic choice: the household of `folk_id` / `target_id`, the owner of `lot`
## (the host's "home" or a converted townie home), or EVERYONE for town-wide disasters.

const EVENTS := {
	"fire_started": "A fire has broken out at %s!",
	"fire_alarm": "A fire alarm is going off at %s!",
	"murder_warning": "%s is in a murderous rage!",
	"died": "%s has died.",
	"arrested": "%s has been arrested.",
	"child_services_warning": "Child services is warning about %s.",
	"labour": "%s is going into labour!",
	"labor": "%s is going into labour!",
	"phone_call": "%s has a phone call.",
}
const DISASTER_PHASES := ["start", "siren", "impact"]

var time: CoopTime
var _connected := false

func _init(p_time: CoopTime = null) -> void:
	time = p_time

func connect_events() -> void:
	if not _connected:
		SimEnv.events().game_event.connect(on_event)
		_connected = true

func disconnect_events() -> void:
	if _connected:
		SimEnv.events().game_event.disconnect(on_event)
		_connected = false

func on_event(ev: String, payload: Dictionary) -> void:
	if time == null:
		return
	var text := ""
	var fid := int(payload.get("folk_id", -1))
	match ev:
		"coop_alert":
			text = str(payload.get("text", "Something is happening."))
		"disaster":
			if not DISASTER_PHASES.has(str(payload.get("phase", ""))):
				return
			text = "A %s warning for the whole town!" % str(payload.get("kind", "disaster")).replace("_", " ")
		"chronicle":
			if int(payload.get("severity", 1)) < 4:
				return
			text = str(payload.get("text", "Something serious happened."))
			if (payload.get("subjects", []) as Array).size() > 0:
				fid = int((payload["subjects"] as Array)[0])
		_:
			if not EVENTS.has(ev):
				return
			text = str(EVENTS[ev]) % _subject(payload, fid)
	var pids := players_for(ev, payload, fid)
	if not pids.is_empty():
		time.alert(pids, text, fid)

func _subject(payload: Dictionary, fid: int) -> String:
	if payload.has("lot"):
		return "your home" if str(payload["lot"]) == Neighborhood.HOME else Neighborhood.label_of(str(payload["lot"]))
	return SysUtil.folk_name(fid)

func players_for(ev: String, payload: Dictionary, fid: int) -> Array:
	var out: Array = []
	if payload.has("alert_players"):
		for p in payload["alert_players"]:
			out.append(int(p))
		return out
	if ev == "disaster":
		return time.players()
	var f = WorldIface.get_folk(fid)
	var t = WorldIface.get_folk(int(payload.get("target_id", -1)))
	for g in [f, t]:
		if g != null:
			var p := Players.player_of(int(g.household_id))
			if p > 0 and not out.has(p):
				out.append(p)
	if payload.has("lot"):
		var lp := PlayerLots.player_of_lot(str(payload["lot"]))
		if lp > 0 and not out.has(lp):
			out.append(lp)
	var live: Array = time.players()
	return out.filter(func(p): return live.has(p))
