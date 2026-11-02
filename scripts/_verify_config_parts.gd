extends SceneTree
## 自检：两张配置单九行都要有照片，同一张单里不能重复，文件都得真的加载得出来。
##   _tools/run_probe.sh res://scripts/_verify_config_parts.gd

var _fails := 0


func _check(ok: bool, msg: String) -> void:
	print(("[ OK ] " if ok else "[FAIL] ") + msg)
	if not ok:
		_fails += 1


func _check_sheet(name: String, spec: Dictionary) -> void:
	var parts: Array = spec["parts"]
	var labels: Array = spec["labels"]
	_check(parts.size() == 9, "%s：9 行（实测 %d）" % [name, parts.size()])
	_check(labels.size() == parts.size(), "%s：labels 行数对齐" % name)
	var seen := {}
	for i in parts.size():
		var part := String(parts[i])
		_check(not part.is_empty(), "%s 第 %d 行「%s」有零件图" % [name, i + 1, String(labels[i])])
		if part.is_empty():
			continue
		var path := "res://assets/story/parts/%s.png" % part
		var tex := load(path) as Texture2D
		_check(tex != null, "%s 第 %d 行加载 %s" % [name, i + 1, path.get_file()])
		if tex != null:
			_check(tex.get_width() == 492 and tex.get_height() == 560,
				"%s 第 %d 行尺寸 492×560（实测 %d×%d）"
				% [name, i + 1, tex.get_width(), tex.get_height()])
		_check(not seen.has(part), "%s 第 %d 行没和前面的行撞图（%s）" % [name, i + 1, part])
		seen[part] = true
	print("[parts] %s 用图：%s" % [name, ", ".join(PackedStringArray(parts))])


func _initialize() -> void:
	_check_sheet("B300", ShopClerk.SHEET_B300)
	_check_sheet("5090", ShopClerk.SHEET_5090)

	# 两张单之间也不允许共用（用户 2026-11-02：「这怎么一样的图片」）
	var a: Array = (ShopClerk.SHEET_B300["parts"] as Array).duplicate()
	var b: Array = (ShopClerk.SHEET_5090["parts"] as Array).duplicate()
	var shared: Array[String] = []
	for p in a:
		if b.has(p):
			shared.append(String(p))
	_check(shared.is_empty(), "两张单之间没有共用图（重复：%s）"
		% (", ".join(PackedStringArray(shared)) if not shared.is_empty() else "无"))

	if _fails == 0:
		print("[parts] 结论：OK")
		quit(0)
	else:
		print("[parts] 结论：FAIL %d 项" % _fails)
		quit(1)
