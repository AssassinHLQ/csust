# 校园扫描碰撞

`scenes/next_level.tscn` 的 `CampusCollision` 使用
`scenes/campus_splattransform.tscn`：31 个原生扫描分块、扫描边界防跌落面、
一座可见连接桥，共 33 个静态碰撞体，2,522,246 三角。
旧网格和 GDGS 资源保留供历史对照，生产场景不加载它们。
`CampusFloor/Collision` 已禁用；该节点仅保留终局封锁需要的 footprint。

## 坐标和几何

- 源 PLY 经 `splatdata/campus_sog/frame.json` 转成世界坐标，只变换一次。
  位置、旋转、尺度一起转换；CLI 的 `--rotate 0,0,180` 抵消隐式 PLY 翻转。
  所有导入节点都使用单位变换，不能再乘 `Campus.global_transform`。
- 与 `campus_ggs.bin` 对照 20,016 个样本，位置最大分量误差
  0.0000641137 m，协方差最大分量误差 0.0000117642。
  这是坐标转换一致性检查，不是碰撞表面精度。
- SplatTransform 体素 0.25 m、opacity 0.3、smooth；核心块 96 m，
  提取时每侧带 8 m halo，再裁回核心及校园 footprint。
- Taubin 平滑 16 次，顶点位移最多 0.25 m；先裁边，再用 LockBorder 简化，
  近似误差参数 0.125 m，避免简化阶段撕开分块边缘。
- 行走面先采样原生碰撞（0.5 m 网格，射线 Y=8 到 -20），
  7 格中值滤波、Gaussian sigma=2。只使用原扫描有支撑的格子，缺失列保持空缺；
  这保留了原始高低地形和世界坐标，不用大平板填洞。
- 结构面用 0.2 m 等高线采样识别连续墙和树干，近地 0.5 m 结构格生成封实底座，
  把薄壳内部的可进入空腔封掉；低矮、断开的扫描噪声不成为隐形墙，原生结构上部仍保留。
  网格简化误差参数为 0.05 m；这是游戏碰撞近似，不是扫描表面毫米精度保证。
  相对原始首射线高度，修正量 p50=0.536 m、p90=2.480 m、最大 18.657 m；
  原始采样混有坑洞、薄壳及高层表面，因此不宣称每个采样高度都原样保留。
- 扫描缺失列不补平板。沿实际支撑轮廓加竖直防跌落面，高度只覆盖对应地面
  下方 0.5 m 到上方 1.1 m，避免上层边缘贯穿下层道路及空中。桥走廊向上完全
  敞开，桥下仍保留局部防护。边界是物理阻挡，未添加可见围栏模型。
- 连接桥宽 2.6 m，路径约 143.6 m，起点 `(10,-0.02,-62)`，经旧桥上的直段和避障坡道
  接到 `(-62,约5,-152)` 的实测地面。桥有可见桥面和栏杆；旧桥直行死路已封口。
- 第二关 Player 的 `safe_margin=0.004`。`step_climb.gd` 按意图方向投影
  判断是否受阻，避免被扫描斜面侧推时漏掉台阶探测。
- 三只霸王龙移到实测地面；追逐遇缺地或单次高差超过 1 m 时停止前进，
  预警圈跟随局部地面，缺地时缩短攻击伸出距离。

## 重建

工具环境：Godot 4.7.1；Python numpy 2.4.6、scipy 1.18.1、trimesh 4.12.2；
Node `@playcanvas/splat-transform@3.11.2`、`meshoptimizer@1.3.0`。
源数据和中间文件均在忽略目录，仓库只保留最终碰撞资源、工具与固定回归坐标。

以下在项目根目录执行。`$gd` 应设为 Godot console 可执行文件绝对路径。
每次使用新的 staging 目录，导入工具拒绝覆盖已有资源。
独立任务均用 headless，不启动编辑器，也不捕获鼠标。

```powershell
$stage = '_tools/_tmp/campus_rebuild'
$runtime = "$stage/runtime"
$env:APPDATA = 'C:/Users/WY157/Desktop/GODOT/_godot_editor_data/Roaming'
$env:LOCALAPPDATA = 'C:/Users/WY157/Desktop/GODOT/_godot_editor_data/Local'
npm install --prefix $runtime --no-audit --no-fund @playcanvas/splat-transform@3.11.2 meshoptimizer@1.3.0
python tools/campus_splattransform_collision.py prepare --out "$stage/world.ply" --bounds -287.8 -10 -558.4 287.8 60 -75
python tools/campus_splattransform_collision.py split --input "$stage/world.ply" --out "$stage/input" --halo 8
python tools/campus_splattransform_collision.py bake --input "$stage/input" --out "$stage/native" --runtime $runtime --voxel .25 --opacity .3 --error .125
python tools/campus_splattransform_collision.py finish --source "$stage/native" --out "$stage/locked" --runtime $runtime --iterations 16 --relaxation .25 --error .125
& $gd --headless --path . --script res://scripts/_import_splattransform_collision.gd -- --no-capture "--directory=res://$stage/locked"
& $gd --headless --path . --script res://scripts/_sample_campus_collision.gd -- --no-capture "--scene=res://$stage/locked.tscn" "--out=res://$stage/ground.f32" --top=8 --bottom=-20
python tools/campus_walk_collision.py --source "$stage/locked" --heightfield "$stage/ground.f32" --out "$stage/surface" --runtime $runtime
& $gd --headless --path . --script res://scripts/_import_splattransform_collision.gd -- --no-capture "--directory=res://$stage/surface"
& $gd --headless --path . --script res://scripts/_sample_campus_collision.gd -- --no-capture "--scene=res://$stage/surface.tscn" "--out=res://$stage/top.f32"
python tools/campus_collision_access.py --top "$stage/top.f32" --support-mask "$stage/surface/terrain_support.u8" --surface "$stage/surface/terrain_height.f32" --out "$stage/access"
& $gd --headless --path . --script res://scripts/_import_campus_access.gd -- --no-capture "--input=res://$stage/access" "--target=res://$stage/surface"
```

验收通过后，将 surface 下的 33 个 `.scn` 与 `manifest.json` 安装到
`scenes/campus_splattransform/`，重建包装场景使 ext_resource 指向正式路径。
不要把中间 `.faces.f32`、PLY、GLB、日志、Python/Node 运行库提交入库。
manifest 保存转换校验、处理参数、桥路径和固定分布的边界候选点。
Python 和 Godot 步骤应分开执行：不要让 Godot 的自定义 `APPDATA` 覆盖 Python
用户包目录；否则已安装的 numpy/scipy 可能无法导入。

## 入口与防护修复验收（2026-11-15）

- 在完整第二关中复现旧桥入口堵塞：玩家在 `(10,-0.02,-68.40)` 撞到
  `CampusBridgeExtension` 位于 `z=-68.7` 的首段侧栏。原有测试从新桥内部开始，
  漏掉了大厅至接头这一段。新增旧桥直段后，完整入口往返均通过。
- `_verify_campus_entry.gd` 验证完整生产关卡的大厅出口、旧桥、新桥和街面接头。
  冻结场景逻辑时保留所有实际碰撞体，避免禁用节点意外移除物理空间。
- `_verify_campus_guards.gd` 共 10 项通过：所有防护三角高度不超过 1.6 m；
  实际护边几何能拦住步行胶囊，飞行及下层胶囊不再碰到跨层墙。
- 92 条校园路线，双向步行和冲刺共 368 次全部通过；桥四次往返和 32 个缺口
  接近/退离样本通过；原有墙角退出 7 项、生产接线 14 项、结构 192 个样本通过。
  以上均为无窗测试，未测渲染帧率。
- `_verify_revive.gd` 共 24 项通过，覆盖步行和实际机甲形态：被击倒后等待
  5 秒游戏时间原地恢复满血，锁定移动/射击/变形，暂停时冻结倒计时。
  跑酷被击倒保留检查点；坠落救援仍独立使用关卡存档点。
- 片尾测试按真实时间执行，126 项通过。加速固定帧率会让音频停止后的等待
  过短并产生退出资源告警，因此该测试不使用 `--fixed-fps`。

## 带渲染实测（2026-11-15）

`scripts/_verify_campus_rendered.gd` 在真实 `next_level.tscn` 中使用玩家原有输入、
物理更新和机甲逻辑，不手动调用玩家物理帧。校园显示使用默认 GDGS Compute，
实际加载 6,144,827 个高斯点；碰撞使用当前正式扫描场景，兜底平板仍关闭。

- 最终运行 31 项通过 / 0 项失败，进程正常退出 0；最终日志无 ERROR / SCRIPT ERROR。
  有三条既有警告：两张光环 PNG 的直接读取不适合导出，以及 13 盏灯仅最强 8 盏
  参与 GDGS relighting。本轮未验证打包后的图片读取。
- 大厅至街面、街面至大厅两条完整路线均走完 30 个路径点，冲刺分别耗时
  26.23 秒、23.57 秒；两处实际分块接缝各双向冲刺一次全部通过。
  本轮未复现卡死或掉落，不能据这些路线保证全校园任意位置都不卡。
- 地面与真实飞行机甲被击倒后，持续按前进、跳跃仍保持倒下位置；4.7 秒时
  均未恢复，分别在 5.000726 秒、4.952305 秒原地满血恢复。SceneTreeTimer 按
  渲染帧推进，验收容许 50 ms 的提前量；测试使用单调时钟测量，不用测试自身
  的游戏计时器充当墙钟。截图回读后先稳定数帧，避免回读长帧污染计时起点。
- 机甲恢复后通过实际下降输入降落到扫描街面，脚下高度约 5.109 m。
- 已逐张检查实际 GPU 截图：`campus_arrival.png`、`mech_landed.png`、
  `hall_return.png`，均来自最终 1600×900 视口。

本机 NVIDIA RTX 4060 Laptop GPU / Vulkan Forward+，1600×900，3D 缩放 1.0，
默认画质、60 FPS 上限，真实时间运行约 85.52 秒。各阶段数值如下：

| 阶段 | 采样帧数 | 平均 FPS | 帧耗时 p95 | 最大单帧 |
| --- | ---: | ---: | ---: | ---: |
| 首次大厅进入校园，包含加载 | 1,157 | 44.2 | 34.17 ms | 2,564.78 ms |
| 校园返回大厅 | 1,192 | 50.6 | 24.63 ms | 86.60 ms |
| 接缝 0，正向 / 反向 | 39 / 55 | 31.4 / 43.2 | 36.16 / 27.21 ms | 41.60 / 29.69 ms |
| 接缝 1，正向 / 反向 | 52 / 37 | 40.3 / 29.4 | 27.19 / 46.18 ms | 28.42 / 47.68 ms |
| 机甲下降落地 | 26 | 29.6 | 39.38 ms | 42.11 ms |

首次进入仍有约 2.565 秒长帧；同轮校园泼溅加载日志为 13.9 秒、缓存命中。
报告中的 `load_seconds=39.26` 是从关卡实例化到完整入口路线走完后检查 ready 的
观察时刻，不是解码耗时。性能尚未达到稳定 60 FPS，需要进一步剖析加载和渲染。
本轮冻结了敌人攻击和自动关卡流程，其他程序仍可能共享 GPU；接缝和下降阶段
样本较短，不能当作完整战斗压力测试，也没有与旧碰撞进行相同条件 A/B。

运行器 `tools/run_godot_private_desktop.py` 在独立 Windows desktop 上创建 Godot，
从不调用 SwitchDesktop，且使用 OffWin 移出屏幕、`--no-capture` 和 Dummy 音频。
APPDATA / LOCALAPPDATA 指向输出目录内的测试配置，不改玩家存档。安全预检和
最终运行均通过；最终运行前后前台句柄一致。渲染覆盖与窗口位置由探针固定，
不通过修改项目默认窗口设置实现。

```powershell
# 必须使用实际 GUI Godot exe；不要传会转发到子进程的 *_console.exe。
$gd_gui = 'D:/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe'
python tools/run_godot_private_desktop.py --godot $gd_gui --project . --script res://scripts/_verify_campus_rendered.gd --out _tools/_tmp/rendered_collision/gameplay --timeout 360
```

最终报告、引擎日志、启动器记录与截图在
`_tools/_tmp/rendered_collision/gameplay/`，均为忽略的测试产物，不提交入库。

## 历史验收（2026-11-14，修复前）

```powershell
$flags = @('--no-capture', '--campus-splat=off', '--splat=off', '--story=off')
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_gs_motion.gd -- @flags --integration --terrain-routes --regression-routes=res://tools/fixtures/campus_collision_routes.json "--ground-reference=res://$stage/surface/terrain_height.f32" --expect-outline-guards --report-tag=splattransform_installed
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_campus_access.gd -- @flags
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_campus_install.gd -- @flags
& $gd --headless --path . --script res://scripts/_verify_campus_structure.gd -- @flags
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_collision_recovery.gd -- @flags
& $gd --headless --path . --script res://scripts/_verify_move_feel.gd -- @flags
& $gd --headless --path . --script res://scripts/_probe_final_phase.gd -- @flags
& $gd --headless --path . --script res://scripts/_smoke_build.gd -- @flags
```

- 正式安装场景：368 次移动全部通过，主动跳跃 0 次。68 次动作所在路线预先检测到
  结构或陡坡；其中 25 次按安全退出验收（23 次后退、2 次侧移），其余直线通过。
  没有把停在障碍前误判成直线通过。
- 固定回归坐标保留早期失败候选的 85 条路线，X/Z 和方向不变，Y 重新采样。
  对原坐标落在扫描结构内部的样本，从最近的可站立位置接近，并记录偏移距离。
- 桥往返步行、冲刺四次通过，包含桥端到原扫描街面的连接。
- 边界 32 个真实玩家样本通过：包含护栏停止、扫描结构先挡住和有支撑的侧向绕行。
  每个样本都要求保持近脚支撑，并能用普通输入离开接触点。
- 独立结构回归 192 / 192 通过：64 个原始扫描墙/树干见证点，在 0.65、1.3、2.0 m
  三个高度仍有碰撞。
- 生产接线、单位变换、平板关闭、玩家 margin、三 Boss 与预警圈贴地、旧桥封口等
  14 项检查通过。
- 玩家墙面/墙角退出 7 项通过，移动手感 19 项通过，主场景冒烟 12 项通过。
- 终局演出回归 58 项通过。
- 移动手感探针按真实时间运行，不能使用加速的 `--fixed-fps`。
- 结构测试以半径 0.35 m 球和长度 1.5 m 横穿射线检查；允许原始见证点位于
  新封实底座内部，不能只用球是否碰到外壳判断结构被删除。

性能是 headless CPU/静态内存数据，没有测 GPU 渲染 FPS：

| 项目 | 旧网格 + 平板基线 | 当前细化扫描 |
| --- | ---: | ---: |
| 扫描三角 | 181,691 | 2,522,900（含防护与桥） |
| 玩家更新 p50 | 0.153 ms | 0.223 ms |
| 玩家更新 p95 | 0.337 ms | 0.654 ms |
| 射线查询 p50 | 7.665 µs | 16.605 µs |
| Godot 静态分配 | 179.4 MiB | 564.3 MiB |

旧、新路线数量与地形不同，这些数字用于估计资源代价，不能当作严格同路线性能比。
当前新碰撞约占旧基线 3.1 倍静态分配，射线约 2.2 倍；不能据此保证实际游玩帧率。
安装探针完整实例化关卡时，headless dummy renderer 在 HUD 字体初始化报告 RID
初始化、空纹理或退出纹理 RID 泄漏；14 项地形断言通过，但不宣称全日志零 ERROR。
