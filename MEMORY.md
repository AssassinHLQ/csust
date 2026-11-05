# MEMORY.md —— 爱丽丝梦游长理（项目级长期事实）

> 本文件是**事实库**，不是流水账。只写可复现、可核对的东西；用户口述但未复测的，明确标注。
> 工作区级偏好与红线见 `../AGENTS.md`；本文件只管这个工程。
> 最后核对：2026-11-05（本机，Git HEAD `5e3f107`）

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
- ⚠️ **室内分支必须撤遮罩**：`_overlay`（「校园渲染器加载中...」）唯一那句 `visible = false`
  在**室外分支**里。`a7ec536` 加了室内释放后，`_process` 在室内直接 return，
  于是 `_make_bundle()` 不跑、遮罩永不撤、`is_ready()` 永远 false（切场景黑屏还干等 20 s）。
  `next_level` 的出生点 `(-2.0, 0.55, 5.2)` 正落在 `hide_inside_aabb` 内，**走门进第二场景必黑屏**。
  已在 `a8de851` 修掉（室内也撤遮罩 + 厅内 `is_ready()` 直接为真）。
  验证探针：`_probe_scene_switch_ggs.gd`（走 MondrianGate2F 进第二场景，截图 `_log/after_switch.png`）。

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
- 分块：**10×10 已做**（`acf6347` 导出 97 块 bin、`5e3f107` 接进运行时，见 §11 的验收）。
  旧的那个 `scenes/campus_chunks.tscn` + `scripts/campus_chunks.gd` 3×3 原型（2026-10-28，未接线、只切 `visible`）**已作废**，别再接线。
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

### 探针出图不要放 res:// 里（已用 `.gdignore` 堵住）

`_log/` 在项目内，写进去的 PNG 会被编辑器当资源导入、生成 `.import`；多个进程同时
写/删时扫描会撞上半成品，于是刷屏：

```
ERROR: Can't find file 'res://_log/textures/Aris_Original_Body.png' during file reimport.
```

2026-11-03 用户拿这批红字当「部室网格在编辑器里不显示」的原因 —— **两者无关**，
那批文件是瞬时状态，源文件当时其实都在（清点时 29 个 `.import` 无一孤儿）。

现在 `_log/.gdignore` 存在 → Godot 整目录忽略（写文件不受影响，只是不再导入）；
目录里历史遗留的 29 个 `.import` 已删除。

### 测量陷阱（下次别再踩）

- `Performance.TIME_PROCESS` 在本工程**和真实帧率对不上**：浮层开着报 29 ms，实测 194 fps。
  只信按真实帧间隔量出来的数。
- 离屏窗口放在 `-4000,-4000` 会被系统按「遮挡」节流，同一机位复跑能得到 7 fps 和 145 fps 两个数。
- 探针把玩家**瞬移进几何体**会让物理耗时飙到 100 ms（穿透解算），是假象，不是现场问题。

### 局内读数工具

按 **F3** 开关性能浮层（`scripts/game.gd`）：FPS、最近 120 帧的 p50/p99/max 帧间隔、
draw call、图元、显存、物体数、**物理步/帧**、物理耗时、玩家坐标、物理步上限。
浮层自身开销 197.7 → 194.6 fps（-1.6%）。

### 物理雪球：用户现场 7 fps（2026-11-03 夜，**未定案**）

用户现场读数（部室里、画质已全关）：`p50 133 ms`、FPS 7、物理 65~82 ms、
draw 914~1370、图元 30~47 万、显存 2985 MiB。
日志确认：`3D 缩放 0.50 / 垂直同步 / 80 fps / AA 关 / 阴影 低 / 渲染距离 100 m /
SSAO・辉光・SSR・雾 全关 / 最大化`，GPU 是 4060 —— **渲染侧已无可省，7 fps 不可能是画得多**。
日志另有 11 次「窗口没有前台焦点」，以及开场 `等画面 10.3 s / 34 帧`（≈3.3 fps）。

**形态**：`133 ms ≈ 8 × 1/60 s` = Godot 每帧物理步上限，配合物理 65~82 ms ⇒ 疑似物理雪球
（帧慢 → 每帧补最多 8 步物理 → 帧更慢）。

**但本机复现不出来**（同配置、泼溅加载中）：609 室内（泼溅可见）88 fps / 11.4 ms；
部室 141 fps / 7.1 ms；1080p 满配 + 同伴进屋 137 fps / 7.3 ms。
**每步物理成本实测 ≈ 1.8 ms**（240 Hz 放大法）；关掉 7 个同伴的物理：103.9 → 147.1 fps。
8 步 ≈ 15 ms，凑不出 133 ms ⇒ 用户机器上一步约 16 ms，是本机的 9 倍。

**待用户读 F3 的「物理步/帧」**：`8.00` ⇒ 雪球成立，去砍物理成本；`~1.00` ⇒ 方向要换。

候选修法（**都还没做**）：降 `max_physics_steps_per_frame`（代价：物理时间被稀释，
就是 `game.gd` 注释里那条「WASD 按了不动」的坑）；同伴互不碰撞（`collision_layer/mask`）；
部室那面 21,892 面凹面 trimesh 换盒体。

### 物理测量的口径陷阱

- ⚠️ **不能**用「帧时间 ÷ 物理步数」当每步成本 —— 步数是跟着帧时间算出来的
  （`steps = min(上限, 帧时间 × 步频)`），除出来恒等于 1/步频。本喵用这个算法得出过
  「5 ms/步」，是纯陷阱。
- 想放大物理占比，就把 `Engine.physics_ticks_per_second` 拉到 240（每帧逼近 8 步）。
- 本次新增的探针：`_probe_scene_perf.gd`（现场同配置）、`_probe_physics_cost.gd`、
  `_probe_physics_gauge.gd`（口径判定）、`_probe_physics_breakdown.gd`、
  `_probe_physics_levers.gd`、`_probe_inside609.gd`、`_probe_splat_visible.gd`、
  `_probe_room_playercam.gd`、`_probe_facefill.gd`、`_probe_perf_overlay_cost.gd`。

## 11. 部室的模型加载与碰撞（2026-11-03 改）

**模型是运行时加载的**：`gamedev_room.tscn` 的 `Model` 是个空 `Node3D` + `scripts/gamedev_room.gd`，
glb 由脚本在 `_ready()` 里挂上去（`36e9bf8` 合规审计改的）。原因：模型授权未核实、被
`.gitignore` 挡在仓外，写成 `[ext_resource]` 时**缺模型会让整个场景加载失败 → 游戏起不来**。

- ⚠️ 副作用：**在编辑器里看不到屋子的网格**（运行时挂的节点编辑器不显示），
  只能看到灯、招牌、机箱和碰撞 gizmo。2026-11-03 用户就是拿这个来问「这是碰撞吗」。
  这不是 bug；**跑游戏**才看得到屋子。
- 编辑器要看碰撞：菜单「调试 → 可见碰撞形状」（跑中的游戏用 `--debug-collisions`）。

**碰撞已从凹面 trimesh 换成 24 块具名盒子**（用户 2026-11-03：「部室碰撞太多面数了」）：

- 生成器 `scripts/_build_gamedev_collision.gd`（`_tools/run_probe.sh` 跑；**幂等**，重跑会先删掉上次的 `Col_*`；
  `-- --dry` 只打印）。它读模型 31 个材质面的局部 AABB 来分类：结构墙按整屋 AABB 重排、
  门框那块板给出门洞范围、扁片/铺地/小件不做碰撞、其余每件一个盒。
- 结果：墙 4 面（门洞那面拆成 `Col_DoorJambA` / `Col_DoorJambB` / `Col_DoorLintel`）
  + `Col_Floor` + `Col_Ceiling` + 16 件家具（`Col_teddybear_01`、`Col_monitor_02`…名字可认）。
  全部挂在 `Model/Collision` 下，编辑器里能拖、能改 `size`。
- 物理同机位 A/B（240 Hz 物理放大、7 名同伴在屋里）：旧 trimesh **57.5 fps / 17.40 ms**
  → 盒子 **108.7 fps / 9.20 ms**（约 1.9×）。射线验证：门洞通（12.94 m，中途撞粉熊）、
  实墙挡（1.67 m 正好是墙面）、地板/天花板/家具都挡。
- 旧 `assets/collision/gamedev_room_trimesh.res`（788 KB）**留在盘上做回退**，场景已不再引用；
  `scripts/_bake_gamedev_trimesh.gd` 也还在。
- 家具用 AABB 会略多吃空间（斜放的沙发/熊）。刻意如此：宁可挡多一点也别穿模；
  嫌胖就在编辑器里把那一块 `size` 改小。
- ✅ **用户 2026-11-03 实测确认：换完就不卡了** —— 所以 §10 那批「角落掉帧」的病根是**物理**
  （8 个 CharacterBody3D 在 21,892 面凹网格上 move_and_slide × 每帧最多 8 个物理步），
  渲染侧那些（1.8M 面 CPU、阴影 pass、draw call 1579）都是次要的。以后遇到「卡」，
  **先量物理，再量画面**；而「拿渲染网格当碰撞网格」这条要一直盯住。

## 12. 2026-11-04：5090 工作站搬家 + 粉熊平滑

**5090 工作站从部室搬到电竞房北墙**（用户：「部室那个 5090 还没去掉吗，先去掉，我们放电竞房的」）

- `gamedev_room.tscn` 删掉 `PC5090Rig` 实例与不再用的 `pc_wall_case` ext_resource。
- `esports_room.tscn` 新增实例：位置 `(3.22, 0.94, -4.53)`、**绕 Y 转 180°**
  （机箱局部 `-z` 是玻璃面，转过来才朝房间；背面挂架贴北墙内表面 z=-4.80）。
  北墙 x≈3.2 那段是空的：凯伊桌到 x≈1.1、门口海报在 x=1.8、东墙主桌在 x≈7.2。
  整套含门边双屏托架宽 3.36 m，实测世界包围盒 `3.35 × 1.57 × 0.64`。
- 生成器 `scripts/_build_esports_room.gd` 同步改了（重跑不会丢）。
- ⚠️ `pc_rig.gd` 里**买了才显示**（`ShopClerk.is_bought()`），买之前隐藏且关碰撞——
  所以电竞房刚进去是看不到这台机箱的，那是商店奖励的既有设计，不是 bug。
- 验收：`scripts/_probe_rig_moved.gd`（部室应无、电竞房应有），图 `_log/rig_in_esports*.png`。

**粉熊改成平滑着色**（用户问「粉色熊有没有渲染圆角」）

- 原来是**硬边平面着色**：teddybear 那 1,026 面，顶点 1,446 / 唯一点位 570（重复 2.54×），
  顶点法线与面法线夹角中位 **2.1°**，所以一块块大棱面。
- 只给这一面做 shade smooth：**面数不变**（21,892 → 21,892），轮廓仍是低模多边形。
  脚本 `tools/_smooth_gamedev_bear.py`（模型本体 gitignore，脚本是唯一记录）。
- ⚠️ 选面必须按 `polygon.material_index`；`material_slot_select()` 在合并网格上会选中**全部 21,892 面**
  （本喵踩过，倒角倒到整间屋子）。平滑要用编辑模式的 `mesh.faces_shade_smooth()`。
- 对比图 `_log/bear_before.png` / `bear_after.png` / `bear_in_room.png`。

**电竞房素材（新）与 Rhino 工作流**（用户：「改 fbx，我在 Rhino 修改」）

- 那个 390 MB 的 `工业风电竞酒店客房_爱给网_aigei_com.zip` **不是一间房**，是 3d66 模型大杂烩：
  1,384 对象 / 1,100 网格 / **1,173 万三角** / 90 材质 / 仅 10 贴图，散在 55 km 范围，同一份 46.5 万面的东西重复 5 遍。
  内含：球形尖刺吊灯（`Obj3d66-782061`）、美容包厢（`youshang-美容包厢`）、油罐、拱门，
  以及确实相关的 `Obj3d66-1094423`（405 对象 / 801 万面；材质名里有「电竞台墙面」「机箱」`cgaxis_electronics`）。
- 已按空间簇抽出「房间尺度」那簇（15 网格 / 52.5 万面 / 14.75 × 20.2 × 5.27 m）导成
  **`酒店客房_Rhino/hotel_room_for_rhino.fbx`（16.3 MB，贴图内嵌，已居中到原点，未缩放）**，
  交给用户在 Rhino 里改。
- ⚠️ **授权红线**：贴图名是 `3d66Model-*`（3d66 商业素材站）+ `cgaxis_electronics`（CGAxis 商业站）
  + 一条卖家微信。按本项目自己的合规标准**不能进仓库、不能进发行版**；
  要接入就照 `gamedev_room` 的先例：gitignore 目录 + 运行时加载 + 缺文件优雅回退，CREDITS 标「授权未核实，仅本地学习」。
- 一个 1 单位 ≈ 1 cm 的推断（房间 428.7 × 428.7 单位）。若单位判断有误，用户从 Rhino 回来时再校正。

## 13. 校园泼溅 10×10 分块的验收结果（2026-11-05）

`5e3f107` 只验了「窗口换没换 / 显存多少」，**从没出过图**。这次补了对照探针
`scripts/_probe_campus_window_shot.gd`（同一机位拍分块 / 全量 / 降采样三种），实测如下。

**一、取景有个坑（写进探针注释了）**
`campus_ggs._make_bundle()` 把 `get_viewport().get_camera_3d()` 传给光栅器并**一直持有**，
光栅器 `update_camera_matrices()` 读的就是它。新建一个 `Camera3D` 设成 current 只能改 3D 后处理，
泼溅视图纹丝不动（两张不同朝向的图 sha256 一模一样）。**必须改 `player._yaw/_pitch` 取景。**

**二、画面：3×3 就是一块浮空地皮**
窗口 3×3 ≈ **60×50 m**（格子 x≈20 m / z≈17 m，校园本体 200×150 m），5×5 ≈ 100×85 m，7×7 ≈ 140×120 m。

| 方案 | 常驻点 | 4 个机位实测显存 | 跨窗口最坏一帧 | 画面 |
|---|---|---|---|---|
| 3×3 窗口 | 43~118 万 | 569~1303 MiB | **711~1169 ms** | 一块浮空地皮，窗外纯黑 |
| 5×5 窗口 | 148~269 万 | 1431~2465 MiB | 1297~2599 ms | 仍有一大片黑 |
| 7×7 窗口 | 284~409 万 | 2527~3066 MiB | 2304~3427 ms | **仍是「左边一块 + 大面积黑」** |
| 全量 `campus_ggs.bin` | 615 万 | 4971 MiB | 无（不切） | 满屏、无空洞 |
| **降采样 1/4 常驻** | **154 万** | **1455 MiB** | **无（不切）** | **满屏、无空洞** |

截图在 `_log/win_w3_*.png` / `win_w5_*` / `win_w7_*` / `win_full_*` / `win_q4_*.png`（`_log/` 不进仓库）。

**三、结论：加大窗口是坏买卖**
7×7 已经吃掉 3 GiB、每次跨格最坏卡 **3.4 s**，画面**还是**缺远处。
`_log/campus_q4.bin`（`_tools/decimate_ggs_bin.py` 每 4 点留 1 生成，352 MB / 154 万点）
反而用 1455 MiB 换来完整画面、且完全没有切换卡顿。

**四、天空透不出来的**真因**（2026-11-05 已修）**
不是采样问题，是着色器把 alpha 写死了：`addons/ggs_campus/shaders/gsplat_render.glsl`

```glsl
imageStore(rasterized_image, ivec2(image_pos), vec4(blended_color + heatmap_color, 1.0));
```

**每个被写到的像素 alpha 都是 1**，包括 16×16 块里没被任何高斯盖到的空地。
后果有两个：`main_sky.gdshader` 的 `mix(天空, 校园, alpha)` 永远等于「校园」→ 全景天空从不出现；
以及「粗层 + 细层」合成不起来（细层的黑底整片盖掉粗层）。
改为写真实覆盖率 `1.0 - t`（`blended_color` 是按 alpha 预乘的，所以先反预乘回直色）。
清屏本来就是 `Color(0,0,0,0)`，规则一致。

**五、第④步：粗层常驻 + 细层叠加（已实现，`campus_ggs.gd`）**
- 粗层 `campus_ggs_q4.bin`（`_tools/decimate_ggs_bin.py` 每 4 点留 1：154 万点 / 352 MB），
  **常驻**，换窗口时不动；细层仍是 3×3 分块窗口，换窗口只重传细层（`_release_campus(true)`）。
- 两层各一个光栅器 + 各一张 `Texture2DRD`，由 `main_sky.gdshader` 合成：
  `天空 → 粗层 → 细层`（`debug_layer` 0/1/2 可单独看某层）。
- `--ggs-no-coarse` 关掉粗层做对照；`--ggs-bin=` 直接指定单份 bin。
- 实测（4 机位，1280×720）：

| 方案 | 常驻点 | 显存 | 帧率 |
|---|---|---|---|
| 只有细层（3×3） | 43~56 万 | 569~780 MiB | 165~171 fps |
| **粗层 + 细层** | 154 + 43~56 万 | **1647~1711 MiB** | **141~171 fps** |
| 全量单层 | 615 万 | 4971 MiB | — |

  → 粗层只花约 1 GiB、帧率基本不掉（**没有**重演「两套渲染器打架掉到 23 fps」那次），
  而画面上远景、天空、植被全回来了（截图 `_log/win_fix_*.png` / `win_final_*.png`）。

**六、还差的（未完成，别当已完成）**
- 换窗口仍有一次 **322~1258 ms 的最坏帧**（重拼 bin + 重传 94~270 MB 是同步的）。
  已改成「换窗口不销毁 quad、任一层就绪就显示」，但这版**没来得及复测**就被用户叫停
  （用户要求别弹窗口，他正在建模）。下次复测要确认「画面空 0 帧」是否成立。
- 粗层抽稀后近处偏糊（splat 变大），16×16 分块在天空交界处有轻微方块感。要不要 stride 6 / 8
  或给粗层单独降 splat 尺寸，等用户看画面再定。
- 粗层 bin 不进仓库（已加 `.gitignore`），换机器/换导出要重新生成一次。

**七、第②步分块的导出尺度是错的（2026-11-05 离线查明并重切）**
拿 97 块和 `campus_ggs.bin` 一比就露馅（**点数、字节数完全相同 = 6,144,827 点 / 1,474,758,480 B**，
所以两种尺度一直没被发现）：

| | x | z |
|---|---|---|
| `campus_ggs.bin`（= 地面网格 CampusFloor z=−316.7、576×484 m 那一套） | −324 ~ 384，中位 −25 | −594 ~ −46，中位 −274 |
| 旧 97 块（`acf6347`，从 SOG 导的） | −109 ~ 127，中位 −9 | −248 ~ −65，中位 −141 |

旧块的跨度正好是全量的 **1/3**、原点也不对 —— 细层渲染出来是「1/3 大小的迷你校园」，
浮在真校园旁边。**这才是 3×3 窗口看起来像「浮空地皮」的真因**，跟窗口大小关系不大。

修法（纯离线，不用开窗口）：`_tools/split_ggs_bin.py` 直接从 `campus_ggs.bin`
按世界坐标切 10×10（记录**逐字节原样搬运**，不解码），产出 `splatdata/campus_chunks10w/`：
- 100 块（2 块是空的），每格 47.6 × 42.5 m，合计 6,144,827 点，和全量逐位一致；
- 清单 `center` 写**网格几何中心**而不是点的均值（均值会被远飞点拉走，选窗会选歪），
  均值另存 `mean` 只作诊断；
- `campus_ggs.gd` 默认改指 `campus_chunks10w/chunks.json`，`--ggs-chunks=` 可退回旧的对照。
- headless 校验：`scripts/_verify_chunks_manifest.gd`（不需要 GPU）→ 100 块齐全、总点数对得上、
  4 个机位的窗口都含玩家所在格、跨度 95×85 m。**全部通过**。

⚠️ 旧的 `splatdata/campus_chunks10/` 留着只作对照，**别再当默认**（1.7 GB，想删要用户同意）。
⚠️ 这一改之后，之前「3×3 只有 60×50 m、太小」的结论作废 —— 现在 3×3 = **95×85 m**。

**八、粗层还能更好（工具已备，未启用）**
`_tools/voxel_thin_ggs_bin.py` 可按体素抽稀（每格留最不透明的一个点），比「每 N 点留 1」
同点数下更保结构。已试：体素 1.0 → 93.7 万点 / 214 MB（压到 15.2%）、1.5 → 42.9 万点 / 98 MB。
现在默认仍是 stride 4 的 `campus_ggs_q4.bin`（154 万点 / 352 MB），换不换等用户看画面定。

## 14. 爱丽丝的 5 套模型（2026-11-05 收进工程）

来源 `C:\Users\WY157\Downloads\BlueArchiveModels-main\BlueArchiveModels-main`。
`models/*.glb` 已被 `.gitignore` 挡住（BA 派生模型不进仓库），本地可用。

| key | 文件 | 网格根 | 骨 | 动作 | 说明 |
|---|---|---|---|---|---|
| normal | `models/Arisu.glb` | `Aris_Original_Halo2` | 170 | 25 | 现在就是玩家模型（`scenes/main.tscn` 的 `Arisu/Model`） |
| maid | `models/Arisu_Maid.glb` | `CH0200_Halo2` | 184 | 32 | 女仆装 + 拖把；2 个骨架 |
| battle | `models/Arisu_Battle.glb` | `CH0334_Halo2` | 191 | 35 | 临战机甲（机甲头饰 + 深色紧身衣） |
| battle_scenario | `models/Arisu_Battle_Scenario.glb` | `CH0334_Halo` | 137 | 11 | 机甲·剧情形态，扛大炮（`CH0334_Weapon02`） |
| battle_carrier | `models/Arisu_Battle_Carrier.glb` | `CH0334_Halo` | 191 | **2** | 机甲·载具形态（飞行背包 + 机械腿）；**只有 Idle/Walk** |

- **5 套骨架同族**：关键骨 `Bip001 L/R Hand`、`Bip001 Head`、`Bip001 eye_L/R`、`Pelvis`、`Spine` **全在**，
  所以「挂武器 / 看朝向 / 光环抛光 / 面部修复」这些按名字找的代码理论上都能复用。
- 差异：网格根名（`Aris_Original_*` / `CH0200_*` / `CH0334_*`）和动作名。
  normal / maid / battle / battle_scenario 都有 `Normal_Idle`、`Normal_Attack_Ing`、`Move_Ing`、`Cafe_*`；
  **carrier 只有 `Idle`/`Walk`**，当玩家皮肤会缺待机与攻击。
- 预览图（后台 Blender 渲染，不开窗口）：`_log/arisu_prev/*.png`，脚本 `_tools/preview_glb.py`。
  ⚠️ 那些 glb 里混着导出残留的 `Cube` / `Icosphere`（2×2×2），会撑爆包围盒 —— 脚本里已过滤。
- 清点探针（headless）：`scripts/_verify_arisu_skins.gd`。
- ⚠️ 新拷进来的 glb **必须先跑一次导入**，否则 `ResourceLoader.exists()` 是 false：
  `_tools/run_probe.sh` 不会导入，要用
  `Godot_..._console.exe --path . --headless --import`（headless，不开窗口）。
- 换皮肤**还没做**：玩家模型是场景里的 `Arisu/Model`（glb 实例），而 `AnimDriver` 挂在它下面
  （`player.gd` 里 `$Arisu/Model/AnimDriver`），换实例要连驱动一起重建；
  再加上网格根名/动作名不同，得先定「换皮肤时哪些按名字找的地方要跟着改」。
  **（载具形态没走这条路 —— 见 §16，它是另外加一个节点，不碰 AnimDriver。）**

## 15. 凯伊（第二场景整备工）+ 载具形态（2026-11-05）

用户：「我要载具的……**花钱找凯伊**，现在不是第二场景就爱丽丝一个人吗，把凯伊放进去」。
并且提醒「剧情里面好像不是买来的」——查证过，确实不是：

> 机体叫 **阿比·埃舒**（アビ・エシュフ / Abi-Eshuh），原本是**时（Toki）**的；
> 被击毁后由**凯伊和爱丽丝合力**、借「无名诸神」的力量**重组到爱丽丝身上** —— 这才成了临战形态。
> 来源：<https://bluearchive.hatenablog.com/entry/2026/02/08/234211>（临战衣装以时让渡的阿比·埃舒为基础、
> 凯伊与爱丽丝精炼）、RekoWiki「蔚藍檔案學生介紹-千年」。所以游戏里写成
> **「凯伊动手改装，玩家出材料费」**，不是货架上买一件。

**落地的东西**
- `scenes/kei_npc.tscn` + `scripts/kei_npc.gd`（**继承 `companion.gd`**）：凯伊站桩在
  第二场景一层大厅里，出生点 (-2.0, 0.55, 5.2) 东侧 3.2 m，面朝出生点。
  站桩是在 `_ready()` 里立刻 `set_standby(true)`（早于第一个物理帧），所以她一步都不会跟队；
  standby 分支里重力照常生效，所以落点是稳的（实测停在 y=0.51 的大厅地面上）。
- 第二场景原来**没有 `DialogueBox`**，这次给凯伊加了一个（`scripts/dialogue_box.gd`）。
- `scripts/mech_state.gd`：解锁标记落盘 `user://mech.cfg`，**跨启动保留**
  （和银行卡「每局清零」故意相反 —— 这是剧情进度）。
- **这场戏是用户 2026-11-05 亲手写的，台词逐字照抄**：
  > 爱丽丝：我想要这个
  > 凯伊：9178万
  > 爱丽丝：凯伊～便宜点～球球了 （づ￣3￣）づ╭♥～
  > 凯伊：好...好吧
  > → 扣除银行卡**所有**钱，爱丽丝获得修复完好的阿比舒机甲。

  ⚠️ 所以**没有固定价**：`mech_state.gd` 的 `QUOTE_YUAN = 91780000` 与
  `kei_npc.gd` 的 `QUOTE_TEXT = "9178万"` **只用来念**，成交价永远是「卡上现有的全部」
  （`BankCard.set_balance(0)`）。卡上 0 元时**不成交**（凯伊吐槽一句），不能白送。
  ⚠️ 刷卡前本喵加了一道「成交！（把卡刷光）／等等，我再想想」的确认 ——
  不然按一下 F 就把卡刷光，玩家连发生了什么都不清楚；**台词一句没改**。
  ⚠️ 颜文字里的 `❤`(U+2764) 换成了 `♥`(U+2665)：`assets/ui/font.ttf` 有 36558 个字形
  却**恰好没有 U+2764**（cmap 实测），直接写会渲染成空白。其余字符（`（づ￣3￣）づ╭～`）都在。
- `scripts/carrier_form.gd` + `player.tscn` 里新增 `Arisu/CarrierForm` 节点：**按 G 变形**。
  它**不接 `AnimDriver`** —— 载具那套只有 `Idle`/`Walk` 两条动作，接驱动会缺
  `Normal_Idle`/`Normal_Attack_Ing`/`Move_Ing`；所以自己按移动速度在两条之间交叉淡化。
  模型不在时（本地素材，不进仓库）按 G 只打 warning，不崩。
- 设置菜单的按键说明补了 `F 交互` 与 `G 变形`。

**headless 自检**：`scripts/_verify_kei_npc.gd`（不开窗口），全过：
节点/模型/AnimDriver 就位；站桩 + 落地 + 水平偏移 0.00 m；DialogueBox 在；
搭话能起；**付款回调扣款 ¥52 万准确、钱不够不扣不解锁**；载具未解锁时变不了、
解锁后能建出来（`Idle`/`Walk`）并能变回本体；跑完把 `mech.cfg` 与银行卡还原。

**两个踩过的坑**
1. ⚠️ `kei_npc.gd` 里**不能有和父类同名的成员**（第一版写了 `var _player`，
   父类 `companion.gd` 已有 → 整份脚本 `Parse Error` 加载失败，
   表现是「节点在、脚本没挂上、按 F 毫无反应」）。现在叫 `_talk_player`。
2. ⚠️ 探针里任何一步报错都会让 `_run()` 中断、`quit()` 走不到 → **挂死 10 分钟**。
   现在 `_verify_kei_npc.gd` 带 90 s 看门狗。

**还没验的（要看画面）**：载具模型的**朝向**（`carrier_form.gd` 的 `facing_yaw_deg`，默认 0）
与**缩放**（`carrier_scale`，默认 1.0）本喵没在窗口里看过 —— 可能倒着走或大小不对，改这两个数即可。

## 16. 显存/性能实测：钱花在哪（2026-11-05）

用户反馈：「为什么这么透明这高斯 / 物体怎么这么多 / fps 跑不到 165 / 缩放 0.5 还行、
开 1.0 掉到 7 fps、F3 显存 6918 MiB」。为此写了一组**离屏真窗口**的探针（都不抢前台）：

| 探针 | 干什么 |
|---|---|
| `_probe_vram_cost.gd` | 四段：进场景 / 泼溅就绪 / 缩放 0.5 / 缩放 1.0 |
| `_probe_vram_trace.gd` | 从第 0 帧起每 15 帧记一次，**并拆纹理/缓冲** |
| `_probe_scene_budget.gd` | 逐个副场景量（找大头） |
| `_probe_vram_leak.gd` | 场景 1 → 场景 2 → 场景 1，看有没有泄漏 |
| `_probe_vram_switch.gd` | 校园里连跨 9 格，看换窗口漏不漏 |
| `_verify_scene_cost.gd` | **headless**：数网格/顶点/唯一贴图 |

**实测（离屏 1920×1080，关 vsync、fps_limit=0）**

| 状态 | 总显存 | 纹理 | 缓冲 |
|---|---|---|---|
| 空引擎 + 相机 | 74 MiB | 44 | 26 |
| 场景 1（`--splat=off`） | **866 MiB** | 555 | 48 |
| 场景 1 + 画室609 | **3069 MiB** | 598 | **1312** |

→ **画室609 这一份泼溅 = +2203 MiB**，其中**缓冲 +1264 MiB**（和按代码算的一致：
splats 60 float×4 B = 665 MB、sort_keys+sort_values（10 倍元素×8 B×2）= 443 MB、
culled_splats 177 MB…），其余约 900 MiB 是引擎侧渲染目标（纹理/缓冲两栏都没算进去）。

**逐项排掉的嫌疑（都不是问题）**
- **副场景**：全部加起来只 **315 MiB**（parkour 197 最大，esports 26、shop 8、gamedev 6、hud 1、player 2）。
- **几何**：整个场景 32 万顶点 / 104 万索引 ≈ **14 MiB**；833 个网格里 765 个是内置盒子。
- **贴图**：唯一贴图 22 张 ≈ **60 MiB**（最大的几张是 SSD 的 2922×802 JPG）。
- **跨场景泄漏**：①3069 → ②校园 2710 → ③回场景 1 **3076（只差 7 MiB）** —— 没有泄漏。
- **换窗口泄漏**：193 → 1944 → 2133，之后连跨 7 格**一直持平** —— 没有泄漏。

**结论**
1. **泼溅自己就是 2.2 GB**，是真正的显存大头；场景内容反而很省（<100 MiB）。
2. 用户那台 8 GB 的卡上，Windows + 浏览器 + OBS 常驻再吃掉 2~3 GB，
   于是「2.2 GB 泼溅 + 0.87 GB 底子 + 引擎目标」已经贴着上限 ——
   **缩放从 0.5 拉到 1.0 时再多要渲染目标就爆了 → 7 fps 是爆显存，不是「像素多 4 倍」能解释的**。
3. **用户报的 6918 MiB 本喵复现不出来**（同一份工程本机只有 3069 MiB）。
   待问：当时窗口分辨率？是否刚从校园回来/逛了很久？OBS 在录？——
   这三条任一都可能是差额来源。**在问到之前不要瞎改。**

**已改的**（用户 2026-11-05 批准「把覆盖率提实」）
- `addons/gdgs/.../gsplat_render.glsl`：`final_alpha = 1-t` 之后做一次 γ 提升
  `α' = 1-(1-α)^2`（0.3→0.51、0.5→0.75、0.7→0.91），并把颜色**按原始 α 反预乘、再按新 α 重预乘**
  （不这么做整片会变暗）。合成是 alpha-over（`gaussian_composite.glsl:119`），
  扫描的 α 在斜面/稀疏处只有 0.3~0.7 → 背后天空/几何透出来 = 用户看到的「透明」。
  想回原样：把该文件的 `COVERAGE_LIFT` 改回 `1.0`。

**还没做的**：GDGS 渲染路径**没有抽稀开关**（只有碰撞管线有 stride）。
要减这 2.2 GB 只能：① 重新导出一份更稀的 `room609.sogdata`；
② 在 `splat_scene.gd` 上传前按 stride 抽样（改动小、但要开窗口看观感）。

## 17. 继续优化（2026-11-05 晚）：**不碰泼溅观感**的前提下把帧时间和卡顿压下去

用户指令原话：「能不能继续优化，现在好卡，**但是不能改高斯泼溅因为这效果已经很差了**」。
所以这一轮只动「非观感」的东西：**重复劳动**、**显存浪费**、**主线程阻塞**。

### 一、先把「卡在哪」量准

`scripts/_probe_frame_cost.gd`（离屏真窗口，关 vsync、`Engine.max_fps = 0`，
逐项关阴影/SSAO/辉光/雾/MSAA）。**探针把窗口最大化之后拿到了用户实机的分辨率
2800×1171，日志里也露出了显卡型号：RTX 4060 Laptop（8 GB）。**

| 档 | p50 | fps | draw call | 显存 |
|---|---|---|---|---|
| 现状（全开 + 泼溅） | **13.05 ms** | 77 | 957 | 3052 MiB |
| 关定向光阴影 | 12.34 | 80 | **342** | 3052 |
| 阴影最大距离 60→25 | 12.83 | 78 | 719 | 3052 |
| 软阴影滤波 3→0 | 13.06 | 77 | 938 | 3052 |
| 关 SSAO / 辉光 / 雾（单个） | 12.86~13.08 | ~77 | 938 | 3052 |
| 关全部后处理 | 12.46 | 80 | 937 | 3052 |
| 关 MSAA | 12.51 | 80 | 937 | 2988 |
| 关阴影 + 关全部后处理 | 12.10 | 84 | 323 | 3017 |
| **`--splat=off`** | **5.06** | **189** | 975 | 875 |

**结论：泼溅一个人吃掉 +8.0 ms（整帧的 61%）。** 阴影只值 0.71 ms、后处理 0.59 ms、
MSAA 0.54 ms —— **不值得为这 1.8 ms 牺牲画面**。注意 957 个 draw call 里有 **615 个是阴影 pass**。

### 二、再把这 8 ms 拆开

`scripts/_probe_splat_scaling.gd` + `_tools/_run_splat_split.sh`：
扫 0.25 / 0.5 / 1.0 三档缩放（像素数变、点数不变），配合 `--gdgs-skip-sort`
（⚠️ 只用于测量，画面是错的）与 `--splat=off`：

| 缩放 | 正常 | 跳排序 | 关泼溅 |
|---|---|---|---|
| 0.25（~700×280） | 10.93 ms | 7.08 | 4.90 |
| 1.00（2800×1119） | — | 11.62 | 5.87 |

→ **基数排序 ≈ 3.9 ms 且与像素数无关**；投影 + 边界 + raster ≈ 2.2 ms（小视口）
到 5.7 ms（全分辨率）。**排序就是那 8 ms 里最大的一块，而它只在相机动了之后才有意义。**

### 三、改了什么（四处，全部可回退）

**① 静止帧复用**（`gdgs` 的 `gaussian_renderer.gd` + `ggs_campus` 的
`gaussian_splatting_rasterizer.gd`）

相机 / 视口 / 光照 / 入场动画都没变的那一帧，**整条 compute 链直接不跑**，把上一帧的
纹理交回去。判据是**精确等价**，不是近似：

- `gsplat_render.glsl` 对 tile 内**每个像素**都 `imageStore`（颜色 + 深度）⇒ 纹理是全量重写的；
- 唯一的非相机输入是 `uniforms.w = time`，而它只喂入场动画（`time - splat.time`）。

**实测（`_probe_frame_cost.gd`，2090×1050，同一进程内 A/B）**

| | p50 | fps |
|---|---|---|
| 复用关 | 11.37 ms | 88 |
| **复用开** | **4.33 ms** | **191** |

⚠️ 两个坑，都踩过：

1. **不加光照容差就完全无效。** `TimeOfDay` 默认 `day_minutes = 20` ⇒ 太阳**每帧都在动**
   ⇒ `refresh_relight()` 每帧判「变了」⇒ 每帧上传 relight ⇒ 复用永远进不去。
   实测开关复用**一模一样**（11.25 vs 11.37 ms）就是因为它压根没生效。
   现在 `gaussian_light_rig.gd` 用**带容差**的比较（`RELIGHT_EPSILON = 1e-3`
   ≈ 方向 0.057°、颜色/能量 0.1%、位置 1 mm；太阳 0.3°/s 所以约 0.19 s 过一次）。
   回到逐字节比较：`-- --gdgs-relight-eps=0`。
2. **「入场动画落定」必须按数据算。** 原来拍了个固定 2.5 s，而
   `splat.time` 的 max 才决定动画什么时候结束。现在从点数据里抽样读出
   `max(time)`（只统计 `t <= now` 的，因为**导出数据里有天文数字时间字段**，
   实测把 `int()` 撑溢出成 `-9223372036854776.0 s`），再 +1.35 s +0.4 s 余量。
   拍短了会把动画冻在半透明状态，那是看得出来的 bug。

**验收的坑：泼溅本身每帧都不一样，所以「逐字节相同」不是可用判据。**

`_verify_idle_skip.gd` 一开始按「复用关着连抓两帧必须逐字节相同」做基准，一直 FAIL。
逐项排查（抓图自证同一帧连读两次 → 相同 ✓；停掉 3419 个节点的 `_process`、
暂停动画、停粒子、藏 5 个 CanvasLayer、杀 Tween、切合成器 `DIRECT_TEXTURE`
只显示泼溅层 → **仍然每帧差 12 万字节、最大通道差 ~100**）之后定性：

> **GPU 基数排序按 key 分桶用的是原子操作，深度量化后大量高斯 key 相同，
> 它们之间的相对顺序不确定；而 alpha-over 累加对顺序敏感 ⇒ 「同样输入、
> 各自完整重算」的两帧本来就不同。**

所以判据改成**噪声底比较**：先量「重算 vs 重算」的差，再量「复用 vs 重算」的差，
后者不得超过前者。噪声底为 0（确定性渲染）时自动退化成「必须逐字节相同」。
副作用：这也说明**留着上一帧的排序顺序，不会比重新排一次更差**。

**最终验收结果**（`_tools/run_shot.sh res://scripts/_verify_idle_skip.gd`）：

```
抓图自证（同一帧连读两次）：逐字节相同 ✓
噪声底（重算 vs 重算）：121655 字节不同（最大通道差 105）
PASS：复用帧 vs 重算帧 = 0 字节不同（最大通道差 0）
结论：通过
```

即：**跳过时交回来的就是「上一帧刚重算出来的那一张纹理，一个字节都没改」** ——
比「和重算一样」更强。另外三条自证也在日志里：
「同一帧连读两次相同」（抓图可靠）、「合成器切到 DIRECT_TEXTURE 成功」（只比泼溅层）、
「泼溅 time 字段 max 0.000、入场动画在 1.4 s 结束、余量 6.5 s」（入场动画确实落定了）。

**② RenderState 缓存上限 4 → 2，且「先淘汰再新建」**
（`gaussian_gpu_state_cache.gd`）

**每个 RenderState 自带一整套泼溅 GPU 缓冲，画室609 一份就是 1.28 GB**
（splats 665 + culled 177 + sort_keys 221 + sort_values 221）。上限 4 ⇒ 最多 5.1 GB。

`_probe_render_states.gd` 复现：在「3D 缩放」上换几个值，显存从 3052 MiB 涨到
**6857 MiB**、帧时间从 13 ms 崩到 **102 ms** ——
**用户报的「F3 显存 6918 MiB / 开 1 就 7 fps」就是这个**（§16 里挂着的那个问题，有答案了）。
改完：来回切 6 次 + 5 个不同缩放，`state 数恒为 2`，显存 4260~4424 MiB。

**③ 大缓冲不填零**（`render_context.gd` / `gaussian_rendering_device_context.gd`
新增 `zero_fill` 参数）

`create_storage_buffer()` 原来给每个缓冲都准备一份**等长的零数组**再交给
`storage_buffer_create` —— 几百 MB 的 malloc + 清零 + 上传纯属白做。而
`splats`（上传时全写）、`culled_splats`（投影只写发出的条目）、
`sort_keys`/`sort_values`（基数排序只碰 `[0, element_count)`，`element_count`
每帧由 CPU 清 0）在用之前都会被整份覆盖。

**实测 `init_gpu`：**

| 缓冲 | 改前 | 改后 |
|---|---|---|
| 205 MB | 364.5 ms | 139 ms（含首次预热） |
| 234 MB | 257.6 ms | 19.8 ms |
| 456 MB | 551.4 ms | 24.3 ms |
| **644 MB** | **732.7 ms** | **25.9 ms** |

`output` 拆开看：缓冲分配 24.8 ms、管线（6 个着色器）**0.1 ms** —— 着色器有磁盘缓存，
钱全在填零上。⚠️ `splat_lighting` **保持填零**（没烘光照时上传会直接返回，
留下垃圾数据会让着色器当光照用）。

**④ 换窗口：后台拼 bin + 双缓冲 + 分帧预算上传 + `fine_ready`**
（`campus_ggs.gd` + `gaussian_splatting_rasterizer.gd` + `main_sky.gdshader`）

原来是主线程同步拷 100~280 MB（`_write_window` 实测 92~124 ms）、
然后 `_pump_bin` 一帧吐 64 MB（**实测单帧最坏 550 ms**）。现在：

- 双缓冲 `user://campus_window_a.bin` / `_b.bin`，`Thread` 在后台写，
  当前窗口继续渲染，主线程一次都不阻塞（日志：`窗口切换 → N 块 / X MB（后台拼好，主线程没停）`）；
- 上传改成**按时间预算 + 自适应块大小**（起始 1 MB，实测吞吐 1~2 MB/ms，
  控制器把块收到「一块 ≈ 4 ms」）：**单帧 550 ms → 1~6 帧，最坏单块 4~29 ms**；
- 新纹理先清成透明，并用 `main_sky.gdshader` 的 `fine_ready` 在细层没就绪时
  **完全不采它**；释放细层时把 quad 的 `render_texture` 槽位临时指到粗层那张合法纹理上
  （否则悬空绑定会报 `Uniforms supplied for set`）。

### 五、效果与残留

这个报错**在本轮优化之前就有**，每次换窗口出现一次。查下来是同一个错误模式，
在四处各有一份，全都是对 `Texture2DRD.texture_rd_rid` 的误解：

> **`texture_rd_rid` 是「拥有权」，不是指针。给它赋值会把原来持有的那个 RID 释放掉。**

于是「先释放纹理、再摘引用」就变成双重释放。四处：

| 位置 | 原写法 | 问题 |
|---|---|---|
| `campus_ggs.gd::_release_campus`（**本轮新引入**） | `tex.texture_rd_rid = 粗层 RID` | 赋值先释放细层 RID，紧接着 `ctx.free()` 再释放一遍 |
| `campus_ggs.gd::_release_campus`（老） | `tex.texture_rd_rid = RID()` | 同上，与 `ctx.free()` 撞 |
| `gaussian_splatting_rasterizer.gd::cleanup_gpu`（老） | `context.free()` 后再 `render_texture.texture_rd_rid = RID()` | 顺序反了 |
| `gaussian_splatting_rasterizer.gd` 的 `texture_size` setter（老，原注释 `# FIXME: idk why I have to do this`） | 每次改尺寸都 `render_texture = Texture2DRD.new()` | 把调用方持有的对象换掉，调用方再把 `texture_rd_rid` 指过来 → 又释放一个已还的 RID |

**改法**

1. `_release_campus()` 两个分支都**不再碰 `tex` / `coarse_tex` 的 RID**，只丢弃引用
   （纹理由光栅器 `cleanup_gpu()` 还）。quad 不会采到悬空纹理 —— `fine_ready = 0`
   时着色器整个跳过采样。
2. `cleanup_gpu()` **先还纹理再 `context.free()`**。
3. `texture_size` setter **不再新建 `Texture2DRD`**：只是换了一张纹理，对象可以复用。
4. `init_gpu()` 与 setter 里赋值前**先 `if texture_rd_rid.is_valid(): = RID()` 兜底**。
5. `_exit_tree()` 里**显式同步**拆 quad（先 `set_shader_parameter(..., null)`，
   再 `free()`），否则 `queue_free()` 要等帧末、而纹理已经还掉了，中间那一瞬
   会报 `Texture (binding: 2, index 0) is not a valid texture` + `Parameter "us" is null`。

**结果**（`_probe_switch_hitch.gd`，连跑两次）：

```
invalid ID        : 0      （原来每次换窗口 1 条）
not a valid texture: 0
Parameter "us" is null: 0
SCRIPT / Parse Error : 0
```

副作用：换窗口最坏帧也跟着降了 —— **48~169 ms**（原 117~560 ms）。
原因大概率是「不再每帧重建 `Texture2DRD` + 不再触发无效 uniform set」，
少了两处 GPU 侧的隐式重建。阶段 B 的上传已经降到 **71.6 ms**。



**换窗口最坏一帧：199~842 ms → 117~158 ms**（同一探针、同一条路径）。

**残留**

1. 那 117~158 ms 大致是 `init_gpu`（26）+ `_release_campus`（31）+ 首块上传（29）
   落在同一帧。要再往下压只剩一条路：**换窗口时不要重建光栅器** ——
   把缓冲按「最大窗口」一次性分配、窗口 bin 补零到固定点数、切窗口只换 bin 重传。
   代价是常驻显存变高（~700 MB）、投影每帧多跑一点。
2. ~~每次释放 GGS 资源都会报一次 `ERROR: Attempted to free invalid ID: ...`~~
   —— **2026-11-06 已查清并修掉，见 §17 六**。
3. ~~**逐像素校验还没通过**~~ —— 已通过（判据换成噪声底，见上面「验收的坑」）。

### 六、`Attempted to free invalid ID` 的真凶（2026-11-06）

这个报错**在本轮优化之前就有**，每次换窗口出现一次。查下来是同一个错误模式，
在四处各有一份，全都是对 `Texture2DRD.texture_rd_rid` 的误解：

> **`texture_rd_rid` 是「拥有权」，不是指针。给它赋值会把原来持有的那个 RID 释放掉。**

于是「先释放纹理、再摘引用」就变成双重释放。四处：

| 位置 | 原写法 | 问题 |
|---|---|---|
| `campus_ggs.gd::_release_campus`（**本轮新引入**） | `tex.texture_rd_rid = 粗层 RID` | 赋值先释放细层 RID，紧接着 `ctx.free()` 再释放一遍 |
| `campus_ggs.gd::_release_campus`（老） | `tex.texture_rd_rid = RID()` | 同上，与 `ctx.free()` 撞 |
| `gaussian_splatting_rasterizer.gd::cleanup_gpu`（老） | `context.free()` 后再 `render_texture.texture_rd_rid = RID()` | 顺序反了 |
| `gaussian_splatting_rasterizer.gd` 的 `texture_size` setter（老，原注释 `# FIXME: idk why I have to do this`） | 每次改尺寸都 `render_texture = Texture2DRD.new()` | 把调用方持有的对象换掉，调用方再把 `texture_rd_rid` 指过来 → 又释放一个已还的 RID |

**改法**

1. `_release_campus()` 两个分支都**不再碰 `tex` / `coarse_tex` 的 RID**，只丢弃引用
   （纹理由光栅器 `cleanup_gpu()` 还）。quad 不会采到悬空纹理 —— `fine_ready = 0`
   时着色器整个跳过采样。
2. `cleanup_gpu()` **先还纹理再 `context.free()`**。
3. `texture_size` setter **不再新建 `Texture2DRD`**：只是换了一张纹理，对象可以复用。
4. `init_gpu()` 与 setter 里赋值前**先 `if texture_rd_rid.is_valid(): = RID()` 兜底**。
5. `_exit_tree()` 里**显式同步**拆 quad（先 `set_shader_parameter(..., null)`，
   再 `free()`），否则 `queue_free()` 要等帧末、而纹理已经还掉了，中间那一瞬
   会报 `Texture (binding: 2, index 0) is not a valid texture` + `Parameter "us" is null`。

**结果**（`_probe_switch_hitch.gd`，连跑两次）：

```
invalid ID           : 0      （原来每次换窗口 1 条）
not a valid texture  : 0
Parameter "us" is null: 0
SCRIPT / Parse Error : 0
```

副作用：换窗口最坏帧也跟着降了 —— **48~169 ms**（原 117~560 ms）。
原因大概率是「不再每帧重建 `Texture2DRD` + 不再触发无效 uniform set」，
少了两处 GPU 侧的隐式重建。阶段 B 的上传已经降到 **71.6 ms**。

### 七、这一轮的验收入口

| 脚本 | 作用 |
|---|---|
| `_probe_frame_cost.gd` | 逐项关阴影/后处理/MSAA，量 p50/p99/draw/显存 |
| `_probe_splat_scaling.gd` + `_tools/_run_splat_split.sh` | 按缩放把「排序 / 投影+raster」拆开 |
| `_probe_render_states.gd` | 复现显存暴涨，看 RenderState 份数 |
| `_probe_switch_hitch.gd` | 换窗口分段计时（拼 bin / 释放 / 建光栅器 / 上传） |
| `_verify_idle_skip.gd` | 静止帧复用的逐像素校验（含「抓图自证」「噪声底」两道前置自证） |
| `_tools/_run_frame_cost.sh` | 跑 §17 一的表 |
| `_tools/_run_splat_split.sh` | 跑 §17 二的表 |
| `_tools/_run_idle_ab.sh` | 复用开/关同进程 A/B（§17 三① 的表） |
| `_tools/_run_hitch.sh` | 冒烟 + 换窗口分段计时 |
| CLI | `--gdgs-idle-skip=off`、`--gdgs-skip-sort`、`--gdgs-relight-eps=0`、`--ggs-idle-skip=off` |

## 18. 出画室609 就释放泼溅显存（2026-11-06）

用户原话：「好卡啊,能不能不动高斯泼溅情况下,降低显存,只在609内部开,出去直接释放显存,
设置可以开关这个选项,默认关闭,如果打开就是显存很友好,但是每次进入609要加载」。

**完全不动观感** —— 这个功能只决定「泼溅在不在」，不改任何渲染参数。

### 一、机制

`GameSettings` 新键 `"splat_unload_outside"`，**默认 false**（= 以前的行为：常驻不还）。
设置界面在「画面」分组最后，标签「出画室609 就释放泼溅显存（进 609 需重新加载）」。

打开后，`splat_scene.gd::_update_room_exit_unload()` 每帧判玩家在不在房间的水平范围内：
- **在范围外满 `unload_delay = 1.5 s`** → `_unload_for_vram()`：把 `splat_node`
  `queue_free()`。`GaussianSplatNode._exit_tree()` → `unregister_splat_node()` →
  注册表发现「一个泼溅节点都不剩」→ 返回 `request_cleanup` →
  `GaussianGpuStateCache.cleanup_all()` 把整份 1.28 GB 缓冲还掉。
- **回范围内满 `reload_delay = 0.4 s`** → `_reload_after_unload()`：后台重解码。

⚠️ **`visible = false` 不还显存** —— 必须真的释放节点。这是这个功能能成立的全部前提。

### 二、实测（`_verify_splat_unload.gd`，离屏真窗口，1280×720 / 0.5 缩放）

```
① 设置默认值 = false              ✓
② 开关关着、走到室外 3 s：节点仍在  ✓（行为未改变）
③ 打开后走出范围：
     节点已释放 = true            ✓
     显存 2271 MiB → 938 MiB      ✓（Δ −1333 MiB）
④ 回到范围：自动重载 = true，用时 2.9 s   ✓（显存回到 2271 MiB）
⑤ 关掉开关后仍有点云 = true        ✓
结论：全部通过
```

**省 1.33 GB**，代价是每次进 609 等 **2.9 s**（缓存命中）。这正是用户要的取舍。

### 三、踩到的四个坑（都很隐蔽，值得记）

1. **回调签名必须吃 `(key, v)` 两个参数。**
   `GameSettings._emit()` 调的是 `cb.call(key, v)`。本喵第一版写 `_on_settings_changed()`，
   被引擎判 `Invalid call ... Expected 0 argument(s)`，**静默失效** —— 设置改了、
   `unload_outside_room` 一直是 false，看起来像「功能没写对」。
2. **房间边界不能用 `content_world_aabb()`。** 那是 `crop` 之后的**内容**盒，
   实测只有 9.3 × 7.9 m；点云整体是 23.9 × 8.3 × 27.2 m。用内容盒判内外，
   玩家站在房间角落就被判「在外面」→ 原地反复释放/重载。
3. **边界变换要用 `_local_basis()` + `_resolve_offset()`，不是 `global_transform`。**
   缩放由 `_local_basis()` 自己带（`world_scale = 4.25`），`splat_scene.gd` 节点本身
   没有缩放；用 `global_transform` 等于只乘一次，算出来偏小。本喵第一版得到
   x −5.1~5.2 / z −4.5~4.7（真实的 1/4.25 倍）。正确结果是
   **x −18.0~16.4 / z −14.6~22.5**（含 2 m 余量）。
4. **探针里挪玩家会掉进虚空。** 直接改 `global_position` 到 40 m 外，玩家 y 一路
   −0.8 → −4.5 → −9，然后 `_die_and_respawn()` 把它送回存档点 `(-15, 0, 4)`
   —— 那是房间**里面**，于是「出房间」永远不成立。验收里必须
   `set_physics_process(false)`。

另外两个小坑：`Rect2` **没有** `snappedf()`（写了会让整份脚本解析失败、
所有字段变 null）；探针等「网络延迟秒数」必须按 `Time.get_ticks_msec()` 计，
数帧不可靠（一帧才 0.1 ms，200 帧 = 0.02 秒，永远等不到 1.5 s）。

### 四、验收入口

| 脚本 | 作用 |
|---|---|
| `_verify_splat_unload.gd` | 五步验收（默认值 / 关着不释放 / 释放且显存下降 / 自动重载 / 关闭可恢复） |
| `_probe_room609_bounds.gd` | headless 量出画室609 的世界包围盒（定边界用） |
| CLI | 设置项本身；探针会自动写回 false 清理 |

## 19. 高面数场景优化手册 + 爱给网那套电竞酒店（2026-11-06）

用户：「你学习一下 godot 的优化，我这里有一个很多面数的电竞酒店」，随后给了
`C:\Users\WY157\Downloads\现代网咖_电竞酒店套房_宿舍上下铺_爱给网_aigei_com.zip`（333 MB）。

**完整手册写在 `优化手册-高面数场景.md`**（工程根目录），下面是结论摘要。

### 一、素材现状：**.max 是硬阻塞**

那个压缩包里 **113 个条目，只有一个工程文件**：

```
817,763,092 字節  06/h06_m210903.max      ← 3ds Max 工程
                + 111 张贴图（57.7 MB）
```

**没有 FBX / OBJ / GLB / DAE**。而：
- Godot **不支持** `.max`
- Blender **也不支持** `.max`（没有原生导入器）
- 本机**没装 3ds Max**（`C:\Program Files\Autodesk` 与 `D:\SOFTWARE` 下都没有）

⇒ **必须在有 3ds Max 的机器上导出 FBX**（导出时选厘米/米要看清楚，
   建筑可视化的单位错一位数会让整个房间缩放成 100 倍或 1%）。
贴图已经先提取到 `C:\Users\WY157\Desktop\GODOT\_aigei_esports`（111 张 / 57.7 MB），
FBX 一到就能直接跑管线。

### 二、量出来的三件事（都改了工程里的探针）

**① 现有电竞房：三角数不重，draw call 重**

`_probe_mesh_budget.gd`（headless，直接 `ClassDB` 问引擎 + 遍历场景）：

```
网格节点 385 | 总顶点 309,962 | 总三角 332,440
表面（≈ draw call 下限）499 | 唯一 Mesh 339 | **唯一材质 24**
→ 按材质合并的上限：draw call 499 → ≤24（少 20 倍）
```

**② 86% 的三角是重复实例**

`_probe_mesh_dupes.gd`：385 节点里只有 339 个唯一 Mesh，重复的 7 组里
最大的两坨是 **×7 把椅子（19,304 三角/份，浪费 115,824）** 和
**×16 张 5090 显卡（6,854 三角/份，浪费 102,810）**。

⚠️ 别被这个数字骗了：**共享 Mesh 资源本来就只占一份显存**，
省的是 draw call 和主线程提交，不是显存。

**③ 贴图才是显存大头**

那套贴图 108 张可读尺寸，**105.8 M 像素**：

| | 显存 |
|---|---|
| 全分辨率 RGBA8（不含 mip） | **403.5 MB** |
| 带 mipmap（×1.33） | **537.8 MB** |
| 缩到 2048 上限（实测跑过 dry-run） | 237.9 MB |
| 再叠 VRAM 压缩 BC1 | **约 40 MB** |

单张 `JS026.jpg` 就是 **8014×3069**（一张 98 MB 显存）。

### 三、引擎能力：不信文档，直接问 `ClassDB`（Godot 4.7.1）

```
GeometryInstance3D  ✓ visibility_range_begin / _begin_margin / _end / _end_margin
                    ✓ visibility_range_fade_mode (DISABLED=0 / SELF=1 / DEPENDENCIES=2)
                    ✓ lod_bias (默认 1.0)   ✓ ignore_occlusion_culling (默认 false)
OccluderInstance3D  ✓ bake_simplification_distance (默认 0.1)
渲染全局            rendering/mesh_lod/lod_change/threshold_pixels = 1.0
                    **rendering/occlusion_culling/use_occlusion_culling = false**  ← 本工程是关的
```

`project.godot` 的 `[rendering]` 段只设了软阴影质量和清屏色，**确实没开遮挡剔除**。
室内场景（电竞房/画室/小屋）最吃这一条：在房间里看柜子时，门外那片校园不该被提交。

### 四、两个新工具（都实测跑通过）

| 脚本 | 干什么 |
|---|---|
| `_tools/opt_archviz.py` | Blender 5.2：FBX/OBJ/GLB 进 → **按材质合并** + 删小件 + 可选减面 → GLB 出 |
| `_tools/opt_archviz_textures.py` | Pillow：按上限缩贴图，报「省多少显存」，`--dry-run` 只报账 |

**实测验证**（拿工程里现成的 `models/_wip_hotel/hotel_782061.glb`，1,787,204 三角）：

```
导入后   物件 66 | 三角 1,787,204 | 表面 67 | 材质 7
按材质合并后 物件  7 | 三角 1,787,204 | 表面  8 | 材质 7
表面数 67 → 8（11.9%）    三角数 100.0%（几何一个字节没动）
导出 hotel_opt.glb（60.5 MB）  ✓ 端到端跑通
```

⚠️ 已知噪音：Blender 启动时报一堆 `BlenderGIS-2210` / `arp_debug_mode` 的
`AttributeError` —— 那是**用户装的第三方插件**和 Blender 5.2 不兼容，与本脚本无关。

### 五、落地顺序（按性价比）

1. `--report` 体检（知道瓶颈在面数、draw call 还是显存）
2. **按材质合并** —— 不改观感，draw call 砍一个数量级
3. **贴图缩尺寸 + VRAM 压缩** —— 显存砍到 1/5~1/10
4. **开遮挡剔除** —— 室内白捡
5. 重复物件上 MultiMesh（同款 ≥10 个才值得）
6. 还卡再减面 / 删小件 / LOD
7. **最后**才动后处理（唯一真会降观感的）

⚠️ 每一步之后都要重量一次。改完不量等于不知道有没有用。

## 20. 爱给网电竞酒店：从 890 万面跑通到 341 万（2026-11-06）

用户给了 `Untitled.fbx`（238 MB，从原来那个只有 `.max` 的包里导出来的）。

### 一、实测流水线（每一档都量过）

`_tools/opt_archviz.py` + `_tools/patch_glb_import.py`：

| 阶段 | 三角 | 顶点 | 显存（模型自己） | draw call | GLB |
|---|---|---|---|---|---|
| 原始 FBX（只按材质合并） | 8,888,803 | 5,564,195 | **+787 MiB** | 89 | 293 MB |
| ＋自适应减面 | 3,413,264 | 2,709,373 | **+407 MiB** | 89 | 130.6 MB |
| ＋贴图缩到 1024 | 3,413,264 | 2,709,373 | **+272 MiB** | 89 | **122.4 MB** |

**合计：三角 −62%、显存 −65%、draw call 1349 → 89（−93%）**。

**观感**（同机位同光照渲染后逐像素比对）：

| 对比 | 完全相同像素 | 平均绝对差 | 差>32 的像素 |
|---|---|---|---|
| 减面版 vs 原版 | **95.43%** | 0.179 | 0.113% |
| 最终版 vs 原版 | 84.70% | 0.770 | **0.279%** |

### 二、五个必须记住的坑

**① FBX 单位是厘米，Godot 当成米 ⇒ 模型变成 7.8 公里。**

包围盒实测 `7813 × 4121 × 7683 m`，正确应该是 `78.14 × 41.22 × 76.84 m`。
**不要在代码里 `scale = 0.01`** —— 用导入设置：
`nodes/root_scale = 0.01` + `nodes/apply_root_scale = true`。
`_tools/patch_glb_import.py --apply --root-scale=0.01` 一条命令搞定。

**② `meshes/ensure_tangents = true` 白烧 41 MB。**
2,709,373 顶点 × 16 B/切线 ≈ 41 MB。没有法线贴图就关掉（`--no-tangents`）。

**③ 贴图必须在 Blender 导出前缩，不能等进 Godot。**
GLB 是**内嵌贴图**的，导出之后在 Godot 里改很麻烦（`.import` 的 `_subresources`
键名难手写）。实测 `--texture-cap=1024`：32.4 M 像素 → 16.5 M，165 MB → 84 MB。
⚠️ 注意 Blender 的 `image.scale()` 只改内存，**必须 `img.pack()` 才落进 GLB**。

**④ 减面顺序：先减面、再合并。**
合并之后每个物件变成「材质大杂烩」，就没法按单个物件的面数决定减多狠了
（地毯该砍 94%、墙一点都不该动）。本脚本的 `main()` 里已经是对的。

**⑤ 自适应减面的档位**（`ADAPTIVE_TIERS`）：这模型的三角分布极不均匀——
**21 个物件占 42.1%**，630 个 <1000 面的小件加起来才 6.2%。最重的是：

```
Circle019 / Circle021      各 478,834 三角  ← 圆形地毯 → 砍到 6%（36,174）
JJKJ213 / JJKJ214          各 224,047 三角  ← 砍到 6%
JS2973/3034/3095/3156      各 142,648 三角  ← 砍到 20%
odeyalo048/049/050/051     各 123,300 三角  ← 毯子（俄文 одеяло）→ 20%
```

**地毯做到 47 万面**是扫描/布料模拟直接倒出来的，玩家俯视根本看不出。
而**墙、地板、大台面一点没动**（低于 8000 面的物件完全不碰）。

### 三、一个「以为是 bug」其实不是

第一版渲染出来左侧木饰面板呈**扇形破碎状**（`_log/preview_hotel_close.png`），
本喵以为是减面搞坏的。做了「只合并不减面」的对照组之后：
**两张图 95.43% 像素完全相同**，扇形是**原模型本身的造型**（竖木格栅）。
⇒ 减面没有破坏任何东西。**这条经验很重要：怀疑优化破坏观感时，先做对照组。**
**但它暴露了另一个真问题**：那个木格栅在 Godot 里看着像坏的，可能需要美术确认。

### 四、新工具（`_tools/`）

| 脚本 | 干什么 |
|---|---|
| `opt_archviz.py` | FBX/OBJ/GLB → 删小件 + 自适应减面 + 按材质合并 + 缩贴图 → GLB |
| `inspect_archviz.py` | 体检：三角分布分桶、最重物件、材质用量、贴图像素负担 |
| `patch_glb_import.py` | 改 `.glb.import`：root_scale 修单位、关切线、（提示）VRAM 压缩 |
| `opt_archviz_textures.py` | 外部贴图批量缩尺寸 + 报省多少显存（支持 `--dry-run`） |

探针：

| 脚本 | 干什么 |
|---|---|
| `_probe_mesh_budget.gd` | ClassDB 盘点引擎能力 + 场景网格/表面/材质预算 |
| `_probe_mesh_dupes.gd` | 重复网格盘点（MultiMesh/实例化机会） |
| `_probe_model_cost.gd` | 任意模型在 Godot 里的**真实**成本（显存/draw call/帧时间） |
| `_probe_model_preview.gd` | 3/4 透视出图（验证缩放后观感） |
| `_probe_topdown.gd` | 正交俯视出图（**和缩放无关**地看布局） |

完整用法见 `_tools/opt_archviz.py` 顶部注释与 `优化手册-高面数场景.md`。

### 五、还没做的

- **VRAM 压缩没做**：现在贴图还是 4 B/px。改成 BC1/BC3/BC7 还能再省一大截
  （84 MB → 约 25 MB）。这一步得在 Godot 的贴图导入面板批量设，
  GLB 内嵌贴图没有全局开关。
- **没放进场景**：模型还是 `models/_wip_esports_hotel/` 下的 WIP 资产，
  没接到 `next_level.tscn` 或新关卡里。摆位和朝向要人看。
- **遮挡剔除仍是关的**（`rendering/occlusion_culling/use_occlusion_culling`），
  这个 78×41×77 m 的空间体量最适合上遮挡体。
- 模型里**没有墙和地板**（看起来只有家具和陈设），可能在 Max 里是分层导出的，
  或者原工程就没做墙体。

## 21. 下一步

1. ~~真实窗口复测 a7ec536~~ —— 已完成（离屏 `--splat=off`，数据见 §4）。
2. ~~部室角落掉帧~~ —— 已定位并修掉 184.5 万面那颗雷（§10）；用户可用 F3 复核，仍低再谈室内降级室外远景。
3. ~~10×10 分块~~ —— 已做（`acf6347` / `5e3f107`）。§13 验收不合格 → 用户已拍板走
   **「粗层常驻 + 细层叠加」**，实现见 §13 五。
   ~~换窗口卡顿复测~~ —— 已做（§17 四：最坏一帧 199~842 ms → 117~158 ms）。
   **剩余**：
   - 「粗层观感调参」还没人看过（`--ggs-no-coarse` 出对照图）；
   - 那 117~158 ms 的大头还是「换窗口时重建光栅器」。要再往下压只有一条路：
     **按最大窗口一次性分配缓冲 + 窗口 bin 补零到固定点数 + 切窗口只换 bin 重传**，
     代价是常驻显存变高（~700 MB）、投影每帧多跑一点。**没做，等用户点头。**
   - 每次释放 GGS 资源会报一次 `ERROR: Attempted to free invalid ID: ...`
     （本轮之前就有，同一个 RID 号，没查）。
4. ~~天空透不出来~~ —— 已修（`gsplat_render.glsl` 的 alpha，见 §13 四）。
5. ~~分块尺度错~~ —— 已离线重切（§13 七），默认指向 `campus_chunks10w`。
   **但画面还没人看过**：重切后的细层是不是终于和粗层/地面网格对齐，需要开一次游戏确认。
6. ⚠️ **用户明确要求：不要随便弹窗口**（出图探针会抢一下前台，打断他建模）。
   要跑 `_tools/run_shot.sh` 那类探针，先问过用户。
7. ~~凯伊进第二场景 + 载具形态可购买~~ —— 已做（§16）。
   **待用户看画面**：载具模型的朝向（`facing_yaw_deg`，默认 0）与缩放（`carrier_scale`），
   本喵没在窗口里看过，可能是倒着走 / 大小不对；两个都是导出参数，改一个数就行。
8. ~~显存 6918 MiB 之谜~~ —— 已解（§17 三②：RenderState 缓存 4 → 2）。要用户实机复核。
9. **性能和观感之间还剩三个可选挡位**（都要用户点头，因为都会动观感）：
   - 排序 ≈ 3.9 ms/帧。既然**排序本身每帧就不确定**（§17 三① 的噪声底），
     「隔帧排一次」在观感上几乎不可分辨，但仍是观感让步。
   - 画室609 那 2.2 GB：重导更稀的 `room609.sogdata`，或上传前按 stride 抽样。
   - 缩放 1.0 的像素成本：MSAA 4x 值 0.54 ms、后处理 0.59 ms（都不多）。
10. 等素材接入开放架。
11. 电竞房布局等用户。
12. 待确认：`campus_buildings.tscn` 删除是否有意；`project.godot` 名称与 description 是否一起收尾提交。