extends SceneTree
## 把 `ArchTerminal.COMPANIONS` 里的台词导出成 JSON。
##
## **为什么要这个**：配音生成（`_tools/gen_companion_voice.py`）需要**准确的台词文本**，
## 如果在 Python 里再抄一份，改了 GDScript 而忘了改 Python，就会出现
## 「屏幕上写一句、配音说另一句」——所以这里从**唯一数据源**导出。
##
##   godot --headless --path . --script res://scripts/_dump_companion_lines.gd

const OUT_PATH := "res://_tools/_tmp/companion_lines.json"


func _initialize() -> void:
	var out := {}
	for who in ["arona", "plana"]:
		var d: Dictionary = ArchTerminal.COMPANIONS[who]
		out[who] = {
			"name": String(d["name"]),
			"open": Array(d["open"]).duplicate(),
			"loop": Array(d["loop"]).duplicate(),
		}
	var dir := ProjectSettings.globalize_path("res://").path_join("_tools/_tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s" % OUT_PATH)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	var n := 0
	for who in out:
		n += int(out[who]["open"].size()) + int(out[who]["loop"].size())
	print("[dump] %s → %d 句台词" % [OUT_PATH, n])
	quit(0)
