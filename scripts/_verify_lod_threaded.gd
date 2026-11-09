extends SceneTree
## 验证：电竞房 LOD 改成后台加载之后
##   ① 开局 instantiate + `_ready` 是否变快（改造前实测 2471 ms）
##   ② 高/中模会不会在若干帧后**自己**到位（后台加载成功）
##   ③ 档位选择是否还能正常切（近 → 高模 / 远 → 低模）
##
##   godot --headless --script res://scripts/_verify_lod_threaded.gd -- --no-capture

const ROOM := "res://scenes/esports_room.tscn"
## 屏幕外窗口（`project.godot` 的 mode=2 会顶掉命令行参数，见 offscreen_window.gd）
const OffWin := preload("res://scripts/offscreen_window.gd")

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[lv] OK   %s" % what)
	else:
		_fails += 1
		print("[lv] FAIL %s" % what)


func _run() -> void:
	# 这个探针不需要出图，`--headless` 就能跑；但万一有人不加 --headless，
	# 也得保证窗口在屏幕外、不抢前台。
	await OffWin.apply(self)
	await _run_body()


func _run_body() -> void:
	await _wait(3)
	print("[lv] ============ LOD 后台加载验证 ============")

	# ── ① 开局 instantiate 的耗时 ──
	var ps: PackedScene = load(ROOM)
	var t0 := Time.get_ticks_usec()
	var room: Node3D = ps.instantiate()
	root.add_child(room)
	await _wait(3)
	var t_ready := (Time.get_ticks_usec() - t0) / 1000.0
	print("[lv] instantiate + _ready = %.1f ms（改造前是 2471 ms）" % t_ready)
	_check(t_ready < 1200.0, "开局不再被 LOD 拖住（%.1f ms < 1200）" % t_ready)

	var lod := room.get_node_or_null("Lod")
	_check(lod != null, "找到 Lod 节点")
	if lod == null:
		quit(1)
		return

	# 刚起来时后台还没加载完，Lod 下应该还没有子模型
	var n_now := lod.get_child_count()
	print("[lv] _ready 刚过时 Lod 子节点数 = %d（应该是 0，说明没同步加载）" % n_now)
	_check(n_now == 0, "开局没有同步加载高/中模（当前 %d 个）" % n_now)

	# ── ② 等后台加载到位 ──
	print("[lv] 等后台加载…")
	var n_final := 0
	var waited_ms := 0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 30000:
		await process_frame
		n_final = lod.get_child_count()
		if n_final >= 2:
			break
	waited_ms = Time.get_ticks_msec() - t1
	print("[lv] 等了 %d ms，Lod 子节点数 = %d" % [waited_ms, n_final])
	for c in lod.get_children():
		print("[lv]   子模型：%s（%s）" % [c.name, c.get_class()])
	_check(n_final >= 2, "高/中模后台加载到位（%d 个）" % n_final)

	# ── ③ 档位切换 ──
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var center: Vector3 = lod.get("_center")
	print("[lv] 房间中心 = %s" % str(center.snappedf(0.01)))

	# 贴近房间（3 m）→ 应该用高模
	cam.global_position = center + Vector3(0, 3.0, 3.0)
	await _wait(6)
	var high: Node3D = lod.get("_high")
	var mid: Node3D = lod.get("_mid")
	var low: Node3D = lod.get("_low")
	print("[lv] 3 m 处：high=%s mid=%s low=%s" % [
		str(high.visible) if high else "-", str(mid.visible) if mid else "-",
		str(low.visible) if low else "-"])
	_check(high != null and high.visible, "3 m 处用高模")
	_check(low != null and not low.visible, "3 m 处低模已关")

	# 远处（45 m）→ 应该用低模
	cam.global_position = center + Vector3(0, 10.0, 45.0)
	await _wait(6)
	print("[lv] 45 m 处：high=%s mid=%s low=%s" % [
		str(high.visible) if high else "-", str(mid.visible) if mid else "-",
		str(low.visible) if low else "-"])
	_check(high != null and not high.visible, "45 m 处高模已关")
	_check(low != null and low.visible, "45 m 处用低模")

	# 中距（20 m）→ 应该用中模
	cam.global_position = center + Vector3(0, 6.0, 20.0)
	await _wait(6)
	print("[lv] 20 m 处：high=%s mid=%s low=%s" % [
		str(high.visible) if high else "-", str(mid.visible) if mid else "-",
		str(low.visible) if low else "-"])
	if mid != null:
		_check(mid.visible, "20 m 处用中模")

	print("[lv] ---------- 结果：%s（%d 项不合格）----------"
		% ["全过" if _fails == 0 else "有失败", _fails])
	quit(0 if _fails == 0 else 1)
