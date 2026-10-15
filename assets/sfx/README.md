# `assets/sfx/` —— 音效文件投放目录

这个目录里是**实际的音频文件**（13 个 `.ogg`，共约 103 KB），
来源与许可见 [`LICENSE_Kenney_CC0.md`](LICENSE_Kenney_CC0.md) ——
**Kenney 的 CC0 素材，故意提交进仓库**：克隆者不用做任何事就有声音。

## 逻辑名 ↔ 文件，别在这里找

**文件名保持 Kenney 的原始命名**（`laserSmall_003.ogg` 这种），
这样「哪个文件来自哪个包」一眼可查、换素材时也不会张冠李戴。

**「游戏里什么时候响哪个文件」写在 `scripts/sfx.gd` 的 `SPEC` 表里**，
代码只认**逻辑名**：

| 逻辑名 | 文件 | 响在哪 |
|---|---|---|
| `fire` | `laserSmall_000` ~ `004`（随机挑一条 + 音高抖动） | `weapon.gd::shoot()` 开火 |
| `empty` | `click_001` | 空仓扣扳机（150 ms 节流，不然按住不放会「咔咔咔」） |
| `reload_out` | `metalLatch` | 换弹开始（`reload_started`） |
| `reload_in` | `metalClick` | 换弹完成（`reload_finished`） |
| `ui_press` | `click_002` | 设置菜单里的按钮（含画质分段按钮） |
| `ui_toggle` | `toggle_001` | 开关（同伴开火 / Boss 攻击） |
| `ui_slider` | `tick_002` | 滑条值变化（音量压得很低，-14 dB） |
| `ui_open` / `ui_close` | `open_001` / `close_001` | 菜单开 / 关 |

## 加一条新音效

1. 把 `.ogg` / `.wav` 丢进这个目录（**保持原始文件名**）；
2. `scripts/sfx.gd` 的 `SPEC` 里加一行：`"逻辑名": {"files": ["xxx.ogg"], "db": -6.0, ...}`；
3. `& <godot> --headless --path . --import` —— 不导入的话 `ResourceLoader.exists()` 认不出来；
4. `& <godot> --path . --script res://scripts/_verify_sfx.gd` ——
   它会核对**文件在不在**、**时长正不正常**，以及**调用点写的名字在不在表里**。

⚠️ **改完 `SPEC` 不用改任何调用点**；反过来，调用点里写错一个字母会被上面第 4 步抓出来。

## 音量

- 每个逻辑名的**基准音量**在 `SPEC` 的 `db` 里（界面音比武器低一截：界面音该是「垫底」的）；
- **总音量**走 `GameSettings` 的 `master_volume`（设置界面里那个滑条），
  它作用在 `Master` 总线上，所以对这批音效全部生效 —— 不需要在这里做任何事。
