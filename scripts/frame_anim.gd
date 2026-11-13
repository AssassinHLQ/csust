class_name FrameAnim
extends RefCounted
## 逐帧动画（PNG 序列）播放器 + **环形缓冲**，阿洛娜 / 普拉娜共用。
##
## ── 为什么要环形缓冲 ──
## 素材是绿幕视频抠出来的序列帧：
##   阿洛娜 389 帧 300×488、普拉娜 443 帧 360×393。
## 全量载入的话显存 ≈ 389×300×488×4 + 443×360×393×4 ≈ **480 MB** ——
## 这项目本来就吃显存（高斯泼溅好几个 G），不能这么干。
## 所以只保留 `CACHE_MAX` 帧，需要哪帧才读哪帧。
##
## ⚠️ 必须用 `ResourceLoader.CACHE_MODE_IGNORE`：否则 `load()` 的结果会被
##    ResourceLoader 自己缓存住、永不释放，等于又变成全量载入。
##
## ── 用法 ──
##     var anim := FrameAnim.new()
##     anim.load_dir("res://assets/arona_frames", 12.0)
##     # 每帧：anim.advance(delta)
##     draw_texture_rect(anim.texture(), rect, false)

## 环形缓冲保留多少帧。48 帧 ≈ 300×488×4×48 ≈ 28 MB，够覆盖约 4 秒
const CACHE_MAX := 48

var fps := 12.0
var frames: Array[String] = []
var index := -1

var _cache := {}
var _order: Array = []
var _t := 0.0


## 列出目录里的 `*.png`（补零命名，字典序 = 帧序）。返回帧数。
func load_dir(dir: String, fps_hint := 12.0) -> int:
	fps = maxf(fps_hint, 1.0)
	frames.clear()
	index = -1
	_t = 0.0
	_cache.clear()
	_order.clear()
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("[FrameAnim] 缺帧目录 %s" % dir)
		return 0
	for f in d.get_files():
		# ⚠️ 导入后目录里会多出 `.png.import`，只认 .png
		if f.ends_with(".png"):
			frames.append(dir.path_join(f))
	frames.sort()
	return frames.size()


func is_ready() -> bool:
	return not frames.is_empty()


func count() -> int:
	return frames.size()


func duration() -> float:
	return float(frames.size()) / fps


## 推进时间；返回帧号是否变了
func advance(delta: float) -> bool:
	if frames.is_empty():
		return false
	_t += delta
	var idx := int(_t * fps) % frames.size()
	if idx == index:
		return false
	index = idx
	# 顺手把后面 3 帧读进来，避免卡顿
	for k in 4:
		_frame_tex((idx + k) % frames.size())
	return true


func texture() -> Texture2D:
	if frames.is_empty() or index < 0:
		return null
	return _frame_tex(index)


## 取某帧；不在缓存就现读，超出 CACHE_MAX 淘汰最旧的
func _frame_tex(i: int) -> Texture2D:
	if _cache.has(i):
		return _cache[i]
	if i < 0 or i >= frames.size():
		return null
	var tex := ResourceLoader.load(frames[i], "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if tex == null:
		return null
	_cache[i] = tex
	_order.append(i)
	while _order.size() > CACHE_MAX:
		var old: int = _order.pop_front()
		if old != i:
			_cache.erase(old)
	return tex


func clear() -> void:
	_cache.clear()
	_order.clear()
	index = -1
	_t = 0.0
