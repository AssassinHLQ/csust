extends Node
## 给「当前相机」挂上 GDGS 的 Compositor —— **只有 Compute 后端需要这一步**。
##
## ── 为什么必须有 ──
## Compute 后端不在 Godot 的标准网格管线里画泼溅：它自己渲染到离屏缓冲，再由
## `GaussianCompositorEffect`（一个 `CompositorEffect`）合成回场景缓冲。
## 而 `Compositor` 在 Godot 4 里**只能挂在 `Camera3D` 上** —— 没有它就什么都看不到。
## Raster 后端走标准网格管线，不需要。
##
## ── 为什么做成 autoload，而不是写在 player.gd 里 ──
## 自检与探针会**自己 new 一台相机**再 `make_current()`（例如 `_verify_room.gd`），
## 那台相机上没有 Compositor，于是一张泼溅都渲不出来 —— 而且失败得很安静。
## 盯着根视口的「当前相机」逐帧比对，玩家相机和自检相机就都被覆盖了。
##
## ── 代价 ──
## 每帧几次属性读 + 相机换代时建一个 `Compositor` 资源；`_attached` 按实例 id 缓存，
## 同一台相机不会反复重建。`_backend_needs_compositor()` 为假时 `_process` 直接关掉。

## 与 gaussian_backend_selector.gd 的 SETTING_KEY 一致。
const BACKEND_SETTING := "gdgs/rendering/backend"
const COMPOSITOR_SCRIPT := "res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd"

var _script: GDScript = null
var _script_checked := false
## 已挂过的相机：实例 id -> Compositor（避免每帧重建资源）
var _attached := {}
## 「被别的系统摘走」只警告一次，别每帧刷屏
var _stolen_warned := false
## `_process` 首次执行日志（只打一次）
var _tick_logged := false


func _enter_tree() -> void:
	# 2026-10-28：校园放大 3 倍后实测两种后端（1600×900、RTX 4060 Laptop）
	#   Compute 3.2 fps（广场边朝校园）/ 3.5 fps（校园地面）
	#   Raster  50.1 fps / 41.2 fps
	# Compute 的排序缓冲随「单个高斯覆盖的 tile 数」膨胀，3 倍缩放后每点覆盖
	# 9 倍面积，直接压垮。这里在**任何 GaussianSplatNode 注册之前**把后端定成
	# Raster —— 用代码改运行时设置，不动用户的 project.godot（里面写的是 Compute）。
	# 2026-10-28 用户选择：保持 3×，用 Compute（排序正确、转视角不跳；代价是 fps 低）。
	#   -- --gdgs-backend=raster    临时跑 Raster（快，但分组排序会跳）
	#   -- --gdgs-backend=auto      用 project.godot 里的值（也是 Compute）
	var want := "Compute"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gdgs-backend="):
			want = a.substr(15).strip_edges().capitalize()
	if want != "Auto":
		ProjectSettings.set_setting(BACKEND_SETTING, want)
	print("[SplatCompositor] 泼溅后端 = %s" % want)


func _ready() -> void:
	var needed := _backend_needs_compositor()
	set_process(needed)
	if not needed:
		print("[SplatCompositor] 后端不需要 Compositor（Raster，或没有 RenderingDevice），本节点不干活")
		return
	print("[SplatCompositor] Compute 后端：将为当前相机自动挂 GaussianCompositorEffect")


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var key := cam.get_instance_id()
	# 2026-11-10：确认 `_process` 真的在跑（曾经出现过「`_ready` 打了日志、但
	# `_process` 一次都没执行」的情况，结果相机上始终没有 Compositor）。
	if not _tick_logged:
		_tick_logged = true
		print("[SplatCompositor] _process 第 1 次跑到：相机「%s」compositor=%s"
			% [cam.name, "有" if cam.compositor != null else "无"])
	# ⚠️ 2026-11-10：`campus_ggs.gd` 会**每帧**把 `cam.compositor` 设成 null
	#    （它 line 625，理由是「校园走全屏 quad，Compositor 会把光栅器拖到个位数帧率」）。
	#    两套系统抢同一台相机的 `compositor`：谁后跑谁赢，表现为校园里偶发整屏异常，
	#    而且**一旦坏掉就一直坏到重开游戏**（用户报「在校园里一直白，重开才好」）。
	#    这里只记录、不硬抢：抢回去会让 campus_ggs 的全屏 quad 方案失效（fps 崩）。
	if _attached.has(key):
		if cam.compositor == _attached[key]:
			return
		if not _stolen_warned:
			_stolen_warned = true
			print("[SplatCompositor] ⚠️ 相机「%s」的 Compositor 被别的系统摘掉/换掉了"
				% cam.name + "（大概率是 campus_ggs 走全屏 quad）—— 本次会话不再自动重挂")
		return
	_attach(cam, key)


## 判据必须和 `gaussian_backend_selector.gd::_compute_preferred()` 保持一致，
## 否则会出现「选中的是 Raster、却挂了一个没人用的 Compositor」或者反过来。
func _backend_needs_compositor() -> bool:
	var setting := str(ProjectSettings.get_setting(BACKEND_SETTING, "Auto"))
	if setting == "Raster":
		return false
	if RenderingServer.get_rendering_device() == null:
		return false
	if setting == "Compute":
		return true
	# "Auto"：Forward+ 且拿得到 RenderingDevice 时插件会解析成 Compute
	return str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus")) == "forward_plus"


func _attach(cam: Camera3D, key: int) -> void:
	if not _script_checked:
		_script_checked = true
		var s: Variant = load(COMPOSITOR_SCRIPT)
		if s is GDScript and (s as GDScript).can_instantiate():
			_script = s
		else:
			push_warning("[SplatCompositor] 加载不了 %s；Compute 后端不会渲染任何泼溅"
				% COMPOSITOR_SCRIPT)
	if _script == null:
		set_process(false)
		return
	var effect: Variant = _script.new()
	if effect == null:
		push_warning("[SplatCompositor] effect 实例化失败（%s）" % COMPOSITOR_SCRIPT)
		set_process(false)
		return
	if not (effect is CompositorEffect):
		push_warning("[SplatCompositor] effect 不是 CompositorEffect（实际 %s）"
			% str(typeof(effect)))
		set_process(false)
		return
	var effects: Array[CompositorEffect] = [effect as CompositorEffect]
	var comp := Compositor.new()
	comp.compositor_effects = effects
	cam.compositor = comp
	_attached[key] = comp
	# 2026-11-10：**挂完立刻回读**。曾经出现过「打印说挂上了、但 `cam.compositor`
	# 仍是 null」的情况（相机换代 / 属性被别的系统重置），而这条路径失败得非常安静：
	# Compute 后端下没有 Compositor 就一张泼溅都渲不出来。这里当场核对一次。
	var back: Compositor = cam.compositor
	if back == null:
		push_warning("[SplatCompositor] ⚠️ 给相机「%s」赋值 Compositor 后回读为 null！" % cam.name)
	elif back != comp:
		push_warning("[SplatCompositor] ⚠️ 相机的 Compositor 被别人换掉了（不是刚建的这台）")
	print("[SplatCompositor] 已为相机「%s」挂上 Compositor + GaussianCompositorEffect（累计 %d 台，回读 %s）"
		% [cam.name, _attached.size(), "OK" if back == comp else "失败"])
