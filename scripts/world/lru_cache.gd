class_name LruCache
extends RefCounted
## Tiny least-recently-used map (Dictionary keeps insertion order; a hit re-inserts the key at the back).

var cap: int
var _d: Dictionary = {}


func _init(capacity: int = 256) -> void:
	cap = capacity


func has(k) -> bool:
	return _d.has(k)


## Value for k (touches it) or `default`.
func fetch(k, default = null):
	if not _d.has(k):
		return default
	var v = _d[k]
	_d.erase(k)
	_d[k] = v
	return v


func put(k, v) -> void:
	if _d.has(k):
		_d.erase(k)
	elif _d.size() >= cap:
		for old in _d:
			_d.erase(old)
			break
	_d[k] = v


func clear() -> void:
	_d.clear()


func size() -> int:
	return _d.size()
