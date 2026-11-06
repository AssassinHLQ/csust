extends SceneTree
## 确认设置界面里真的长出了「LOD 切换阈值」这一行（滑块 + 数值标签）。
##
## 用法：_tools/run_probe.sh res://scripts/_verify_lod_row.gd

const MENU_SCRIPT := "res://scripts/settings_menu.gd"
const KEY := "lod_threshold_px"

var _menu: Node
var _frames := 0


func _initialize() -> void:
	# 设置菜单不是独立场景，它挂在 game.tscn 里（脚本 settings_menu.gd）
	var g: PackedScene = load("res://scenes/game.tscn")
	if g == null:
		print("[row] FAIL: 载不动 game.tscn")
		quit()
		return
	_menu = g.instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	var menu := _find_first(_menu, "SettingsMenu")
	if menu == null:
		print("[row] 找不到 SettingsMenu 节点")
		quit()
		return true

	var rows: Variant = menu.get("_rows")
	if rows == null or not (rows is Dictionary):
		print("[row] 读不到 _rows")
		quit()
		return true
	var d: Dictionary = rows
	print("[row] 设置界面共 %d 行" % d.size())
	var ok := false
	if d.has(KEY):
		var row: Dictionary = d[KEY]
		var ctl: Variant = row.get("control")
		var lbl: Variant = row.get("value")
		print("[row] 找到 %s：控件=%s  数值标签文本=「%s」" % [
			KEY,
			("HSlider" if ctl is HSlider else str(ctl)),
			(str((lbl as Label).text) if lbl is Label else "?")])
		if ctl is HSlider:
			var s := ctl as HSlider
			print("[row] 滑块 min=%.2f max=%.2f step=%.2f value=%.2f" % [
				s.min_value, s.max_value, s.step, s.value])
			ok = is_equal_approx(s.min_value, 0.1) and is_equal_approx(s.max_value, 8.0)
	else:
		print("[row] 没有 %s 这一行" % KEY)

	print("[row] 结果: %s" % ("PASS" if ok else "FAIL"))
	_menu.queue_free()
	quit()
	return true


func _find_first(n: Node, _cls: String) -> Node:
	# 按**脚本资源路径**匹配：普通脚本没有 global class name，
	# `get_script().get_global_name()` 会是空串（第一次就栽在这）。
	var sc: Script = n.get_script() as Script
	if sc != null and String(sc.resource_path) == MENU_SCRIPT:
		return n
	for c in n.get_children():
		var r := _find_first(c, _cls)
		if r != null:
			return r
	return null
