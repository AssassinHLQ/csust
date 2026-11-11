# `assets/music/` —— 背景音乐投放目录

这个目录下的**音频文件不进仓库**（`.gitignore` 已排除），
但**导入配置 `*.ogg.import` 会进仓库** —— 循环开关存在那里面，
克隆者只要把音频按下面的文件名放进来，就直接是循环的，不用再改任何设置。

## 需要放什么

| 文件名 | 用在哪 | 来源 |
|---|---|---|
| `shop_theme.ogg` | 商店「柴关电脑城」的 BGM（走进去淡入、走出去淡出） | UNDERTALE「Tem Shop」，© Toby Fox / Materia Collective |
| `gamedev_theme.ogg` | 游戏开发部活动室的 BGM（走进房间淡入、走出去淡出） | 「碧蓝档案OST Vol.1」P70「Pixel Time（游戏开发部）」，© NEXON Games / Yostar |
| `esports_theme.ogg` | 电竞房的 BGM（走进房间淡入、走出去淡出；房子买回来之前不出声） | 「碧蓝档案OST Vol.1」P8「Colorful Mess」，© NEXON Games / Yostar |

**只有本地放好这些文件，对应的房间才有音乐**。没有它时不会报错：
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

## 游戏开发部那首（`gamedev_theme.ogg`）

源文件 131.1927 s（320 kbps MP3，`「碧蓝档案OST🎵」音乐合集~Vol.1（320K）_P70_Pixel Time（游戏开发部）_音频.mp3`）。

⚠️ **循环点就是游戏里原本的循环点**（用户 2026-11-11：「只需要裁掉最后两秒
就可以循环，就是游戏里面的效果」）：取**前 129.2292 s**，硬裁、不做交叉淡化。

```python
import sys; sys.path.insert(0, "tools/audio")
import make_loop as ml
x = ml.load_audio(源文件)          # 131.1927 s
y = x[:int(round(129.2292 * ml.SR))]   # 硬裁，不 make_seamless
# 再按 -1 dBFS 归一化成 16 bit wav，交给 ffmpeg 编码
```

实测数值（在「裁掉 1.9 ~ 2.1 s」区间内按 **环绕跳变 + 斜率差** 以 0.2 ms 步长精扫）：

```
内部相邻样点平均跳变 = 0.043299
选定 L = 129.2292 s（裁掉最后 1.9635 s）
  → 环绕跳变 0.003693（= 内部平均的 ×0.085）
  → 斜率差 0.000580
峰值归一化到 −1 dBFS
```

**为什么不做交叉淡化**：这个点本来就是游戏里的循环点，硬接就已经连续
（跳变只有内部平均的 1/12），再混 25 ms 反而会把循环点前后各 25 ms 的内容
重叠一次，越改越不「原版」。

**为什么不切在整数周期上**（早先那版切在 119.9993 s = 15 × 8 s 周期）：
虽然那也是个数学上干净的接缝，但它**多切掉了最后 9 s 的曲子内容**，
而那 9 s 本来就是循环的一部分 —— 已经在跑的段落被砍掉了，听感上会「少了半段」。

**为什么不正好裁 2.000 s**：精确 2.000 s（L=129.1927）那一点附近，
真正的波形连续点在 129.2292，两者只差 36 ms（听不出长短），但 129.1927
处的环绕跳变是 0.028（×0.65），而 129.2292 处是 0.0037（×0.085）——
差了 7.6 倍。切在连续点上才是对的。

## 电竞房那首（`esports_theme.ogg`）

源文件 111.8293 s（320 kbps MP3，`「碧蓝档案OST🎵」音乐合集~Vol.1（320K）_P8_Colorful Mess_音频.mp3`）。

**这首不能用「周期整数倍」那套直接套**，原因有两个：

1. 自相关最强峰在 22.3256 s，但相关系数只有 **0.40** —— 曲子不是严格周期结构；
2. **结尾没有淡出**：末 10 s 的 RMS 0.145，和全曲 0.155 差不多。
   直接整首循环会从响亮的结尾硬切回安静的前奏（开头 5 s 的 RMS 只有 0.100）。

所以改成「在曲子内部找一个接缝本来就干净的点」：先按 `--target 40` 让工具报出周期，
再用 `make_loop.py` 里的函数（`load_audio` / `make_seamless`）扫一遍候选长度，
判据不是「周期整数倍」而是**环绕交叉淡化之后还剩多大的跳变**。

```python
import sys; sys.path.insert(0, "tools/audio")
import make_loop as ml
x = ml.load_audio(源文件)
y = ml.make_seamless(x, int(round(92.070 * ml.SR)), 25.0)   # 92.070 s
# 再按 -1 dBFS 归一化成 16 bit wav，交给 ffmpeg 编码
```

实测数值：

```
自相关周期候选：P = 22.3256 s（ac 0.40）/ 5.5814 s（0.39）/ 11.1628 s（0.37）
   —— 都不是干净的整数周期，所以不走「整数倍」那条路
选定 L = 92.0700 s（全曲的 82.33%，4.124 × P）
  → 与开头 4 s 的相关系数 r = +0.5647（20~106 s 全长度扫描里最高的一档）
  → 淡化前接缝跳变 0.005445（曲子内部相邻样点平均跳变 0.0413，×0.13）
环绕交叉淡化 25 ms（等功率 sqrt 曲线）
  → 淡化后环绕断点 0.002878（内部平均的 ×0.07）
峰值归一化到 −1 dBFS
```

切掉的末尾约 19.8 s 主要是收尾段落 —— 那一段本来也不是循环要的。

## 循环开关在哪

`gamedev_theme.ogg.import` / `shop_theme.ogg.import` 里的 `loop=true`（以及 `loop_offset=0`）。
这是 Godot 的**导入期**选项，`scripts/music.gd` **不会**在运行期改它 ——
运行期改循环要每帧盯 `finished` 信号再 `play()` 一次，那会有一帧的空隙。

⚠️ 改完 `.import` 的 `loop` 要**强制重导**才生效（只改文件 Godot 不会重导，
因为源文件没变）：删掉 `.godot/imported/<名字>-<哈希>.oggvorbisstr`
和同名 `.md5`，再跑 `godot --headless --path . --import`。
自检脚本里会打印 `loop = true/false`，改完跑一遍就知道有没有生效。

## 代码在哪

- `scripts/music.gd` —— 曲目表（逻辑名 → 文件 + 音量）、播放 / 停止 / 交叉淡入淡出
- `scripts/shop.gd::_build_music_zone()` —— 店里的 `Area3D`，玩家进出时开 / 关音乐
  （烘焙场景 `shop_baked.tscn` 里的 `MusicZone` 节点走 `_wire_baked()` 接信号）
- `scripts/gamedev_room.gd::_build_music_zone()` —— 活动室同理；盒子尺寸是**运行时**
  从 `Model/Collision` 的碰撞盒量出来的，房间尺寸怎么改都不会漂
- `scripts/esports_collision.gd::_build_music_zone()` —— 电竞房同理，盒子从
  `BakedCollision/AutoCol` 的 769 个烘焙盒量出来。**多一道可见性判断**：
  这栋房子默认藏着（`game.tscn` 里 `visible = false`，买完才从天而降），
  而 `Area3D` 的监测跟可见性无关 —— 不判的话玩家走过那块空地就会响起 BGM
- `scripts/_verify_music.gd` —— 自检：三个房间的循环开关、进/出播放与停止
  （电竞房那段还验「房子藏着时不出声、现身才出声」）
