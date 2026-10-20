class_name Canon
extends RefCounted
## Canonical serialization — the single implementation of the format contract in
## `docs/ENGINEERING.md` §9 (S1.1a). Everything that has to be compared
## byte-for-byte (world generation, save migrations, golden fixtures) goes
## through this file instead of `JSON.stringify()`.
##
## Rules (all of them are asserted by `tools/verify.gd::s1_1_canon`):
##   * keys are sorted by Unicode code point, ascending, recursively
##     (`Array.sort()` on Strings — note `String.unicode_compare()` does not
##     exist in Godot 4, the docs used to claim it did);
##   * 2-space indent, `\n` line endings only, no BOM, exactly one trailing `\n`;
##   * integers are written as decimal; floats are written as integers when the
##     value is integral, otherwise as `%.6f` — Godot's JSON parser turns *every*
##     number into a float, so a pure `%.6f` format could never round-trip;
##   * the root object must carry an integer `schema` field;
##   * arrays keep their order (order is data, not an artifact of iteration);
##   * anything that is not `null`/`bool`/`int`/`float`/`String`/`Array`/`Dictionary`
##     (e.g. `Vector3`, `Color`, `Object`) is a hard failure with the offending
##     key path — never a silent `str(v)`, which would turn "byte identical"
##     into "Str() identical".
##
## All entry points return a Dictionary instead of a bare String on purpose:
## an empty string is indistinguishable from "valid but empty output", and a
## caller that ignores an error must have to ignore an explicit `ok` flag.

const SCHEMA_KEY := "schema"
const INDENT := "  "
const FLOAT_DECIMALS := 6
const MAX_DEPTH := 64
## Largest float that is still exactly representable as an int64.
const INT_EXACT_LIMIT := 9007199254740992.0


## ![String] → `{ok, text, reason}`. `text` is "" when `ok` is false.
static func to_text(value: Variant) -> Dictionary:
	var w := _Writer.new()
	var text := w.write(value)
	if not w.error.is_empty():
		return {"ok": false, "text": "", "reason": w.error}
	return {"ok": true, "text": text, "reason": ""}


## ![String] → `{ok, value, reason}`. Numbers come back as floats (Godot JSON).
static func from_text(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {
			"ok": false,
			"value": null,
			"reason": "JSON 解析失败（第 %d 行）：%s" % [parser.get_error_line(), parser.get_error_message()],
		}
	return {"ok": true, "value": parser.data, "reason": ""}


## ![String] → `{ok, text, reason}`: parse then re-emit in canonical form.
## Useful for "is this file already canonical?" and for future save migrations.
static func canonicalize(text: String) -> Dictionary:
	var parsed := from_text(text)
	if not bool(parsed["ok"]):
		return {"ok": false, "text": "", "reason": String(parsed["reason"])}
	return to_text(parsed["value"])


## Write `value` to `path` as canonical text and read it back to prove the bytes.
## `{ok, path, bytes, sha256, reason}`. Overwrites: this is for deterministic
## artifacts, durability (tmp + rename) is `SaveSystem`'s job, not ours.
static func write_file(path: String, value: Variant) -> Dictionary:
	var built := to_text(value)
	if not bool(built["ok"]):
		return {"ok": false, "path": path, "bytes": 0, "sha256": "", "reason": String(built["reason"])}
	var text := String(built["text"])
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return {
				"ok": false, "path": path, "bytes": 0, "sha256": "",
				"reason": "无法创建目录 %s：%s" % [dir, error_string(made)],
			}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false, "path": path, "bytes": 0, "sha256": "",
			"reason": "无法写入 %s：%s" % [path, error_string(FileAccess.get_open_error())],
		}
	file.store_string(text)
	file.flush()
	file.close()
	var back := FileAccess.get_file_as_string(path)
	if back != text:
		return {
			"ok": false, "path": path, "bytes": 0, "sha256": "",
			"reason": "写入后回读不一致（写入 %d 字节，回读 %d 字节）" % [
				text.to_utf8_buffer().size(), back.to_utf8_buffer().size(),
			],
		}
	return {
		"ok": true,
		"path": path,
		"bytes": text.to_utf8_buffer().size(),
		"sha256": FileAccess.get_sha256(path),
		"reason": "",
	}


## True for ints and for floats that hold an integral value (JSON parse gives us
## floats, so "this number is an integer" cannot be a `typeof()` check alone).
static func is_integral(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			var f := float(value)
			return is_finite(f) and f == floorf(f)
		_:
			return false


## ---------------------------------------------------------------------------
##  Writer — one instance per call so a failure cannot leak into the next value.
## ---------------------------------------------------------------------------
class _Writer:
	extends RefCounted

	var error := ""

	func write(value: Variant) -> String:
		if typeof(value) == TYPE_DICTIONARY:
			var root: Dictionary = value
			if not root.has(Canon.SCHEMA_KEY):
				return _fail("$." + Canon.SCHEMA_KEY, "顶层对象缺少 `schema` 字段（整数字段，用于版本判定）")
			if not Canon.is_integral(root[Canon.SCHEMA_KEY]):
				return _fail("$." + Canon.SCHEMA_KEY,
						"`schema` 必须是整数（实际 %s）" % type_string(typeof(root[Canon.SCHEMA_KEY])))
		var text := _value(value, "$", 0)
		if not error.is_empty():
			return ""
		return text + "\n"

	func _value(value: Variant, path: String, depth: int) -> String:
		if depth > Canon.MAX_DEPTH:
			return _fail(path, "嵌套超过 %d 层（疑似自引用结构）" % Canon.MAX_DEPTH)
		match typeof(value):
			TYPE_NIL:
				return "null"
			TYPE_BOOL:
				return "true" if bool(value) else "false"
			TYPE_INT:
				return str(int(value))
			TYPE_FLOAT:
				return _number(float(value), path)
			TYPE_STRING:
				return JSON.stringify(String(value))
			TYPE_DICTIONARY:
				return _dictionary(value, path, depth)
			TYPE_ARRAY:
				return _array(value, path, depth)
			_:
				return _fail(path, "不支持的值的类型 `%s`（只接受 null / bool / int / float / String / Array / Dictionary）"
						% type_string(typeof(value)))

	func _number(f: float, path: String) -> String:
		if not is_finite(f):
			return _fail(path, "非有限浮点（NaN / Inf）不是合法 JSON 数字")
		if f == floorf(f):
			if absf(f) <= Canon.INT_EXACT_LIMIT:
				return str(int(f))
			return "%.0f" % f
		var text := "%.6f" % f
		# `%.6f` renders -1e-9 as "-0.000000"; normalise so ±epsilon agree.
		if text == "-0.000000":
			text = "0.000000"
		return text

	func _dictionary(value: Variant, path: String, depth: int) -> String:
		var dict: Dictionary = value
		if dict.is_empty():
			return "{}"
		var keys: Array = dict.keys()
		for k in keys:
			if typeof(k) != TYPE_STRING:
				return _fail(path, "字典的键必须是 String（实际 %s）" % type_string(typeof(k)))
		keys.sort()
		var pad := Canon.INDENT.repeat(depth + 1)
		var parts := PackedStringArray()
		for k in keys:
			var key := String(k)
			var child := _value(dict[k], path + "." + key, depth + 1)
			if not error.is_empty():
				return ""
			parts.append(pad + JSON.stringify(key) + ": " + child)
		return "{\n" + ",\n".join(parts) + "\n" + Canon.INDENT.repeat(depth) + "}"

	func _array(value: Variant, path: String, depth: int) -> String:
		var arr: Array = value
		if arr.is_empty():
			return "[]"
		var pad := Canon.INDENT.repeat(depth + 1)
		var parts := PackedStringArray()
		for i in arr.size():
			var child := _value(arr[i], "%s[%d]" % [path, i], depth + 1)
			if not error.is_empty():
				return ""
			parts.append(pad + child)
		return "[\n" + ",\n".join(parts) + "\n" + Canon.INDENT.repeat(depth) + "]"

	func _fail(path: String, why: String) -> String:
		if error.is_empty():
			# A self-referential structure makes the path explode to hundreds of
			# `.self` segments; keep the message readable, the cause is the tail.
			var shown := path
			if shown.length() > 72:
				shown = "…" + shown.right(60)
			error = "%s：%s" % [shown, why]
		return ""
