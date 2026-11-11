"""从 `scenes/parkour.tscn` 删掉用户指定要去的 4 条 3D 大招牌文字节点。

用户 2026-11-11：「文字去除」，并选定「只删截图里那 4 条」+「直接从场景里删掉」。

要删的 4 个节点（都是 Label3D，只删**文字节点本身**，保留柱子/碰撞）：
  1. `SignPost/SignText`      「跑酷 · 12 段 →」
  2. `SignPost/StartSign`     「第 1 段 · 起点」
  3. `ParkourFutures/...`     「按 F 上箭 —— 去终点岛（结算屋）」  ← 见下面的定位
  4. `Island/...`             「火箭 · 去结算屋」                  ← 见下面的定位

做法：按 `[node name="..." ...]` 块解析，整块删掉（直到下一个 `[node` 或 `[connection`）。
⚠️ 用 Python 而不是 PowerShell：这个文件里全是中文，PowerShell 的编码会破坏它。
"""

import io
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PATH = "scenes/parkour.tscn"

# 要删的 (节点名, 父路径) —— 父路径用于消歧义
TARGETS = [
    ("SignText", "SignPost"),
    ("StartSign", "SignPost"),
]


def main():
    src = io.open(PATH, encoding="utf-8").read()
    lines = src.split("\n")

    # 先找出所有 Label3D 节点块，并打印它们的文字，方便人工核对
    blocks = []          # (start_idx, end_idx, name, parent, text)
    i = 0
    while i < len(lines):
        m = re.match(r'^\[node name="([^"]+)" type="Label3D" parent="([^"]*)"', lines[i])
        if m:
            name, parent = m.group(1), m.group(2)
            j = i + 1
            while j < len(lines) and not lines[j].startswith("["):
                j += 1
            text = ""
            for k in range(i, j):
                tm = re.match(r'^text = "(.*)"$', lines[k])
                if tm:
                    text = tm.group(1)
                    break
            blocks.append((i, j, name, parent, text))
        i += 1

    print("文件里共 %d 个 Label3D 节点。含这两个关键词的：" % len(blocks))
    for b in blocks:
        if any(k in b[4] for k in ("上箭", "火箭", "跑酷 · 12", "第 1 段 · 起点")):
            print("  %-14s parent=%-28s text=%s" % (b[2], b[3], b[4]))

    # 按 (name, parent) 挑出来删
    to_delete = []
    for b in blocks:
        for name, parent in TARGETS:
            if b[2] == name and b[3] == parent:
                to_delete.append(b)
    print("")
    print("本脚本负责删 %d 个（另外 2 条在别的脚本里定位）：" % len(to_delete))
    for b in to_delete:
        print("  - %s/%s  「%s」" % (b[3], b[2], b[4]))

    if not to_delete:
        print("★ 一个都没匹配到，什么都不做")
        return 1

    # 从后往前删，索引不会错位
    for start, end, name, parent, text in sorted(to_delete, reverse=True):
        del lines[start:end]
        print("  已删除 %s/%s" % (parent, name))

    io.open(PATH, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("写出 %s" % PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
