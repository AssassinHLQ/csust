"""读 GLB 里的动画，报**真实时长 / 关键帧数 / 折算到各帧率的帧数**。

glTF 只存**秒**，不存帧。「几帧」取决于用哪个帧率解释，所以这里一次给三个：

    python tools/glb_anim.py models/Arisu_ext.glb
    python tools/glb_anim.py models/Arisu_ext.glb Attack
    python tools/glb_anim.py models/Arisu_ext.glb --fps 30

Blender 的 glTF 导入器按**场景帧率**换算：frame = 秒 × fps + 1。
所以同一段动画在 24 fps 和 60 fps 下「帧数」差 2.5 倍，但**时间长度一模一样**。
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys

COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
        5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path: str) -> tuple[dict, bytes]:
    with open(path, "rb") as f:
        magic, _ver, _len = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise SystemExit(f"不是 GLB：{path}")
        gltf: dict = {}
        binbuf = b""
        while True:
            head = f.read(8)
            if len(head) < 8:
                break
            clen, ctype = struct.unpack("<II", head)
            data = f.read(clen)
            if ctype == 0x4E4F534A:
                gltf = json.loads(data.decode("utf-8"))
            elif ctype == 0x004E4942:
                binbuf = data
    return gltf, binbuf


def read_floats(g: dict, blob: bytes, idx: int) -> list[float]:
    """读一个 float accessor 的全部数值（足够本工具用）。"""
    acc = g["accessors"][idx]
    ctype = acc["componentType"]
    n = NCOMP[acc["type"]]
    if ctype not in COMP:
        return []
    fmt, size = COMP[ctype]
    bv = g["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (size * n)
    out: list[float] = []
    for i in range(acc["count"]):
        off = base + i * stride
        vals = struct.unpack_from("<" + fmt * n, blob, off)
        out.extend(float(v) for v in vals)
    return out


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("filter", nargs="?", default="", help="只列名字里含这串的动画")
    ap.add_argument("--fps", type=float, nargs="*", default=[24.0, 30.0, 60.0])
    args = ap.parse_args()

    g, blob = load_glb(args.glb)
    anims = g.get("animations", [])
    print(f"{os.path.basename(args.glb)}：{len(anims)} 条动画\n")

    if not anims:
        print("没有 animations。")
        return 0

    rows = []
    for a in anims:
        name = a.get("name", "<无名>")
        if args.filter and args.filter.lower() not in name.lower():
            continue
        t_min = float("inf")
        t_max = float("-inf")
        max_keys = 0
        for s in a.get("samplers", []):
            times = read_floats(g, blob, s["input"])
            if not times:
                continue
            t_min = min(t_min, min(times))
            t_max = max(t_max, max(times))
            max_keys = max(max_keys, len(times))
        if t_min == float("inf"):
            continue
        dur = t_max - t_min
        rows.append((name, t_min, t_max, dur, max_keys, len(a.get("channels", []))))

    if not rows:
        print(f"没有名字含「{args.filter}」的动画。")
        return 0

    fps_list = args.fps
    head = f"{'动画':<32}{'起(s)':>8}{'止(s)':>8}{'时长(s)':>9}{'关键帧':>7}"
    for f in fps_list:
        lab = f"{int(f) if float(f).is_integer() else f}fps"
        head += f"{lab:>9}"
    print(head)
    print("-" * len(head))
    for name, t0, t1, dur, keys, ch in rows:
        line = f"{name:<32}{t0:>8.3f}{t1:>8.3f}{dur:>9.3f}{keys:>7}"
        for f in fps_list:
            line += f"{dur * f:>9.2f}"
        print(line)
    print()
    print("说明：glTF 只存秒；「帧数」= 时长 × 帧率。")
    print("      Blender 导入时用场景帧率换算（frame = 秒 × fps + 1），")
    print("      所以同一段动画在 24 / 30 / 60 fps 下帧数不同，时长相同。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
