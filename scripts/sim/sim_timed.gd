class_name SimTimed
extends RefCounted
## Timed wake-ups keyed by absolute game minute ("wake folk 12 at 07:00", "fire stage change at minute X", "bill due day 9").
## Deterministic: due entries fire ordered by (minute, seq), seq = registration order. Cost when nothing is due: one comparison.

var _by_min: Dictionary = {}      # minute -> Array of entries [seq, owner, name, fn, args]
var _mins: Array = []             # sorted distinct pending minutes
var _min_of: Dictionary = {}      # seq -> minute (for cancel)
var _seq: int = 0

func size() -> int:
	return _min_of.size()

func add(minute: int, owner: String, name: String, fn: Callable, args: Array = []) -> int:
	_seq += 1
	if not _by_min.has(minute):
		_by_min[minute] = []
		_mins.insert(_mins.bsearch(minute), minute)
	(_by_min[minute] as Array).append([_seq, owner, name, fn, args])
	_min_of[_seq] = minute
	return _seq

func cancel(id: int) -> bool:
	if not _min_of.has(id):
		return false
	var minute: int = _min_of[id]
	_min_of.erase(id)
	var list: Array = _by_min[minute]
	for i in list.size():
		if int(list[i][0]) == id:
			list.remove_at(i)
			break
	if list.is_empty():
		_by_min.erase(minute)
		_mins.remove_at(_mins.bsearch(minute))
	return true

func cancel_owner(owner: String) -> int:
	var ids: Array = []
	for minute in _by_min:
		for e in _by_min[minute]:
			if e[1] == owner:
				ids.append(int(e[0]))
	for id in ids:
		cancel(id)
	return ids.size()

func next_minute() -> int:
	return int(_mins[0]) if not _mins.is_empty() else -1

## Remove and return every entry due at or before `now`, in (minute, seq) order.
func pop_due(now: int) -> Array:
	var out: Array = []
	while not _mins.is_empty() and int(_mins[0]) <= now:
		var minute: int = _mins.pop_front()
		for e in _by_min[minute]:
			_min_of.erase(int(e[0]))
			out.append(e)
		_by_min.erase(minute)
	return out
