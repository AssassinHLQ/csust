# `assets/sfx/` —— 音效文件投放目录

这个目录**根下**是 Kenney 的 CC0 素材（`.ogg`）+ 本工程自己合成的枪声（`.wav`），
来源与许可见 [`LICENSE_Kenney_CC0.md`](LICENSE_Kenney_CC0.md) ——
**故意提交进仓库**：克隆者不用做任何事就有声音。

⚠️ 但 **`aris/` 子目录是例外**：那是蔚蓝档案的游戏内音频（© NEXON Games / Yostar），
**音频本体不随仓库分发**，只留 `*.wav.import`。见 [`aris/README.md`](aris/README.md)。
分出子目录就是为了让「哪些能分发、哪些不能」在磁盘上一眼可见
（`_verify_credits.gd` 对 `assets/` 是「每个子目录都必须有自己的署名条目」）。

## 逻辑名 ↔ 文件，别在这里找

**文件名保持素材的原始命名**（`laserSmall_003.ogg`、`SFX_Public_Aris_shot.wav` 这种），
这样「哪个文件来自哪个包」一眼可查、换素材时也不会张冠李戴。

**「游戏里什么时候响哪个文件」写在 `scripts/sfx.gd` 的 `SPEC` 表里**，
代码只认**逻辑名**：

| 逻辑名 | 文件 | 响在哪 |
|---|---|---|
| `fire` | `gunshot_000` ~ `004`（随机挑一条 + 音高抖动） | `weapon.gd::shoot()` 开火 |
| `fire_beam` | `laserSmall_000` ~ `004`（`pitch_base 0.78` 压低成炮） | 机甲形态的激光大炮 |
| `empty` | `click_001` | 空仓扣扳机（150 ms 节流，不然按住不放会「咔咔咔」） |
| `reload_out` | `aris/SFX_Common_RG_aris_Reload_out` | 换弹开始（`reload_started`） |
| `reload_in` | `aris/SFX_Common_RG_aris_Reload_in` | 换弹完成（`reload_finished`） |
| `ex_fire` | `aris/SFX_Skill_Aris_Ex_blast` | EX 必杀发射（`ex_system.gd::_fire_max()`，连按 E→X） |
| `ui_press` | `click_002` | 设置菜单里的按钮（含画质分段按钮） |
| `ui_toggle` | `toggle_001` | 开关（同伴开火 / Boss 攻击） |
| `ui_slider` | `tick_002` | 滑条值变化（音量压得很低，-14 dB） |
| `ui_open` / `ui_close` | `open_001` / `close_001` | 菜单开 / 关 |

> **`fire` 为什么用回合成枪声**：2026-11-11 试过换成爱丽丝的轨道炮原声（裁短 + 高通，
> 裁好的文件还留在 `aris/*_shot.wav` 里），用户听完 A/B 说「枪声还是前面 1.5 秒好听」，
> 于是回到合成那批。取舍的完整量化记录在 `scripts/sfx.gd` 的 `fire` 注释与
> `aris/README.md` 里 —— 别再重复试一轮。
>
> `reload_out` / `reload_in` / `ex_fire` 用的仍是爱丽丝原声（用户对换弹音效表示满意）。

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
