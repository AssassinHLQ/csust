class_name RenderEnv
extends RefCounted
## 画面旋钮 → 实际渲染参数的**唯一落地处**。
##
## ⚠️ 为什么要有这个文件（2026-11-06）：
##    用户：「next_level.gd（校园场景）完全不碰任何画面设置 是为什么,需要同步画面设置」。
##    确实是漏了 —— `game.gd::_apply_render()` 一直是**只有主场景**在执行，而
##    `next_level.gd` 里连一个「画面」关键词都没有。后果是：设置界面（两个场景都有
##    `SettingsMenu`）里拖「3D 渲染缩放 / 帧率上限 / 垂直同步 / 抗锯齿 / 阴影质量 /
##    SSAO / 辉光 / SSR / 雾 / 渲染距离 / 窗口模式」，**进了校园场景全部失效**，
##    而界面照旧把数字改掉、照旧落盘 —— 属于「看起来生效了，其实没生效」。
##
##    那些逻辑当时埋在 `game.gd` 里，因为它顺手要摸主场景的 `_auto_scale` /
##    `RenderDistance` / 灯光原始状态。为了让校园场景也能用，把**叶子逻辑**整体
##    搬到这里的静态函数里，两个场景各自只留一层薄壳：
##
##      `game.gd`      : `_apply_render()` → `RenderEnv.apply(self, _auto_scale)` + 打日志
##      `next_level.gd`: `_apply_render()` → `RenderEnv.apply(self, _auto_scale)` + 打日志
##
##    薄壳各写一遍、真正的东西只有一份 —— 这样以后再加旋钮不会又只加给一个场景。
##
## ⚠️ 校园场景**没有** `RenderDistance` 节点（主场景有），所以第 ⑦ 步对它是
##    「只改摄像机远裁剪面」；`get_node_or_null()` 一旦拿不到就跳过，不会报错。
##
## ⚠️ 校园场景的远处全靠 `far` 兜着：实测 97 个块的中心范围 x −83~116、z −236~−85，
##    校园半径约 150~180 m，默认渲染距离 300 m 覆盖得住（`player.tscn` 原本写死
##    `far = 500.0`）。**但把滑块拖到 100 m 就真的会切掉远处的楼** —— 这是这个旋钮
##    本该有的语义，不是 bug。

## 设计分辨率（`project.godot` 的 `window/size/viewport_width/height`）。
const DESIGN_VIEWPORT := Vector2(1600, 900)

## 视口面积 / 设计面积 低于这个比值（即窗口大于约 6 倍设计分辨率）才降分辨率。
## 1600×900 × 6 ≈ 2938×1653。2560×1334 的比值是 0.42，远在阈值之上。
## 详见 `_probe_gameplay_input.gd` 与 game.gd 里那段事故记录（位移被稀释）。
const RENDER_SCALE_AREA_RATIO_MIN := 0.16

## 窗口极大时算出来的自动上限（只看窗口尺寸，默认 1.0）。
## 真正的缩放 = 这个 × 设置里的「3D 渲染缩放」，在 `apply()` 第 ① 步相乘。
static var _auto_scale := 1.0

## 每盏灯**场景原本**的 `shadow_enabled`。
## 只恢复/关闭场景原本的投影状态，不强行把「本来不投影」的灯打开
## （路线上的地标灯本来就是关阴影省电）。
## ⚠️ 键是 `get_instance_id()`，换场景后 id 会被回收复用，所以 `apply()` 一旦
##    发现根节点变了就整张表清空，免得把上一关的「作者意图」套到新场景的灯上。
static var _shadow_authored := {}
static var _active_root_id := 0

## 窗口模式的重入闸 + 上一次生效的模式（递归 bug 的修法，见 `apply_window_mode()`）。
static var _last_window_mode := ""
static var _applying_window := false


## 视口尺寸 → 自动分辨率上限。**纯函数**：不改任何状态，`_auto_scale` 由调用方存。
##
## ⚠️ 必须用 `vp.size`（= `Window.size`，就是**渲染目标**的像素数），
##    **不能**用 `vp.get_visible_rect().size` —— 在 `canvas_items` 拉伸模式下
##    后者返回的是**画布矩形**（= 设计分辨率 1600×900），跟真实渲染尺寸无关。
static func auto_scale_for(vp_size: Vector2) -> float:
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return 1.0
	var ratio := (DESIGN_VIEWPORT.x * DESIGN_VIEWPORT.y) / (vp_size.x * vp_size.y)
	if ratio < RENDER_SCALE_AREA_RATIO_MIN:
		return clampf(sqrt(ratio), 0.5, 1.0)
	return 1.0


## 把**所有**画面旋钮落到当前场景。`auto_scale` 传调用方存的那个自动上限。
##
## 返回实际生效的那几个数，调用方拿去打日志（免得到处重算一遍又算出不一样的数）。
## 键：`scale`（最终 3D 缩放）/ `auto`（窗口给的自动上限）/ `fps`（0 = 不限）/
##     `rd`（渲染距离，米）/ `lod`（LOD 阈值，px）。
static func apply(node: Node, auto_scale: float) -> Dictionary:
	var vp: Viewport = node.get_viewport()
	if vp == null:
		return {}
	# 换场景了：上一关的灯光原始状态不能带过来（instance_id 会被复用）
	var root_id := node.get_instance_id()
	if _active_root_id != root_id:
		_shadow_authored.clear()
		_active_root_id = root_id

	# ① 3D 渲染缩放：只**乘**自动上限（窗口极大时它小于 1），不放大过 1.0
	var res := float(GameSettings.value("resolution_scale"))
	var target := clampf(auto_scale * res, 0.25, 1.0)
	if not is_equal_approx(vp.scaling_3d_scale, target):
		vp.scaling_3d_scale = target

	# ② 帧率上限 / 垂直同步（两个独立旋钮）
	var fps := fps_limit()
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(GameSettings.value("vsync"))
		else DisplayServer.VSYNC_DISABLED)

	# ③ 抗锯齿（互斥：TAA 打开时 MSAA / FXAA 必须全关）
	apply_aa(vp)

	# ④ 阴影
	apply_shadows(node)

	# ⑤ 后处理 + 雾
	var we := node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.ssao_enabled = bool(GameSettings.value("ssao"))
		env.glow_enabled = bool(GameSettings.value("glow"))
		env.ssr_enabled = bool(GameSettings.value("ssr"))
		env.fog_enabled = bool(GameSettings.value("fog"))

	# ⑥ 窗口模式
	apply_window_mode()

	# ⑦ 渲染距离：摄像机**远裁剪面**直接等于它（天空盒是无限远，不受影响）。
	#    两道保险：远裁剪面负责「超出距离的别画」，`RenderDistance` 负责「别进视锥、
	#    也别投阴影」—— 只靠 `far` 的话，被裁掉的物体**阴影会消失但物体自己还在
	#    剔除列表里**，而且 `far` 对阴影相机不生效。
	var rd := GameSettings.render_distance()
	for n in node.find_children("*", "Camera3D", true, false):
		(n as Camera3D).far = maxf(rd, 1.0)
	var rd_node := node.get_node_or_null("RenderDistance")
	if rd_node != null and rd_node.has_method("refresh"):
		rd_node.call("refresh")

	# ⑧ 全局 LOD 阈值（`Viewport.mesh_lod_threshold`，单位：像素）。
	#    物体在屏幕上的投影高度小于这个值 → 切到下一级 LOD。
	#    ↑ 调大 = 更早切低模 = 省性能 / 远处更糊；↓ 调小 = 更晚切 = 画质好 / 更耗。
	#    ⚠️ 只对 `meshes/generate_lods=true` 的模型有效。
	var lod := GameSettings.apply_lod_threshold()

	return {"scale": target, "auto": auto_scale, "fps": fps, "rd": rd, "lod": lod}


## `fps_limit` 现在是**滑块数值**：0（最左）= 不限帧，其余当上限。
static func fps_limit() -> int:
	return maxi(int(round(float(GameSettings.value("fps_limit")))), 0)


## 抗锯齿：滑块 6 档 —— 0 关 / 1 FXAA / 2 MSAA2× / 3 MSAA4× / 4 MSAA8× / 5 TAA。
## ⚠️ 三者互斥：TAA 打开时必须把 MSAA 和屏幕空间 AA 都关掉，否则后处理链打架。
static func apply_aa(vp: Viewport) -> void:
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	match clampi(int(round(float(GameSettings.value("aa_mode")))), 0, 5):
		1:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		2:
			vp.msaa_3d = Viewport.MSAA_2X
		3:
			vp.msaa_3d = Viewport.MSAA_4X
		4:
			vp.msaa_3d = Viewport.MSAA_8X
		5:
			vp.use_taa = true


## 阴影质量（滑块 0~3）：关 / 低 / 中 / 高。
##
## ⚠️ 2026-10-21 用户：「阴影怎么感觉高质量比低质量还难看一点点」——
##    原来三档只改 `directional_shadow_max_distance`（低 40 / 中 60 / 高 120），
##    而阴影图是固定 4096²：**铺得越远，每个 texel 摊到的地面越大**
##    （120 m ≈ 29 mm/texel，40 m ≈ 10 mm）。所以「高」反倒是最糊、锯齿最明显的那档，
##    方向完全搞反了。现在换成「距离收近 + 角直径变大 + 模糊加大」三件套：
##      低：60 m、硬边（angular 0）、blur 0.6 —— 便宜、边利，但会抖
##      中：50 m、0.5°、blur 1.1
##      高：40 m、1.0°、blur 1.4 + 4 段混合 —— PCSS 软阴影，边是半影不是锯齿
##    ⚠️ 高挡的角直径**别按 1.6° 给**：实测会在墙面上刷出一层颗粒
##    （Godot 的 PCSS 采样次数是固定的，半影一宽就噪）。1.0° + blur 1.4 是甜点。
##    另外把 `shadow_normal_bias` 从默认 2.0 压到 0.9：默认值会把影子推离物体
##    （peter-panning，脚下一圈没有影子），那才是「看着不自然」的主因。
static func apply_shadows(node: Node) -> void:
	var off := false
	var dist := 40.0
	var angular := 1.0
	var blur := 1.4
	var normal_bias := 0.9
	var bias := 0.03
	match clampi(int(round(float(GameSettings.value("shadow_quality")))), 0, 3):
		0:
			off = true
		1:
			dist = 60.0
			angular = 0.0
			blur = 0.6
			normal_bias = 1.4
			bias = 0.02
		2:
			dist = 50.0
			angular = 0.5
			blur = 1.1
			normal_bias = 1.0
			bias = 0.025
	for n in node.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		var id := l.get_instance_id()
		if not _shadow_authored.has(id):
			_shadow_authored[id] = l.shadow_enabled
		l.shadow_enabled = false if off else bool(_shadow_authored[id])
		if l is DirectionalLight3D and not off:
			var d := l as DirectionalLight3D
			d.directional_shadow_max_distance = dist
			d.light_angular_distance = angular
			d.shadow_blur = blur
			d.shadow_normal_bias = normal_bias
			d.shadow_bias = bias
			d.directional_shadow_blend_splits = true


## 窗口模式。**headless 下直接跳过**（`--headless` 没有真窗口，调了只会刷警告）。
##
## 2026-10-20 晚：
##   · **删掉「独占全屏」**（用户：「独占全屏怎么变成这样子了，去掉这个选项」）——
##     切进 `WINDOW_MODE_EXCLUSIVE_FULLSCREEN` 之后窗口会留在全屏坐标系里，
##     再选「窗口」只得到**黑边包围的一小块画面**（用户截图就是这个）；
##   · 全屏只留 `WINDOW_MODE_FULLSCREEN`（无边框全屏），切回窗口时**显式重设尺寸 +
##     居中**，否则从全屏回来也常常卡在「一小块」。
##
## ⚠️⚠️ 2026-10-20 深夜修的两个真 bug（用户：「窗口模式看不完整界面，设置都点不到；
##     全屏下面一条黑，全屏也点东西点不到，鼠标感觉是歪了一点」）：
##   1. **`window_set_mode()` 会**同步**发 `size_changed` → `_fit_render_scale()` →
##      `_apply_render()` → 又回到这里。那一刻 `window_get_mode()` 还没变成新值，
##      于是**再次** `window_set_mode()`……无限递归，实测刷了 5000+ 条错误、
##      窗口在两种模式之间疯狂重建 —— 画面/视口/鼠标就全歪了。
##      修法：`_applying_window` 重入闸 + `_fit_render_scale()` 改成 `call_deferred`。
##   2. 切窗口模式时 `window_get_current_screen()` 在重建瞬间可能返回**非法值**
##      （屏幕上只剩 0 个 screen），`screen_get_usable_rect()` 于是给一个**空矩形**；
##      旧代码拿空矩形算居中 = `(0,0) - size/2` = **负坐标**，窗口被摆到屏幕左上角外面 ——
##      看到的正好是「界面不完整 + 点不到 + 鼠标歪」。
##      修法：屏幕数 ≤ 0 或可用区太小时**什么都不做**（宁可保持原样，也不摆到屏幕外）。
static func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless" or _applying_window:
		return
	var mode := String(GameSettings.value("window_mode"))
	var want := DisplayServer.WINDOW_MODE_MAXIMIZED
	match mode:
		"windowed":
			want = DisplayServer.WINDOW_MODE_WINDOWED
		"fullscreen":
			want = DisplayServer.WINDOW_MODE_FULLSCREEN
		_:
			want = DisplayServer.WINDOW_MODE_MAXIMIZED
	var changed := _last_window_mode != mode
	_last_window_mode = mode
	if DisplayServer.window_get_mode() != want:
		_applying_window = true
		DisplayServer.window_set_mode(want)
		_applying_window = false
	# 窗口模式永远给一个「放得下」的矩形：启动时（`_last_window_mode` 还是空）
	# 和每次真正切到窗口模式时校正一次。**不要每次改画质都居中** ——
	# 用户把窗口拖到别处以后，调个抗锯齿不该把它弹回屏幕中央。
	if want == DisplayServer.WINDOW_MODE_WINDOWED and changed:
		_restore_window_rect()


## 把窗口摆成「可用区里居中的 1600×900（放不下就缩）」。
## ⚠️ 拿不到屏幕信息时**直接返回** —— 宁可窗口保持原样，也不能用空矩形算出一个
##    负坐标的窗口位置。
static func _restore_window_rect() -> void:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return
	var scr := clampi(DisplayServer.window_get_current_screen(), 0, count - 1)
	var usable := DisplayServer.screen_get_usable_rect(scr)
	if usable.size.x < 640 or usable.size.y < 480:
		return
	var size := Vector2i(1600, 900)
	size.x = mini(size.x, usable.size.x - 40)
	size.y = mini(size.y, usable.size.y - 80)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
