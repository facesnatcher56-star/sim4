class_name SimJob
extends RefCounted
## One registered unit of periodic work in a SimScheduler (see sim_scheduler.gd). Plain data + the bucket bookkeeping.
## Bucketed jobs own an id list per slot: slot = id % cadence, so for N tracked ids about N / cadence of them run each minute.

var name: String = ""
var owner: String = ""            # system name, for stats / the registry table
var group: String = ""            # installer key: a whole group is enabled / disabled / removed together
var cadence: int = 1              # minutes between runs: 1, 5, 15, 60 (hour) or 1440 (day); bucketed jobs: the period every id is visited
var phase: int = 0                # plain jobs with cadence 5 / 15: runs when (total_minutes - phase) % cadence == 0
var order: int = 0                # position inside the layer (lower first); ties broken by registration order (seq)
var seq: int = 0
var prio: int = 1                 # SimScheduler.CRITICAL / NORMAL / LOW
var fn: Callable = Callable()
var arg_kind: String = ""         # "" = fn(), otherwise fn(value): the minute total, the hour or the day number
var active: Callable = Callable() # optional emptiness gate: returns false = nothing to do, the job costs one call and nothing else
var note: String = ""             # tier behaviour / active set / caps, shown in SimScheduler.describe()
var enabled: bool = true
var removed: bool = false
# bucketed jobs
var slots: Array = []             # slots[s] = ids visited when total_minutes % cadence == s
var count: int = 0                # tracked ids
# stats
var calls: int = 0
var usec: int = 0
var deferred: int = 0             # times a due run was postponed by the frame budget
var coalesced: int = 0            # due runs merged into an already postponed one
var idle_skips: int = 0
var last_batch: int = 0
var max_batch: int = 0
var items: int = 0                # bucketed: ids processed in total

func is_bucketed() -> bool:
	return not slots.is_empty()

func make_buckets() -> void:
	slots = []
	for i in cadence:
		slots.append([])

func track(id: int) -> void:
	var s: Array = slots[posmod(id, cadence)]
	if not s.has(id):
		s.append(id)
		count += 1

func untrack(id: int) -> void:
	var s: Array = slots[posmod(id, cadence)]
	var i := s.find(id)
	if i >= 0:
		s.remove_at(i)
		count -= 1

func cadence_label() -> String:
	match cadence:
		1: return "minute"
		60: return "hour"
		1440: return "day"
	return "%d min" % cadence
