"""找出「只被上级目录条目覆盖、自己没有登记」的素材目录。

`Credits.covers()` 用的是**前缀匹配**，所以 `models` 这一条会覆盖 `models/` 下
任何没单独登记的目录。结果是新增一套素材目录、忘了署名，自检**也不会红**。
这个脚本把这种目录单独列出来。

    python tools/audit_credits.py
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COVER_ROOTS = ["models", "assets", "addons", "splatdata"]
RE_PATH = re.compile(r'"path":\s*"([^"]+)"')


def credited_paths() -> list[str]:
    text = open(os.path.join(ROOT, "scripts", "credits.gd"), encoding="utf-8").read()
    return [p.rstrip("/") for p in RE_PATH.findall(text)]


def subdirs(root: str) -> list[str]:
    base = os.path.join(ROOT, root)
    out: list[str] = []
    if not os.path.isdir(base):
        return out
    for dirpath, dirnames, _files in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        rel = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if rel != root:
            out.append(rel)
    return sorted(out)


def tracked(path: str) -> bool:
    import subprocess
    r = subprocess.run(["git", "ls-files", "--error-unmatch", path],
                       cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode == 0


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    own = set(credited_paths())
    exact: list[str] = []
    ancestor_only: list[str] = []

    for r in COVER_ROOTS:
        for sub in subdirs(r):
            if sub in own:
                exact.append(sub)
                continue
            # 有没有任何 own 条目是它的前缀？
            parent = next((q for q in own if sub.startswith(q + "/")), None)
            ancestor_only.append((sub, parent))

    print(f"素材目录共 {len(exact) + len(ancestor_only)} 个")
    print(f"  自己有条目：{len(exact)}")
    print(f"  只被上级条目盖住：{len(ancestor_only)}\n")

    if not ancestor_only:
        print("每个素材目录都有自己的署名条目。")
        return 0

    print("以下目录**没有自己的署名条目**，只有上级帮忙兜着：\n")
    flagged = 0
    for sub, parent in ancestor_only:
        has_tracked = any(
            tracked(os.path.join(sub, f).replace("\\", "/"))
            for f in os.listdir(os.path.join(ROOT, sub))
            if os.path.isfile(os.path.join(ROOT, sub, f))
        )
        mark = "★ 已入库" if has_tracked else "  （未入库）"
        print(f"  {mark}  {sub}")
        print(f"      只由「{parent}」覆盖")
        if has_tracked:
            flagged += 1
    print(f"\n其中 {flagged} 个目录的内容**真的提交进仓库了**，必须有自己的署名条目。")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
