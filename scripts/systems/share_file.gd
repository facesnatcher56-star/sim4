class_name ShareFile
extends RefCounted
## Reading and writing shared files in user://exports/ (plain JSON). Only plain file names are accepted (no folders, no ".."),
## the extension must match, and the size is checked BEFORE the file is read.

static var dir_override: String = ""      # tests point this at a scratch folder

static func dir() -> String:
	return dir_override if dir_override != "" else str(ShareClean.cap("export_dir", "user://exports"))

static func shown_path() -> String:
	return ProjectSettings.globalize_path(dir())

## A safe file stem: letters, digits, space, dash, underscore.
static func stem(title: String) -> String:
	var out := ""
	for i in title.length():
		var ch := title[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in [" ", "-", "_"]:
			out += ch
	out = out.strip_edges().replace(" ", "_").substr(0, 40)
	return out if out != "" else "shared"

static func ext_of(kind: String) -> String:
	return str(ShareClean.cap(kind + "_ext", kind))

## A plain file name with the right extension and nothing that can leave the folder.
static func valid_name(file_name: String, ext: String) -> bool:
	if file_name == "" or file_name.length() > 80 or file_name != file_name.get_file():
		return false
	if file_name.find("..") >= 0 or file_name.find(":") >= 0 or file_name.find("\\") >= 0 or file_name.find("/") >= 0 or file_name.find("%") >= 0:
		return false
	return file_name.get_extension().to_lower() == ext

static func write(kind: String, title: String, data: Dictionary) -> Dictionary:
	var ext := ext_of(kind)
	DirAccess.make_dir_recursive_absolute(dir())
	var name := "%s.%s" % [stem(title), ext]
	var n := 2
	while FileAccess.file_exists("%s/%s" % [dir(), name]) and n < 100:
		name = "%s_%d.%s" % [stem(title), n, ext]
		n += 1
	var fa := FileAccess.open("%s/%s" % [dir(), name], FileAccess.WRITE)
	if fa == null:
		return {"ok": false, "error": "cannot write to the exports folder", "file": ""}
	fa.store_string(JSON.stringify(data))
	fa.close()
	return {"ok": true, "error": "", "file": name, "path": "%s/%s" % [shown_path(), name]}

## {ok, error, data}: the parsed JSON of an exports file (still untrusted: pass it to ShareValidate).
static func read(kind: String, file_name: String) -> Dictionary:
	var ext := ext_of(kind)
	if not valid_name(file_name, ext):
		return ShareValidate.fail("that is not a valid file name")
	var path := "%s/%s" % [dir(), file_name]
	if not FileAccess.file_exists(path):
		return ShareValidate.fail("the file was not found")
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ShareValidate.fail("the file cannot be opened")
	var limit: int = int(ShareClean.cap("max_%s_bytes" % kind, 262144))
	if fa.get_length() > limit:
		return ShareValidate.fail("the file is too big (limit %d KB)" % int(limit / 1024))
	var text := fa.get_as_text()
	fa.close()
	return parse(text, limit)

static func parse(text: String, limit: int) -> Dictionary:
	if text.length() > limit:
		return ShareValidate.fail("the file is too big")
	var js := JSON.new()
	if js.parse(text) != OK or not (js.data is Dictionary):
		return ShareValidate.fail("the file is damaged or is not a Sim 4 file")
	return ShareValidate.good(js.data)

static func list(kind: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir())
	if d == null:
		return out
	var ext := ext_of(kind)
	for f in d.get_files():
		if valid_name(f, ext):
			out.append(f)
	out.sort()
	return out
