# splatdata/ —— 高斯泼溅数据（不随仓库分发）

这个目录在本仓库里**只有说明文件**。泼溅数据由使用者自行提供，
其拍摄权、场地权、肖像权与再分发权均未由本项目核实（见 [../THIRD_PARTY.md](../THIRD_PARTY.md)）。

本工程用到**两份**扫描，接法完全不同（详见 [../README.md](../README.md) §6.5 与 §6.8）：

| | 校园（`school_playable.sogdata`） | 画室609（`room609.sogdata`） |
|---|---|---|
| 场景类型 | 俯拍航拍（只能从上方看） | 教室内部（站在里面玩） |
| 点数 | 6,150,154 | 2,774,116（裁后 2,769,851） |
| `world_scale` | 25（世界 211 × 160 m） | 4.25（世界约 23.9 × 27.2 m、净高约 5.4 m） |
| 摆放 | `auto_place` + `top_gap = 12`（沉到平台下方） | `use_anchor`（地板中心对到 **(0, 0.03, 4.25)**） |
| `yaw_degrees` | 0 | 248.6（轴对齐，见 §6.8 里「歪了 39.5°」那段） |
| 裁剪 | 关（靠下沉量把 floaters 顶到平台上方） | **开**（`margin 0.5` / `max_scale 0.5`） |
| 碰撞 | 无 | 四面墙（厚 0.3 m）+ 朝靶场那面开 1.6 m 门洞 |
| 首次解码 | ≈ 50 s | ≈ 21 s |

## 校园那份：放什么

`SogRuntime.find_source()` 按下面的顺序找第一个存在的文件：

1. `school_playable.sogdata` ← **推荐**（清理过 floaters 的版本）
2. `school_playable.sog`
3. `school.sogdata`
4. `school.sog`

也可以不改文件名，用命令行显式指定：

```powershell
& $godot --path . -- --sog=D:/path/to/your.sogdata
```

## ⚠️ 为什么后缀要写成 `.sogdata` 而不是 `.sog`

Godot 会通过 GDGS 插件的 `EditorImportPlugin` 把 `.sog` 展开成 GaussianResource
写进 `res://.godot/imported/*.res`：615 万点 × 60 float × 4 B ≈ **2.89 GB**，
导出时会整份塞进 PCK，exe 从 200 MB 膨胀到 3 GB。

改成 **`.sogdata`**（Godot 不认识的后缀）就不会触发导入器，只当普通文件随包携带，
运行时由 `scripts/sog_runtime.gd` 现场解码。

## 数据要求

| 项 | 值 |
|---|---|
| 格式 | SOG v2（zip 容器：`meta.json` + `means_l/u.webp` + `quats.webp` + `scales.webp` + `sh0.webp` + `shN_*.webp`） |
| 本工程验证用的规模 | 6,150,154 点，86.6 MB（校园）；2,774,116 点，40.7 MB（画室609） |
| 首次解码 | 约 50 s / 约 21 s（后台线程，HUD 左上角一场一行显示进度） |
| 缓存命中 | 约 1.0 s / 约 1.5 s（`user://splat_cache`，`SplatScene.cache_mode = "auto"`） |
| 显存/内存 | 约 1.5 GB / 约 0.7 GB（`point_data_byte` = 点数 × 240 B） |
| 帧率开销 | 校园 RTX 4060 Laptop / 1600×900 下约 −20 fps（108.9 vs 128.8） |

⚠️ **两份同时加载时显存按点数之和算**（GDGS 会把场上所有泼溅合并成一个 GPU
缓冲，详见 README §6.8）。8 GB 显卡上建议用 `-- --venue=room` 只留一份。

## 没有数据也能玩

```powershell
& $godot --path . -- --splat=off          # 两份都不加载
& $godot --path . -- --venue=room         # 只加载画室609
& $godot --path . -- --venue=campus       # 只加载校园
```

`SplatScene` 会跳过没被选中的那份，射击场照常运行（第六节）。

## 换自己的场景要注意

`scenes/game.tscn` 里两个泼溅节点的摆放参数都是**按各自那份扫描量出来的**，
不要互换：

- 校园 `SplatScene`：`world_scale = 25`（放大后约 211 × 160 m）、
  `top_gap = 12`（顶面沉到平台下方 12 m）、`auto_place = true`
  （水平自动居中，参数由 `SplatScene.content_bounds()` 抽样算分位数包围盒得到）
- 画室609 `Room609`：`world_scale = 4.25`（世界约 23.9 × 27.2 m、净高约 5.4 m；
  **别再往下调到 1.8 以下** —— 这份扫描偏扁，×1.8 时相机到天花板只剩 0.39 m，
  上半屏会糊）、
  `yaw_degrees = 248.6`、`auto_place = false` + `use_anchor = true`
  （把源坐标的地板中心对到 **(0, 0.03, 4.25)** —— 罩住出生点，否则第三人称相机会落到
  房间外面）、`crop_enabled = true`（裁掉离群 floaters）、
  `build_box_collision = false` + **`Room609/RoomCollision` 下 5 个手摆的盒**
  （4 面墙，z− 那面被 1.6 m 门洞切成 2 段；数值是把生成算法的输出抄进来的，见主 README §6.8）

⚠️ 换缩放时注意：`crop_margin` / `crop_max_scale` 是**源坐标单位**，与 `world_scale`
无关，改缩放不用重调；但 `anchor_world` 和 `box_wall_thickness` / `box_door_width`
是**世界单位**，缩放变小以后要重新看它们合不合适（例如墙厚 0.3 m 在 ×6.4 下几乎看不见，
在 ×1.8 下才是一堵正常的墙）。

⚠️⚠️ **改完摆放参数必须重摆房间碰撞**：`game.tscn` 里那 5 个盒是**静态**数值，和
`world_scale` / `yaw_degrees` / `anchor_*` / `crop_*` 绑死，不会自己跟着动。重摆办法：

```powershell
# ① 把 Room609 的 build_box_collision 临时设成 true，导出生成结果
& $godot --headless --path . --script res://scripts/_probe_room_collision.gd
# ② 把 stdout 那段 .tscn 文本贴回 game.tscn 覆盖旧的 5 个盒，再把开关设回 false
# ③ 跑 _verify_room.gd —— §5 会拿 box_* 参考值校验这 5 个盒
& $godot --path . --script res://scripts/_verify_room.gd
```

换一份扫描后的两条路：

```powershell
# ① 先看数据本身长什么样：地面在哪、主轴偏多少、floater 有多少、高度图
& $godot --path . --script res://scripts/_probe_room_layout.gd -- --sog=<你的文件>

# ② 再在真实游戏相机下扫缩放 / 朝向，渲出玩家真正会看到的画面
& $godot --path . --script res://scripts/_probe_room_on_platform.gd -- `
      --sog=<你的文件> --scale=2.0 --yaw=0 --margin=0.5 --maxscale=0.5

# ③ 定完参数写进 game.tscn，最后跑自检把「轴对齐」等判据验一遍
& $godot --path . --script res://scripts/_verify_room.gd
```

⚠️ 定 `yaw` 时**别用手算或肉眼看**：本工程就在这上面栽过 —— 上一版把
「相对 +X 的协方差主轴角」当成「相对 +Z」用，结果房间整整歪了 39.5°。
`_verify_room.gd` §3 的「墙直方图峰值集中度」扫描会直接告诉你还差多少度，
并且自带一个「人为转 23°」的合成自检来锁符号方向（README §6.8）。
