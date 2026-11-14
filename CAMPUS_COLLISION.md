# 校园扫描碰撞

`scenes/next_level.tscn` 的 `CampusCollision` 使用
`scenes/campus_splattransform.tscn`：31 个原生扫描分块、扫描边界防跌落面、
一座可见连接桥，共 33 个静态碰撞体，3,868,654 三角，压缩资源约 78 MB。
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
- 近地去噪先采样原生碰撞（0.5 m 网格，射线 Y=8 到 -20），
  5 格中值滤波、Gaussian sigma=2。目标高度相对采样最多修正 ±0.8 m。
  原生壳体 1.3 m 带内向目标收敛，随后 0.7 m 淡出；仅移动已有顶点 Y，
  X/Z 保持不变，去退化面后再以 0.1 m 近似误差 LockBorder 简化。
  这些参数用于去除扫描表面的薄壳和尖刺，不代表 0.25 m 的绝对精度保证。
- 扫描缺失列不补平板。沿实际支撑轮廓加竖直防跌落面；桥经过时仅在桥面
  附近开竖向窗口，保留桥下的防护。边界是物理阻挡，未添加可见围栏模型。
- 连接桥宽 2.6 m，路径约 135.6 m，起点 `(10,0,-70)`，经避障坡道
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
python tools/campus_splattransform_collision.py ground --source "$stage/locked" --heightfield "$stage/ground.f32" --out "$stage/surface" --runtime $runtime --error .1
& $gd --headless --path . --script res://scripts/_import_splattransform_collision.gd -- --no-capture "--directory=res://$stage/surface"
& $gd --headless --path . --script res://scripts/_sample_campus_collision.gd -- --no-capture "--scene=res://$stage/surface.tscn" "--out=res://$stage/top.f32"
python tools/campus_collision_access.py --top "$stage/top.f32" --out "$stage/access"
& $gd --headless --path . --script res://scripts/_import_campus_access.gd -- --no-capture "--input=res://$stage/access" "--target=res://$stage/surface"
```

验收通过后，将 surface 下的 33 个 `.scn` 与 `manifest.json` 安装到
`scenes/campus_splattransform/`，重建包装场景使 ext_resource 指向正式路径。
不要把中间 `.faces.f32`、PLY、GLB、日志、Python/Node 运行库提交入库。
manifest 保存转换校验、处理参数、桥路径和固定分布的边界候选点。

## 验收（2026-11-14）

```powershell
$flags = @('--no-capture', '--campus-splat=off', '--splat=off', '--story=off')
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_gs_motion.gd -- @flags --integration --terrain-routes --regression-routes=res://tools/fixtures/campus_collision_routes.json --jump-obstacles --expect-outline-guards --report-tag=splattransform_installed
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_campus_access.gd -- @flags
& $gd --headless --fixed-fps 60 --path . --script res://scripts/_verify_campus_install.gd -- @flags
& $gd --headless --path . --script res://scripts/_probe_final_phase.gd -- @flags
& $gd --headless --path . --script res://scripts/_smoke_build.gd -- @flags
```

- 正式安装场景：344 次移动全部通过。64 次用了主动跳跃，12 次预先判定会接近
  扫描边界，其中 9 次实际接触边界。不能将此结果描述为全部纯走路通行。
- 固定回归坐标保留早期失败候选的 85 条路线，X/Z 和方向不变，Y 重新采样。
  另加入当前可行路线与接缝检查；不因新几何受阻而删除回归案例。
- 桥往返步行、冲刺四次通过，包含桥端到原扫描街面的连接。
- 边界 32 个真实玩家样本通过：31 个停在护栏，1 个绕过小缺口拐角。
  绕行样本保留且逐帧检查，100 帧均有近脚支撑，不把越过有限护栏的平面等同跌落。
- 生产接线、单位变换、平板关闭、玩家 margin、三 Boss 与预警圈贴地、旧桥封口等
  14 项检查通过。
- 终局演出 58 项通过，主场景冒烟 12 项通过。
- 公共 ground 命令重跑最大的相邻两块，输出 faces 的 SHA-256 与安装来源完全相同。

性能是 headless CPU/静态内存数据，没有测 GPU 渲染 FPS：

| 项目 | 旧网格 + 平板基线 | 当前细化扫描 |
| --- | ---: | ---: |
| 扫描三角 | 181,691 | 3,868,654（含防护与桥） |
| 玩家更新 p50 | 0.153 ms | 0.161 ms |
| 玩家更新 p95 | 0.337 ms | 0.488 ms |
| 射线查询 p50 | 7.665 µs | 16.113 µs |
| Godot 静态分配 | 179.4 MiB | 774.9 MiB |

旧、新路线数量与地形不同，这些数字用于估计资源代价，不能当作严格同路线性能比。
当前新碰撞约占旧基线 4.3 倍静态分配，射线约两倍；不能据此保证实际游玩帧率。
安装探针完整实例化关卡时，headless dummy renderer 在 HUD 字体初始化报告 RID
初始化、空纹理或退出纹理 RID 泄漏；14 项地形断言通过，但不宣称全日志零 ERROR。
