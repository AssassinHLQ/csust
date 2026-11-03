extends Node
## 时间系统：游戏内 **1 天 = 现实 N 分钟**，驱动太阳、天空和环境曝光。
##
## 用户 2026-11-03：
##   「只做户外的，不管泼溅了」+ 选了「实时流逝：游戏里 1 天 = 现实 N 分钟」。
##
## ⚠️ **泼溅不参与**（`gaussian_raster.gdshader` 是 `unshaded` + `ambient_light_disabled`，
##    颜色是扫描时烘死的）。所以本系统只对**我们自己搭的网格**有效：平台、柴关电脑城、
##    蒙德里安楼、电竞房、开发部。画室 609 / 校园泼溅不会跟着变 —— 这是已知且接受的取舍。
##
## 设计要点：
##   · **太阳角度**由「小时」算出来：6 点东升、12 点最高、18 点西落，夜里换成月光。
##   · **天空**走 `ProceduralSkyMaterial`（工程里已经用的就是它，不用换贴图）。
##   · 场景里必须有一个叫 `Sun` 的 `DirectionalLight3D` 和一个 `WorldEnvironment`；
##     每帧检查一次，场景切换后自动重新绑定（第二关也是这套节点名）。
##   · 所有观感参数集中在下面的 `KEY_*` 帧表里，改数值就能调，不用动逻辑。

const AUTOLOAD_NAME := "TimeOfDay"

## 现实多少分钟 = 游戏内一天。设置面板以后可以改这个。
const DEFAULT_DAY_MINUTES := 20.0

## 出生时刻（小时）。8 点 = 早晨，和现在的观感最接近。
const START_HOUR := 8.0

## 关键帧：按「太阳高度角」插值。`elev` 是太阳在地平线上的角度（度，负 = 已落山）。
const KEY_ELEV := [-18.0, -6.0, 0.0, 6.0, 20.0, 90.0]
const KEY_SUN_COL := [
	Color(0.55, 0.62, 0.95),   # -18 深夜月光（偏蓝）
	Color(0.85, 0.60, 0.55),   #  -6 天将亮/将暗
	Color(1.00, 0.62, 0.38),   #   0 贴地平线（橙红）
	Color(1.00, 0.80, 0.60),   #   6 低角度
	Color(1.00, 0.96, 0.90),   #  20 正常日光
	Color(1.00, 0.98, 0.94),   #  90 正午（略偏暖，避免死白）
]
const KEY_SUN_ENERGY := [0.12, 0.35, 0.85, 1.05, 1.30, 1.35]
const KEY_SKY_TOP := [
	Color(0.03, 0.04, 0.10),
	Color(0.10, 0.10, 0.22),
	Color(0.28, 0.26, 0.38),
	Color(0.34, 0.42, 0.62),
	Color(0.22, 0.28, 0.42),
	Color(0.20, 0.26, 0.40),
]
const KEY_SKY_HOR := [
	Color(0.06, 0.07, 0.14),
	Color(0.28, 0.22, 0.30),
	Color(0.95, 0.48, 0.30),
	Color(0.95, 0.74, 0.58),
	Color(0.52, 0.56, 0.64),
	Color(0.50, 0.55, 0.64),
]
const KEY_AMBIENT := [0.22, 0.32, 0.42, 0.55, 0.72, 0.75]
const KEY_EXPOSURE := [0.95, 0.95, 0.92, 1.02, 1.00, 1.00]

## 太阳一天走过的方位角范围（度）。6 点 −90（东）、18 点 +90（西）。
const AZIMUTH_EAST := -90.0
const AZIMUTH_WEST := 90.0

var hours := START_HOUR
## 探针用的覆盖值；< 0 表示「跟随设置面板里的 `day_minutes`」。
var _override_minutes := -1.0

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _scene: Node


func _ready() -> void:
	# 时间系统要在暂停菜单打开时也继续走？—— 不。暂停就停，符合直觉。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(false)


func _process(delta: float) -> void:
	var dm := effective_day_minutes()
	# 0（或负数）= 时间不流动，太阳钉在原地
	if dm > 0.001:
		hours = fmod(hours + delta * 24.0 / (dm * 60.0), 24.0)
	_bind_if_needed()
	_apply()


## 游戏内 1 天 = 现实多少分钟。跟随设置面板的 `day_minutes`（0 = 不走）。
func effective_day_minutes() -> float:
	if _override_minutes >= 0.0:
		return _override_minutes
	return float(GameSettings.value("day_minutes"))


## 场景切换 / 节点被换掉之后重新找 `Sun` 和 `WorldEnvironment`。
func _bind_if_needed() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cur := tree.current_scene
	if cur == null:
		# `--script` 跑的探针里 `current_scene` 是空的（场景是手动 add_child 进去的），
		# 这时退回整棵树找 —— 否则探针里本系统会静默什么都不做，
		# 出图看起来像「参数没生效」（2026-11-03 踩过）。
		cur = tree.root
	if cur == null:
		return

	if cur != _scene:
		_scene = cur
		_sun = null
		_env = null
		_sky = null

	if is_instance_valid(_sun) and is_instance_valid(_env):
		return

	_sun = cur.find_child("Sun", true, false) as DirectionalLight3D
	var we := cur.find_child("WorldEnvironment", true, false) as WorldEnvironment
	_env = we.environment if we != null else null
	_sky = null
	if _env != null and _env.sky != null:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial


## 太阳在地平线上的角度（度）。6 点 0°、12 点 65°、18 点 0°、夜里为负。
static func elevation_for(h: float) -> float:
	var t := (h - 6.0) / 12.0            # 6 点 → 0，18 点 → 1
	var e := sin(clampf(t, 0.0, 1.0) * PI) * 65.0
	if t < 0.0 or t > 1.0:
		# 夜里：让角度继续往下走，最多 −20°，用来取月光的关键帧。
		# 18 点之后 / 6 点之前各走一段线性斜坡，2 小时到底。
		var night := fposmod(h - 18.0, 24.0) if t > 1.0 else fposmod(6.0 - h, 24.0)
		e = -minf(20.0, night * 12.0)
	return e


func _apply() -> void:
	if not is_instance_valid(_sun):
		return
	var elev := elevation_for(hours)
	var t := (hours - 6.0) / 12.0
	var azimuth := lerpf(AZIMUTH_EAST, AZIMUTH_WEST, clampf(t, -0.35, 1.35))
	# DirectionalLight3D 沿自身 −Z 照射；X 抬到负数是让光朝下
	_sun.rotation_degrees = Vector3(-elev, azimuth, 0.0)
	_sun.light_color = _sample_color(KEY_SUN_COL, elev)
	_sun.light_energy = _sample(KEY_SUN_ENERGY, elev)

	if _env != null:
		_env.ambient_light_energy = _sample(KEY_AMBIENT, elev)
		_env.tonemap_exposure = _sample(KEY_EXPOSURE, elev)
	if _sky != null:
		_sky.sky_top_color = _sample_color(KEY_SKY_TOP, elev)
		_sky.sky_horizon_color = _sample_color(KEY_SKY_HOR, elev)


func _sample(keys: Array, elev: float) -> float:
	var i := _seg(elev)
	var a: float = keys[i]
	var b: float = keys[i + 1]
	var w := _w(elev, i)
	return lerpf(a, b, w)


func _sample_color(keys: Array, elev: float) -> Color:
	var i := _seg(elev)
	var a: Color = keys[i]
	var b: Color = keys[i + 1]
	return a.lerp(b, _w(elev, i))


func _seg(elev: float) -> int:
	for i in range(KEY_ELEV.size() - 1):
		if elev <= KEY_ELEV[i + 1]:
			return i
	return KEY_ELEV.size() - 2


func _w(elev: float, i: int) -> float:
	var lo: float = KEY_ELEV[i]
	var hi: float = KEY_ELEV[i + 1]
	if hi - lo < 0.0001:
		return 0.0
	return clampf((elev - lo) / (hi - lo), 0.0, 1.0)


# ── 给设置面板 / 自检用的接口 ──

## 直接跳到某个时刻（0~24）。
func set_hours(h: float) -> void:
	hours = fposmod(h, 24.0)
	_bind_if_needed()
	_apply()


func set_day_minutes(m: float) -> void:
	_override_minutes = maxf(0.0, m)
