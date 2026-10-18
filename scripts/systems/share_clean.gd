class_name ShareClean
extends RefCounted
## Sanitising primitives for shared files (data/share_schema.json holds the caps). Everything read from a shared file is
## untrusted: text is stripped of control characters and markup, numbers must be finite and are clamped, ids are never kept.

static var _schema: Dictionary = {}

static func schema() -> Dictionary:
	if _schema.is_empty():
		var fa := FileAccess.open("res://data/share_schema.json", FileAccess.READ)
		if fa != null:
			var v = JSON.parse_string(fa.get_as_text())
			if v is Dictionary:
				_schema = v
	return _schema

static func cap(key: String, def: Variant = 0) -> Variant:
	return schema().get(key, def)

## Display text: control characters, markup / BBCode brackets and path separators removed, whitespace collapsed, length capped.
static func text(v: Variant, max_len: int) -> String:
	if not (v is String):
		return ""
	var out := ""
	for i in (v as String).length():
		var c: int = (v as String).unicode_at(i)
		if c < 32 or (c >= 127 and c < 160) or c == 0x2028 or c == 0x2029 or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E):
			c = 32
		if c == 0xFFFD or c in [60, 62, 91, 93, 123, 125, 92, 47, 96]:       # < > [ ] { } \ / `
			continue
		out += String.chr(c)
	var parts: PackedStringArray = out.split(" ", false)
	out = " ".join(parts)
	while out.find("..") >= 0:
		out = out.replace("..", ".")
	return out.substr(0, max_len).strip_edges()

## A lower-case id-like key ([a-z0-9_]), capped.
static func key(v: Variant, max_len: int = 32) -> String:
	if not (v is String):
		return ""
	var out := ""
	for i in (v as String).length():
		var ch: String = (v as String)[i].to_lower()
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	return out.substr(0, max_len)

static func is_hex(v: Variant) -> bool:
	if not (v is String) or (v as String).length() != 7 or not (v as String).begins_with("#"):
		return false
	return (v as String).substr(1).is_valid_hex_number()

## True for an int or a finite float.
static func is_num(v: Variant) -> bool:
	if v is int:
		return true
	return v is float and not is_nan(v) and not is_inf(v)

static func is_whole(v: Variant) -> bool:
	return v is int or (v is float and is_num(v) and v == floorf(v))

static func clampf_(v: Variant, lo: float, hi: float, def: float = 0.0) -> float:
	return clampf(float(v), lo, hi) if is_num(v) else def

static func clampi_(v: Variant, lo: int, hi: int, def: int = 0) -> int:
	return clampi(int(float(v)), lo, hi) if is_num(v) else def

## A string that tries to leave the sandbox (path traversal, absolute or engine paths).
static func bad_path(s: String) -> bool:
	var l := s.to_lower()
	return l.find("../") >= 0 or l.find("..\\") >= 0 or l.find("res://") >= 0 or l.find("user://") >= 0 or l.find(":\\") >= 0 or l.find("file://") >= 0

## Walks any value: finite numbers inside +-max_abs, strings capped and free of bad paths, node and depth caps, keys are strings.
## Returns "" when fine, else a reason.
static func scan(v: Variant, state: Dictionary = {}, depth: int = 0, max_str: int = -1) -> String:
	if state.is_empty():
		state["n"] = 0
	state["n"] = int(state["n"]) + 1
	if int(state["n"]) > int(cap("max_nodes", 600000)):
		return "the file is too big or complex"
	if depth > int(cap("max_depth", 24)):
		return "the file is nested too deeply"
	if v is Dictionary:
		for k in (v as Dictionary):
			if not (k is String) or (k as String).length() > 80 or bad_path(k):
				return "an entry has a bad name"
			var r := scan(v[k], state, depth + 1, max_str)
			if r != "":
				return r
	elif v is Array:
		for x in (v as Array):
			var r2 := scan(x, state, depth + 1, max_str)
			if r2 != "":
				return r2
	elif v is String:
		if (v as String).length() > (max_str if max_str > 0 else int(cap("max_string", 600))) or bad_path(v):
			return "a text is too long or points outside the game"
	elif v is float or v is int:
		if not is_num(v) or absf(float(v)) > float(cap("max_abs_number", 1000000000)):
			return "a number is out of range"
	elif v != null and not (v is bool):
		return "an unsupported value"
	return ""
