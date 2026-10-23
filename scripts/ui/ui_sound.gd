class_name UISound
extends RefCounted
## Task 59: one place for the small UI sounds (coin in / out, skill up, an order given...). There is no audio in the game yet: `cue(name)` plays
## res://assets/sounds/<name>.ogg when that file exists and does nothing otherwise, so adding a sound later is dropping a file in.

static var _cache: Dictionary = {}          # name -> AudioStream or null


static func cue(name: String) -> void:
	if not _cache.has(name):
		var p := "res://assets/sounds/%s.ogg" % name
		_cache[name] = load(p) if ResourceLoader.exists(p) else null
	var st = _cache[name]
	if st == null:
		return
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.bus = "Master"
	(ml as SceneTree).root.add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
