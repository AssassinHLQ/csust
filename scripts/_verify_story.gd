extends SceneTree
## 验「剧情系统」：
##   1. 解析器：注释 / 空行 / 半角全角冒号 / 旁白 / 四个指令 / **行号对不对**
##   2. 报错：写错的剧本要**报出第几行、原行是什么**（不是静默跳过）
##   3. 编码：带 BOM 的 UTF-8 能吃；真的 GBK 字节要报「不是 UTF-8」
##   4. 真剧本文件：解析无错 + 按**真实字体**量「有没有哪句撑破对话框」
##   5. 播放：打字机 / 第一次按键把当前句打完 / 翻页 / @end 收尾并恢复
##   6. 和 Esc 设置界面的交接：菜单开着时剧情不抢输入、播完不解暂停
##   7. 设定表（`story/设定.md`）：角色表 / 场景表能解析，说话人校验能给建议，
##      表里写的节点与场景实际状态一致
##
## 用法：godot --path <工程> --script res://scripts/_verify_story.gd -- --splat=off
##
## ⚠️ 必须带 `--splat=off`：第 4 节起会 instantiate 整个 game.tscn，
##    615 万点的泼溅会白白拖慢每一条用例。
##
## ⚠️ 两个「别把它写成 flaky」的要点（本文件踩过）：
##   · `advance()` 的行为**取决于当前有没有在打字** —— 打字中 = 把本句打完，
##     打完了 = 翻页。所以凡是要断言「翻页」的地方，前面必须先等它打完。
##   · 打字机的推进速度是 `字/秒 × 帧间隔`，**和帧率有关**。断言「推进了一部分」
##     要用**足够长的正文**（这里 120 字 / 60 字每秒），这样帧率从 10 到 10000
##     都能落在「0 < 已打字数 < 全句」这个区间里。

const GBK_FILE := "user://_verify_story_gbk.txt"
const BOM_FILE := "user://_verify_story_bom.txt"
const TEMPLATE := "res://story/开场.txt"

## 打字机用例用的长句：120 字，配 60 字/秒 ≈ 2 秒打完。
const LONG_TEXT := "这一句很长很长。"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	_test_parse()
	_test_errors()
	_test_encoding()

	# 后面几节要场景（第 4 节要真字体，第 5/6 节要真节点）
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	_test_template_file()
	await _test_playback(game)
	_test_bible(game)

	_cleanup()
	print("\n================ 结果 ================")
	_quit()


# --- 1. 解析器 ---------------------------------------------------------------

func _test_parse() -> void:
	print("========== 1. 解析器 ==========")
	# 行号是**故意排开的**：注释和空行不会变成步骤，但步骤上的 line 必须是原文行号。
	var src := "# 这一行是注释\n" \
		+ "\n" \
		+ "优香: 半角冒号\n" \
		+ "凯伊：全角冒号\n" \
		+ "* 星号旁白\n" \
		+ "优香: 他说：好\n" \
		+ "@wait 1.5\n" \
		+ "@clear\n" \
		+ "@speed 45\n" \
		+ "@end\n"
	var res := StoryScript.parse(src)
	var steps: Array = res["steps"]

	_check(res["ok"], "解析通过（errors=%d）" % res["errors"].size())
	for e in res["errors"]:
		print("      %s" % e)
	_check(int(res["lines"]) == 10,
		"原文行数 = %d（文件结尾那个空行不算）" % int(res["lines"]))
	_check(steps.size() == 8, "切出 %d 步（注释与空行被跳过）" % steps.size())
	if steps.size() != 8:
		return

	_check(steps[0]["kind"] == StoryScript.K_SAY and steps[0]["who"] == "优香" \
		and steps[0]["text"] == "半角冒号" and int(steps[0]["line"]) == 3,
		"第 3 行 半角冒号 → say 优香 / %s" % steps[0]["text"])
	_check(steps[1]["kind"] == StoryScript.K_SAY and steps[1]["who"] == "凯伊" \
		and steps[1]["text"] == "全角冒号" and int(steps[1]["line"]) == 4,
		"第 4 行 全角冒号 → say 凯伊 / %s" % steps[1]["text"])
	_check(steps[2]["kind"] == StoryScript.K_NARRATE \
		and steps[2]["text"] == "星号旁白" and int(steps[2]["line"]) == 5,
		"第 5 行 星号 → narrate / %s" % steps[2]["text"])
	_check(steps[3]["kind"] == StoryScript.K_SAY and steps[3]["who"] == "优香" \
		and steps[3]["text"] == "他说：好" and int(steps[3]["line"]) == 6,
		"第 6 行 正文里的冒号没被切走 → %s" % steps[3]["text"])
	_check(steps[4]["kind"] == StoryScript.K_WAIT \
		and absf(float(steps[4]["seconds"]) - 1.5) < 0.001 and int(steps[4]["line"]) == 7,
		"第 7 行 @wait 1.5 → %.2f s" % float(steps[4]["seconds"]))
	_check(steps[5]["kind"] == StoryScript.K_CLEAR and int(steps[5]["line"]) == 8,
		"第 8 行 @clear")
	_check(steps[6]["kind"] == StoryScript.K_SPEED \
		and absf(float(steps[6]["cps"]) - 45.0) < 0.001 and int(steps[6]["line"]) == 9,
		"第 9 行 @speed 45 → %.1f 字/秒" % float(steps[6]["cps"]))
	_check(steps[7]["kind"] == StoryScript.K_END and int(steps[7]["line"]) == 10,
		"第 10 行 @end")

	var sum := StoryScript.summary(res)
	var sp: Array = sum["speakers"]
	_check(sp.size() == 2 and sp.has("优香") and sp.has("凯伊"),
		"说话人去重排序 = %s" % str(sp))
	_check(int(sum["chars"]) == 16, "正文字数合计 = %d" % int(sum["chars"]))

	# 制表符分隔 / 指令大写 / 行尾空格，都该能吃
	var res2 := StoryScript.parse("@WAIT\t2\n@clear   \n")
	_check(res2["ok"] and res2["steps"].size() == 2,
		"制表符分隔 + 指令大写 + 行尾空格都能吃（%d 步）" % res2["steps"].size())

	# @end 处截断，但要提醒后面还有内容
	var res3 := StoryScript.parse("优香: 一\n@end\n优香: 后面这句不该播\n")
	_check(res3["steps"].size() == 2,
		"@end 处截断（%d 步：一句台词 + @end）" % res3["steps"].size())
	_check(res3["warnings"].size() == 1,
		"@end 之后还有内容 → %d 条提醒" % res3["warnings"].size())
	for w in res3["warnings"]:
		print("      %s" % w)

	# 只有注释 / 空行的剧本：不算错，但零步骤（播放器会拒绝播）
	var res4 := StoryScript.parse("# 只有注释\n\n")
	_check(res4["ok"] and res4["steps"].is_empty(), "只有注释的剧本：无错、零步骤")


# --- 2. 报错 -----------------------------------------------------------------

func _test_errors() -> void:
	print("\n========== 2. 报错必须带行号 ==========")
	# 每种错误单独喂一遍，断言「报出来了」且**行号正确**
	var cases := [
		{"src": "优香: 一\n@bgm 天台\n", "line": 2, "key": "不认识的指令"},
		{"src": "优香: 一\n\n@wait abc\n", "line": 3, "key": "@wait"},
		{"src": "优香: 一\n@speed 0\n", "line": 2, "key": "@speed"},
		{"src": "优香: 一\n这一行既没冒号也不是星号\n", "line": 2, "key": "认不出这一行"},
		{"src": "优香:\n", "line": 1, "key": "没有正文"},
		{"src": "*\n", "line": 1, "key": "没写内容"},
		{"src": ": 冒号前面是空的\n", "line": 1, "key": "没有名字"},
	]
	for c in cases:
		var res := StoryScript.parse(String(c["src"]))
		var joined := _join(res["errors"])
		var want_line := "第 %d 行" % int(c["line"])
		var ok: bool = (not res["ok"]) and joined.contains(String(c["key"])) \
			and joined.contains(want_line)
		_check(ok, "「%s」→ %s 报错" % [String(c["key"]), want_line])
		if not ok:
			print("      errors=%s" % str(res["errors"]))

	# 一条报错里要能看到**原行**，否则用户还得回去数行
	var res2 := StoryScript.parse("优香: 一\n@bgm 天台\n")
	_check(_join(res2["errors"]).contains("原行"), "报错里带了原行原文")

	# 未知指令要**列出可用的指令**（不然用户去翻文档）
	var res3 := StoryScript.parse("@bgm 天台\n")
	_check(_join(res3["errors"]).contains("@wait") \
		and _join(res3["errors"]).contains("@end"),
		"未知指令的报错列出了全部可用指令")


# --- 3. 编码 -----------------------------------------------------------------

func _test_encoding() -> void:
	print("\n========== 3. 编码：BOM 与 GBK ==========")

	# 真·GBK 字节：0xBA 0xC3 是「好」的 GBK 编码，当作 UTF-8 解必然失败。
	# 这是本工程最可能踩的坑 —— 中文 Windows 记事本的「ANSI」就是 GBK。
	var f := FileAccess.open(GBK_FILE, FileAccess.WRITE)
	if f == null:
		_check(false, "写不了 %s" % GBK_FILE)
	else:
		f.store_buffer(PackedByteArray([0xBA, 0xC3]))
		f.close()
		var res := StoryScript.load_file(GBK_FILE)
		_check(not res["ok"] and _join(res["errors"]).contains("UTF-8"),
			"GBK 字节被认出来并报「不是 UTF-8」")
		if not res["errors"].is_empty():
			print("      %s" % res["errors"][0])

	# UTF-8 BOM：记事本常加。不剥掉的话第一行会变成「认不出这一行」，
	# 而那一行**看着完全正常** —— 属于最气人的一类 bug。
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF])
	bytes.append_array("优香: 早上好。\n".to_utf8_buffer())
	var f2 := FileAccess.open(BOM_FILE, FileAccess.WRITE)
	if f2 == null:
		_check(false, "写不了 %s" % BOM_FILE)
	else:
		f2.store_buffer(bytes)
		f2.close()
		var res2 := StoryScript.load_file(BOM_FILE)
		_check(res2["ok"], "带 BOM 的 UTF-8 能正常解析")
		if res2["steps"].size() == 1:
			_check(res2["steps"][0]["who"] == "优香" \
				and res2["steps"][0]["text"] == "早上好。",
				"BOM 被剥掉了（说话人「%s」/ 正文「%s」）" % [
					res2["steps"][0]["who"], res2["steps"][0]["text"]])
		else:
			_check(false, "带 BOM 的剧本切出了 %d 步" % res2["steps"].size())

	# 找不到文件也要是干净的一条错误，不是崩溃
	var res3 := StoryScript.load_file("res://story/这个文件肯定不存在.txt")
	_check(not res3["ok"] and _join(res3["errors"]).contains("找不到"),
		"文件不存在 → 一条「找不到」错误")


# --- 4. 真剧本文件 + 排版检查 -------------------------------------------------

func _test_template_file() -> void:
	print("\n========== 4. 真剧本 %s ==========" % TEMPLATE)
	_check(FileAccess.file_exists(TEMPLATE), "模板剧本在 %s" % TEMPLATE)
	if not FileAccess.file_exists(TEMPLATE):
		return

	var res := StoryScript.load_file(TEMPLATE)
	_check(res["ok"], "模板剧本解析**零错误**（errors=%d）" % res["errors"].size())
	for e in res["errors"]:
		print("      %s" % e)
	for w in res["warnings"]:
		print("      [warn] %s" % w)

	var sum := StoryScript.summary(res)
	_check(int(sum["steps"]) > 0, "共 %d 步 / %d 字 / 说话人 %s" % [
		int(sum["steps"]), int(sum["chars"]), str(sum["speakers"])])

	# 目录扫描：`game.gd` 在指定文件缺失时靠它兜底
	var listed := StoryScript.list_in_dir("res://story/")
	_check(listed.size() >= 1, "story/ 里扫到 %d 份剧本：%s" % [listed.size(), str(listed)])
	_check(StoryScript.first_in_dir("res://story/") != "",
		"story/ 排序第一份 = %s" % StoryScript.first_in_dir("res://story/"))

	# ── 排版检查：按**真实字体**量每一句会不会撑破对话框 ──
	# 这一段是给写剧本的人用的：改完剧本跑一次，就知道哪一行太长。
	var font := UiSkin.ui_font()
	_check(font != null, "拿到界面字体 %s" % UiSkin.ui_font_path())
	if font == null:
		return
	var max_lines := DialogueBox.max_body_lines(font)
	print("  ── 排版：正文区 %.0f 逻辑 px、字号 %d、行高 %.1f px → 最多 %d 行 ──" % [
		DialogueBox.text_area_width(), DialogueBox.BODY_FONT_SIZE,
		font.get_height(DialogueBox.BODY_FONT_SIZE), max_lines])
	_check(max_lines >= 2, "对话框放得下至少 2 行（实测 %d 行）" % max_lines)

	var worst := 0
	var worst_line := 0
	var worst_text := ""
	var over := 0
	for s in res["steps"]:
		var t := String(s.get("text", ""))
		if t.is_empty():
			continue
		var n := DialogueBox.body_lines(font, t)
		if n > worst:
			worst = n
			worst_line = int(s["line"])
			worst_text = t
		if n > max_lines:
			over += 1
			print("      [太长] 第 %d 行要 %d 行 →「%s」" % [int(s["line"]), n, t])
	if over == 0:
		_check(true, "没有一句撑破对话框；最长的一句在第 %d 行、%d 字、占 %d 行"
			% [worst_line, worst_text.length(), worst])
		print("      最长：「%s」" % worst_text)
	else:
		_check(false, "有 %d 句太长（见上面 [太长]）—— 拆成两句，或删点字" % over)


# --- 5-6. 播放 + 与设置界面的交接 --------------------------------------------

func _test_playback(game: Node) -> void:
	print("\n========== 5. 播放 ==========")
	var box := game.get_node_or_null("DialogueBox")
	_check(box != null, "game.tscn 里有 DialogueBox")
	if box == null:
		return
	_check(not bool(box.call("is_active")), "初始没在播")
	_check(not paused, "初始没有暂停（--script 下不自动播开场）")

	var done := [0]
	box.connect("finished", func() -> void: done[0] += 1)

	# ── 5a. 打字机 + 「第一下按键把当前句打完」 ──
	var long_text: String = LONG_TEXT.repeat(15)      # 120 字
	var a_steps := [
		{"kind": StoryScript.K_SAY, "who": "优香", "text": long_text, "line": 1},
		{"kind": StoryScript.K_NARRATE, "text": "第二句。", "line": 2},
	]
	box.call("set_cps", 60.0)
	box.call("play_steps", a_steps, "")
	_check(paused, "开播 → 游戏被暂停")
	_check(bool(box.call("is_active")), "is_active = true")
	_check(bool(box.call("is_typing")), "开播就在打字")
	_check(String(box.call("current_who")) == "优香",
		"说话人「%s」" % box.call("current_who"))
	_check(String(box.call("current_text")) == long_text,
		"完整正文 %d 字" % String(box.call("current_text")).length())

	await _wait(10)
	var v := String(box.call("visible_text"))
	_check(v.length() > 0 and v.length() < long_text.length(),
		"打字机推进中：已打出 %d / %d 字" % [v.length(), long_text.length()])
	_check(long_text.begins_with(v), "打出来的确实是完整正文的前缀")
	_check(bool(box.call("is_typing")), "还没打完")

	box.call("advance")     # 第一下：把当前句**立刻打完**，不翻页
	_check(not bool(box.call("is_typing")), "按一下 → 当前句立刻打完")
	_check(String(box.call("visible_text")) == long_text, "打完 = 完整正文")
	_check(int(box.call("current_index")) == 0, "还停在第 0 步（没有直接翻页）")

	box.call("advance")     # 第二下：翻页
	_check(int(box.call("current_index")) == 1, "再按一下 → 第 1 步")
	_check(String(box.call("current_who")) == "",
		"旁白没有名字牌（名字 =「%s」）" % box.call("current_who"))
	_check(String(box.call("current_text")) == "第二句。",
		"翻到旁白「%s」" % box.call("current_text"))

	box.call("finish")
	_check(not bool(box.call("is_active")), "finish() → 结束")
	_check(not paused, "finish() → 恢复运行")
	_check(done[0] == 1, "finished 信号发了 %d 次" % done[0])
	var after_a: int = done[0]

	# 空 steps 不该把世界暂停在那儿
	box.call("play_steps", [], "")
	_check(not bool(box.call("is_active")) and not paused, "空 steps 直接忽略、不暂停")

	# ── 5b. @wait 自己往下走 + @end 收尾 ──
	var b_steps := [
		{"kind": StoryScript.K_SAY, "who": "优香", "text": "第一句。", "line": 1},
		{"kind": StoryScript.K_NARRATE, "text": "旁白第二句。", "line": 2},
		{"kind": StoryScript.K_WAIT, "seconds": 0.02, "line": 3},
		{"kind": StoryScript.K_SAY, "who": "凯伊", "text": "第三句。", "line": 4},
		{"kind": StoryScript.K_END, "line": 5},
	]
	box.call("set_cps", 60.0)
	box.call("play_steps", b_steps, "")
	_check(int(box.call("step_count")) == 5, "步骤总数 %d" % int(box.call("step_count")))
	_check(String(box.call("current_text")) == "第一句。",
		"第一句「%s」" % box.call("current_text"))
	await _wait(10)
	_check(not bool(box.call("is_typing")), "4 字 / 60 字每秒，10 帧内该打完")

	box.call("advance")     # 已打完 → 翻页
	_check(int(box.call("current_index")) == 1,
		"翻页 → 第 %d 步" % int(box.call("current_index")))
	_check(String(box.call("current_who")) == "", "旁白没有名字")
	_check(String(box.call("current_text")) == "旁白第二句。",
		"旁白正文「%s」" % box.call("current_text"))

	await _wait(10)
	box.call("advance")     # → @wait
	_check(int(box.call("current_index")) == 2,
		"进到 @wait（第 %d 步）" % int(box.call("current_index")))
	# @wait 是**自己往下走**的
	await _wait(20)
	_check(int(box.call("current_index")) == 3,
		"@wait 到点自己往下走 → 第 %d 步" % int(box.call("current_index")))
	_check(String(box.call("current_who")) == "凯伊",
		"下一句是凯伊（实测「%s」）" % box.call("current_who"))

	# 收尾：一路按到底（最多 6 下），断言 @end 之后世界恢复
	for _i in 6:
		if not bool(box.call("is_active")):
			break
		box.call("advance")
		await _wait(2)
	_check(not bool(box.call("is_active")), "@end → 播放结束")
	_check(not paused, "播完 → 游戏恢复运行")
	_check(done[0] == after_a + 1, "finished 又发了 %d 次" % (done[0] - after_a))

	# ── 6. 和 Esc 设置界面的交接 ──
	print("\n========== 6. 和 Esc 设置界面的交接 ==========")
	var menu := game.get_node_or_null("SettingsMenu")
	_check(menu != null, "场景里有 SettingsMenu")
	if menu == null:
		return

	box.call("play_steps", b_steps, "")
	_check(paused, "剧情开播 → 暂停")
	var before := int(box.call("current_index"))
	menu.call("open")
	_check(bool(menu.get("is_open")) and paused, "剧情播着也能开设置界面")
	await _press_space()
	_check(int(box.call("current_index")) == before,
		"设置界面开着时空格**不会**翻剧情（还停在第 %d 步）" % before)
	box.call("finish")
	_check(paused, "菜单开着时剧情播完 → **不**解除暂停（交给菜单）")
	_check(not bool(box.call("is_active")), "剧情确实已经结束")
	menu.call("close")
	_check(not paused, "菜单关掉 → 恢复运行")


# --- 7. 设定表（角色表 / 场景表） ---------------------------------------------

## `story/设定.md` 是**给人看的**，同时也被 `story_script.gd` 解析来校验剧本。
## 这一节验三件事：
##   1. 表本身能解析（列名对、名字不重复、标记没被删掉）；
##   2. 剧本里的说话人**都在表里** —— 含反例：故意打错一个字要能被认出来并给出建议；
##   3. 表里写的**节点**在 game.tscn 里真的存在，且「校园在不在场景里」两边说法一致。
##
## 第 3 条才是这一节存在的主要理由：设定表最容易变成「写了、但早就过期」的文档，
## 而过期的文档比没有文档更坑人。
func _test_bible(game: Node) -> void:
	print("\n========== 7. 设定表 %s ==========" % StoryScript.BIBLE_PATH)
	_check(FileAccess.file_exists(StoryScript.BIBLE_PATH),
		"设定表在 %s" % StoryScript.BIBLE_PATH)
	if not FileAccess.file_exists(StoryScript.BIBLE_PATH):
		return

	var bible := StoryScript.read_bible()
	_check(bool(bible["ok"]), "设定表解析零错误（errors=%d）" % bible["errors"].size())
	for e in bible["errors"]:
		print("      %s" % e)

	# 反例：没有表时必须**明确失败**，不能静默返回一张空表
	var none := StoryScript.read_bible("user://_verify_story_none.md")
	_check(not bool(none["ok"]), "设定表缺失 → ok = false（不是静默成功）")

	var cast_rows: Array = bible["cast"]["rows"]
	var names: Array[String] = []
	for row in cast_rows:
		names.append(String(row.get(StoryScript.COL_NAME, "")))
	# 13 = 主角 + 七名同伴 + 五位 Boss。少一个多半是表被误删了行。
	_check(names.size() >= 13, "角色表里 %d 个名字：%s" % [names.size(), str(names)])

	# 真剧本的说话人必须都在表里
	var real := StoryScript.load_file(TEMPLATE)
	var speakers: Array = StoryScript.summary(real)["speakers"]
	var unknown: Array[String] = StoryScript.check_speakers(real, names)
	_check(unknown.is_empty(), "真剧本 %s 的说话人 %s 全在角色表里"
		% [TEMPLATE.get_file(), str(speakers)])
	for u in unknown:
		print("      [!!] %s" % u)

	# 反例①：故意打错一个字（凯依 / 凯伊），必须报出来**并给出正确的建议**
	var typo := StoryScript.parse("凯依: 打错了一个字。\n")
	var hits: Array[String] = StoryScript.check_speakers(typo, names)
	_check(hits.size() == 1 and hits[0].contains("凯伊") and hits[0].contains("第 1 行"),
		"说话人打错一个字（凯依）→ 报出来并建议「凯伊」：%s" % _join(hits))
	# 反例②：没有角色表（导出忘了放行 .md）时必须**沉默**，不能每句都报警
	var empty_names: Array[String] = []
	_check(StoryScript.check_speakers(typo, empty_names).is_empty(),
		"没有角色表 → 不校验、不报警（不影响播放）")
	# 旁白没有名字，不参与校验
	_check(StoryScript.check_speakers(StoryScript.parse("* 只有旁白。\n"), names).is_empty(),
		"旁白（`*` 行）不参与说话人校验")

	# ── 表里写的节点必须真的在 game.tscn 里 ──
	var all_rows: Array = []
	all_rows.append_array(cast_rows)
	all_rows.append_array(bible["scenes"]["rows"])
	var missing: Array[String] = []
	var checked := 0
	for row in all_rows:
		var node := String(row.get(StoryScript.COL_NODE, "")).strip_edges()
		if node.is_empty() or node.begins_with("不在"):
			continue
		checked += 1
		if game.get_node_or_null(node) == null:
			missing.append("%s → %s" % [String(row.values()[0]), node])
	_check(missing.is_empty() and checked >= 10,
		"设定表里 %d 个「节点」在 game.tscn 里都存在%s"
		% [checked, "" if missing.is_empty() else "（缺 %s）" % str(missing)])

	# ── 「校园在不在场景里」：表里怎么写、场景里就该怎么是 ──
	# 校园那份泼溅是按用户要求从 game.tscn 搬去 campus_venue.tscn 的，而开场旁白
	# 第一句就在讲「脚下的校园」—— 这里是「文案里有的东西，画面里没有」最容易复发
	# 的地方，所以钉成常驻断言。
	var campus_in_scene := game.get_node_or_null("CampusVenue") != null
	var campus_row := _row_by(bible["scenes"]["rows"], StoryScript.COL_SCENE, "campus")
	if campus_row.is_empty():
		_check(false, "场景表里有 campus 这一行")
	else:
		var flag := String(campus_row.get(StoryScript.COL_INSIDE, "")).strip_edges()
		var said_in := flag == "在"
		_check(said_in == campus_in_scene,
			"校园：game.tscn 里%s、场景表写「%s」→ %s" % [
				"有" if campus_in_scene else "没有", flag,
				"一致" if said_in == campus_in_scene else "**对不上，改 story/设定.md 那一行**"])


## 在 `rows` 里按某个列的取值找一行（找不到返回空字典）。
func _row_by(rows: Array, key: String, value: String) -> Dictionary:
	for row in rows:
		if String(row.get(key, "")) == value:
			return row
	return {}


# --- 工具 -------------------------------------------------------------------

## 走**真实输入路径**按一下空格（和 `_verify_settings.gd` 按 Esc 同一套），
## 这样连「按键到底有没有进到 DialogueBox」一起验了。
func _press_space() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(4)


func _join(errs: Array) -> String:
	return " ｜ ".join(PackedStringArray(errs))


func _cleanup() -> void:
	for p in [GBK_FILE, BOM_FILE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
