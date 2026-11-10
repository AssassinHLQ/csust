"""改 esports_parts.json：把**窗帘**的碰撞盒去掉。

使用者 2026-11-10：「门卡住进不去什么鬼?!」「窗帘可以进入…」
实测门洞开在本地 x[-2.55, 1.35]（两侧墙板 物件_7 / 物件_11），
但三片窗帘 JJKJ211/213/214 就挂在门洞里，被烘成了实心盒子 → 人过不去。

窗帘是**布**，本来就不该挡人。这些件在 `parts` 里的 `boxes` 清空即可，
`_bake_esports_parts.gd` 会跳过没有盒子的件。

用法：
  C:\\Python314\\python.exe tools\\drop_curtain_collision.py [--dry]

⚠️ 想恢复：`git checkout -- models/esports_room/esports_parts.json` 再重烘。
"""

import json
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

PARTS = r"models/esports_room/esports_parts.json"

## 窗帘：3ds Max 里叫 JJKJ###。这些是布料，不做碰撞。
## 只清「挂着的帘子」，不含杆子/轨道（那些体积小，留着也无妨）。
CURTAIN_PREFIX = "JJKJ"


def main():
    dry = "--dry" in sys.argv
    with open(PARTS, encoding="utf-8") as f:
        d = json.load(f)

    parts = d["parts"]
    n_hit = 0
    n_box = 0
    for p in parts:
        if not p.get("name", "").startswith(CURTAIN_PREFIX):
            continue
        nb = len(p.get("boxes", []))
        if nb == 0:
            continue
        n_hit += 1
        n_box += nb
        print("[curtain] %-10s 去掉 %d 个盒子  mat=%s" % (p["name"], nb, p.get("mat")))
        if not dry:
            p["boxes"] = []

    total = sum(len(p.get("boxes", [])) for p in parts)
    print("[curtain] 处理 %d 件窗帘、删掉 %d 个盒子；剩余总盒数 %d" % (n_hit, n_box, total))

    if dry:
        print("[curtain] --dry：没写文件")
        return

    d["box_count"] = total
    with open(PARTS, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
    print("[curtain] 已写回 %s" % PARTS)
    print("[curtain] 下一步：godot --headless --path . --script res://scripts/_bake_esports_parts.gd")


main()
