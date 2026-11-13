extends SceneTree
## 独立验收：`PlanaPage` 能不能正确逐帧播放抠像素材。
##
## ⚠️ 为什么要「独立」：`game.gd:105` 里 `preload("res://scripts/title_intro.gd")`，
##    而那个文件当时正被**另一个会话**改到一半（缩进语法错）⇒ 任何加载 `game.tscn`
##    的探针都会连带失败。所以这里**不碰 game.tscn**，直接实例化 PlanaPage
##    （尺寸照抄屏幕 SubViewport 的 1280×720），把「帧序列 + 播放 + 界面」验掉。
##    终端→页面的接线等 title_intro 修好后另跑一次端到端。
##
##   godot --path . --script res://scripts/_verify_plana.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")
const VP := Vector2i(1280, 720)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(900, 720))
	for _i in 3:
		await process_frame
	print("═══ 普拉娜逐帧播放 · 独立验收 ═══\n")

	var page := PlanaPage.new()
	page.name = "PlanaPage"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	# 模拟 SubViewport 的尺寸（真实场景里是 PRESET_FULL_RECT 撑满 1280×720）
	page.set_deferred("size", Vector2(VP))
	await _wait(4)
	page.size = Vector2(VP)

	var n := page.frame_count()
	_check(n > 100, "帧序列已列出（%d 帧）" % n)
	if n == 0:
		print("  !! 缺 assets/plana_frames/*.png —— 用 ffmpeg 重新生成")
		_summary()
		quit(1)
		return

	page.open()
	await _wait(4)
	_check(page.visible, "open() 之后可见")

	# 播放：帧号要前进
	var f0 := int(page.get("_frame_i"))
	await _wait(20)
	var f1 := int(page.get("_frame_i"))
	_check(f1 != f0, "帧号在前进（%d → %d）" % [f0, f1])

	# 纹理真的读进来了（缓存里应有东西）
	var cache: Dictionary = page.get("_cache")
	_check(cache.size() > 0, "已缓存纹理 %d 张" % cache.size())
	var tex_ok := false
	for k in cache.keys():
		var t = cache[k]
		if t != null and t is Texture2D and (t as Texture2D).get_size().x > 0:
			tex_ok = true
			print("  样本帧 %s: %s" % [str(k), str((t as Texture2D).get_size())])
			break
	_check(tex_ok, "纹理是有效的 Texture2D")

	# 缓存上限：跑久一点不该无限增长
	await _wait(180)
	var cache2: Dictionary = page.get("_cache")
	_check(cache2.size() <= PlanaPage.CACHE_MAX,
		"缓存受控（%d ≤ %d）" % [cache2.size(), PlanaPage.CACHE_MAX])

	# 循环：跑过一整轮后帧号仍在范围内
	var idx := int(page.get("_frame_i"))
	_check(idx >= 0 and idx < n, "帧号在 0..%d 内（当前 %d）" % [n - 1, idx])

	# 台词打字
	var ty0 := float(page.get("_typed"))
	await _wait(20)
	var ty1 := float(page.get("_typed"))
	_check(ty1 >= ty0, "台词在打字（%.1f → %.1f）" % [ty0, ty1])

	await _shot("plana_a")
	await _wait(45)
	await _shot("plana_b")

	# Esc 关闭
	#
	# ⚠️ 必须先把 `close_requested` 接上 `close()` —— 真实接线在
	#    `hut_computer._close_plana()` 里，这个独立探针没有那个上层，
	#    不接的话按 Esc 只会发信号、没人收，页面照样可见（第一版就是这条红）。
	page.close_requested.connect(page.close)
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_ESCAPE
	page.feed(e)
	await _wait(3)
	_check(not page.visible, "Esc 关闭")
	_check((page.get("_cache") as Dictionary).is_empty(), "关闭时释放纹理缓存")

	_summary()
	quit(0)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_plana")
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s.png" % name))
	print("  [img] %s" % out.path_join("%s.png" % name))


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
