class_name L10n
extends RefCounted
## L10n — 把 key 变成"给玩家看的字"的唯一入口（S1.5a）。
##
## WHY THIS EXISTS。 面向玩家的文案一律走 key：`data/i18n/strings.csv` 是**唯一**
## 存明文的地方，代码里只出现 `SETTLEMENT_KIND_VILLAGE` 这类标识符。换语言只改数据，
## 不动存档、不重编译；反过来，代码里出现中文字面量就是违例（守卫规则
## `hardcoded_text`，见 `tools/verify.gd`）。
##
## REGISTRATION, NOT A PRIVATE DICTIONARY。 读 CSV 后建 `Translation` 并交给
## `TranslationServer.add_translation()`，所以产品代码用的是**引擎的 `tr()`**，
## 而不是自造的查表函数：将来接 `.translation` / PO 只需要换注册源，调用点不动。
##
## NOT AN AUTOLOAD。 autoload 名额 9/10（§3.1 是硬上限），这里用 `class_name` + 静态
## 状态，首次用到才读盘。没有进程回调，也没有 `Time.*`（S0.6 的冻结规则不适用于它）。
##
## MISSING KEY FALLS BACK LOUDLY。 缺 key 时回退成 key 本身 + `push_warning`，每个
## key 只警告一次。回退刻意显眼：静默给空串会让"文案没接上"看起来像"这栏本来就没字"。
##
## COLUMN LAYOUT。 第一列固定是 `keys`，其余每一列是一种语言（当前只有 `zh_CN`）。
## 新增语言 = 在 CSV 里加一列，代码零改动。

const PATH := "res://data/i18n/strings.csv"
const KEY_COLUMN := "keys"
## `tr()` 没命中时的兜底语言（也是当前唯一的语言）。
const DEFAULT_LOCALE := "zh_CN"

static var _loaded := false
static var _keys := PackedStringArray()
static var _locales := PackedStringArray()
static var _translations := {}
static var _warned := {}


## 幂等：读一次盘，注册一次翻译。返回"确实读到了东西"。
## 任何产品入口都可以无脑先调它；重复调用不产生第二次 IO。
static func ensure() -> bool:
	if _loaded:
		return not _keys.is_empty()
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("L10n 读不到 %s：所有 key 都会回退成 key 本身" % PATH)
		return false
	var header := f.get_csv_line()
	for i in range(1, header.size()):
		_locales.append(String(header[i]).strip_edges())
	var rows := {}
	while not f.eof_reached():
		var cells := f.get_csv_line()
		if cells.size() == 0:
			continue
		var key := String(cells[0]).strip_edges()
		if key.is_empty() or key == KEY_COLUMN:
			continue
		rows[key] = cells
	f.close()

	var sorted_keys: Array = rows.keys()
	sorted_keys.sort()
	# 先把消息全部塞进 Translation，再一次性交给 TranslationServer：
	# 注册后再改消息，服务端缓存与资源状态容易出现"注册了但查不到"的半截状态。
	var built := {}
	for key in sorted_keys:
		var cells: PackedStringArray = rows[key]
		_keys.append(String(key))
		for i in range(1, header.size()):
			if i >= cells.size():
				continue
			var text := String(cells[i])
			if text.is_empty():
				continue
			var locale := String(header[i]).strip_edges()
			if not built.has(locale):
				var t := Translation.new()
				t.locale = locale
				built[locale] = t
			(built[locale] as Translation).add_message(String(key), text)
	for locale in built.keys():
		TranslationServer.add_translation(built[locale])
		_translations[locale] = built[locale]
	return not _keys.is_empty()


## 一条文案。`number > 0` 时拼成"<文案> <数字>"（生成聚落的"村庄 3"）。
static func text(key: String, number: int = 0) -> String:
	ensure()
	var s := TranslationServer.translate(key)
	if s == key:
		s = _default_message(key)
	var suffix := "" if number <= 0 else " %d" % number
	if s == "" or s == key:
		if not _warned.has(key):
			_warned[key] = true
			push_warning("L10n 缺少 key `%s`（回退成 key 本身）" % key)
		return key + suffix
	return s + suffix


## key 是否在表里（不触发 `tr()`，也不告警）。
static func has(key: String) -> bool:
	ensure()
	return _keys.has(key)


static func keys() -> PackedStringArray:
	ensure()
	return _keys.duplicate()


static func locales() -> PackedStringArray:
	ensure()
	return _locales.duplicate()


## 已经警告过多少个缺失的 key（用例用来验证"每个 key 只警告一次"）。
static func warned_count() -> int:
	return _warned.size()


## `tr()` 没命中当前语言时，回落到默认语言的原文。空串表示真的没这条。
static func _default_message(key: String) -> String:
	if not _translations.has(DEFAULT_LOCALE):
		return ""
	return String((_translations[DEFAULT_LOCALE] as Translation).get_message(key))
