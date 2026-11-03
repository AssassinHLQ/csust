"""查一条 glTF 动画里，指定帧区间内**哪根骨头在动、动多少**。

用来定位「25~45 帧这段突然抬起来」到底是脊柱、胸、脖子还是手臂造成的。

    python tools/glb_curve.py models/Arisu_ext.glb Normal_Attack_Ing --frames 25 45
    python tools/glb_curve.py models/Arisu_ext.glb Normal_Attack_Ing --frames 25 45 --dump "Spine"

每条通道输出：
    帧区间内的总转角 / 每帧最大转角 / 转折轴
位移通道输出总位移与每帧最大位移。
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys

COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
        5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path: str) -> tuple[dict, bytes]:
    with open(path, "rb") as f:
        magic, _v, _l = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise SystemExit(f"不是 GLB：{path}")
        gltf: dict = {}
        blob = b""
        while True:
            head = f.read(8)
            if len(head) < 8:
                break
            clen, ctype = struct.unpack("<II", head)
            data = f.read(clen)
            if ctype == 0x4E4F534A:
                gltf = json.loads(data.decode("utf-8"))
            elif ctype == 0x004E4942:
                blob = data
    return gltf, blob


def read_accessor(g: dict, blob: bytes, idx: int) -> list[tuple[float, ...]]:
    acc = g["accessors"][idx]
    ctype = acc["componentType"]
    n = NCOMP[acc["type"]]
    if ctype not in COMP:
        return []
    fmt, size = COMP[ctype]
    bv = g["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (size * n)
    out = []
    for i in range(acc["count"]):
        vals = struct.unpack_from("<" + fmt * n, blob, base + i * stride)
        out.append(tuple(float(v) for v in vals))
    return out


def q_angle_deg(a: tuple[float, ...], b: tuple[float, ...]) -> float:
    dot = abs(sum(x * y for x, y in zip(a, b)))
    dot = min(1.0, max(-1.0, dot))
    return math.degrees(2.0 * math.acos(dot))


def q_delta_axis(a: tuple[float, ...], b: tuple[float, ...]) -> str:
    """粗略判断两帧之间绕哪个轴转得多（在父空间里近似）。"""
    # 相对旋转 q = b * conj(a)
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    # conj(a) = (-ax,-ay,-az,aw)
    cx, cy, cz, cw = -ax, -ay, -az, aw
    rx = bw * cx + bx * cw + by * cz - bz * cy
    ry = bw * cy - bx * cz + by * cw + bz * cx
    rz = bw * cz + bx * cy - by * cx + bz * cw
    rw = bw * cw - bx * cx - by * cy - bz * cz
    if rw < 0:
        rx, ry, rz = -rx, -ry, -rz
    mags = {"X": abs(rx), "Y": abs(ry), "Z": abs(rz)}
    return max(mags, key=mags.get)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("clip")
    ap.add_argument("--frames", type=int, nargs=2, required=True)
    ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--dump", default="", help="把名字含这串的骨头的逐帧值打出来")
    ap.add_argument("--top", type=int, default=12)
    args = ap.parse_args()

    g, blob = load_glb(args.glb)
    f0, f1 = args.frames
    t0, t1 = f0 / args.fps, f1 / args.fps

    anim = next((a for a in g.get("animations", []) if a.get("name") == args.clip), None)
    if anim is None:
        print(f"没有动画 {args.clip}")
        return 1

    nodes = g.get("nodes", [])

    rows = []
    dumps: list[str] = []

    for ch in anim["channels"]:
        target = ch["target"]
        node_i = target["node"]
        path = target["path"]
        name = nodes[node_i].get("name", f"node{node_i}")
        s = anim["samplers"][ch["sampler"]]
        times = [v[0] for v in read_accessor(g, blob, s["input"])]
        vals = read_accessor(g, blob, s["output"])
        if not times or not vals:
            continue

        # 取帧区间两端的采样点（就近）
        def at(t: float) -> int:
            return min(range(len(times)), key=lambda i: abs(times[i] - t))

        print_u = "-"
        if path == "rotation" and len(vals[0]) == 4:
            ia, ib = at(t0), at(t1)
            total = q_angle_deg(vals[ia], vals[ib])
            # 窗口内每帧最大
            worst = 0.0
            axis = "-"
            for i in range(ia, ib):
                d = q_angle_deg(vals[i], vals[i + 1])
                if d > worst:
                    worst = d
                    axis = q_delta_axis(vals[i], vals[i + 1])
            rows.append((total, worst, name, path, axis))
            print_u = axis
            if args.dump and args.dump.lower() in name.lower():
                lines = [f"    {name} rotation 逐帧（角度增量）"]
                for i in range(ia, ib):
                    lines.append(f"      f{round(times[i] * args.fps):>4}  "
                                 f"{q_angle_deg(vals[i], vals[i + 1]):6.2f}°  "
                                 f"q=({vals[i][0]:+.3f},{vals[i][1]:+.3f},{vals[i][2]:+.3f},{vals[i][3]:+.3f})")
                dumps.append("\n".join(lines))
        elif path == "translation" and len(vals[0]) == 3:
            ia, ib = at(t0), at(t1)
            d = [vals[ib][k] - vals[ia][k] for k in range(3)]
            total = math.sqrt(sum(x * x for x in d)) * 1000.0  # mm
            worst = 0.0
            for i in range(ia, ib):
                step = [vals[i + 1][k] - vals[i][k] for k in range(3)]
                worst = max(worst, math.sqrt(sum(x * x for x in step)) * 1000.0)
            rows.append((total, worst, name, path, "-"))

    rows.sort(key=lambda r: r[0], reverse=True)

    print(f"{args.clip}：帧 {f0} ~ {f1}（{args.fps} fps，{t0:.3f} ~ {t1:.3f} s）\n")
    print(f"{'骨头':<26}{'通道':<12}{'区间总量':>10}{'每帧最大':>10}  轴")
    print("-" * 74)
    for total, worst, name, path, axis in rows[:args.top]:
        unit = "°" if path == "rotation" else "mm"
        print(f"{name:<26}{path:<12}{total:>9.2f}{unit}{worst:>9.2f}{unit}  {axis}")

    if dumps:
        print()
        for d in dumps:
            print(d)

    print("\n说明：只统计「rotation / translation」通道；")
    print("      「每帧最大」= 相邻两个关键帧之间的最大跳变 —— 这就是突兀感的来源。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
