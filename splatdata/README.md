# splatdata/ —— 校园高斯泼溅数据（不随仓库分发）

这个目录在本仓库里**只有说明文件**。泼溅数据由使用者自行提供，
其拍摄权、场地权、肖像权与再分发权均未由本项目核实（见 [../THIRD_PARTY.md](../THIRD_PARTY.md)）。

## 放什么

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
| 本工程验证用的规模 | 6,150,154 点，86.6 MB |
| 首次解码 | 约 50 s（后台线程，HUD 左上角显示进度） |
| 缓存命中 | 约 1.0 s（`user://splat_cache`，`SplatScene.cache_mode = "auto"`） |
| 显存/内存 | 约 1.5 GB（`point_data_byte` = 点数 × 240 B） |
| 帧率开销 | RTX 4060 Laptop / 1600×900 下约 −20 fps（108.9 vs 128.8） |

## 没有数据也能玩

```powershell
& $godot --path . -- --splat=off
```

`SplatScene` 会跳过加载，射击场照常运行（第六节）。

## 换自己的场景要注意

`scenes/game.tscn` 里 `SplatScene` 的摆放参数是按**这份校园扫描**调的：

- `world_scale = 25`：这份数据的「模型尺度」放大 25 倍后约 211 × 160 m
- `top_gap = 12`：内容顶面沉到悬浮平台下方 12 m
- `auto_place = true`：水平自动居中、竖向按 `top_gap` 下沉，参数由
  `SplatScene.content_bounds()` 抽样点数据算分位数包围盒得到

换一份扫描后先跑 `scripts/_probe_platform.gd` 扫几组（缩放 × 下沉量），
它会把「floaters 会不会飘到平台上方」和两种视角的渲图一起打出来（README §6.5）。
