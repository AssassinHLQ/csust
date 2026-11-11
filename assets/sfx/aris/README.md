# `assets/sfx/aris/` —— 爱丽丝（Blue Archive）轨道炮音效

这一目录里是**从蔚蓝档案游戏内 SFX 包裁出来的短音**，用于玩家武器的开枪 / 换弹。
音频本体 **不随仓库分发**（`.gitignore` 排除），只保留 `*.wav.import` 导入桩与本文件。

- 音频版权：© NEXON Games / Yostar（Blue Archive 游戏内素材）
- 用途：个人 / 非商业的同人项目，本地演示；**不得再分发、不得用于任何发布产物**
- 出处：用户 2026-11-11 提供本地 SFX 包；原始文件名写在下面表里

## 为什么是「裁过的短音」而不是原文件

| 原文件 | 原长度 | 为什么不能直接用 |
|---|---|---|
| `SFX_Common_RG_aris_Attack.wav` | 1.82 s | 一发是「充能 0.2 s → 放电 → 轰鸣」，而本工程 `fire_interval = 0.075`（13 发/秒），整条塞进去叠成一锅粥；`_verify_sfx.gd` 的 `MAX_LEN = 1.5` 也会判红 |
| `SFX_Public_Aris.wav` | 1.92 s | 同上（前半段是充能扫频，后半段才是放电） |
| `SFX_Common_RG_aris_Reload.wav` | 1.68 s | 太长；但它天然是**两段**（0.10~0.72 退弹 / 1.16~1.66 上弹），正好拆成两个逻辑名 |

裁剪 + 滤波全部由 `_godot_editor_data/make_aris_sfx.py` 完成，**可重跑、结果确定**。
不要手工截 —— 里面写清了为什么必须高通、以及哪些素材被淘汰。

## 文件清单

| 文件 | 来源 | 裁决 | 用于 |
|---|---|---|---|
| `SFX_Public_Aris_shot.wav` | `SFX_Public_Aris.wav` 峰 1.297 s 起切 0.130 s，高通 200 Hz | 质心 3205 Hz、RMS −14.6 dBFS、起振 0 ms | `fire`（变体①） |
| `SFX_Aris_Hit_shot.wav` | `SFX_Aris_Hit.wav` 0.000 s 起切 0.130 s，高通 200 Hz | 质心 3551 Hz、RMS −14.8 dBFS、起振 0 ms | `fire`（变体②） |
| `SFX_Common_RG_aris_Reload_out.wav` | `SFX_Common_RG_aris_Reload.wav` 0.100~0.590 s | RMS −9.0 dBFS（不过滤，保留机械 body） | `reload_out` |
| `SFX_Common_RG_aris_Reload_in.wav` | `SFX_Common_RG_aris_Reload.wav` 1.160~1.640 s | RMS −12.7 dBFS（不过滤） | `reload_in` |

全部 **22050 Hz 单声道 16-bit**，峰值归一化到 −1 dBFS（变体之间响度必须一致，
否则 13 发/秒连发会「忽大忽小声」）。

## 被淘汰的候选（留档，别重复试）

拿被替换掉的合成枪声 `gunshot_000.wav` 当基准：0.320 s、RMS −14.1 dB、谱质心 3404 Hz。

| 候选 | 结果 | 结论 |
|---|---|---|
| `SFX_Common_RG_aris_Attack` 峰顶 | 质心只有 **1418 Hz**，是超低频闷雷；高通加到 800 Hz 质心也才 2735，RMS 却被掏到 −24.5 | 淘汰：要么闷、要么响度撑不住 |
| `SFX_Common_RG_aris_Delay` 峰顶 | 质心 2346 Hz（偏闷） | 淘汰：和变体①亮度差太多，连发会断续 |
| `SFX_Public_Aris` 峰 0.798 | 质心 **5900 Hz**（过亮、偏「嘶」） | 淘汰：同上 |

## 重跑

```bash
python _godot_editor_data/make_aris_sfx.py      # 需要本地 SFX 包在 C:\Users\WY157\Downloads\archive
godot --headless --path . --import              # 不导入的话 ResourceLoader.exists() 认不出来
godot --path . --script res://scripts/_verify_sfx.gd
```

脚本顶部有 `SRC` / `DST` 两个常量，换机器要改。
