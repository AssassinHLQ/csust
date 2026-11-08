extends Node3D
## 电竞房的室内照明（2026-11-08）
##
## 用户：「给电竞房一点灯吧，里面好黑」。
##
## 为什么屋里那么黑：
##   · GLB 里**一个灯光节点都没有**（101 个 node，0 个 Light）——
##     Sketchfab 那个 GLB 只导了网格和自发光材质；
##   · 场景里也没有任何 OmniLight / SpotLight；
##   · 全局只有一盏 `Sun`（DirectionalLight3D）+ 环境光，
##     而这屋子是**封闭外壳**，太阳光根本照不进来。
##
## ── 布局实测（`scripts/_probe_esports_layout.gd` 量出来的，别再猜）──
##   外壳 `M_材质_3`：x −5.20~+5.20、y 0.30~3.60、z −8.42~+8.42
##   室内地面 y = 0.00（外壳下沿 0.30 是墙脚裙边）
##   室内净高 3.30 m
##   工位（显示器）x 0.46~1.03、y 2.16~3.00、z ≈ −2.5~−3.0
##   左侧储物架 x −4.4~−2.4
##   **门口在 +Z**（本地 z = +8.42 那侧），人从 +Z 进来
##
## 第一版按「门口在 -Z」猜，结果灯全装到墙外面了（墙上两个亮斑 = 灯穿墙照的），
## 而且能量给太大，天花板直接照爆。本版按实测坐标重排 + 能量砍到 1/3。

## 房间内沿（留 0.6 m 贴墙，别把灯塞进墙里）
const ROOM_HALF_X := 4.60
const ROOM_HALF_Z := 7.80
## 天花板净高
const CEIL_Y := 3.30
## 灯装在离天花板 0.45 m 处（第二版给 3.05 → 只差 0.25，天花板直接过曝）
const LIGHT_Y := 2.85

## 补光色（暖，和电竞房氛围搭）
const FILL_COLOR := Color(1.0, 0.93, 0.84)
## 灯带色（偏冷白，和 GLB 里自发光灯带同色）
const STRIP_COLOR := Color(0.74, 0.87, 1.0)
## 单盏能量。
## ⚠️ 调参记录（2026-11-08）：
##    第一版 3.2 → 天花板过曝成一片白，墙面出现灯穿墙的亮斑；
##    第二版 0.9 → 天花板还是亮，但地面偏暗；
##    这一版 **0.55** + 天花板柔光 0.35：靠 GLB 里自发光灯带当主光源，
##    实体灯只负责「让家具能看清轮廓」，亮度压到刚好不抢戏。
const FILL_ENERGY := 0.55
## 天花板柔光能量
const CEIL_ENERGY := 0.35

## 补光位置（**房间本地坐标**）
##
## 布局实测（`_probe_esports_furniture.gd`）：工位那批家具顶点在 **y 1.5~3.0**
## （显示器/桌面），也就是它们本身就在**中高处**（这酒店是阁楼式布局）。
## 所以灯不用压到多低 —— 装在 **y 2.85**（天花板下 0.45）正好在家具上方，
## 照得到桌面。
##
## ⚠️ 调参记录（2026-11-08）：
##   第一版能量 3.2 + 灯位 3.05 → 天花板过曝、墙面出现灯穿墙的亮斑；
##   第二版 0.9 → 地板亮、天花板还是白；
##   这一版 **0.55**，位置也挪到 x = ±2.4（贴两侧墙，避免正上方直射天花板）。
const FILL_SPOTS := [
	Vector3(-2.4, LIGHT_Y, 5.6),
	Vector3(2.4, LIGHT_Y, 1.4),
	Vector3(-2.4, LIGHT_Y, -2.8),
	Vector3(2.4, LIGHT_Y, 4.2),
	Vector3(-2.4, LIGHT_Y, -0.7),
]


func _ready() -> void:
	# 等一帧，确保 GLB 实例和它的子节点都挂好了（房间可能被整体拖动过）
	await get_tree().process_frame
	_build_lights()


func _build_lights() -> void:
	# 已经有灯就不重复建（`_ready` 可能被多次触发）
	if get_node_or_null("IndoorLights") != null:
		return

	var root := Node3D.new()
	root.name = "IndoorLights"
	add_child(root)

	# ① 工位排的补光：让椅子、桌面、显示器有明暗层次
	for i in FILL_SPOTS.size():
		var l := OmniLight3D.new()
		l.name = "Fill%d" % i
		l.position = FILL_SPOTS[i]
		l.light_color = FILL_COLOR
		l.light_energy = FILL_ENERGY
		l.omni_range = 6.5
		# ⚠️ 不投影：一屋子 7 盏投影灯在 Forward+ 里太贵，
		#    氛围靠自发光灯带 + 环境光就够了。
		l.shadow_enabled = false
		root.add_child(l)

	# ② 天花板柔光：模拟「灯带把整间屋子照亮」，
	#    比逐盏点光均匀，也不会有明显的亮斑。
	var strip := OmniLight3D.new()
	strip.name = "CeilingFill"
	strip.position = Vector3(0.0, CEIL_Y - 0.15, 0.0)
	strip.light_color = STRIP_COLOR
	strip.light_energy = CEIL_ENERGY
	strip.omni_range = 11.0
	strip.shadow_enabled = false
	root.add_child(strip)

	# ③ 门口那盏：从门外看进去不会是一团黑
	var door := OmniLight3D.new()
	door.name = "DoorFill"
	door.position = Vector3(0.0, 2.4, ROOM_HALF_Z - 1.2)
	door.light_color = FILL_COLOR
	door.light_energy = 0.45
	door.omni_range = 5.0
	door.shadow_enabled = false
	root.add_child(door)

	print("[EsportsLight] 室内灯 %d 盏（补光 %d + 天花板柔光 + 门口）"
		% [FILL_SPOTS.size() + 2, FILL_SPOTS.size()])
