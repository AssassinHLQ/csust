# 开场 PV 素材（`assets/cg/pv/`）

这里是开场 PV 用的图片 + 音乐，**按文件名的字典序循环播放**。

## 现在的内容

| 文件 | 说明 |
| --- | --- |
| `01_gamedev.jpg` … `08_esports.jpg` | 8 张宽幅**原图**，开场 PV 逐张「从左往右」缓慢平移 |
| `../pv_hd/` | 同一套图的 **AI 超分版**（Real-ESRGAN 4× → 降采样到高 1440），有就优先用 |
| `../music/pv_theme.mp3` | 「Constant Moderato（PV1）」，循环播放，点「开始游戏」时淡出 |

取材：「碧蓝档案 OST Vol.1（320K）」P2「Constant Moderato（PV1）」，
以及本地游戏内截图 / 二创素材。**第三方版权，只留本地，不随仓库分发**
（`.gitignore` 已排除，规则写在那里）。

## 为什么有 `pv_hd/`（2026-11-12：使用者说「实机画面太糊了」）

原图是视频截帧，本身信息就少。`pv_hd/` 是用 **Real-ESRGAN ncnn 版** 4× 超分、
再用 ffmpeg Lanczos 降采样到 **高 1440** 的版本；显示时约 1.6× 超采样。
`scripts/title_intro.gd` 会**逐张**优先同名 HD 文件，缺哪张就退回原图。
游戏内再叠一层很轻的「锐化 + 胶片颗粒 + 暗角」着色器，把残余的软边和压缩块藏掉。

重新生成（需要 `GODOT/_tools/realesrgan/` 和 PATH 里的 ffmpeg）：

```powershell
powershell -File _tools/upscale_pv_images.ps1
```

⚠️ 换图之后要重跑一次；没重跑也不会错，只是那张退回原图（软一点）。

## 怎么换图

1. 把 png / jpg 丢进这个目录（两种都认），文件名决定顺序（`01_xxx.jpg`、`02_xxx.jpg`…）。
   宽幅图最合适：横向平移的行程 = 图宽减去屏宽。
2. 跑一次导入：`<godot> --headless --path . --import`
   （编辑器里打开项目也会自动导入）。
3. 启动游戏即可，无需改代码。张数、顺序、横竖比例都会自己适配。

没有图片时不会报错：`scripts/title_intro.gd` 会退回「渐变深蓝底 + 标题」，
进度条与开始按钮照常出现。

## 怎么换音乐

替换 `assets/music/pv_theme.mp3` 即可；代码会把它设成循环播放。
没有这个文件时 PV 静音，不会卡启动。
