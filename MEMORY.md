# MEMORY.md —— 爱丽丝梦游长理（项目级长期事实）

> 本文件是**事实库**，不是流水账。只写可复现、可核对的东西；用户口述但未复测的，明确标注。
> 工作区级偏好与红线见 `../AGENTS.md`；本文件只管这个工程。
> 最后核对：2026-11-03（本机，Git HEAD `a7ec536`）

---

## 1. 工程坐标

| 项 | 值 |
|---|---|
| 工程根 | `C:\Users\WY157\Desktop\GODOT\_arisu_learn` |
| 引擎 | Godot **4.7.1.stable.mono**（`a13da4feb`，.NET 版） |
| 可执行 | `D:\SOFTWARE\Godot-4.7.1-dotnet\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` |
| 主场景 | `res://scenes/game.tscn`（`project.godot`） |
| 渲染 | Forward+ / Vulkan 1.4 |
| 显卡 | RTX 4060 Laptop，8188 MiB，驱动 616.56 |
| 中文名 | `config/name` 已改为「爱丽丝梦游长理」；**该改动尚未提交**，`config/description` 仍是旧的「长沙理工：2067」 |

真实日志（编辑器 / 正式运行）：

```
%APPDATA%\Godot\app_userdata\爱丽丝梦游长理\logs\godot.log
```

## 2. 工具链：只认这两个入口

`_tools/run_probe.sh <res://脚本>` —— **headless**，跑探针 / 自检 / 构建场景脚本。
`_tools/run_shot.sh <res://脚本> [-- 额外参数]` —— **离屏真窗口**，出图或测性能，窗口在 `-4000,-4000` 且 `NO_FOCUS`，不抢前台。

两个脚本都强制：

```bash
export APPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming'
export LOCALAPPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local'
```

**不要绕过这一步直接调 Godot**：不指这两个变量就会用用户真实 AppData，导入缓存和 `settings.cfg` 跟编辑器不是同一份，之前已经栽过一次。

其他：

- `_tools/boot_check.sh [帧数]`：headless 启动冒烟，只捞 `SCRIPT ERROR` / `Parse Error` / `push_error`。`push_warning` 是刻意的，不算失败。
- `--script` 模式下 `game.gd` 会跳过抢前台 / 抢鼠标（见 `_watch_input()`），探针不会把鼠标锁走。
- 出图必须真窗口：`--headless` 下 `get_texture().get_image()` 拿不到内容。

## 3. `Performance.RENDER_VIDEO_MEM_USED` 的口径（容易误读）

它报的是 **本进程** 的显存用量，**不是整卡占用**。

2026-11-03 实测：`nvidia-smi` 整卡已用 3295 MiB（编辑器 + OBS 在跑），同一时刻探针里 Godot 只报 **190.4 MiB**。

所以本文件所有 VRAM 数字都是「进程内」口径，别拿去跟 8188 MiB 的卡容量直接比。

## 4. 校园 GGS：架构与释放（提交 `a7ec536`）

- 校园不用 Compositor，走「GGS 渲染到纹理 + 全屏 quad」；GGS 纹理宽度封顶 1920，4K 最大化按 3504×2049 光栅化只有 28 fps，这条是踩过的坑。
- 素材 `res://campus_ggs.bin`：1,475,478,480 B（≈1406 MB），**6,144,827 点**。
- 大厅 AABB（`hide_inside_aabb`）从场景 `Campus` 的 `SplatScene` 读，当前值 `P(-17,-3,-11) S(33,19,25)`，即 `z > 14` 即属室外。
- 触发：玩家在 AABB 内累计 **0.3 s** → `_release_campus()` 停光栅器、`quad.queue_free()`、`RenderingServer.call_on_render_thread(ctx.free)` 真释放 RID；出门累计 **0.25 s** → `_make_bundle()` 重建，bin 分帧 `pump_load` 上传。
- `hide_inside_aabb` 那套旧办法（`SplatScene` 自带）只隐藏节点、**不释放显存**；真释放只有 a7ec536 这条路径。

**本次复测（2026-11-03，`run_shot.sh ... -- --splat=off`，1280×720 离屏）：**

```
[ggsprobe] 初始 VRAM=190.4 MiB  hide=[P: (-17.0, -3.0, -11.0), S: (33.0, 19.0, 25.0)]
[ggsprobe] 室内 释放后 rasterizer=<null> quad=<null> VRAM=190.4 MiB
[ggsprobe] 室内 FPS=165.0 VRAM=190.4 MiB
[ggsprobe] 门外 rasterizer=<null> quad=<null> VRAM=190.4 MiB
[ggs] bin 开始分帧上传：1406 MB
[ggs] bin 上传完成：6144827 点
[ggsprobe] 重建后 FPS=67.0 rasterizer=(...Resource) quad=(...MeshInstance3D) VRAM=4975.5 MiB
```

结论：释放真生效（`rasterizer` / `quad` 都变 `<null>`，VRAM 不随门外继续涨），出门重建能恢复。与交接记录的 190 MiB / 165 FPS、4975 MiB / 66 FPS 一致（FPS 66→67 属正常抖动）。
**未复测**：重建耗时 1.5 s、切场景 6.0 s + 预载 1.5 s —— 这两个数是用户口述，探针没打时间戳。

## 5. 场景与规模

- 第二场景 `res://scenes/next_level.tscn`；`CampusGGS` 不是场景节点，由 `scripts/next_level.gd::_maybe_enable_campus_ggs()` 在运行时 `new()` 后挂上去，所以探针要等 ~120 帧再 `get_node_or_null("CampusGGS")`。
- 分块：只有 **3×3 原型**（`scenes/campus_chunks.tscn` + `scripts/campus_chunks.gd`，2026-10-28，**未接线**，只切 `visible` 不释放，3×3 加载 37 s）。**10×10 没做**。
- `scenes/campus_buildings.tscn` 在工作区里显示为 **已删除（−3819 行）**，未提交；除 `scripts/_probe_campus_buildings_shot.gd` 外没有其他引用。删除意图未经确认。

## 6. 工作区未提交状态（2026-11-03，勿整体提交）

`git status` 共 80 项。提交时**只 `git add` 自己动的文件**。

已提交部分：

| 提交 | 内容 |
|---|---|
| `a7ec536` | 校园 GGS 室内释放：进大厅释放光栅器，出门重建 |
| `88fc60f` | 显示器改 2×2 四屏：第二排上墙，修曲面屏反字 —— **已被未提交的回滚取代** |

未提交、但看起来是**有意**的改动：

- `scenes/pc_wall_case.tscn`（−250/+138）＋ `scripts/_build_pc_wall_case.gd`：2×2 四屏回滚为**双屏独立托板**（场景里只剩 `Monitor0` / `Monitor1`，生成脚本注释也写明「双屏独立托板」）。
- `scenes/game.tscn`：新增 `EsportsRoom` 实例，位置 `(52, 0.01, 13)`。
- 新增未跟踪：`scenes/esports_room.tscn`、`scripts/_build_esports_room.gd`、`scripts/_verify_esports_room.gd`、`scripts/_probe_ggs_inside.gd`、`scripts/_probe_segments.gd`、`scripts/_tmp_room_bounds.gd`、`_tools/run_probe.sh`、`_tools/run_shot.sh`、`_tools/boot_check.sh`。
- `project.godot`：中文名改动（见 §1）。

其余大量 `*.uid`、`.import`、`_log/`、`_backup/`、`_arisu_captures/` 属于噪声或私有产物，不随本次提交。

## 7. 电竞房（已生成，布局归用户）

`scripts/_build_esports_room.gd` 生成 `scenes/esports_room.tscn`。房间局部 x ±8.2 / z ±5.0，门在西墙 `x=-8.1`。

- 东墙 4 个主力位（4 桌 4 屏 4 椅）
- 北墙凯伊 1 桌 1 屏
- 南墙 8 卡 9995WX 开放架
- 世界位置 `(52, 0.01, 13)`

**布局用户已接手，不要改动。**

## 8. 内容与素材现状

- 角色 / 场景 GLB 在 `models/`、`assets/`；`.gitignore` 把 Blue Archive 派生模型、校园扫描、Boss 模型挡在仓库外（理由见 `THIRD_PARTY.md`），**这些不能提交**。
- 待接入（用户下载或自建）：PSU、风扇、SSD、DDR5 ECC、WRX90、开放架、9995WX。
- Blender 已装 `io_scene_max` 1.9.2、`import_3dm` 0.0.18（rhino3dm 8.35）；C4D 导入插件被夸克盘挡住；`io_scene_max` 不支持 3ds Max 2024。
- 署名与来源记在 `CREDITS.md` / `THIRD_PARTY.md`，第三方素材一律本地存放并署名。

## 9. 红线（违反即返工）

1. 数字必须带实测，没跑就说没跑，不编。
2. 不弹前台、不抢 GPU、**录制中别杀进程**（OBS 常驻 `obs64.exe` + `obs-ffmpeg-mux.exe`）。
3. 完成就提交，但只提交自己的文件。
4. 第三方素材：本地保存 + 署名。
5. 卡顿要藏起来（黑屏预载、分帧上传），不许把加载卡顿暴露给玩家。
6. 用户给短指令时，先对齐「改哪个对象」再动手。
7. 「给某人留一个」= 同等规格的工位，不是边角料。

## 10. 部室「窗 + 储物柜」那一角掉帧（2026-11-03）

用户报：站到那个角就持续低帧。**结论：那一角本身不重，是门口把整片室外场地框进了视野。**

真实配置（泼溅开、1600×900、无后台）：

| 机位 | fps | draw call | 图元 |
|---|---|---|---|
| 窗 + 储物柜那一角（看向门） | **98.2** | **1579** | 40.9 万 |
| 对面那一角（看向窗户） | 159.7 | 320 | 12.7 万 |

已修（`fb6abf8`）：609 屋顶 149 颗 9950X3D，单颗 12,386 面 × 149 = **184.5 万面**，
从部室看过去每帧全过一遍顶点。加 22 m 可见距离 + 关投影后同机位 A/B 两轮一致：
**131.4 → 144.1 fps**，图元 214.4 万 → 35.5 万；5 m 近处图元数不变（拾取范围 3.2 m 不受影响）。

已排除：

- 部室本体只有 **31 个材质面 / 21,892 面**（一个 MeshInstance，不是 draw call 爆炸）。
- 阴影级联距离：60 m → 30 m 只换回 1.1 帧（噪声内）。但阴影 pass 仍占该机位
  **约 46% 的 draw call**（1517 → 关阴影 817）；全关值 **+19%**（163.7 → 194.8 fps），代价是画面，未做。
- 泼溅没释放：`Performance` 报 3011 MiB，开关泼溅差别不大。
- **贴脸补光 `FaceFill`**（`3b9ffb4`，Player 下 0.32 能量 / 2.2 m / 无阴影的 OmniLight）：
  它就是墙上那团跟着人走的光斑的来源，但**不吃帧**。同机位交替开关：
  开 171.4 fps / 关 163.0 fps（关掉那轮反而更慢 ⇒ 噪声），draw call 1540 vs 1539 完全一样。
  已按「只照角色」修掉观感问题（`6998d1d`，见下）。

**没复现出「非常卡」**：最差 98 fps。若用户现场确实低得多，得先拿局内读数。

### 渲染层约定：贴脸补光只照角色

- 玩家自己的网格（`Arisu` + `Weapon` 子树里的所有 `MeshInstance3D`）在 `player.gd::_setup_face_fill()`
  里被设为 **`layers = 1 | 2`**；`FaceFill.light_cull_mask` 只留第 2 层。
- 于是：这盏灯照不到墙（墙在第 1 层），**太阳和屋内灯默认照所有层，角色受光完全不变**。
  仍然保留第 1 层，是为了万一别处按层剔除时角色不会消失。
- 全工程此前**没有任何 `layers` / `cull_mask` 用法**（`addons/` 之外），第 2 层是空着的。
- 验证图：`_log/facefill_before.png`（灯照所有层，墙上一团光斑）／`_log/facefill_after.png`（干净）。

### 测量陷阱（下次别再踩）

- `Performance.TIME_PROCESS` 在本工程**和真实帧率对不上**：浮层开着报 29 ms，实测 194 fps。
  只信按真实帧间隔量出来的数。
- 离屏窗口放在 `-4000,-4000` 会被系统按「遮挡」节流，同一机位复跑能得到 7 fps 和 145 fps 两个数。
- 探针把玩家**瞬移进几何体**会让物理耗时飙到 100 ms（穿透解算），是假象，不是现场问题。

### 局内读数工具

按 **F3** 开关性能浮层（`scripts/game.gd`）：FPS、最近 120 帧的 p50/p99/max 帧间隔、
draw call、图元、显存、物体数、物理耗时、玩家坐标。浮层自身开销 197.7 → 194.6 fps（-1.6%）。

## 11. 下一步

1. ~~真实窗口复测 a7ec536~~ —— 已完成（离屏 `--splat=off`，数据见 §4）。
2. ~~部室角落掉帧~~ —— 已定位并修掉 184.5 万面那颗雷（§10）；用户可用 F3 复核，仍低再谈室内降级室外远景。
3. 仍卡就上 10×10 分块 / 降点云。
4. 等素材接入开放架。
5. 电竞房布局等用户。
6. 待确认：`campus_buildings.tscn` 删除是否有意；`project.godot` 名称与 description 是否一起收尾提交。