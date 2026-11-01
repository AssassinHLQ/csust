extends SceneTree
## 出图：配置单默认态 + 悬停「显卡」+ 悬停「内存」。
##   _tools/run_shot.sh res://scripts/_probe_sheet_shot.gd

const PARTS := ["gpu", "server", "cpu", "ram", "ssd", "ssd", "nic", "cooling", "psu"]
const LABELS := [
	"显卡 · NVIDIA B300 · 288GB HBM3E ×8",
	"整机 · HGX B300 八卡基板 + 8U 机箱",
	"处理器 · Intel Xeon 6 6980P ×2",
	"内存 · DDR5-6400 ECC RDIMM 64GB ×24 = 1.5TB",
	"系统盘 · PCIe 5.0 NVMe 1.92TB ×2（RAID 1）",
	"数据盘 · PCIe 5.0 NVMe 7.68TB ×8（RAID 10）",
	"网络 · ConnectX-8 800G ×8",
	"液冷 · 机架式 CDU + 冷板 ≥60 kW",
	"配电 · 12kW 电源框 · 2N 冗余",
]
var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _shoot(nm: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, nm])


func _hover(box: DialogueBox, idx: int) -> void:
	var z := box.get_node_or_null("Root/ConfigSheet/Row%d" % idx) as Control
	if z == null:
		print("[sheet] 没有 Row%d" % idx)
		return
	var c := z.get_global_rect().get_center()
	Input.warp_mouse(c)
	for _i in 4:
		await process_frame
	var ev := InputEventMouseMotion.new()
	ev.position = c
	ev.global_position = c
	ev.relative = Vector2(1, 1)
	root.push_input(ev)
	for _i in 8:
		await process_frame
	var hov := root.gui_get_hovered_control()
	print("[sheet] 悬停第 %d 行 → hovered=%s" % [idx, hov.name if hov != null else "none"])


func _run() -> void:
	root.size = Vector2i(1600, 900)  # 设计分辨率，缩放 1:1，鼠标坐标直接对得上
	var bg := CanvasLayer.new()
	bg.layer = 0
	root.add_child(bg)
	var rect := ColorRect.new()
	rect.color = Color(0.10, 0.12, 0.14, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(rect)

	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)
	var rows: Array = []
	for i in PARTS.size():
		rows.append({"top": 146.0 + i * 66.0, "bottom": 146.0 + (i + 1) * 66.0,
			"image": "res://assets/story/parts/%s.png" % PARTS[i],
			"label": LABELS[i]})
	box.play_steps([
		{"kind": "say", "who": "芹香", "text": "老板,看这套配置怎么样[TVT]"},
		{"kind": "config_sheet", "base": "res://assets/story/config_sheet.png",
			"photo": {"x": 1064, "y": 146, "w": 492, "h": 560}, "rows": rows,
			"caption": "图上为八卡计算托盘：8 颗 B300 + 24 条 ECC 内存（鼠标移到左边的部件名试试）"},
	], "shot")
	for _i in 20:
		await process_frame
	box.advance()
	for _i in 20:
		await process_frame

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_sheet")
	DirAccess.make_dir_recursive_absolute(_out)
	await _shoot("01_default")
	await _hover(box, 0)
	await _shoot("02_hover_gpu")
	await _hover(box, 3)
	await _shoot("03_hover_ram")
	await _hover(box, 8)
	await _shoot("04_hover_psu")
	print("[sheet] 输出到 %s" % _out)
	quit(0)
