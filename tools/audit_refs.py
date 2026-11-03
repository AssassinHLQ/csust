"""引用审计：找出「代码/场景硬引用了一个不在仓库里的文件」的地方。

这类问题最阴险 —— 本机因为文件都在，跑得好好的；别人克隆下来就炸。
2026-11-03 的电竞房海报就是这一种（`.tscn` 的 `[ext_resource]` 指向
.gitignore 挡掉的 BA 截图 → 整个场景 Parse Error → game.tscn 也起不来）。

用法：
    python tools/audit_refs.py            # 只报告问题
    python tools/audit_refs.py --all      # 连「软引用」一起列

判定：
    HARD   .tscn 的 [ext_resource]、.gd 的 preload()
           → 文件不在 = 场景/脚本加载失败，克隆后必炸
    SOFT   .gd 里 load("res://...") 或纯字符串路径
           → 文件不在只是那次调用拿不到东西，不炸
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## 已知且「有意为之」的硬引用：README §11.2 把主角模型标成**必需素材**，
## 没它就是没有游戏，所以缺了主动报错反而是对的。
## 这里的每一条都必须能在 README 里找到对应的「必需」说明。
ACCEPTED_HARD = {
    "models/Arisu.glb",       # 动画查看器 main.tscn
    "models/Arisu_ext.glb",   # 主角 player.tscn
}

# [ext_resource type="..." path="res://..." id="..."]
RE_TSCN_EXT = re.compile(r'\[ext_resource[^\]]*?path="(res://[^"]+)"')
# preload("res://...")  —— 解析期就要存在
RE_PRELOAD = re.compile(r'preload\("(res://[^"]+)"\)')
# load("res://...") / load('res://...')
RE_LOAD = re.compile(r'(?<!pre)load\("(res://[^"]+)"\)')
# 任何裸的 res:// 字符串（兜底，用于 --all）
RE_ANY = re.compile(r'"(res://[^"]+)"')


def git(*args: str) -> str:
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return out.stdout


def tracked() -> set[str]:
    """仓库里被跟踪的文件（相对路径，正斜杠）。"""
    return {p for p in git("ls-files").splitlines() if p}


def ignored(path: str) -> bool:
    r = subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT)
    return r.returncode == 0


def to_rel(url: str) -> str:
    return url.replace("res://", "").rstrip("/")


def main() -> int:
    # Windows 控制台默认 GBK，输出中文/符号会炸；强制 UTF-8。
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="连软引用一起列")
    args = ap.parse_args()

    tr = tracked()
    if not tr:
        print("!! git ls-files 没返回内容，确认在工程根目录下跑")
        return 2

    srcs = [p for p in tr if p.endswith((".tscn", ".gd", ".tres"))]
    hard_missing: list[tuple[str, str, str]] = []   # (引用方, 目标, 原因)
    accepted: list[tuple[str, str, str]] = []
    soft_missing: list[tuple[str, str]] = []

    for src in sorted(srcs):
        full = os.path.join(ROOT, src)
        try:
            text = open(full, encoding="utf-8", errors="replace").read()
        except OSError:
            continue

        if src.endswith(".tscn"):
            targets = [(m, "ext_resource") for m in RE_TSCN_EXT.findall(text)]
        else:
            targets = [(m, "preload") for m in RE_PRELOAD.findall(text)]

        for url, kind in targets:
            rel = to_rel(url)
            if rel.endswith("*") or "*" in rel or "%" in rel:
                continue  # 通配 / 格式化路径，跳过
            if not rel:
                continue
            # 目标是目录（比如 .glb 的 import 目录形式）也算存在性检查
            on_disk = os.path.exists(os.path.join(ROOT, rel))
            in_git = rel in tr
            if in_git:
                continue
            reason = "被 .gitignore 挡掉" if ignored(rel) else ("磁盘有但未跟踪" if on_disk else "磁盘上没有")
            if rel in ACCEPTED_HARD:
                accepted.append((src, rel, kind))
                continue
            hard_missing.append((src, rel, f"{kind} / {reason}"))

        if args.all:
            for url in RE_ANY.findall(text):
                rel = to_rel(url)
                if not rel or "*" in rel or "%" in rel:
                    continue
                if rel in tr or os.path.exists(os.path.join(ROOT, rel)):
                    continue
                if any(rel == h[1] for h in hard_missing):
                    continue
                soft_missing.append((src, rel))

    print(f"扫描 {len(srcs)} 个 .tscn/.gd/.tres\n")

    if not hard_missing:
        print("✅ 硬引用全部在仓库里（克隆后不会因为缺文件崩）")
    else:
        print(f"❌ {len(hard_missing)} 处硬引用指向仓库外的文件：\n")
        for src, rel, why in hard_missing:
            print(f"  {src}")
            print(f"    -> {rel}   [{why}]")
        print("\n  这些必须改成「运行时可缺」或把文件补进仓库，否则克隆后直接炸。")

    if accepted:
        print(f"\n已知且有意为之（README §11.2 的「必需素材」）共 {len(accepted)} 处：")
        for src, rel, kind in accepted:
            print(f"  {src} -> {rel}  [{kind}]")
        print("  缺它们时游戏起不来是**预期行为**，不是 bug。")

    if args.all:
        if soft_missing:
            print(f"\n以下是软引用（运行时可缺，不致命）共 {len(soft_missing)} 处：\n")
            seen: set[tuple[str, str]] = set()
            for src, rel in soft_missing:
                if (src, rel) in seen:
                    continue
                seen.add((src, rel))
                print(f"  {src}\n    -> {rel}")
        else:
            print("\n软引用也都找得到。")

    return 0 if not hard_missing else 1


if __name__ == "__main__":
    sys.exit(main())
