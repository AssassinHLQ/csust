"""生成跑酷第 3 段「同花顺 K 线区」：12 根红绿蜡烛，并把后 4 段整体西移。

为什么用脚本生成而不是在编辑器里手摆：

1. **这一段的全部风险都在「跳不跳得过去」上**。每根蜡烛的间距不是拍脑袋，
   是拿 `Player` 的真常数（跑速 6.8 / 跳速 7.1 / 重力 20）按弹道解出来的：
   先定「落到板上多深」（= 余量），再反推间距 —— 脚本里那条 `HOPS` 表就是这么算的，
   差 0.05 m 都能看出来。
2. **红绿必须和涨跌对上**。上涨的蜡烛一定是红（阳线）、下跌的一定是绿（阴线），
   这是「同花顺」的语义；手摆容易摆反，脚本里直接断言。
3. **插入一段要连带改 6 个地方**：`route` / `segments` / `seg_names` /
   `special_hops` / `short_hops` / 后面四个段的路标文字，还有 4 段站位的整体平移。
   手改必漏，而且漏了是「静默」的（自检照样绿，只是路标写着第 3 段其实是第 4 段）。

几何约定（和场景里其它站完全一致，自检第 1 节逐项核对）：
    · 一站 = `StaticBody3D`，节点原点在**箱体中心**；
    · `Mesh` / `Col` 是**同一个 1×1×1 单位盒**，靠 `scale` 拉成 (进深, 厚度, 宽度)；
    · 所有 position / scale 必须落在 **0.05 m 网格**上（否则自检第 1 节红）。

用法：
    python tools/make_flush_section.py             # 打印余量表 + 写回 scenes/parkour.tscn
    python tools/make_flush_section.py --dry-run   # 只打印，不写文件
"""

import math
import re
import sys
from pathlib import Path

# 控制台可能是 GBK（Windows），中文 + 负号会炸：统一按 UTF-8 输出
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
TSCN = ROOT / "scenes" / "parkour.tscn"

# --- 玩家的真常数（scripts/player.gd，改那里就得改这里 + 重跑自检第 3 节）---------
JUMP_V = 7.1
GRAVITY = 20.0
RUN_SPEED = 6.8
# 实测标定系数（`_verify_parkour.gd` 第 3 节每次都重量一遍，1.05 ~ 1.06）
K_MEAS = 1.054
# 挂边容忍（胶囊半径 0.30，见 README §1.16）
EDGE = 0.30

GRID = 0.05


def snap(v: float) -> float:
    return round(v / GRID) * GRID


# --- 蜡烛表 ---------------------------------------------------------------------
#
# top       台面高度（= 收盘价；玩家踩的就是它）
# margin    解析落点**离板近边**的距离 —— 也就是这一跳的余量（自检第 3 节的闸门）
# depth     进深（沿 x，行进方向）
# width     宽度（沿 z）
# z         z 中心（小幅「之」字，让线看起来不是一根直尺）
# body      实体厚度（纯视觉：蜡烛的「实体」，只朝下长，不影响台面）
# wd / wu   下影线 / 上影线长度（wu 挂在**远端边缘**，不挡走位）
# mat       up_a/up_b = 阳线（红，两档亮度）；dn_a/dn_b = 阴线（绿）
# pct       牌子上写的涨跌幅（flavor，断言只看正负号与涨跌一致）
CANDLES = [
    dict(name="K1",  top=2.00, margin=3.20, depth=3.60, width=3.80, z=-4.90,
         body=1.20, wd=1.20, wu=1.40, mat="up_a", pct="+0.00%", kind="十字星・开盘"),
    dict(name="K2",  top=2.60, margin=1.60, depth=3.00, width=3.00, z=-5.30,
         body=1.80, wd=0.60, wu=0.40, mat="up_a", pct="+2.31%", kind="小阳线"),
    dict(name="K3",  top=3.30, margin=1.40, depth=3.00, width=2.80, z=-4.60,
         body=2.40, wd=0.70, wu=0.50, mat="up_b", pct="+3.52%", kind="中阳线"),
    dict(name="K4",  top=3.90, margin=1.10, depth=2.60, width=2.60, z=-5.10,
         body=0.80, wd=2.00, wu=1.80, mat="up_a", pct="+2.24%", kind="十字星（长影）"),
    dict(name="K5",  top=4.60, margin=1.30, depth=3.20, width=3.00, z=-4.40,
         body=3.00, wd=0.60, wu=0.30, mat="up_b", pct="+3.31%", kind="大阳线"),
    dict(name="K6",  top=5.40, margin=1.00, depth=4.00, width=1.20, z=-4.90,
         body=0.90, wd=0.40, wu=0.00, mat="up_a", pct="+3.76%", kind="一字板（涨停・窄梁）"),
    dict(name="K7",  top=4.60, margin=1.50, depth=3.40, width=3.20, z=-5.40,
         body=2.80, wd=0.50, wu=0.80, mat="dn_b", pct="-3.48%", kind="大阴线"),
    dict(name="K8",  top=3.60, margin=1.60, depth=3.20, width=3.00, z=-4.50,
         body=2.00, wd=0.80, wu=0.70, mat="dn_a", pct="-4.55%", kind="跳空缺口"),
    dict(name="K9",  top=2.60, margin=1.30, depth=3.00, width=2.60, z=-5.20,
         body=2.60, wd=0.60, wu=0.70, mat="dn_b", pct="-4.61%", kind="大阴线"),
    dict(name="K10", top=1.70, margin=1.40, depth=3.20, width=3.00, z=-4.60,
         body=1.40, wd=1.60, wu=0.90, mat="dn_a", pct="-3.49%", kind="阴线・长下影"),
    dict(name="K11", top=1.20, margin=1.30, depth=2.80, width=2.80, z=-5.10,
         body=0.80, wd=2.20, wu=0.80, mat="dn_a", pct="-1.02%", kind="锤头线"),
    dict(name="K12", top=1.80, margin=1.60, depth=3.20, width=3.40, z=-4.90,
         body=1.60, wd=0.60, wu=0.80, mat="up_a", pct="+2.27%", kind="反转阳线"),
]

# 第 2 段终点 C2 的台面（场景里写死的 −135.65 / 4.30 / 台面 2.00），新段从它西边缘往西排
SEG2_END = dict(name="C2", top=2.00, x0=-137.80, x1=-133.50, z0=-7.05, z1=-2.75)

# 新段最后一根蜡烛 → 原第 3 段起点 X1（进深 3.70 / 宽 3.70 / 台面 2.00 / z −1.70）
X1_GAP_MARGIN = 1.60
X1_DEPTH = 3.70
X1_WIDTH = 3.70
X1_TOP = 2.00
X1_Z = -1.70

# 平移阈值：x 小于它、且父节点是 `.` 或 `Route` 的节点 = 原第 3~6 段（+ 岛 / 机关 / 柱）
SHIFT_MAX_X = -139.90

# 原数组（v3 的 59 站版）—— 生成器按这份「真值」重写，插入 K 段后自动偏移
BASE_ROUTE = [
    "Launch", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "C1",
    "B1", "BA", "S1", "BB", "T1", "T2", "T3", "T4", "T5", "T6", "C2",
    "X1", "X2", "X3", "X4", "X5", "F1", "F2", "C3",
    "W1", "W2", "W3", "W4", "W5", "W6", "W7", "C4",
    "E1", "Q1", "H1", "V1", "V2", "V3", "V4", "L1", "U1", "U2", "Q2", "H2", "C5",
    "R1", "R2", "R3", "R4", "R5", "J1", "J2", "J3", "J4", "Island",
]
BASE_SEGMENTS = [0, 9, 20, 28, 36, 49]
BASE_SEG_NAMES = ["起跳・极限跳", "独木桥・绕角・台阶链", "横跳区・移动平台",
                  "绕柱螺旋塔", "机关区（弹跳/消失/传送/气流）", "螺旋下降・竖井 → 终点岛"]
BASE_SPECIAL = [26, 27, 38, 45, 47, 48]      # F1 F2 H1 U2 H2 C5
BASE_SHORT = [29, 30, 31, 32, 33, 34, 35]    # W2…C4
INS_AT = BASE_ROUTE.index("C2")              # K 段插在 C2 之后
FLUSH_SEG_NAME = "同花顺 K 线区"

MATERIALS = {
    # 阳线（红）：涨停/大阳用亮红，普通用深红
    "up_a": ("Mat_k_up_a", (0.78, 0.13, 0.17), (0.42, 0.05, 0.07), 0.28),
    "up_b": ("Mat_k_up_b", (0.55, 0.09, 0.13), (0.30, 0.03, 0.05), 0.22),
    # 阴线（绿）
    "dn_a": ("Mat_k_dn_a", (0.10, 0.55, 0.28), (0.03, 0.28, 0.12), 0.25),
    "dn_b": ("Mat_k_dn_b", (0.07, 0.38, 0.20), (0.02, 0.20, 0.09), 0.20),
}


# --- 弹道（照抄 parkour.gd 的 hop_analysis / _verify_parkour 的判据）-------------

def reach_of(rise: float) -> float:
    """解析射程：跑速 × 滞空时间。抬升太高就无解（返回 −1）。"""
    disc = JUMP_V * JUMP_V - 2.0 * GRAVITY * rise
    if disc < 0.0:
        return -1.0
    return RUN_SPEED * (JUMP_V + math.sqrt(disc)) / GRAVITY


def hop(a: dict, b: dict) -> dict:
    """和 Parkour.hop_analysis 同源：起跳点取 A 上离 B 中心最近的点。"""
    cx = (b["x0"] + b["x1"]) * 0.5
    cz = (b["z0"] + b["z1"]) * 0.5
    tx = min(max(cx, a["x0"]), a["x1"])
    tz = min(max(cz, a["z0"]), a["z1"])
    nx = min(max(tx, b["x0"]), b["x1"])
    nz = min(max(tz, b["z0"]), b["z1"])
    required = math.hypot(nx - tx, nz - tz)
    rise = b["top"] - a["top"]
    reach = reach_of(rise)
    return dict(takeoff=(tx, tz), near=(nx, nz), required=required, rise=rise, reach=reach)


def exit_dist(b: dict, fx: float, fz: float, dx: float, dz: float) -> float:
    """从 (fx,fz) 沿 (dx,dz) 走出盒子的距离 —— 照抄 `_verify_parkour._exit`。"""
    t = math.inf
    if abs(dx) > 1e-9:
        t = min(t, (b["x1"] - fx) / dx if dx > 0 else (b["x0"] - fx) / dx)
    if abs(dz) > 1e-9:
        t = min(t, (b["z1"] - fz) / dz if dz > 0 else (b["z0"] - fz) / dz)
    return max(t, 0.0)


def landing_checks(a: dict, b: dict, h: dict) -> dict:
    """自检第 3 节那三条「入板」判据：前 / 后 / 侧 都要够，且要算上挂边。"""
    reach = h["reach"] * K_MEAS
    cx = (b["x0"] + b["x1"]) * 0.5
    cz = (b["z0"] + b["z1"]) * 0.5
    dx, dz = cx - h["takeoff"][0], cz - h["takeoff"][1]
    n = math.hypot(dx, dz) or 1.0
    dx, dz = dx / n, dz / n
    lx = h["takeoff"][0] + dx * reach
    lz = h["takeoff"][1] + dz * reach
    back = exit_dist(b, lx, lz, -dx, -dz)
    fwd = exit_dist(b, lx, lz, dx, dz)
    side = min(exit_dist(b, lx, lz, -dz, dx), exit_dist(b, lx, lz, dz, -dx))
    return dict(land=(lx, lz), back=back, fwd=fwd, side=side)


# --- 布局 -----------------------------------------------------------------------

def layout() -> list:
    """从 C2 西边缘往西排：gap 由「落点多深」（margin）反推。"""
    out = []
    prev = SEG2_END
    for c in CANDLES:
        rise = c["top"] - prev["top"]
        reach = reach_of(rise)
        if reach < 0:
            raise SystemExit("!! %s 抬升 %.2f 无解" % (c["name"], rise))
        gap = snap(reach * K_MEAS - c["margin"])
        x1 = snap(prev["x0"] - gap)
        x0 = snap(x1 - c["depth"])
        box = dict(c)
        # ⚠️ 影线长度必须归到 **0.1**：影线中心 = (实体厚 + 影线长) / 2，
        #    两个都是 0.05 的倍数时一半可能落在 0.025 上 —— 自检第 1 节会红。
        box["wd"] = round(float(c["wd"]), 1)
        box["wu"] = round(float(c["wu"]), 1)
        box.update(x0=x0, x1=x1, z0=snap(c["z"] - c["width"] * 0.5),
                   z1=snap(c["z"] + c["width"] * 0.5), gap=gap,
                   body_bottom=snap(c["top"] - c["body"]))
        out.append(box)
        prev = box
    # 最后一根 → X1：先算 X1 应该落在哪儿
    last = out[-1]
    reach = reach_of(X1_TOP - last["top"])
    gap_x1 = snap(reach * K_MEAS - X1_GAP_MARGIN)
    x1_center = snap(last["x0"] - gap_x1 - X1_DEPTH * 0.5)
    return out, dict(center=x1_center, gap=gap_x1)


def report(boxes: list, x1_tgt: dict) -> dict:
    prev = SEG2_END
    rows = []
    worst, worst_name, tight, jumps = math.inf, "", 0, 0
    for b in boxes + [dict(name="X1", top=X1_TOP, depth=X1_DEPTH, width=X1_WIDTH,
                           z=X1_Z, x0=x1_tgt["center"] - X1_DEPTH * 0.5,
                           x1=x1_tgt["center"] + X1_DEPTH * 0.5,
                           z0=X1_Z - X1_WIDTH * 0.5, z1=X1_Z + X1_WIDTH * 0.5)]:
        h = hop(prev, b)
        lc = landing_checks(prev, b, h)
        margin = h["reach"] * K_MEAS - h["required"]
        ok = margin >= 0.80 and lc["back"] + EDGE >= 0.40 and lc["fwd"] + EDGE >= 0.40 \
            and lc["side"] + EDGE >= 0.20
        rows.append(dict(name=b["name"], gap=h["required"], rise=h["rise"],
                         margin=margin, back=lc["back"], fwd=lc["fwd"],
                         side=lc["side"], lx=lc["land"][0], ok=ok, x=b["x0"]))
        jumps += 1
        if margin < worst:
            worst, worst_name = margin, "%s→%s" % (prev["name"], b["name"])
        if margin <= 0.90:
            tight += 1
        if not ok:
            print("  !! %s→%s 不合格：余量 %.2f  后 %.2f 前 %.2f 侧 %.2f"
                  % (prev["name"], b["name"], margin, lc["back"], lc["fwd"], lc["side"]))
        prev = b
    # 语义：上涨必须红、下跌必须绿（同花顺的红涨绿跌）
    prev = SEG2_END
    for b in boxes:
        up = b["top"] >= prev["top"]
        is_red = b["mat"].startswith("up")
        if up != is_red:
            print("  !! %s 涨跌与颜色不一致（%s / %s）" % (b["name"], up, b["mat"]))
        prev = b
    tops = [SEG2_END["top"]] + [b["top"] for b in boxes]
    print("\n  同花顺 K 线区：%d 根蜡烛，台面 %.2f → 峰 %.2f → 谷 %.2f → %.2f"
          % (len(boxes), tops[0], max(tops), min(tops), tops[-1]))
    print("  起伏幅度（峰 - 谷）= %.2f m；x 跨度 %.1f m"
          % (max(tops) - min(tops), SEG2_END["x0"] - boxes[-1]["x0"]))
    print("  %-6s %8s %7s %8s %8s %8s %8s %8s"
          % ("站", "间距", "抬升", "余量", "后", "前", "侧", "落点x"))
    for r in rows:
        print("  %-6s %8.2f %7.2f %8.2f %8.2f %8.2f %8.2f %8.2f"
              % (r["name"], r["gap"], r["rise"], r["margin"], r["back"], r["fwd"],
                 r["side"], r["lx"]))
    print("\n  最紧 %s 余量 %.2f m（闸门 0.80）；紧张区 %d/%d"
          % (worst_name, worst, tight, jumps))
    return dict(worst=worst, tight=tight, jumps=jumps, rows=rows)


# --- .tscn 文本手术 -------------------------------------------------------------

HEADER = re.compile(r"^\[(node|sub_resource|ext_resource|gd_scene|connection|resource)")
NODE = re.compile(r'^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]*)")?')
XF = re.compile(r"^transform = Transform3D\(([^)]*)\)$")


def chunks(text: str) -> list:
    """按 `[xxx]` 头切块（头之前的内容归第一块，通常是空串）。"""
    out, cur = [], []
    for line in text.split("\n"):
        if HEADER.match(line) and cur:
            out.append("\n".join(cur))
            cur = [line]
        else:
            cur.append(line)
    out.append("\n".join(cur))
    return out


def node_of(chunk: str):
    m = NODE.match(chunk.split("\n", 1)[0])
    if not m:
        return None
    return dict(name=m.group(1), type=m.group(2), parent=m.group(3) or ".")


POS = re.compile(r"^position = Vector3\(([^)]*)\)$")
POINT = re.compile(r"^(point_[ab]) = Vector3\(([^)]*)\)$")


def get_transform(chunk: str):
    """读节点自己的位置。**两种写法都要认**：
    `transform = Transform3D(...)`（编辑器保存的常态）和 `position = Vector3(...)`
    （无旋转无缩放时的简写 —— 旧版场景里就是这种；只认前者会**静默漏平移**，
    平台/柱留在原地、自检却说「平移了 49 个节点」）。"""
    for line in chunk.split("\n"):
        m = XF.match(line)
        if m:
            return [float(v) for v in m.group(1).split(",")]
        m = POS.match(line)
        if m:
            v = [float(x) for x in m.group(1).split(",")]
            return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, v[0], v[1], v[2]]
    return None


def set_x(chunk: str, dx: float) -> str:
    lines = chunk.split("\n")
    for i, line in enumerate(lines):
        m = XF.match(line)
        if m:
            v = [float(x) for x in m.group(1).split(",")]
            v[9] = snap(v[9] + dx)
            lines[i] = "transform = Transform3D(%s)" % ", ".join(_num(x) for x in v)
            break
        m = POS.match(line)
        if m:
            v = [float(x) for x in m.group(1).split(",")]
            v[0] = snap(v[0] + dx)
            lines[i] = "position = Vector3(%s)" % ", ".join(_num(x) for x in v)
            break
    return "\n".join(lines)


def get_points(chunk: str):
    """读 `point_a` 的 x（没有就返回 None）。"""
    for line in chunk.split("\n"):
        m = POINT.match(line)
        if m and m.group(1) == "point_a":
            return float(m.group(2).split(",")[0])
    return None


def set_points(chunk: str, dx: float) -> str:
    """移动平台的 `point_a` / `point_b` 是**导出的绝对坐标**，只平移节点不管这两个数
    ⇒ 平台一 `_ready` 就窜回老位置（实测：两台平台全红，人站着不动被带走 9.00 m）。"""
    lines = chunk.split("\n")
    for i, line in enumerate(lines):
        m = POINT.match(line)
        if m:
            v = [float(x) for x in m.group(2).split(",")]
            v[0] = snap(v[0] + dx)
            lines[i] = "%s = Vector3(%s)" % (m.group(1), ", ".join(_num(x) for x in v))
    return "\n".join(lines)


def _num(v: float) -> str:
    return ("%g" % round(v, 4))


def build_nodes(boxes: list, x1: dict) -> list:
    """每根蜡烛 → 节点块（StaticBody3D + Mesh + Col + 下影 + 上影 + 涨跌幅牌）。"""
    out = []
    for b in boxes:
        cy = snap(b["top"] - b["body"] * 0.5)
        out.append('[node name="%s" type="StaticBody3D" parent="Route"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)'
                   % (b["name"], _num(b["x0"] + b["depth"] * 0.5), _num(cy), _num(b["z"])))
        xf = "Transform3D(%s, 0, 0, 0, %s, 0, 0, 0, %s, 0, 0, 0)" % (
            _num(b["depth"]), _num(b["body"]), _num(b["width"]))
        out.append('[node name="Mesh" type="MeshInstance3D" parent="Route/%s"]\n'
                   'transform = %s\nmaterial_override = SubResource("%s")\n'
                   'mesh = SubResource("Box_unit")'
                   % (b["name"], xf, MATERIALS[b["mat"]][0]))
        out.append('[node name="Col" type="CollisionShape3D" parent="Route/%s"]\n'
                   'transform = %s\nshape = SubResource("Shape_unit")' % (b["name"], xf))
        if b["wd"] > 0.0:
            out.append('[node name="WickDown" type="MeshInstance3D" parent="Route/%s"]\n'
                       'transform = Transform3D(1, 0, 0, 0, %s, 0, 0, 0, 1, 0, %s, 0)\n'
                       'material_override = SubResource("Mat_k_wick")\n'
                       'mesh = SubResource("Box_wick")'
                       % (b["name"], _num(b["wd"]),
                          _num(-(b["body"] * 0.5 + b["wd"] * 0.5))))
        if b["wu"] > 0.0:
            out.append('[node name="WickUp" type="MeshInstance3D" parent="Route/%s"]\n'
                       'transform = Transform3D(1, 0, 0, 0, %s, 0, 0, 0, 1, %s, %s, 0)\n'
                       'material_override = SubResource("Mat_k_wick")\n'
                       'mesh = SubResource("Box_wick")'
                       % (b["name"], _num(b["wu"]), _num(-b["depth"] * 0.5),
                          _num(b["body"] * 0.5 + b["wu"] * 0.5)))
        col = "0.95, 0.25, 0.25, 1" if b["mat"].startswith("up") else "0.25, 0.9, 0.45, 1"
        out.append('[node name="Pct" type="Label3D" parent="Route/%s"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                   'pixel_size = 0.006\nbillboard = 1\nalpha_cut = 1\n'
                   'modulate = Color(%s)\ntext = "%s"\nfont_size = 48\noutline_size = 12'
                   % (b["name"], _num(b["body"] * 0.5 + 2.60), col, b["pct"]))
    # 段起点路标：照抄 Beacon_C* 的结构（杆 + 球 + 牌），文字改成「同花顺」
    bx = boxes[0]["x0"] + 0.60
    bz = snap(boxes[0]["z1"] + 0.90)
    by = snap(boxes[0]["top"] - 0.50)
    out.append('[node name="Beacon_K1" type="StaticBody3D" parent="Route"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)'
               % (_num(bx), _num(by), _num(bz)))
    for nm, sub, y, mat, mesh in [
            ("Mast", "Mat_tower", "2.5", "Mat_tower", "Cyl_mast"),
            ("Head", "Mat_beacon", "5.3", "Mat_beacon", "Sphere_beacon")]:
        out.append('[node name="%s" type="MeshInstance3D" parent="Route/Beacon_K1"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                   'material_override = SubResource("%s")\nmesh = SubResource("%s")'
                   % (nm, y, mat, mesh))
    out.append('[node name="Col" type="CollisionShape3D" parent="Route/Beacon_K1"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 0)\n'
               'shape = SubResource("Shape_mast")')
    out.append('[node name="Sign" type="Label3D" parent="Route/Beacon_K1"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.2, 0)\n'
               'pixel_size = 0.01\nbillboard = 1\nalpha_cut = 1\n'
               'text = "第 3 段 · 同花顺 K 线"\nfont_size = 64\noutline_size = 14')
    return out


def build_subresources() -> list:
    out = []
    for key, (mid, albedo, emiss, energy) in MATERIALS.items():
        out.append('[sub_resource type="StandardMaterial3D" id="%s"]\n'
                   'albedo_color = Color(%s, %s, %s, 1)\nmetallic = 0.1\nroughness = 0.45\n'
                   'emission_enabled = true\nemission = Color(%s, %s, %s, 1)\n'
                   'emission_energy_multiplier = %s'
                   % (mid, albedo[0], albedo[1], albedo[2], emiss[0], emiss[1], emiss[2],
                      energy))
    out.append('[sub_resource type="StandardMaterial3D" id="Mat_k_wick"]\n'
               'albedo_color = Color(0.24, 0.26, 0.31, 1)\nmetallic = 0.35\nroughness = 0.5')
    out.append('[sub_resource type="BoxMesh" id="Box_wick"]\nsize = Vector3(0.15, 1, 0.15)')
    return out


def rewrite_arrays(text: str, boxes: list) -> str:
    names = [c["name"] for c in boxes]
    route = BASE_ROUTE[:INS_AT + 1] + names + BASE_ROUTE[INS_AT + 1:]
    n = len(names)
    # 新段插在 C2 之后 ⇒ 段起点：前 3 个不动，X1 那一段（20）让位给 K1，整体 +n
    segments = [int(v) for v in BASE_SEGMENTS[:3]] + [BASE_SEGMENTS[2] + n]         + [v + n for v in BASE_SEGMENTS[3:]]
    seg_names = BASE_SEG_NAMES[:2] + [FLUSH_SEG_NAME] + BASE_SEG_NAMES[2:]
    # ⚠️ 判据是「站号 ≥ 插入点」，不是「≥ 第 4 段起点」——F1/F2（26/27）也在插入点之后
    special = [v + n if v >= INS_AT + 1 else v for v in BASE_SPECIAL]
    short = [v + n for v in BASE_SHORT]
    subs = [
        ("route", "[%s]" % ", ".join('NodePath("%s")' % ("Route/" + r)
                                     if r not in ("Launch", "Island") else 'NodePath("%s")' % r
                                     for r in route)),
        ("segments", "[%s]" % ", ".join(str(v) for v in segments)),
        ("seg_names", "[%s]" % ", ".join('"%s"' % s for s in seg_names)),
        ("special_hops", "[%s]" % ", ".join(str(v) for v in special)),
        ("short_hops", "[%s]" % ", ".join(str(v) for v in short)),
    ]
    lines = text.split("\n")
    for i, line in enumerate(lines):
        for key, val in subs:
            if line.startswith(key + " = "):
                lines[i] = "%s = %s" % (key, val)
    return "\n".join(lines)


def bump_labels(parts: list) -> list:
    """后面四段的「第 N 段 · 终点」整体后移一位（不然牌子和 HUD 对不上）。

    ⚠️ 必须**按节点名写死**，不能用「把所有『第 3 段』换成『第 4 段』」：
       那样第二次跑生成器会把 C3 的牌子再推到第 5 段（生成器就不可重入）。
    """
    for i, ch in enumerate(parts):
        nd = node_of(ch)
        if nd is None:
            continue
        want = {"Beacon_C3": "第 4 段 · 终点", "Beacon_C4": "第 5 段 · 终点",
                "Beacon_C5": "第 6 段 · 终点", "SignPost": "跑酷 · 7 段 →",
                "SignText": "跑酷 · 7 段 →"}.get(nd["name"])
        if want is None:
            continue
        parts[i] = re.sub(r'(?m)^text = ".*"$', 'text = "%s"' % want, ch)
    return parts


def grid_check(boxes: list) -> None:
    """生成期就把「0.05 m 网格」卡住 —— 自检第 1 节那条红起来很难查
    （这次就是影线中心落在 0.025 上，12 根里 3 根中招）。"""
    bad = []
    for b in boxes:
        vals = {"top": b["top"], "body": b["body"], "depth": b["depth"],
                "width": b["width"], "z": b["z"], "wd": b["wd"], "wu": b["wu"],
                "x": b["x0"] + b["depth"] * 0.5,
                "cy": b["top"] - b["body"] * 0.5,
                "wick_down_y": -(b["body"] * 0.5 + b["wd"] * 0.5),
                "wick_up_y": b["body"] * 0.5 + b["wu"] * 0.5,
                "label_y": b["body"] * 0.5 + 2.60}
        for k, v in vals.items():
            q = abs(v) / GRID
            if abs(q - round(q)) > 1e-6:
                bad.append("%s.%s=%g" % (b["name"], k, v))
    if bad:
        raise SystemExit("!! 没落在 0.05 m 网格上：%s" % ", ".join(bad))


def main() -> None:
    dry = "--dry-run" in sys.argv
    boxes, x1 = layout()
    grid_check(boxes)
    stats = report(boxes, x1)
    if stats["worst"] < 0.80:
        raise SystemExit("!! 最紧的余量 %.2f < 0.80，先调 CANDLES 表" % stats["worst"])

    text = TSCN.read_text(encoding="utf-8")
    parts = chunks(text)

    # 1) 先量 X1 现在在哪儿（上次生成过就是已经平移过的位置）
    cur_x1 = None
    for ch in parts:
        nd = node_of(ch)
        if nd and nd["parent"] == "Route" and nd["name"] == "X1":
            cur_x1 = get_transform(ch)[9]
    if cur_x1 is None:
        raise SystemExit("!! 找不到 Route/X1")
    delta = snap(x1["center"] - cur_x1)
    print("\n  后 4 段整体平移：X1 %.2f → %.2f（Δ = %+.2f m）"
          % (cur_x1, x1["center"], delta))

    # 2) 丢掉上次生成的块
    gen = []
    for ch in parts:
        nd = node_of(ch)
        if nd is None:
            gen.append(ch)
            continue
        top = nd["parent"].split("/")[1] if "/" in nd["parent"] else nd["name"]
        if re.fullmatch(r"K\d+", nd["name"]) or re.fullmatch(r"K\d+", top) \
                or nd["name"] == "Beacon_K1" or top == "Beacon_K1":
            continue
        gen.append(ch)

    # 3) 平移第 3~6 段 + 岛 / 机关 / 柱
    #    ⚠️ `Movers` / `Mechanics` / `Pillars` 这三个组节点自己在原点（没有 transform），
    #       它们的子节点 x 就是世界 x —— 漏掉这三组，移动平台和传送门会留在原地。
    shift_hosts = (".", "Route", "Movers", "Mechanics", "Pillars")
    shifted = 0
    for i, ch in enumerate(gen):
        nd = node_of(ch)
        if nd is None or nd["parent"] not in shift_hosts:
            continue
        xf = get_transform(ch)
        if xf is None or xf[9] >= SHIFT_MAX_X:
            continue
        gen[i] = set_x(ch, delta)
        if nd["parent"] == "Movers":
            # 端点用**节点实际位置**校准（point_a 原本就等于节点位置）：
            # 这样即使上一次跑漏了（历史 bug），这一次也会自己补上，可重入。
            nx = get_transform(gen[i])[9]
            pa = get_points(gen[i])
            if pa is not None:
                gen[i] = set_points(gen[i], nx - pa)
        shifted += 1
    print("  平移了 %d 个节点" % shifted)

    # 4) 子资源（缺哪个补哪个）
    have = set(re.findall(r'id="([^"]+)"', "\n".join(gen)))
    add = [s for s in build_subresources() if re.search(r'id="([^"]+)"', s).group(1) not in have]
    if add:
        last_sub = max(i for i, ch in enumerate(gen) if ch.startswith("[sub_resource"))
        gen[last_sub + 1:last_sub + 1] = add

    # 5) 新蜡烛块插在 C2 子树之后
    c2_end = 0
    for i, ch in enumerate(gen):
        nd = node_of(ch)
        if nd and (nd["name"] == "C2" or nd["parent"].startswith("Route/C2")
                   or nd["parent"] == "Route/C2"):
            c2_end = i
    gen[c2_end + 1:c2_end + 1] = build_nodes(boxes, x1)

    gen = bump_labels(gen)
    out = "\n".join(gen)
    out = rewrite_arrays(out, boxes)
    out = re.sub(r"\n{3,}", "\n\n", out)

    print("\n  站数 %d → %d；段数 6 → 7" % (len(BASE_ROUTE), len(BASE_ROUTE) + len(boxes)))
    if dry:
        print("  --dry-run：不写文件")
        return
    TSCN.write_text(out, encoding="utf-8")
    print("  已写入 %s" % TSCN.relative_to(ROOT))


if __name__ == "__main__":
    main()
