extends SceneTree
## 验「所有资源都要署名」这条要求 —— 机制上保证，不靠记性。
##
## 六节：
##   1. `scripts/credits.gd` 的数据本身完整（每条都有作者 / 许可 / 分发标志）
##   2. **覆盖率**：`models/`、`assets/`、`addons/`、`splatdata/` 下的每一个目录
##      都在表里登记过 —— 以后新加一套素材忘了署名，这一节就红
##   3. 分发标志与 `.gitignore` 一致：标「不随仓库分发」的路径必须真被忽略
##   4. 许可原文（LICENSE 文件）在位；随仓库分发的素材真在磁盘上
##   5. `CREDITS.md` 与 `credits.gd` 没走散（每条 path / 作者都在人读版里出现）
##   6. 游戏内面板真的画得出来（Esc → 设置 →「致谢与素材署名」），
##      并且 5 位 Boss 的 HUD 血条不会压到左上角的泼溅状态行
##
## 用法：godot --path <工程> --script res://scripts/_verify_credits.gd

var _fail := 0
var _pass := 0

const FIELD_KEYS := ["group", "path", "title", "author", "license",
	"distributed", "source", "license_file", "note"]
## 覆盖率检查的根目录。`story/`、`scripts/` 等本项目自己的目录不在此列
## （它们在表里以单条「本项目作者 / MIT」整体登记）。
const COVER_ROOTS := ["models", "assets", "addons", "splatdata"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	print("========== 1. credits.gd 数据完整性 ==========")
	var entries: Array = Credits.ENTRIES
	print("  登记了 %d 条素材，%d 个分组" % [entries.size(), Credits.GROUPS.size()])
	_check(entries.size() >= 15, "登记条数 ≥ 15（实测 %d）" % entries.size())
	var seen := {}
	var groups_used := {}
	for e in entries:
		var d: Dictionary = e
		var ok := true
		for k in FIELD_KEYS:
			if not d.has(k):
				print("    ⚠️ 缺字段 %s：%s" % [k, str(d.get("title", "?"))])
				ok = false
		if not ok:
			_check(false, "「%s」字段齐全" % str(d.get("title", "?")))
			continue
		_check(d["title"] != "" and d["author"] != "" and d["license"] != "",
			"「%s」作者与许可都写了" % d["title"])
		_check(Credits.GROUPS.has(d["group"]),
			"「%s」分组 %s 在 GROUPS 里" % [d["title"], d["group"]])
		groups_used[d["group"]] = true
		var key := "%s|%s" % [d["path"], d["title"]]
		_check(not seen.has(key), "「%s」没有重复登记" % d["title"])
		seen[key] = true
	for g in Credits.GROUPS:
		_check(groups_used.has(g), "分组「%s」至少有一条素材" % g)

	print("\n========== 2. 覆盖率：每个素材目录都登记过 ==========")
	for r in COVER_ROOTS:
		var dirs := _subdirs("res://" + r)
		print("  %s/ 下 %d 个目录" % [r, dirs.size()])
		for sub in dirs:
			_check(Credits.covers(sub), "%s 已登记（有署名）" % sub)
	# 根目录下直接放的素材文件（models/Arisu.glb 等）也要被覆盖
	for f in _files("res://models"):
		_check(Credits.covers("models/" + f) or Credits.covers("models"),
			"models/%s 已被「models」这条整体覆盖" % f)

	print("\n========== 3. 分发标志 vs .gitignore ==========")
	var ignore_text := FileAccess.get_file_as_string("res://.gitignore")
	_check(ignore_text.length() > 0, "读到了 .gitignore（%d 字节）" % ignore_text.length())
	for e in entries:
		var d: Dictionary = e
		var path: String = d["path"]
		# 只有目录级素材才逐条比 .gitignore；单文件（gunshot_000.wav 之类）不在此判
		if _is_dir("res://" + path):
			if d["distributed"]:
				continue
			_check(ignore_text.contains(path),
				"「%s」标了不随仓库分发，.gitignore 里确实有 %s" % [d["title"], path])
		else:
			_check(true if d["distributed"] else ignore_text.contains(path),
				"「%s」分发标志与 .gitignore 一致" % d["title"])

	print("\n========== 4. 许可原文 / 素材在位 ==========")
	for e in entries:
		var d: Dictionary = e
		var lf: String = d["license_file"]
		if lf != "":
			_check(FileAccess.file_exists("res://" + lf),
				"「%s」的许可原文在 %s" % [d["title"], lf])
		var p: String = d["path"]
		var exists := _path_exists("res://" + p)
		if d["distributed"]:
			_check(exists, "「%s」随仓库分发，磁盘上确实有 %s" % [d["title"], p])
		else:
			print("  ·「%s」不在仓库里（本地%s）" % [d["title"], "有" if exists else "也没有"])

	print("\n========== 5. CREDITS.md 与 credits.gd 同步 ==========")
	var md := FileAccess.get_file_as_string("res://CREDITS.md")
	_check(md.length() > 500, "读到 CREDITS.md（%d 字节）" % md.length())
	for e in entries:
		var d: Dictionary = e
		_check(md.contains(d["path"]),
			"CREDITS.md 里写了「%s」的路径 %s" % [d["title"], d["path"]])
		_check(md.contains(d["author"].split("（")[0]),
			"CREDITS.md 里写了「%s」的作者 %s" % [d["title"], d["author"]])

	print("\n========== 6. 游戏内「致谢与素材署名」面板 ==========")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(15)
	var menu := game.get_node_or_null("SettingsMenu")
	_check(menu != null, "场景里有 SettingsMenu")
	if menu == null:
		_quit()
		return
	menu.open()
	await _wait(2)
	_check(menu.is_open, "设置界面打开")
	menu.open_credits()
	await _wait(2)
	var panel := menu.get_node_or_null("CreditsPanel") as Control
	_check(panel != null and panel.visible, "致谢面板存在且可见")
	if panel != null:
		var body := panel.find_child("Body", true, false) as Label
		_check(body != null, "面板里有正文 Body")
		if body != null:
			var text := body.text
			print("  正文 %d 字 / %d 行" % [text.length(), text.split("\n").size()])
			_check(text.length() > 1500, "正文够长（%d 字，整张表都进来了）" % text.length())
			for who in ["一个睿智", "Kenney", "TakWolf", "NEXON Games", "ReconWorldLab"]:
				_check(text.contains(who), "正文里写到了作者「%s」" % who)
			for what in ["霍德", "佩洛洛斯拉", "倭瓜优香", "飞猪优香", "霸王龙优香"]:
				_check(text.contains(what), "正文里写到了素材「%s」" % what)
			_check(text.contains("不随仓库分发"), "正文说明了哪些素材不随仓库分发")
		var scroll := panel.find_child("Scroll", true, false) as ScrollContainer
		_check(scroll != null, "正文放在可滚动容器里（整张表会超出面板）")
	menu.close_credits()
	_check(panel != null and not panel.visible, "关掉致谢面板（Esc 的第一下只关它）")
	menu.close()
	_check(not menu.is_open, "设置界面可以关闭")

	print("\n========== 7. 五位 Boss 的 HUD 血条不压泼溅状态行 ==========")
	var hud := game.get_node_or_null("HUD")
	_check(hud != null, "场景里有 HUD")
	if hud != null:
		var consts: Dictionary = hud.get_script().get_script_constant_map()
		var boss_count := 0
		for ch in game.get_children():
			if ch is Boss:
				boss_count += 1
		var row_h: float = consts["BOSS_ROW_HEIGHT"]
		var top: float = consts["BOSS_TOP"]
		var bar_h: float = consts["BOSS_BAR_HEIGHT"]
		var floor_top: float = consts["SPLAT_ROW_TOP"]
		var boss_bottom := top + float(boss_count - 1) * row_h + bar_h
		# 泼溅状态行的起点现在**跟着 Boss 条数走**（见 hud.gd::splat_row_top）
		var splat_top: float = hud.call("splat_row_top")
		print("  Boss %d 位 → 血条组占 y = %.0f ~ %.0f；泼溅状态行从 %.0f 开始（下限 %.0f）" % [
			boss_count, top - 28.0, boss_bottom, splat_top, floor_top])
		_check(boss_count == 7, "场上正好 7 位 Boss（--bosses=all，实测 %d）" % boss_count)
		_check(splat_top > boss_bottom,
			"泼溅状态行（%.0f）在最后一条 Boss 血条（%.0f）下面" % [splat_top, boss_bottom])
		_check(splat_top >= floor_top,
			"泼溅状态行没有高过血量面板下沿（%.0f ≥ %.0f）" % [splat_top, floor_top])
		var status := hud.get_node_or_null("SplatStatus0") as Label
		if status != null:
			_check(status.position.y >= boss_bottom,
				"泼溅状态行实际 y = %.0f，没被血条盖住" % status.position.y)
		else:
			print("  ·（泼溅状态行还没建，跳过实际位置断言）")

	_quit()


# --- 工具 ---

func _subdirs(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(path)
	if da == null:
		return out
	for d in da.get_directories():
		if d.begins_with("."):
			continue
		out.append(path.trim_prefix("res://").path_join(d))
	return out


func _files(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(path)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		out.append(f)
	return out


func _is_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _path_exists(path: String) -> bool:
	return _is_dir(path) or FileAccess.file_exists(path)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
		_pass += 1
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _quit() -> void:
	print("\n汇总：%d 项通过 / %d 项失败" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
