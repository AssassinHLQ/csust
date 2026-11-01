class_name DialogueBox
extends CanvasLayer
## 剧情对话框：屏幕下方浮出一块面板，正文逐字显示，按键翻页。
##
## ── 为什么是「原地式」 ──
## 用户选的路线：**不切镜头**，人物就站在校园 / 画室里，只有屏幕下方浮出对话框。
## 这一版刻意不碰相机、不摆人物走位 —— 好处是它已经是「带运镜的过场」的**地基**：
## 以后加一个 `@camera` 指令，播放器一行都不用改，只是多一个步骤分支。
##
## ── 播放时游戏是暂停的 ──
## `get_tree().paused = true`，和 Esc 设置界面同一套机制。两个理由：
##   · 开场剧情不该被同伴的枪声、Boss 的预警圈打断；
##   · 暂停顺带**关掉了开火**。`player.gd` 开火用的是**轮询**
##     `Input.is_mouse_button_pressed()`，光靠 `set_input_as_handled()` 拦不住
##     （那只能拦事件、拦不住 poll），暂停才拦得住。
## 所以本节点必须是 `PROCESS_MODE_ALWAYS`：否则自己也跟着暂停，打字机和翻页
## 全停死。和 `settings_menu.gd` 遇到的是同一个问题（那边开头有详细说明）。
##
## ── 和 Esc 设置界面的交接规则（本文件最容易踩的地方） ──
## 两个节点都会 `paused = true`，就必须定清楚谁说了算，否则会有两个真 bug：
##   1. 设置界面开着时，本节点**什么都不吞**（连鼠标移动都不碰）。
##      Godot 的 `_input` **比 GUI 事件先跑** —— 这里吞掉鼠标，设置界面的按钮
##      就点不动了。见 `_input()` 的第一个提前返回。
##   2. 剧情结束时**只在设置界面没开的情况下**才解除暂停。否则「剧情播完」
##      会把用户正在看的设置界面解除暂停 —— 表现是剧情和菜单都开着、世界却在跑。
##      见 `_resume()`。
##
## ── 语音（`@voice`）──
## 每句话可以带一条配音。播放器只做三件事：**显示这句时开播、翻页时停、结束时不响**。
## 用的是本节点自己的一个 `AudioStreamPlayer`（不走 `Sfx` 的池子）—— 池子会按
## 「最早的那个」抢占，配音被抢掉正是最不能被容忍的一种失败。
##
## 三条取舍：
##   · 文件缺失**不报错**、不中断演出，只在控制台 warning 一次（配音是锦上添花）；
##   · 翻页时**立刻停**上一条，不让人听着两句话重叠；
##   · 走 `Master` 总线，所以设置界面的主音量管得到它。
##
## ── 正文用哪套字体 ──
## 走 `UiSkin.ui_font()`，**不用皮肤字体**。两套皮肤的 `font.ttf` 都没有汉字
## （`assets/ui_sprout/font.ttf` 实测 cmap 只覆盖 80 个拉丁字形、**0 个汉字**），
## 靠 Godot 的系统字体回退虽然能显示，但换一台机器就换一副字。
## 皮肤只负责面板九宫格和配色 —— 换皮肤时对话框的木头板跟着换，字不跟着换。

## 播放开始 / 结束。`game.gd` 靠 finished 决定「要不要在演完之后做点什么」。
signal started
signal finished
## 玩家在一次 `choice` 步骤里选定了第 index 项（value 是选项自带的 `value`，
## 没写就用下标）。剧情会接着播选项里的 `then` 步骤。
signal choice_made(index: int, value: Variant)

## ── 布局（**逻辑单位**，`canvas_items` 拉伸下再乘缩放）──
##
## 贴在画布**下沿**。刻意不用「绝对 y = 900 - …」那种写法：那样一旦设计分辨率
## 变了就得改一堆常量。这里用 `anchor_bottom = 1.0` 钉底边，只给「离底边多远」。
##
## 宽度和位置是**避开右下角弹药面板**算出来的：弹药面板逻辑宽 198、右边距 18，
## 于是它在 x ∈ [画布宽 − 216, 画布宽 − 18]。对话框 1120 宽居中之后，
## 在 1600 设计宽度下右边到 1360，比 1384 早 24 px —— 不重叠、也不用藏 HUD。
const BOX_WIDTH := 1120.0
## 高度按「正文最多 2 行」定的：26 + 34 + 2 × 32（实测行高）= 124，留 12 px 余量。
## 框高写死是为了让**面板不随文字长短跳动**（视觉小说都是这么做的）。
## 放不下第 3 行不是问题 —— 自检里的排版检查会指出「第几行太长」，改短即可。
const BOX_HEIGHT := 136.0
const BOX_BOTTOM := 30.0

const BOX_PAD_X := 30.0
## 正文区上下边界（相对框顶 / 框底）
const BODY_TOP := 26.0
const BODY_BOTTOM := 34.0
const BODY_FONT_SIZE := 24
## 名字牌：骑在对话框**上沿**上（下半个在框内），所以框顶之上还要留它的高度。
const NAME_PLATE_HEIGHT := 40.0
const NAME_PLATE_PAD := 22.0
const NAME_FONT_SIZE := 22
const HINT_FONT_SIZE := 14
const HINT_TEXT := "空格 / 回车 / 左键　继续"

## ── 选项列（`choice` 步骤）──
## 钉在对话框正上方，一行一项。当前项左侧一个小箭头，边框做呼吸闪烁。
const CHOICE_WIDTH := 860.0
const CHOICE_ROW_H := 46.0
const CHOICE_GAP := 8.0
const CHOICE_ARROW := "▶"
const CHOICE_HINT_TEXT := "W / S 选择　空格 / 回车 确认"
## 呼吸灯周期（秒）
const CHOICE_PULSE := 0.85

## 打字速度（字/秒）。剧本里 `@speed` 可以中途改。30 大致是「比默读稍快」。
const CHARS_PER_SEC := 30.0

## 配音音量（分贝）。0 = 原样；设置界面的主音量在 Master 总线上再乘一次。
const VOICE_DB := 0.0

## 设置界面节点（和本节点同为 Game 的子节点）。见文件头「交接规则」。
const SETTINGS_MENU_PATH := ^"../SettingsMenu"

var _skin: Dictionary = {}
## 正文 / 名字用的中文字体。拿不到（有人删了 assets/ui/font.ttf）就退回皮肤字体，
## 中文交给系统回退 —— 能看，但不是像素风。
var _font: Font = null

var _root: Control
var _box: Panel
var _name_plate: Panel
var _name_label: Label
var _body: Label
var _hint: Label
## 配音播放器（见文件头「语音」）。**单独一个**，不走 `Sfx` 的池子。
var _voice: AudioStreamPlayer
## 当前这句配音的**实际文件路径**（没有配音 / 找不到 = 空串）。自检与探针用它。
var _voice_path := ""

## 正在播的步骤表与游标
var _steps: Array = []
var _index := 0
var _active := false
var _finished_emitted := false
## 当前这一句（`@clear` 之后是空串）
var _body_text := ""
## 已经打出来的字数（浮点，因为 cps 可能很小，一帧不足一个字）
var _shown := 0.0
## `@wait` / `@clear` 剩下的秒数；> 0 时不接受翻页（按键会直接跳过这段）
var _hold := 0.0
var _cps := CHARS_PER_SEC

## ── 选项状态（`choice` 步骤）──
var _choice_panel: Control
var _choice_rows: Array[Panel] = []
var _choice_arrows: Array[Label] = []
var _choice_styles: Array[StyleBoxFlat] = []
var _choice_options: Array = []
var _choice_index := 0
var _choosing := false
var _choice_pulse: Tween


func _ready() -> void:
	# 压在 HUD（层 1）之上、设置界面（层 10）之下
	layer = 5
	# ⚠️ 见文件头：播放时世界是暂停的，本节点必须无视暂停才能打字和翻页
	process_mode = Node.PROCESS_MODE_ALWAYS
	_skin = UiSkin.pick()
	_build()
	_root.visible = false
	set_process(false)
	print("[Dialogue] 皮肤 = %s  正文字体 = %s" % [
		_skin["label"], UiSkin.ui_font_path() if _font != null else "**皮肤字体（无汉字）**"])


# --- 对外接口 ---------------------------------------------------------------

## 从剧本文件播放。返回有没有真的开播。
##
## 剧本**有错就完全不播**：宁可什么都不发生，也不要用半截剧本演一遍 ——
## 那样更难查。每一条错误都打到控制台（含行号和原行）。
func play_file(path: String) -> bool:
	var res := StoryScript.load_file(path)
	for w in res.get("warnings", []):
		push_warning("[Dialogue] %s" % w)
	if not res.get("ok", false):
		for e in res.get("errors", []):
			push_error("[Dialogue] %s" % e)
		print("[Dialogue] %s 有 %d 处错误，**已跳过播放**（改完再进游戏）"
			% [path, res["errors"].size()])
		return false
	var steps: Array = res["steps"]
	if steps.is_empty():
		print("[Dialogue] %s 里一句台词都没有，跳过" % path)
		return false
	var sum := StoryScript.summary(res)
	print("[Dialogue] 播 %s：%d 步 / %d 字 / 配音 %d 条 / 说话人 %s" % [
		path, sum["steps"], sum["chars"], int(sum["voiced"]), str(sum["speakers"])])
	# 点名的语音文件**提前查一遍**：缺了不该让演出失败（配音是锦上添花），
	# 但一次性全列出来比「演到那一句才静音」清楚得多。
	var named: Array[String] = []
	for s in steps:
		var v := String(s.get("voice", ""))
		if not v.is_empty():
			named.append(v)
	for m in StoryVoice.missing(named):
		push_warning("[Dialogue] %s" % StoryVoice.missing_hint(m))
	# 说话人校验：名字打错**不会**让剧本失败（照样能播），但名字牌上会出现一个
	# 游戏里不存在的角色 —— 这是写剧本时最容易犯、又最难自己发现的错，所以每次
	# 都按 `story/设定.md` 的角色表查一遍。设定表读不到就静默跳过（导出的包
	# 忘了放行 `.md` 时不该每句刷一条报警）。
	for w in StoryScript.check_speakers(res, StoryScript.cast_names()):
		push_warning("[Dialogue] %s" % w)
	play_steps(steps, path)
	return true


## 直接播一串已经解析好的步骤（自检和探针走这条）。
func play_steps(steps: Array, source := "") -> void:
	if steps.is_empty():
		return
	_steps = steps
	_index = 0
	_finished_emitted = false
	_body_text = ""
	_shown = 0.0
	_hold = 0.0
	_active = true
	_root.visible = true
	set_process(true)
	_choosing = false
	_choice_options = []
	_choice_index = 0
	if _choice_panel != null:
		_choice_panel.visible = false
	_stop_voice()
	_body.text = ""
	_body.visible_characters = 0
	_name_label.text = ""
	_layout_name_plate("")
	# 暂停世界。恢复的规则见 `_resume()`。
	get_tree().paused = true
	print("[Dialogue] 开始播放（%s）：已暂停游戏" % ("内联" if source.is_empty() else source))
	started.emit()
	_run_current()


## 立刻结束（探针用；以后做「跳过」也走这里）。
func finish() -> void:
	if not _active:
		return
	_active = false
	_steps = []
	_index = 0
	_body_text = ""
	_shown = 0.0
	_hold = 0.0
	_stop_voice()
	_root.visible = false
	_choosing = false
	_choice_options = []
	if _choice_panel != null:
		_choice_panel.visible = false
	if _choice_pulse != null and _choice_pulse.is_valid():
		_choice_pulse.kill()
	set_process(false)
	_resume()
	if not _finished_emitted:
		_finished_emitted = true
		print("[Dialogue] 播放结束")
		finished.emit()


func is_active() -> bool:
	return _active


## 正在逐字显示（还没打完）
func is_typing() -> bool:
	return _shown < float(_body_text.length())


## 当前这一句的**完整**正文
func current_text() -> String:
	return _body_text


## 当前这一句**已经打出来**的部分（自检用它验打字机）
func visible_text() -> String:
	return _body_text.substr(0, mini(int(_shown), _body_text.length()))


func current_who() -> String:
	return _name_label.text


## 当前这句配音的文件路径。没有配音、或点了名但文件找不到 → 空串。
func current_voice_path() -> String:
	return _voice_path


## 现在有没有配音在响（自检 / 探针用）
func is_voice_playing() -> bool:
	return _voice != null and _voice.playing


## 当前步骤在 steps 里的下标（-1 = 没在播）
func current_index() -> int:
	return _index if _active else -1


func step_count() -> int:
	return _steps.size()


## 打字速度覆盖（自检要的是「立刻打完」和「慢慢打」两个极端）
func set_cps(v: float) -> void:
	_cps = maxf(0.0001, v)


func get_cps() -> float:
	return _cps


## 玩家按了一下「继续」。
## 正在打字 → 把这一句**立刻打完**（第一次按键的标准行为）；
## 已经打完 → 翻到下一步。
func advance() -> void:
	if not _active:
		return
	# 选择时「继续」键归选择用（空格 = 确认），不能让 advance 顺手翻页
	if _choosing:
		return
	if _hold > 0.0:
		_hold = 0.0
		_index += 1
		_run_current()
		return
	if is_typing():
		_shown = float(_body_text.length())
		_body.visible_characters = int(_shown)
		_update_hint()
		return
	_index += 1
	_run_current()


# --- 输入 -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _active:
		return
	# ⚠️ 见文件头「交接规则」第 1 条：设置界面开着时什么都不吞。
	#    `_input` 比 GUI 事件先跑，这里吞鼠标 = 设置界面的按钮点不动。
	if _menu_open():
		return

	# 选择中：W/S（或上下方向键）移动，空格/回车确认，其余键不响应。
	if _choosing:
		if event is InputEventKey:
			var ck := event as InputEventKey
			if ck.pressed and not ck.echo:
				match ck.keycode:
					KEY_W, KEY_UP:
						_move_choice(-1)
					KEY_S, KEY_DOWN:
						_move_choice(1)
					KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
						_confirm_choice()
					_:
						return
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			var cmb := event as InputEventMouseButton
			if cmb.pressed and cmb.button_index == MOUSE_BUTTON_LEFT:
				_confirm_choice()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		# 过场里不该转视角（`player.gd` 收到鼠标移动就改 `_yaw`）。
		# ⚠️ 只吞鼠标移动，**不吞 Esc** —— 设置界面还等着它。
		get_viewport().set_input_as_handled()


# --- 播放 -------------------------------------------------------------------

## 从 `_index` 往下走到「需要停下来等玩家」的那一步。
func _run_current() -> void:
	while _index < _steps.size():
		var s: Dictionary = _steps[_index]
		match String(s.get("kind", "")):
			StoryScript.K_SAY:
				_set_line(String(s.get("who", "")), String(s.get("text", "")),
					String(s.get("voice", "")))
				return
			StoryScript.K_NARRATE:
				_set_line("", String(s.get("text", "")), String(s.get("voice", "")))
				return
			StoryScript.K_WAIT:
				# 「停一拍」= 画面**保持不动**等 N 秒（不清空）。
				# 开头就 @wait 的话就是一个空面板停一下，也合理。
				_hold = float(s.get("seconds", 0.0))
				_update_hint()
				return
			StoryScript.K_CLEAR:
				_set_line("", "")
				_hold = StoryScript.CLEAR_SECONDS
				_update_hint()
				return
			StoryScript.K_SPEED:
				_cps = maxf(0.0001, float(s.get("cps", CHARS_PER_SEC)))
			StoryScript.K_CHOICE:
				_begin_choice(s)
				return
			StoryScript.K_END:
				finish()
				return
			_:
				pass    # 不认识的步骤直接跳过（解析阶段已经报过错了）
		_index += 1
	finish()


func _process(delta: float) -> void:
	if not _active:
		return

	if _hold > 0.0:
		_hold -= delta
		_update_hint()
		if _hold <= 0.0:
			_hold = 0.0
			_index += 1
			_run_current()
		return

	if _body_text.is_empty():
		# 兜底：正常情况下空正文一定伴随 `_hold > 0`（见 `@clear`）。
		# 真出现就往前走，免得卡死在这儿。
		_index += 1
		_run_current()
		return

	if is_typing():
		_shown = minf(float(_body_text.length()), _shown + _cps * delta)
		_body.visible_characters = int(_shown)
	_update_hint()


## 右下角那行「空格 / 回车 / 左键 继续」：等按键时亮，正在打字时压暗。
## 它同时是**唯一的操作提示** —— 没有它，第一次玩的人不知道该按什么。
func _update_hint() -> void:
	_hint.text = CHOICE_HINT_TEXT if _choosing else HINT_TEXT
	_hint.modulate.a = 0.22 if is_typing() else 0.85


# --- 选项 -------------------------------------------------------------------
#
# 一个 `choice` 步骤长这样：
#   {"kind": "choice", "options": [
#       {"text": "商人啊！我正是为此而来！", "value": 1, "then": [ {"kind":"say", …} ]},
#       {"text": "[观察了银行卡的余额，摇了摇头]", "then": [ … ]},
#   ]}
# 问题句本身由上一条 `say` 负责显示；选项出现时把它立刻打完，不压在半截字上。
# `then` 里的步骤会被**插到当前步之后**接着播，不需要动作节点。

## 进入一次选择：把问题句打完、列选项、等 W/S + 空格。
func _begin_choice(step: Dictionary) -> void:
	var opts: Array = step.get("options", [])
	if opts.size() < 2:
		push_warning("[Dialogue] choice 至少要有 2 个选项，这一步跳过")
		_index += 1
		_run_current()
		return
	# 问题句先打完，别让选项压在半截字上
	_shown = float(_body_text.length())
	_body.visible_characters = int(_shown)
	_choice_options = opts
	_choice_index = 0
	_build_choice_rows()
	_choosing = true
	_choice_panel.visible = true
	_refresh_choices()
	_update_hint()
	print("[Dialogue] 选项 %d 个：%s" % [
		opts.size(), str(opts.map(func(o): return String(o.get("text", ""))))])


func _build_choice_rows() -> void:
	for c in _choice_panel.get_children():
		_choice_panel.remove_child(c)
		c.queue_free()
	_choice_rows.clear()
	_choice_arrows.clear()
	_choice_styles.clear()

	var n := _choice_options.size()
	var total := n * CHOICE_ROW_H + (n - 1) * CHOICE_GAP
	_choice_panel.offset_left = -CHOICE_WIDTH * 0.5
	_choice_panel.offset_right = CHOICE_WIDTH * 0.5
	_choice_panel.offset_bottom = -(BOX_BOTTOM + BOX_HEIGHT + 14.0)
	_choice_panel.offset_top = _choice_panel.offset_bottom - total

	for i in n:
		var opt: Dictionary = _choice_options[i]
		var row := Panel.new()
		row.name = "Choice%d" % i
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.position = Vector2(0.0, i * (CHOICE_ROW_H + CHOICE_GAP))
		row.size = Vector2(CHOICE_WIDTH, CHOICE_ROW_H)
		var sb := _choice_style(0.25, 0.62)
		row.add_theme_stylebox_override("panel", sb)
		_choice_panel.add_child(row)

		var arrow := Label.new()
		arrow.name = "Arrow"
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.text = CHOICE_ARROW
		arrow.position = Vector2(14.0, 0.0)
		arrow.size = Vector2(26.0, CHOICE_ROW_H)
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 20)
		arrow.add_theme_color_override("font_color", _skin["dialogue_name"])
		arrow.modulate.a = 0.0
		row.add_child(arrow)

		var text := Label.new()
		text.name = "Text"
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.text = String(opt.get("text", ""))
		text.position = Vector2(46.0, 0.0)
		text.size = Vector2(CHOICE_WIDTH - 60.0, CHOICE_ROW_H)
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.clip_text = true
		text.add_theme_font_size_override("font_size", 22)
		text.add_theme_color_override("font_color", _skin["text"])
		row.add_child(text)

		_choice_rows.append(row)
		_choice_arrows.append(arrow)
		_choice_styles.append(sb)


func _choice_style(border_a: float, bg_a: float) -> StyleBoxFlat:
	var accent: Color = _skin["dialogue_name"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.05, bg_a)
	sb.border_color = Color(accent.r, accent.g, accent.b, border_a)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


## 把「谁被选中」画出来：箭头只在当前项出现，边框做呼吸闪烁。
func _refresh_choices() -> void:
	if _choice_pulse != null and _choice_pulse.is_valid():
		_choice_pulse.kill()
	var accent: Color = _skin["dialogue_name"]
	for i in _choice_rows.size():
		var sel := i == _choice_index
		_choice_rows[i].modulate = Color(1, 1, 1, 1) if sel else Color(1, 1, 1, 0.70)
		_choice_arrows[i].modulate.a = 1.0 if sel else 0.0
		_choice_styles[i].border_color = Color(accent.r, accent.g, accent.b,
			1.0 if sel else 0.26)
	if _choice_rows.is_empty():
		return
	# 呼吸灯：当前项的边框在 0.30 ↔ 1.0 之间来回。暂停时也要跑。
	var sb: StyleBoxFlat = _choice_styles[_choice_index]
	var bright := Color(accent.r, accent.g, accent.b, 1.0)
	var dim := Color(accent.r, accent.g, accent.b, 0.30)
	_choice_pulse = create_tween().set_loops()
	_choice_pulse.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_choice_pulse.tween_property(sb, "border_color", dim, CHOICE_PULSE) \
		.set_trans(Tween.TRANS_SINE)
	_choice_pulse.tween_property(sb, "border_color", bright, CHOICE_PULSE) \
		.set_trans(Tween.TRANS_SINE)


func _move_choice(step: int) -> void:
	if _choice_rows.is_empty():
		return
	_choice_index = wrapi(_choice_index + step, 0, _choice_rows.size())
	Sfx.play("ui_slider", -10.0)
	_refresh_choices()


func _confirm_choice() -> void:
	if not _choosing or _choice_rows.is_empty():
		return
	var idx := _choice_index
	var opt: Dictionary = _choice_options[idx]
	_choosing = false
	_choice_panel.visible = false
	if _choice_pulse != null and _choice_pulse.is_valid():
		_choice_pulse.kill()
	Sfx.play("ui_press")
	choice_made.emit(idx, opt.get("value", idx))
	print("[Dialogue] 选了第 %d 项：%s" % [idx + 1, String(opt.get("text", ""))])
	# 选项自带的后续步骤插在当前步后面，接着往下播
	var extra: Variant = opt.get("then", [])
	if extra is Array and not (extra as Array).is_empty():
		var arr: Array = extra
		for k in arr.size():
			_steps.insert(_index + 1 + k, arr[k])
	_index += 1
	_run_current()


## 正在选择时是第几项（没在选择 → −1），自检用
func current_choice() -> int:
	return _choice_index if _choosing else -1


func choice_count() -> int:
	return _choice_options.size() if _choosing else 0


func choice_text(index: int) -> String:
	if index < 0 or index >= _choice_options.size():
		return ""
	return String((_choice_options[index] as Dictionary).get("text", ""))


# --- 暂停交接 ---------------------------------------------------------------

## 设置界面是不是开着。**必须有这层判断**：两个节点都会 `paused = true`，
## 没有交接规则就会出现「剧情播完把用户正在看的设置界面解除暂停」。
func _menu_open() -> bool:
	var menu := get_node_or_null(SETTINGS_MENU_PATH)
	return menu != null and bool(menu.get("is_open"))


func _resume() -> void:
	if _menu_open():
		print("[Dialogue] 播完，但 Esc 设置界面还开着 —— 保持暂停，把恢复交给它")
		return
	var t := get_tree()
	if t != null:
		t.paused = false


# --- 构建 UI ----------------------------------------------------------------

## 全部**代码构建**（和 `hud.gd` / `settings_menu.gd` 一致）：对话框的布局是
## 算出来的（名字牌宽度要量字），写成 .tscn 反而两头对不上。
func _build() -> void:
	_font = UiSkin.ui_font()

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 不吃鼠标：这个 Control 铺满全屏，STOP 的话整个 HUD 和设置界面都不用点了。
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := UiSkin.make_theme(_skin)
	if _font != null:
		theme.default_font = _font
		theme.default_font_size = BODY_FONT_SIZE
	_root.theme = theme
	add_child(_root)

	_box = Panel.new()
	_box.name = "Box"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_stylebox_override("panel", UiSkin.panel_style(_skin))
	_pin_bottom_center(_box, BOX_WIDTH, BOX_HEIGHT, BOX_BOTTOM)
	_root.add_child(_box)

	# 名字牌：骑在上沿上（上半个在框外），宽度按名字的**真实字宽**算，
	# 所以「优香」和「霸王龙优香」的牌子不一样长。
	_name_plate = Panel.new()
	_name_plate.name = "NamePlate"
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.add_theme_stylebox_override("panel", UiSkin.button_style(_skin, "normal"))
	_box.add_child(_name_plate)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", _skin["dialogue_name"])
	_name_plate.add_child(_name_label)

	_body = Label.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.anchor_left = 0.0
	_body.anchor_top = 0.0
	_body.anchor_right = 0.0
	_body.anchor_bottom = 0.0
	_body.offset_left = BOX_PAD_X
	_body.offset_right = BOX_WIDTH - BOX_PAD_X
	_body.offset_top = BODY_TOP
	_body.offset_bottom = BOX_HEIGHT - BODY_BOTTOM
	# CJK 没有词间空格，`WORD_SMART` 才会在汉字之间断行；`ARBITRARY` 会把拉丁词劈开。
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body.clip_text = true
	_body.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_body.add_theme_color_override("font_color", _skin["text"])
	_box.add_child(_body)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.anchor_left = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -300.0
	_hint.offset_right = -BOX_PAD_X
	_hint.offset_top = -BODY_BOTTOM + 4.0
	_hint.offset_bottom = -6.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.text = HINT_TEXT
	_hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint.add_theme_color_override("font_color", _skin["subtext"])
	_box.add_child(_hint)
	_layout_name_plate("")

	# 选项列：钉在对话框正上方。行是**按选项数临时生成**的，这里只建容器。
	_choice_panel = Control.new()
	_choice_panel.name = "Choices"
	_choice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_panel.anchor_left = 0.5
	_choice_panel.anchor_right = 0.5
	_choice_panel.anchor_top = 1.0
	_choice_panel.anchor_bottom = 1.0
	_choice_panel.visible = false
	_root.add_child(_choice_panel)

	# 配音播放器。**单独一个**（不走 `Sfx` 的池子），理由见文件头「语音」。
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = &"Master"
	_voice.volume_db = VOICE_DB
	# 播放时世界是暂停的，本节点也是 ALWAYS；子节点会继承，这里写死是为了明确。
	_voice.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_voice)


## 钉在画布**下沿**居中：`anchor_bottom = 1.0` + 负偏移，
## 所以设计分辨率或窗口怎么变，它都贴着底边（不用写死「900 − …」）。
func _pin_bottom_center(c: Control, w: float, h: float, bottom: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = -(bottom + h)
	c.offset_bottom = -bottom


## 按名字的长度摆名字牌。空名字（旁白）就把牌子藏起来。
func _layout_name_plate(who: String) -> void:
	if _name_plate == null:
		return
	var w := 140.0
	if _font != null and not who.is_empty():
		w = _font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FONT_SIZE).x \
			+ NAME_PLATE_PAD * 2.0
	_name_plate.visible = not who.is_empty()
	_name_plate.anchor_left = 0.0
	_name_plate.anchor_right = 0.0
	_name_plate.anchor_top = 0.0
	_name_plate.anchor_bottom = 0.0
	_name_plate.offset_left = BOX_PAD_X - 10.0
	_name_plate.offset_right = BOX_PAD_X - 10.0 + maxf(w, 96.0)
	_name_plate.offset_top = -NAME_PLATE_HEIGHT * 0.5
	_name_plate.offset_bottom = NAME_PLATE_HEIGHT * 0.5


func _set_line(who: String, text: String, voice_name := "") -> void:
	_name_label.text = who
	_layout_name_plate(who)
	_body_text = text
	_shown = 0.0
	_body.text = text
	_body.visible_characters = 0
	_play_voice(voice_name)
	_update_hint()


## 播这句的配音。空名字 / 文件缺失 / 读不出来 → **只停掉上一条，不报错**。
##
## 「找不到」每个名字只 warning 一次（`StoryVoice.note_missing()`）：
## 一句一句往回翻的时候，同一个缺文件会被触发很多次，刷屏就没法看别的日志了。
func _play_voice(name: String) -> void:
	if _voice == null:
		return
	_voice.stop()
	_voice_path = ""
	if name.is_empty():
		return
	var path := StoryVoice.find(name)
	if path.is_empty():
		if StoryVoice.note_missing(name):
			push_warning("[Dialogue] %s" % StoryVoice.missing_hint(name))
		return
	var stream := StoryVoice.load_stream(path)
	if stream == null:
		if StoryVoice.note_missing(name):
			push_warning("[Dialogue] 语音「%s」读不出来（%s），这一句静音" % [name, path])
		return
	_voice_path = path
	_voice.stream = stream
	_voice.play()


func _stop_voice() -> void:
	if _voice != null:
		_voice.stop()
	_voice_path = ""


# --- 给探针 / 自检用的量法 ---------------------------------------------------

## 正文区宽度（逻辑单位）。排版检查要知道「一行能放多少字」。
static func text_area_width() -> float:
	return BOX_WIDTH - BOX_PAD_X * 2.0


## 这段正文在对话框里要占**几行**（按真实字体量，不是数换行符）。
##
## ⚠️ 用它的人要注意：`Font.get_string_size()` 只有在 `width > 0` 时才会**折行**，
##    所以这里必须把 `text_area_width()` 传进去，传 -1 得到的是「一行到底」的宽度。
static func body_lines(font: Font, text: String) -> int:
	if font == null or text.is_empty():
		return 1
	var lh := font.get_height(BODY_FONT_SIZE)
	if lh <= 0.0:
		return 1
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		text_area_width(), BODY_FONT_SIZE)
	return maxi(1, int(ceil(sz.y / lh - 0.001)))


## 对话框最多放得下几行正文。
static func max_body_lines(font: Font) -> int:
	if font == null:
		return 3
	var lh := font.get_height(BODY_FONT_SIZE)
	if lh <= 0.0:
		return 3
	return maxi(1, int(floor((BOX_HEIGHT - BODY_TOP - BODY_BOTTOM) / lh)))


## 对话框（不含名字牌）落在**物理像素**上的矩形 —— 和 `hud.gd` 的
## `crosshair_physical_rects()` 用同一套换算，供探针量「有没有压到弹药面板」。
func box_physical_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null or _box == null:
		return Rect2()
	var xf := vp.get_final_transform()
	var gr := _box.get_global_rect()
	var p0 := xf * gr.position
	var p1 := xf * (gr.position + gr.size)
	return Rect2(p0, p1 - p0)


## 当前「画布逻辑单位 → 物理像素」的缩放（探针用）
func canvas_scale() -> float:
	var vp := get_viewport()
	return 1.0 if vp == null else maxf(vp.get_final_transform().get_scale().x, 0.0001)
