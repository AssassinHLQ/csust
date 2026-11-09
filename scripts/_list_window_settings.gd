extends SceneTree
## 列出本项目所有 display/window 相关设置名，用来确认「启动时不抢焦点」的
## 正确项目设置键名（override.cfg 用）。
## 纯 headless，不开窗口、不渲染。

func _initialize() -> void:
	var hits: Array[String] = []
	for p in ProjectSettings.get_property_list():
		var nm: String = str(p.get("name", ""))
		if nm.begins_with("display/window") or nm.to_lower().contains("focus"):
			hits.append(nm)
	hits.sort()
	print("======== display/window 相关设置 ========")
	for h in hits:
		print("  %s = %s" % [h, str(ProjectSettings.get_setting(h))])
	print("---- 共 %d 条 ----" % hits.size())
	quit(0)
