# `assets/music/` —— 背景音乐投放目录

这个目录下的**音频文件不进仓库**（`.gitignore` 已排除），
但**导入配置 `*.ogg.import` 会进仓库** —— 循环开关存在那里面，
克隆者只要把音频按下面的文件名放进来，就直接是循环的，不用再改任何设置。

## 需要放什么

| 文件名 | 用在哪 | 来源 |
|---|---|---|
| `shop_theme.ogg` | 商店「柴关电脑城」的 BGM（走进去淡入、走出去淡出） | UNDERTALE「Tem Shop」，© Toby Fox / Materia Collective |

**只有本地放好这个文件，商店才有音乐**。没有它时不会报错：
`scripts/music.gd` 会 `push_warning` 一次然后静默跳过，游戏照常跑
（和 `assets/ui_sprout/`、`assets/ui_font/` 一样的处理）。

## 怎么生成这个循环

源文件是比较长的一条（现在用的那版是 45.44 s），**不能直接按整数秒切**——
切在整数秒上会在接缝处「咔」一下。要先用自相关量出曲子自身的循环周期，
再切在周期的整数倍上。

工程里带了工具，一条命令复现：

```bash
python tools/audio/make_loop.py \
  "<你的源文件>" \
  "$TEMP/shop_loop.wav" \
  --target 40

# 再编码成 Ogg Vorbis（Godot 吃这个格式，q5 约 127 kbps）
ffmpeg -i "$TEMP/shop_loop.wav" -c:a libvorbis -q:a 5 -ar 44100 assets/music/shop_theme.ogg
```

现在的这一版实测数值（`make_loop.py` 的输出）：

```
自相关循环周期 P = 10.0524 s
选定 L = 40.20943 s（= 4 × P，误差 0.0000 ms）
  → 与开头的波形相关系数 r = +0.6601
  → 接缝跳变 0.000610（曲子内部相邻样点平均跳变 0.0126）
环绕交叉淡化 25 ms（等功率 sqrt 曲线）
峰值归一化到 −1 dBFS
```

⚠️ 为什么是 **40.20943 s** 而不是用户说的整数 40 s：差 0.21 s 听不出长短，
但切在 40.20943 上接缝相关系数 +0.66，切在 40.000 上只有 +0.06、
跳变是内部平均的 1.8 倍（会「咔」）。工具默认就是在目标值附近扫出最好的那个点。

## 循环开关在哪

`shop_theme.ogg.import` 里的 `loop=true`（以及 `loop_offset=0`）。
这是 Godot 的**导入期**选项，`scripts/music.gd` **不会**在运行期改它 ——
运行期改循环要每帧盯 `finished` 信号再 `play()` 一次，那会有一帧的空隙。

## 代码在哪

- `scripts/music.gd` —— 曲目表（逻辑名 → 文件 + 音量）、播放 / 停止 / 交叉淡入淡出
- `scripts/shop.gd::_build_music_zone()` —— 店里的 `Area3D`，玩家进出时开 / 关音乐
- `scripts/_verify_music.gd` —— 自检：循环开关、进店播放、出店停止
