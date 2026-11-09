extends SceneTree
## 诊断：当前两份泼溅的**缓存键**是什么，磁盘上哪些文件是孤儿。
##
## 用户 2026-11-09：「666这不是流氓软件吗」—— 质疑 AppData 里 2.75 GB 缓存。
## 本喵先把「哪份还在用、哪份已经是死文件」量清楚，再谈清理。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_splat_cache.gd

const SogRuntime := preload("res://scripts/sog_runtime.gd")


func _initialize() -> void:
	var srcs := ["res://splatdata/room609.sogdata", "res://splatdata/school_playable.sogdata"]
	var live: Array[String] = []
	print("========== 泼溅缓存键诊断 ==========")
	for s in srcs:
		if not FileAccess.file_exists(s):
			print("  %s —— 文件不存在" % s)
			continue
		var stamp: Dictionary = SogRuntime._source_stamp(s)
		var key: String = SogRuntime._cache_path(s, stamp)
		live.append(key.get_file())
		var f := FileAccess.open(s, FileAccess.READ)
		var mb := float(f.get_length()) / 1048576.0
		f.close()
		print("  %-46s size=%d mtime=%d (%.1f MB)" % [s.get_file(), stamp["size"], stamp["mtime"], mb])
		print("      → 期望缓存文件：%s" % key.get_file())
		print("      → 该文件存在：%s" % str(FileAccess.file_exists(key)))

	# 列出目录里所有 .gdgsrt，标出孤儿
	var dir := DirAccess.open(SogRuntime.CACHE_DIR)
	if dir == null:
		print("\n  （缓存目录还不存在）")
		quit(0)
		return
	print("\n── 磁盘上现有的缓存文件 ──")
	var total_live := 0
	var total_dead := 0
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir() and n.ends_with(".gdgsrt"):
			var full := SogRuntime.CACHE_DIR.path_join(n)
			var fl := FileAccess.open(full, FileAccess.READ)
			var mb := float(fl.get_length()) / 1048576.0 if fl != null else 0.0
			if fl != null:
				fl.close()
			var is_live := live.has(n)
			if is_live:
				total_live += int(mb)
			else:
				total_dead += int(mb)
			print("  %-6s %8.0f MB  %s" % ["在用" if is_live else "孤儿", mb, n])
		n = dir.get_next()
	dir.list_dir_end()
	print("\n  在用合计 ≈ %d MB" % total_live)
	print("  孤儿合计 ≈ %d MB  ← 删掉这些不丢任何东西" % total_dead)
	quit(0)
