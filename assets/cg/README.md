# CG / 开场 PV 目录

开场画面由 `scripts/title_intro.gd` 负责，**四级优先级**（先有谁用谁）：

| 优先级 | 放什么 | 走哪条路 |
|---|---|---|
| ① | `assets/cg/pv/*.png / *.jpg` | PV 图：按文件名排序循环，每张**从左往右缓慢平移**；同名 `assets/cg/pv_hd/` 存在就优先用 AI 超分版 |
| ② | `assets/cg/opening.ogv` | 整段 CG，`VideoStreamPlayer` 循环播 |
| ③ | `assets/cg/opening/*.png` | 帧序列，当 PV 图一样逐张平移 |
| ④ | 都没有 | 渐变深蓝底 + 标题（兜底，进度条与开始按钮照常） |

⚠️ 现在的正片是 ①（`assets/cg/pv/`，8 张宽幅截图 + `assets/music/pv_theme.mp3`）。
原图是视频截帧、偏软，所以另有 `assets/cg/pv_hd/`（Real-ESRGAN 4× 超分版，
用 `_tools/upscale_pv_images.ps1` 生成）。想看整段 CG 就把 `pv/` 里的图撤掉，再按下面转码。

## 整段 CG 的格式

**Godot 4 只认 Ogg Theora（`.ogv`）**。mp4 / webm 播不了，是引擎限制。

转码（ffmpeg 已在机器上）：

```bash
_tools/mp4_to_ogv.sh 你的CG.mp4
```

不给第二个参数就写到本目录的 `opening.ogv`。

## 图片序列 / PV 图

- `assets/cg/pv/`：开场 PV（现在用的），png / jpg 都认，按文件名排序。
- `assets/cg/opening/`：整段 CG 的帧序列，同样按文件名排序。

两者都支持任意张数；宽幅图横向平移的行程 = 图宽 − 屏宽，16:9 的图就是静态淡入淡出。

## 现在的播放规矩（2026-11-12 用户口径）

1. 正片盖住**高斯泼溅解码**（冷缓存约 50 s，暖缓存约 2 s），底下一行进度条实时显示；
2. 加载完才在下方出现「开始游戏」，**点了才进游戏**；有缓存加载很快时也照样走一遍；
3. **不做「任意键跳过」** —— 因为「有人会听歌」，PV 与音乐一直放到玩家自己点开始；
4. 点开始后 PV 淡出、音乐淡出，房间 BGM 接手。

缺图片 / 缺音乐都不会报错：自动退回 ④ / 静音，启动、进度条、开始按钮不受影响。
