extends SceneTree
## 探针：跑酷计时 HUD 与玩家血量面板**不许重叠**（并出一张真机图）。
##
## 起因（本喵验收 `cb25aa0` 时抓到）：计时 HUD 原来摆在左上角 `(28, 20)`，
## 而那正是玩家血量面板 `(24, 20)–(368, 112)`（`hud.gd` 的 `HP_PANEL_POS` /
## `HP_PANEL_SIZE`）；`Parkour` 在 `game.tscn` 里又排在 `HUD` **前面** ——
## 两个 `CanvasLayer` 同为 layer 1 时按树序画，HUD 盖在上面，
## **计时文字会被血量面板整个挡掉**。现已改到右上角（右对齐）。
##
## 为什么两个矩形能直接比：`HUD` 与 `ParkourHUD` 都是挂在 `game.tscn` 下的
## `CanvasLayer`，里面的 `Control` 的 `get_global_rect()` 都在**同一套画布坐标**里
## （1600 × 900 的逻辑画布）。
##
## 用法：godot --path <工程> --script res://scripts/_probe_parkour_hud.gd -- --splat=off
## 输出：`user://parkour_hud.png`（**不隐藏任何 HUD**）+ 两个矩形的读数

const HP_POS := Vector2(24.0, 20.0)     ## = hud.gd 的 HP_PANEL_POS
const HP_SIZE := Vector2(344.0, 92.0)   ## = hud.gd 的 HP_PANEL_SIZE

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	# 把玩家挪到跑道上，让计时 HUD 有真实的段名可显示
	var pk := game.get_node_or_null("Parkour")
	if pk == null:
		print("!! 场景里没有 Parkour")
		quit(1)
		return
	var p := game.get_node_or_null("Player") as Player
	if p != null:
		p.global_position = pk.call("respawn_point", 1)
		await _wait(6)

	var hp := Rect2(HP_POS, HP_SIZE)
	print("血量面板（hud.gd 常量）  %s" % str(hp))
	for n in ["ParkourHUD/Timer", "ParkourHUD/Seg"]:
		var l := pk.get_node_or_null(n) as Label
		if l == null:
			_check(false, "找得到 %s" % n)
			continue
		var r := l.get_global_rect()
		print("%-22s %s  文本「%s」" % [n, str(r), l.text])
		_check(not r.intersects(hp),
			"%s 与血量面板**不相交**（重叠面积 = %.0f px²）"
			% [n, r.intersection(hp).get_area()])
		_check(r.position.x > 1600.0 * 0.5,
			"%s 在画面右半边（x = %.0f）" % [n, r.position.x])

	var out := "user://parkour_hud.png"
	print("[probe] save_png err = %d → %s"
		% [root.get_texture().get_image().save_png(out),
			ProjectSettings.globalize_path(out)])
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
