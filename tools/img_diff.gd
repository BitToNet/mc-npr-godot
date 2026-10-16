extends SceneTree
## =============================================================================
##  tools/img_diff.gd — 两图差异像素比（B- 类验收门禁，S0.2 交付物）
## =============================================================================
##  用法：
##    Godot --headless --path <proj> --script res://tools/img_diff.gd -- \
##        --a=<a.png> --b=<b.png> [--tol=0.001] [--channel=8] [--json=<out.json>]
##
##  退出码：0 = 差异在容差内（pass）；1 = 差异超容差或尺寸不一致（fail）；
##          2 = 用法/读取错误（error）。
##
##  设计要点：
##  - 纯 Godot `Image` API，**无任何外部依赖**（不需要 ImageMagick / Python）。
##  - 用 `FileAccess` 读原始字节再 `load_png_from_buffer`：`res://.shots/*.png`
##    不在 Godot 的导入库里，走 `Image.load()` 会失败，必须这样读。
##  - 尺寸不一致**显式判失败并给出原因**，绝不静默裁剪到公共区域。
##  - 单通道差 ≤ `--channel`（默认 8/255）不计入，用来吸收显卡驱动的微小抖动；
##    要严格逐位比对就传 `--channel=0`。
##  - 同时输出两侧 sha256，作为不可篡改的证据锚点。
##
##  ⚠️ 与 verify.gd 相同：本脚本以 `--script` 运行，**不得**使用 autoload 标识符。
## =============================================================================

const DEFAULT_TOL := 0.001          # 0.1%，即 ROADMAP S0.1 的 B- 门禁值
const DEFAULT_CHANNEL := 8          # 单通道差阈值（0..255）


## 核心：返回差异统计。verdict ∈ {"pass","fail","error"}。
static func diff(a_path: String, b_path: String,
		channel_threshold: int = DEFAULT_CHANNEL,
		tol: float = DEFAULT_TOL) -> Dictionary:
	var res := {
		"a": a_path,
		"b": b_path,
		"a_sha256": "",
		"b_sha256": "",
		"width": 0,
		"height": 0,
		"total_pixels": 0,
		"changed_pixels": 0,
		"ratio": 0.0,
		"ratio_pct": 0.0,
		"channel_threshold": channel_threshold,
		"tol": tol,
		"verdict": "error",
		"reason": "",
	}

	if not FileAccess.file_exists(a_path):
		res["reason"] = "文件不存在：%s" % a_path
		return res
	if not FileAccess.file_exists(b_path):
		res["reason"] = "文件不存在：%s" % b_path
		return res

	res["a_sha256"] = FileAccess.get_sha256(a_path)
	res["b_sha256"] = FileAccess.get_sha256(b_path)

	var ia := _load_png(a_path)
	if ia == null:
		res["reason"] = "无法解码 PNG：%s" % a_path
		return res
	var ib := _load_png(b_path)
	if ib == null:
		res["reason"] = "无法解码 PNG：%s" % b_path
		return res

	ia.convert(Image.FORMAT_RGBA8)
	ib.convert(Image.FORMAT_RGBA8)

	var wa := ia.get_width()
	var ha := ia.get_height()
	var wb := ib.get_width()
	var hb := ib.get_height()
	res["width"] = wa
	res["height"] = ha

	if wa != wb or ha != hb:
		res["verdict"] = "fail"
		res["total_pixels"] = wa * ha
		res["changed_pixels"] = wa * ha
		res["ratio"] = 1.0
		res["ratio_pct"] = 100.0
		res["reason"] = "尺寸不一致：A=%dx%d  B=%dx%d（不静默裁剪，直接判失败）" % [wa, ha, wb, hb]
		return res

	var da := ia.get_data()
	var db := ib.get_data()
	var total := wa * ha
	var changed := 0
	var n := da.size()
	var i := 0
	while i < n:
		var dr: int = absi(int(da[i]) - int(db[i]))
		var dg: int = absi(int(da[i + 1]) - int(db[i + 1]))
		var dbl: int = absi(int(da[i + 2]) - int(db[i + 2]))
		var dalpha: int = absi(int(da[i + 3]) - int(db[i + 3]))
		if dr > channel_threshold or dg > channel_threshold \
				or dbl > channel_threshold or dalpha > channel_threshold:
			changed += 1
		i += 4

	var ratio := 0.0 if total == 0 else float(changed) / float(total)
	res["total_pixels"] = total
	res["changed_pixels"] = changed
	res["ratio"] = ratio
	res["ratio_pct"] = ratio * 100.0
	if ratio <= tol:
		res["verdict"] = "pass"
		res["reason"] = "差异 %.4f%% <= 容差 %.4f%%" % [ratio * 100.0, tol * 100.0]
	else:
		res["verdict"] = "fail"
		res["reason"] = "差异 %.4f%% > 容差 %.4f%%（%d/%d 像素）" \
				% [ratio * 100.0, tol * 100.0, changed, total]
	return res


static func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


## -----------------------------------------------------------------------------
##  CLI
## -----------------------------------------------------------------------------
func _initialize() -> void:
	var a_path := ""
	var b_path := ""
	var json_path := ""
	var tol := DEFAULT_TOL
	var channel := DEFAULT_CHANNEL

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--a="):
			a_path = a.split("=", true, 1)[1]
		elif a.begins_with("--b="):
			b_path = a.split("=", true, 1)[1]
		elif a.begins_with("--json="):
			json_path = a.split("=", true, 1)[1]
		elif a.begins_with("--tol="):
			tol = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--channel="):
			channel = a.split("=", true, 1)[1].to_int()

	if a_path == "" or b_path == "":
		printerr("[img_diff] 用法错误：需要 --a=<png> --b=<png> [--tol=] [--channel=] [--json=]")
		quit(2)
		return

	var r := diff(a_path, b_path, channel, tol)

	print("[img_diff] A = ", r["a"], "  sha256=", String(r["a_sha256"]).substr(0, 16), "…")
	print("[img_diff] B = ", r["b"], "  sha256=", String(r["b_sha256"]).substr(0, 16), "…")
	print("[img_diff] 尺寸 %dx%d  像素 %d" % [r["width"], r["height"], r["total_pixels"]])
	print("[img_diff] 差异像素 %d/%d = %.4f%%  (通道阈值 %d, 容差 %.4f%%)"
			% [r["changed_pixels"], r["total_pixels"], r["ratio_pct"],
			r["channel_threshold"], float(r["tol"]) * 100.0])
	print("[img_diff] 判定 ", String(r["verdict"]).to_upper(), " — ", r["reason"])

	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(r, "  ", false))
			f.close()

	match String(r["verdict"]):
		"pass":
			quit(0)
		"fail":
			quit(1)
		_:
			quit(2)
