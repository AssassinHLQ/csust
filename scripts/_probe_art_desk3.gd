extends SceneTree
## 探针 3：用**水平面密度**找那张办公桌，而不是俯视最大高度。
##
## 为什么换量法：「每格最大 y」会被高度相近的东西盖住 —— 桌前的靠背椅（背高约 1.0 m）
## 正好压在桌沿上方，于是桌面在俯视图里被切成碎片，候选全变成画架托盘。
## 真正的桌面特征不是「高」，而是**一大片连续的水平面**：在 y∈[0.68, 0.88] 这个
## 薄片里点数很多、且这些点的 y 方差极小。画架托盘（0.8 m 深、30 cm 宽）、
## 椅面（40×40）在面积上比不过办公桌（1.2×0.6 起），高度更不齐。
##
## 输出 `_arisu_captures/_artdesk/probe03.txt` + `p3_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk3.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
const CELL := 0.04
## 桌面薄片（世界 y）
const BAND_LO := 0.66
const BAND_HI := 0.90
## 薄片里一个格子至少要有这么多点，才算「有水平面」
const MIN_PTS := 3
## 一片桌面至少要这么多格子（0.04 m 格 → 100 格 = 0.16 m²）
const MIN_CELLS := 60
const STRIDE := 2

var _rep := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	root.add_child(game)
	var room := game.get_node_or_null("Room609") as Node3D
	var waited := 0
	while waited < 9000 and (room == null or not bool(room.call("is_ready"))):
		await process_frame
		waited += 1
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Companion:
			(c as Node3D).visible = false

	var splat := room.get("splat_node") as Node3D
	var res: Resource = splat.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var pc_xf: Transform3D = room.global_transform * splat.transform
	_p("等 %d 帧；点数 %d" % [waited, xyz.size()])

	# 房间范围直接用墙盒外框（和探针 1 一致）
	var lo := Vector3(-5.86, 0.0, -6.78)
	var hi := Vector3(4.86, 0.0, 13.86)
	var nx := int(ceil((hi.x - lo.x) / CELL)) + 1
	var nz := int(ceil((hi.z - lo.z) / CELL)) + 1
	var cnt := PackedInt32Array()
	cnt.resize(nx * nz)
	cnt.fill(0)
	var ysum := PackedFloat32Array()
	ysum.resize(nx * nz)
	var ymin := PackedFloat32Array()
	ymin.resize(nx * nz)
	ymin.fill(999.0)
	var ymax := PackedFloat32Array()
	ymax.resize(nx * nz)
	ymax.fill(-999.0)

	var t0 := Time.get_ticks_msec()
	var i := 0
	var n := xyz.size()
	while i < n:
		var w: Vector3 = pc_xf * xyz[i]
		if w.y >= BAND_LO and w.y <= BAND_HI and w.x >= lo.x and w.x <= hi.x \
				and w.z >= lo.z and w.z <= hi.z:
			var ix := int((w.x - lo.x) / CELL)
			var iz := int((w.z - lo.z) / CELL)
			var k := ix + iz * nx
			cnt[k] += 1
			ysum[k] += w.y
			ymin[k] = minf(ymin[k], w.y)
			ymax[k] = maxf(ymax[k], w.y)
		i += STRIDE
	_p("薄片 y∈[%.2f,%.2f] 统计 %.2f s" % [BAND_LO, BAND_HI,
		float(Time.get_ticks_msec() - t0) / 1000.0])

	# 连通块：薄片里有足够点、且厚度 ≤ 6 cm（真水平面）的格子
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	seen.fill(0)
	var found: Array = []
	for iz in nz:
		for ix in nx:
			var k0 := ix + iz * nx
			if seen[k0] != 0 or cnt[k0] < MIN_PTS:
				continue
			if ymax[k0] - ymin[k0] > 0.06:
				continue
			var stack: Array[int] = [k0]
			seen[k0] = 1
			var nc := 0
			var lox := float(ix)
			var hix := float(ix)
			var loz := float(iz)
			var hiz := float(iz)
			var ys := 0.0
			var pts := 0
			while not stack.is_empty():
				var k: int = stack.pop_back()
				var kx := k % nx
				var kz := k / nx
				nc += 1
				ys += ysum[k] / float(cnt[k])
				pts += cnt[k]
				lox = minf(lox, float(kx))
				hix = maxf(hix, float(kx))
				loz = minf(loz, float(kz))
				hiz = maxf(hiz, float(kz))
				var dz := -1
				while dz <= 1:
					var dx := -1
					while dx <= 1:
						var jx: int = kx + dx
						var jz: int = kz + dz
						if jx >= 0 and jx < nx and jz >= 0 and jz < nz:
							var jk := jx + jz * nx
							if seen[jk] == 0 and cnt[jk] >= MIN_PTS \
									and ymax[jk] - ymin[jk] <= 0.06:
								seen[jk] = 1
								stack.append(jk)
						dx += 1
					dz += 1
			if nc < MIN_CELLS:
				continue
			found.append({
				"lo": Vector3(lo.x + lox * CELL, ys / float(nc), lo.z + loz * CELL),
				"hi": Vector3(lo.x + (hix + 1.0) * CELL, ys / float(nc),
					lo.z + (hiz + 1.0) * CELL),
				"cells": nc,
				"pts": pts,
				"area": float(nc) * CELL * CELL,
				"y": ys / float(nc),
			})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["area"]) > float(b["area"]))
	_p("\n=== 水平面连通块（薄片 y∈[%.2f,%.2f]，≥%d 格，厚度≤6cm） ===" % [BAND_LO, BAND_HI, MIN_CELLS])
	_p("  按面积倒序；dW×dD 是外框尺寸，fill = 面积 / 外框面积（1.0 = 实心矩形）")
	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := Vector3.ZERO
	if sensei != null:
		sp = sensei.global_position
	var pick: Array = []
	for c in found:
		var d: Dictionary = c
		var a: Vector3 = d["lo"]
		var b: Vector3 = d["hi"]
		var w: float = b.x - a.x
		var dep: float = b.z - a.z
		var fill: float = float(d["area"]) / maxf(w * dep, 0.0001)
		d["fill"] = fill
		d["w"] = w
		d["d"] = dep
		_p("  x[%7.2f,%7.2f] z[%7.2f,%7.2f]  %5.2f×%5.2f m  面积%5.2f m²  fill %.2f  点数 %5d  y %.3f  中心(%6.2f,%.2f,%6.2f)  ΔSensei(%.2f,%.2f)"
			% [a.x, b.x, a.z, b.z, w, dep, float(d["area"]), fill, int(d["pts"]),
				float(d["y"]), (a.x + b.x) * 0.5, float(d["y"]), (a.z + b.z) * 0.5,
				(a.x + b.x) * 0.5 - sp.x, (a.z + b.z) * 0.5 - sp.z])
	# 桌面判据：面积 ≥ 0.45 m²、外框 ≥ 0.55×0.55、fill ≥ 0.55
	for c in found:
		var d: Dictionary = c
		if float(d["area"]) >= 0.45 and float(d["w"]) >= 0.55 and float(d["d"]) >= 0.55 \
				and float(d["fill"]) >= 0.55:
			pick.append(d)
	_p("\n  满足「桌面」判据（面积≥0.45、外框≥0.55×0.55、fill≥0.55）的有 %d 个" % pick.size())

	# ── 桌下柜体探测：桌面外框正下方 y∈[0.15,0.60] 有没有点（抽屉柜 / 桌腿） ──
	_p("\n=== 桌下（y∈[0.15,0.60]）点数，判断有没有柜体 ===")
	var low := PackedInt32Array()
	low.resize(nx * nz)
	low.fill(0)
	i = 0
	while i < n:
		var w2: Vector3 = pc_xf * xyz[i]
		if w2.y >= 0.15 and w2.y <= 0.60 and w2.x >= lo.x and w2.x <= hi.x \
				and w2.z >= lo.z and w2.z <= hi.z:
			var ix2 := int((w2.x - lo.x) / CELL)
			var iz2 := int((w2.z - lo.z) / CELL)
			low[ix2 + iz2 * nx] += 1
		i += STRIDE
	for idx in pick.size():
		var d: Dictionary = pick[idx]
		var a: Vector3 = d["lo"]
		var b: Vector3 = d["hi"]
		var x0 := maxi(0, int((a.x - lo.x) / CELL))
		var x1 := mini(nx - 1, int((b.x - lo.x) / CELL))
		var z0 := maxi(0, int((a.z - lo.z) / CELL))
		var z1 := mini(nz - 1, int((b.z - lo.z) / CELL))
		var s := 0
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				s += low[ix + iz * nx]
		_p("  D%d 中心(%6.2f,%.2f,%6.2f) 桌面下方点数 %6d  平均每格 %5.1f"
			% [idx + 1, (a.x + b.x) * 0.5, float(d["y"]), (a.z + b.z) * 0.5, s,
				float(s) / float(maxi((x1 - x0 + 1) * (z1 - z0 + 1), 1))])

	# ── 出图：每个候选正面 + 侧面近景 ───────────────────────────────────────
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	var shown := 0
	for d in pick:
		if shown >= 8:
			break
		shown += 1
		var a: Vector3 = d["lo"]
		var b: Vector3 = d["hi"]
		var ctr := (a + b) * 0.5
		var inward := Vector3(0.0, 0.0, 3.5) - ctr
		inward.y = 0.0
		if inward.length() < 0.5:
			inward = Vector3(0.0, 0.0, 1.0)
		inward = inward.normalized()
		var cp := ctr + inward * 2.4
		cp.y = 1.50
		await _look(cam, cp, Vector3(ctr.x, 0.80, ctr.z),
			OUT_ABS.path_join("p3_d%02d.png" % shown))
		var cp2 := ctr + inward * 1.7 + Vector3(0.0, 0.9, 0.0)
		await _look(cam, cp2, Vector3(ctr.x, 0.55, ctr.z),
			OUT_ABS.path_join("p3_d%02d_low.png" % shown))
		_p("[img] D%d 尺寸 %.2f×%.2f y=%.3f 中心 %s"
			% [shown, float(d["w"]), float(d["d"]), float(d["y"]), str(ctr.snappedf(0.01))])

	_flush()
	quit(0)


func _look(cam: Camera3D, from: Vector3, to: Vector3, path: String) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe03.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe3] 写入 %s/probe03.txt" % OUT_ABS)
