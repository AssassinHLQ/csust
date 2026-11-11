# CG 目录

`opening.ogv` 放这里就会被当成开场 CG 播（`scripts/title_intro.gd` 的 `CG_VIDEO`）。

## 格式

**Godot 4 只认 Ogg Theora（`.ogv`）**。mp4 / webm 播不了，是引擎限制。

转码（ffmpeg 已在机器上）：

```bash
_tools/mp4_to_ogv.sh 你的CG.mp4
```

不给第二个参数就写到本目录的 `opening.ogv`。

## 也可以放图片序列

把 `0001.png`、`0002.png`… 放进 `assets/cg/opening/` 子目录，
会按文件名排序、以 `title_intro.gd::FRAME_FPS`（默认 24）逐帧播。
比视频稳，没有容器/编码问题。

## 三级优先级

1. `assets/cg/opening.ogv` ← 视频
2. `assets/cg/opening/*.png` ← 帧序列
3. 都没有 → 播程序化标题卡（`title_intro.gd` 里那版）

⚠️ 三者共用同一套骨架：**黑幕一直盖到 609 泼溅加载完**、按键只跳动画不跳加载。
你的 CG 播完了如果世界还没就绪，画面照样会等 —— 那一段加载卡顿不是标题卡造成的。