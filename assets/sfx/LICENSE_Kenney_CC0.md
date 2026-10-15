# 音效素材许可：Kenney（CC0）

`assets/sfx/` 里的 13 个 `.ogg` 全部取自 **Kenney**（<https://kenney.nl>）的三个音频包，
三个包都声明为 **Creative Commons Zero (CC0)**，即**可以随本仓库分发**、商用也无需署名。

| 包 | 取用的文件 | 作者给的版本 / 日期 |
|---|---|---|
| Interface Sounds | `click_001` `click_002` `toggle_001` `tick_002` `open_001` `close_001` | 1.0 / 2020-02-11 |
| Sci-fi Sounds | `laserSmall_000` ~ `laserSmall_004` | — |
| RPG Audio | `metalLatch` `metalClick` | — |

原包里的 `License.txt` 原文（三个包措辞一致）：

```
License: (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/
```

CC0 的完整文本：<https://creativecommons.org/publicdomain/zero/1.0/legalcode>

## 为什么这几个文件可以进仓库，而模型和泼溅数据不行

本工程对第三方素材只有一条规矩：**能不能随仓库分发**。

- ❌ 角色模型、Boss、泼溅扫描数据 —— 专有 / 权利状态未核实，一律 `.gitignore` 排除；
- ✅ Kenney 的 UI 皮肤（CC0）—— 已经在仓库里，见 `assets/ui/LICENSE_Kenney_UI-Pack_CC0.md`；
- ✅ **这批音效（CC0）—— 同上**，所以它们**故意**提交进仓库：克隆者不用做任何事就有声音。

（`tools/font/` 那套字体的取舍见 `assets/ui_font/README.md` 与 `THIRD_PARTY.md`。）

## 想换掉 / 加新的

1. 把 `.ogg`（或 `.wav`）丢进 `assets/sfx/`；
2. 在 `scripts/sfx.gd` 的 `SPEC` 里加一行逻辑名 → 文件名；
3. `--headless --path . --import` 导入一次（Godot 要生成 `.import`）；
4. 跑 `--script res://scripts/_verify_sfx.gd` 确认能加载、时长正常。

⚠️ 这一步**不需要改任何别的代码** —— 调用点只认逻辑名。也**不要**改这几个文件的文件名：
它们保持 Kenney 的原始命名，是为了让「哪些文件来自哪个包」一眼可查（见上表）。
