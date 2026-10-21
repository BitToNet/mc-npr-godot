class_name UiKit
extends RefCounted
## UiKit — 新粗野主义（neo-brutalist）UI 的公共控件工厂。
##
## 【ROADMAP §5 S0.4 批次 1】
##
## 为什么抽这一层：`ui_panel.gd` / `menu_page.gd` / `save_grid.gd` 各自抄了一份
## 一模一样的 `SystemFont` 构造、`_sb()` 与 `_label()`（连措辞都相同）。三份实现
## 只要有一处被改动，"全项目同一套视觉语言"就退化成人肉同步表。UI 从这里开始
## 变多（S1.5 聚落面板、S2.x 战斗 HUD、S4.5 指挥层），所以先把复本收成一份。
##
## ⚠️ 本批是**纯重构**：本文件里的每个数值都必须与被抽取的原实现逐字一致
## （含默认参数、含"哪些 `add_theme_*_override` 调用过/没调用过"）。
## 判定标准不是"看起来一样"，而是 6 机位与菜单 4 张截图的 sha256 **逐位不变**；
## 三处调用方还各自保留同名薄包装（`_sb` / `_label` / `_button`），调用点一行不改，
## 于是视觉等价性由"参数完全没变"直接保证，不靠复核。
##
## 刻意**不做**的事：
##   * **不缓存字体实例**。`font()` 每次返回新对象，与抽取前"每个类各建一个
##     `SystemFont`"的内存画像完全相同 —— `memory_static` 不变是"纯重构"的
##     第二个独立旁证。共享字体实例确实能省内存，但那属于登记在案的
##     「UI 内存可选项」（换子集化随包字体，见 ENGINEERING §6.5 注），
##     不该混进一次纯重构里（一次提交只承载一件事）。
##   * **不做主题资源（Theme）**。Theme 会改变控件的默认解析路径，
##     属于行为变更；本文件只提供显式工厂函数。

# ---------------------------------------------------------------------------
# 调色板：全项目唯一来源。
# 调用方保留 `const INK := UiKit.INK` 这种同名别名 —— 调用点不动，diff 面最小。
# ---------------------------------------------------------------------------
const INK := Color("13101b")
const PAPER := Color("fff9e8")
const YELLOW := Color("ffe45c")
const CYAN := Color("6fe3e1")
const PINK := Color("ff8fb1")
const GREEN := Color("7ed957")
const LILAC := Color("c3b1ff")
## 宫格空槽位的底色 / 各类次要文字（原 `save_grid.gd`、`menu_page.gd` 各自一份）。
const GREY := Color("cdc7bb")
const MUTED := Color("6b6480")
## 菜单整页背板（半透明墨色，见 `menu_page.gd`）。
const BACKDROP := Color(0.07, 0.06, 0.10, 0.62)


## 面板/按钮共用的一套中文字体配置（原三处逐字相同）。
## 返回**新实例**，理由见文件头。
static func font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC",
		"Source Han Sans SC", "Microsoft YaHei", "Arial Unicode MS", "Sans-Serif"])
	f.font_weight = 700
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


## 厚墨边 + 硬投影 + 零圆角 + 关闭抗锯齿的纯色块（HUD 与菜单共用的唯一一种"面板"）。
static func sb(bg: Color, border: int = 4, shadow: int = 0, offset := Vector2.ZERO,
		pad: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = INK
	s.set_border_width_all(border)
	s.set_corner_radius_all(0)
	s.shadow_color = INK
	s.shadow_size = shadow
	s.shadow_offset = offset
	s.anti_aliasing = false
	s.set_content_margin_all(pad)
	return s


## 统一字体/字号的标签；默认忽略鼠标，避免挡住下层控件的命中检测。
static func label(font_: Font, text: String, size: int, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## HUD 面板按钮（`ui_panel.gd` 抽取前原样）：hover **反白**（墨底纸字），带 disabled 态。
static func button_hud(font_: Font, text: String, accent: Color) -> Button:
	var b := _button_base(font_, text, 46, 17, PAPER)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_stylebox_override("normal", sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("hover", sb(INK, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("pressed", sb(accent.darkened(0.12), 4, 0, Vector2(1, 1), 10))
	b.add_theme_stylebox_override("focus", sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("disabled", sb(accent.darkened(0.3), 4, 0, Vector2.ZERO, 10))
	return b


## 给已建好的 HUD 按钮换底色（S1.4b：档位按钮的"当前档"是黄色，其余是纸色）。
## 样式清单与 `button_hud` 逐项相同 —— 只是作用在既有实例上，调用方不必为了换个颜色
## 重建控件（重建会丢掉连接与焦点顺序）。
static func repaint_hud(b: Button, accent: Color) -> void:
	b.add_theme_stylebox_override("normal", sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("hover", sb(INK, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("pressed", sb(accent.darkened(0.12), 4, 0, Vector2(1, 1), 10))
	b.add_theme_stylebox_override("focus", sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("disabled", sb(accent.darkened(0.3), 4, 0, Vector2.ZERO, 10))


## 菜单页按钮（`menu_page.gd` 抽取前原样）：hover **同色提亮**，无 disabled 态。
static func button_page(font_: Font, text: String, accent: Color) -> Button:
	var b := _button_base(font_, text, 48, 18, INK)
	b.add_theme_stylebox_override("normal", sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("hover", sb(accent.lightened(0.14), 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("pressed", sb(accent.darkened(0.14), 4, 0, Vector2(1, 1), 10))
	b.add_theme_stylebox_override("focus", sb(accent, 4, 6, Vector2(5, 5), 10))
	return b


## 两种按钮唯一的公共部分：字号/高度/字色/焦点环。
## `focus_mode = FOCUS_NONE` 是硬要求 —— 焦点环会让同一逻辑状态出现两种像素，
## 而截图门禁要求逐位可复现（键盘导航改用显式标记，见 `save_grid.gd` 注释）。
static func _button_base(font_: Font, text: String, height: int, font_size: int,
		hover_font: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", hover_font)
	b.add_theme_color_override("font_pressed_color", INK)
	return b
