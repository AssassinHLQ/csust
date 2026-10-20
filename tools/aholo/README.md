# Aholo 3DGS 重建 / 生成（`tools/aholo/`）

[Aholo](https://labs.aholo3d.cn) 是 ManyCore 的 **3DGS（高斯泼溅）重建 / 生成**服务：
给一堆照片（或一段视频），它返回 **PLY / SPZ** 的泼溅场景。

本工程只认 **`.sogdata`**（`scripts/sog_runtime.gd` 运行时展开的 SOG 归档），
所以中间要多一步 **PLY/SPZ → SOG** 的转换 —— 这个 CLI 的 `--convert` 帮你顺手做了。

---

## 0. 一句话用法

```powershell
$env:AHOLO_API_KEY = "你的密钥"     # 只在当前终端有效，别写进任何文件
$env:AHOLO_REGION  = "cn"           # 国内站；海外站用 com

node tools/aholo/aholo.mjs whoami    # 先确认密钥能用
```

## 1. 素材怎么拍（决定成败的一步）

| 项目 | 要求 |
|---|---|
| 数量 | **≥ 20 张**（官方硬要求）。想干净一点就 **60~120 张** |
| 重叠 | 相邻两张重叠 **70%** 以上（绕着走，别原地转圈） |
| 曝光 | **锁定曝光 / 白平衡 / 焦距**，全程别变（自动曝光会让重建出「阴阳脸」） |
| 角度 | 绕着物体走 **2~3 圈**（低机位一圈、平视一圈）；房间就沿墙走 + 中间补几张 |
| 别动的东西 | 拍摄期间**别有人/椅子走动**，窗帘、屏幕画面也别变 |
| 避免 | 大面积纯白墙、镜子、玻璃、强反光 —— 这些区域容易糊成一团 |
| 视频 | 也可以直接给一段 4K 视频（`.mp4`/`.mov`），匀速走、别急转；Insta360 用 `.insv` |

> 想重建「画室 609」这种室内：**space**。想重建一个手办/道具：**object**。

## 2. 重建（室内 / 物体）

```powershell
# 室内：给一个目录（里面全是 jpg/png）
node tools/aholo/aholo.mjs space D:\photos\room609 --name 画室609 --quality high --wait

# 物体
node tools/aholo/aholo.mjs object D:\photos\figure --name 手办 --quality normal --wait
```

- `--quality`：`low`（快速预览）/ `normal`（默认）/ `high`（专业）
- 不加 `--wait` 会**立刻返回 worldId**，之后用 `wait <worldId>` 查
- 上传是逐张的，控制台会打印进度

## 3. AI 生成（不用照片）

```powershell
node tools/aholo/aholo.mjs generate --prompt "夜晚的赛博朋克教室，蓝色霓虹" --quality normal --wait
node tools/aholo/aholo.mjs generate --prompt "把这张图做成 3D 场景" --image D:\ref.png --wait
```

> 生成任务**最多 1 张参考图**；给多张请走 `space` / `object` 重建。

## 4. 查进度 / 拿产物

```powershell
node tools/aholo/aholo.mjs list                  # 最近的任务
node tools/aholo/aholo.mjs get   <worldId>        # 状态 + PLY/SPZ 下载地址
node tools/aholo/aholo.mjs wait  <worldId>        # 轮询到 SUCCEEDED / FAILED
node tools/aholo/aholo.mjs download <worldId> --out out/room609 --convert
```

`--convert` 做的事：

```
out/room609/<worldId>.ply
   └─ npx @playcanvas/splat-transform <id>.ply <id>.sog
        └─ 改名 <id>.sogdata     ← 本工程要的就是这个
```

## 5. 接进游戏

1. 把 `<worldId>.sogdata` 拷到 `_arisu_learn/splatdata/`；
2. 改场景里那台 `SplatScene` 的 `sog_path`，或命令行覆盖：
   ```powershell
   & <godot> --path . -- --sog=D:/.../room609.sogdata
   ```
3. `SplatScene` 的 `world_scale / yaw_degrees / anchor_* / crop_*` 按新场景量一遍
   （画室 609 那组参数在 `README.md` §6 里，不能照抄）。

> ⚠️ SOG 里的**点数是几百万级**：先跑一次看帧率（`_probe_fps`），再决定要不要
> `crop_enabled` / `crop_max_scale`。

## 6. 常见错误

| 现象 | 原因 |
|---|---|
| `401` | 密钥不在 `AHOLO_API_KEY` 里，或复制时带了空格/引号 |
| 创建任务被拒 | 图片 < 20 张；或图片和视频混着传 |
| 任务 `FAILED` | 素材重叠不够 / 有大面积反光 / 纯白墙；换一组素材重试 |
| 下载 403 | URL 有过期时间，重新 `get` 一次拿新地址 |
| `--convert` 报错 | 第一次跑 `npx` 要下载 `@playcanvas/splat-transform`，需要网络 |

## 7. 安全

- 密钥**只走环境变量**，不要写进 `aholo.mjs`、脚本、`.env` 里提交。
- 这个 CLI 的 `node_modules/` 和 `out/` 都在 `.gitignore` 里。
