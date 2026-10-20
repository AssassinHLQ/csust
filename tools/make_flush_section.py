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
    # 期货通版：z 在 −10.2 ~ −3.9 之间甩（四面八方），高度 2.00 → 6.60 → 2.00。
    # `ferry`：这一跳之间的**直跳是不可能的**，靠会动的方块摆渡（见 parkour_futures.gd）。
    # `mat="sch"`：薛定谔块 —— 踩上去之前不知道红绿（运行时才坍缩）。
    dict(name="K1",  top=2.00, margin=3.20, depth=3.60, width=3.80, z=-4.90,
         body=1.20, wd=1.20, wu=1.40, mat="up_a", pct="+0.00%", kind="开盘十字星"),
    dict(name="K2",  top=2.60, margin=1.60, depth=3.00, width=3.20, z=-8.20,
         body=1.80, wd=0.60, wu=0.40, mat="up_a", pct="+2.31%", kind="小阳线"),
    dict(name="K3",  top=3.30, margin=1.45, depth=3.00, width=3.00, z=-3.90,
         body=2.40, wd=0.70, wu=0.50, mat="up_b", pct="+3.52%", kind="中阳线"),
    dict(name="K4",  top=3.90, margin=1.10, depth=2.60, width=2.60, z=-9.20,
         body=0.80, wd=2.00, wu=1.80, mat="up_a", pct="+2.24%", kind="十字星（长影）"),
    dict(name="K5",  top=4.60, margin=1.30, depth=3.20, width=3.00, z=-4.90,
         body=3.00, wd=0.60, wu=0.30, mat="up_b", pct="+3.31%", kind="大阳线"),
    dict(name="K6",  top=6.20, ferry="lift", depth=4.00, width=2.00, z=-8.40,
         body=0.90, wd=0.40, wu=0.00, mat="up_a", pct="+3.76%", kind="一字板（涨停留）+ 升降台"),
    dict(name="K7",  top=6.80, margin=1.20, depth=2.80, width=2.80, z=-6.20,
         body=1.60, wd=0.90, wu=0.90, mat="sch", pct="+2.90%", kind="薛定谔・十字星"),
    dict(name="K8",  top=6.20, ferry="slide", depth=3.40, width=3.20, z=-10.20,
         body=2.80, wd=0.50, wu=0.80, mat="dn_b", pct="-3.48%", kind="大阴线 + 平移台"),
    dict(name="K9",  top=5.40, margin=1.40, depth=3.20, width=3.00, z=-5.90,
         body=1.40, wd=1.30, wu=0.70, mat="sch", pct="-2.10%", kind="薛定谔"),
    dict(name="K10", top=4.60, margin=1.30, depth=3.00, width=2.60, z=-10.20,
         body=2.60, wd=0.60, wu=0.70, mat="dn_b", pct="-4.61%", kind="大阴线（布朗块在旁边）"),
    dict(name="K11", top=3.60, margin=1.45, depth=3.20, width=3.00, z=-6.30,
         body=1.40, wd=1.60, wu=0.90, mat="dn_a", pct="-3.49%", kind="阴线・长下影"),
    dict(name="K12", top=2.60, margin=1.30, depth=2.80, width=2.80, z=-9.50,
         body=0.80, wd=2.20, wu=0.80, mat="sch", pct="+1.80%", kind="薛定谔・锤头"),
    dict(name="K13", top=2.00, margin=1.45, depth=3.20, width=3.40, z=-4.60,
         body=1.60, wd=0.60, wu=0.80, mat="dn_a", pct="-0.80%", kind="收盘阴线"),
]

# 第 2 段终点 C2 的台面（场景里写死的 −135.65 / 4.30 / 台面 2.00），新段从它西边缘往西排
SEG2_END = dict(name="C2", top=2.00, x0=-137.80, x1=-133.50, z0=-7.05, z1=-2.75)

# 新段最后一根蜡烛 → 原第 3 段起点 X1（进深 3.70 / 宽 3.70 / 台面 2.00 / z −1.70）
# 渡船跳（升降台 / 平移台）的**边到边**缺口：必须**大于**直跳射程，
# 否则玩家可以绕过会动的方块直接跳过去，那这些机关就白做了。
FERRY_GAP = 6.00
FERRY_GAP_SLIDE = 6.20

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
BASE_SEG_NAMES = ["起跳・极限跳", "独木桥・绕角・台阶链",
                  "内存条市场・横跳", "内存条螺旋塔",
                  "机关区（弹跳/消失/传送/气流）", "螺旋下降・竖井 → 终点岛"]
BASE_SPECIAL = [26, 27, 38, 45, 47, 48]      # F1 F2 H1 U2 H2 C5
BASE_SHORT = [29, 30, 31, 32, 33, 34, 35]    # W2…C4
INS_AT = BASE_ROUTE.index("C2")              # K 段插在 C2 之后
FLUSH_SEG_NAME = "同花顺期货通"

MATERIALS = {
    # 阳线（红）：涨停/大阳用亮红，普通用深红
    "up_a": ("Mat_k_up_a", (0.78, 0.13, 0.17), (0.42, 0.05, 0.07), 0.28),
    "up_b": ("Mat_k_up_b", (0.55, 0.09, 0.13), (0.30, 0.03, 0.05), 0.22),
    # 阴线（绿）
    "dn_a": ("Mat_k_dn_a", (0.10, 0.55, 0.28), (0.03, 0.28, 0.12), 0.25),
    "dn_b": ("Mat_k_dn_b", (0.07, 0.38, 0.20), (0.02, 0.20, 0.09), 0.20),
    # 薛定谔：踩上去之前是这个灰紫色，坍缩时才换成红/绿（见 parkour_futures.gd）
    "sch": ("Mat_k_unknown", (0.34, 0.30, 0.46), (0.30, 0.24, 0.55), 0.45),
    # 第 4 段三道：底板颜色固定表示「哪一类」，跳的是牌子上的数字
    "m_spot": ("Mat_b_spot", (0.90, 0.85, 0.66), (0.45, 0.40, 0.24), 0.18),
    "m_swap": ("Mat_b_swap", (0.95, 0.56, 0.12), (0.55, 0.26, 0.03), 0.30),
    "m_btc": ("Mat_b_btc", (0.88, 0.33, 0.05), (0.45, 0.10, 0.02), 0.34),
    # 第 5~7 段：期权（权利金深紫 / 行权亮青）、A股（涨停红 / 跌停绿 / 天地板紫红）、
    # 外汇（金 / 杠杆橙金 / 闪崩暗红）
    "m_opt_prem": ("Mat_s_opt_prem", (0.45, 0.30, 0.75), (0.20, 0.12, 0.45), 0.30),
    "m_opt_exer": ("Mat_s_opt_exer", (0.15, 0.75, 0.85), (0.05, 0.40, 0.50), 0.35),
    "m_ash_up": ("Mat_s_ash_up", (0.85, 0.12, 0.14), (0.45, 0.04, 0.05), 0.30),
    "m_ash_dn": ("Mat_s_ash_dn", (0.08, 0.55, 0.22), (0.02, 0.28, 0.10), 0.28),
    "m_ash_lei": ("Mat_s_ash_lei", (0.72, 0.10, 0.45), (0.36, 0.03, 0.20), 0.32),
    "m_fx": ("Mat_s_fx", (0.95, 0.80, 0.20), (0.50, 0.40, 0.06), 0.28),
    "m_fx_lev": ("Mat_s_fx_lev", (1.00, 0.52, 0.05), (0.55, 0.24, 0.01), 0.36),
    "m_fx_crash": ("Mat_s_fx_crash", (0.55, 0.05, 0.08), (0.30, 0.01, 0.02), 0.40),
    # 第 8 段「暗网黑市」：深紫黑 + 紫霓虹边
    # ⚠️ 用户 2026-10-19：「黑市太黑了」—— 上一版 albedo 0.02 进场景几乎纯黑，
    #    板沿 / 台面高度全看不见，跳哪块只能靠猜。抬到 0.16（仍是黑市的深紫，
    #    但顶面吃得到光、边角有轮廓），紫霓虹发光保留。
    "m_spot_dark": ("Mat_s_dark", (0.16, 0.13, 0.24), (0.42, 0.13, 0.78), 0.30),
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

def make_box(c: dict, x1: float) -> dict:
    box = dict(c)
    box["wd"] = round(float(c["wd"]), 1)
    box["wu"] = round(float(c["wu"]), 1)
    box.update(x1=snap(x1), x0=snap(x1 - c["depth"]),
               z0=snap(c["z"] - c["width"] * 0.5),
               z1=snap(c["z"] + c["width"] * 0.5))
    return box


def solve_gap(prev: dict, c: dict) -> float:
    """二分出**边到边**的 x 间距，让**解析落点正落在目标板中心**。

    ⚠️ 不能直接 `gap = 射程 − 余量`：台面在 z 上甩开之后 `required` 是**斜距**，
       还夹着两块板之间的 z 边缝，x 间距只是它的一个分量。第一版照抄直线版公式，
       K3→K4 的余量直接掉到 0.25；第二版改成「解余量」，又因为斜跳把落点顶到板外
       （前 / 侧 都是 0）。**只有解「落点在板上」这一条同时管住上下界**：
       余量 = 近边到落点的距离，落在中心 ⇒ 前后各半个板、侧向也是半个板。
    """
    def err(gap: float) -> float:
        box = make_box(c, prev["x0"] - gap)
        h = hop(prev, box)
        cx = (box["x0"] + box["x1"]) * 0.5
        cz = (box["z0"] + box["z1"]) * 0.5
        tx, tz = h["takeoff"]
        dx, dz = cx - tx, cz - tz
        n = math.hypot(dx, dz) or 1.0
        reach = h["reach"] * K_MEAS
        lx, lz = tx + dx / n * reach, tz + dz / n * reach
        return (lx - cx) * dx / n + (lz - cz) * dz / n

    lo, hi = 0.0, 12.0
    if err(lo) < 0.0:
        return 0.0
    for _ in range(60):
        mid = (lo + hi) * 0.5
        if err(mid) > 0.0:
            lo = mid
        else:
            hi = mid
    return snap((lo + hi) * 0.5)


def layout() -> list:
    """从 C2 西边缘往西排。

    普通跳：gap 由「落点多深」（margin）反推；
    **渡船跳**（`ferry`）：gap 直接给死（6.00 / 6.20 m），并断言**直跳一定过不去** ——
    不然玩家可以绕过会动的方块直接跳过去，那套机关就白做了。
    """
    out = []
    prev = SEG2_END
    for c in CANDLES:
        rise = c["top"] - prev["top"]
        if c.get("ferry"):
            gap = FERRY_GAP if c["ferry"] != "slide" else FERRY_GAP_SLIDE
        else:
            reach = reach_of(rise)
            if reach < 0:
                raise SystemExit("!! %s 抬升 %.2f 无解" % (c["name"], rise))
            gap = solve_gap(prev, c)
        x1 = snap(prev["x0"] - gap)
        x0 = snap(x1 - c["depth"])
        box = make_box(c, x1)
        box.update(gap=gap, body_bottom=snap(c["top"] - c["body"]))
        out.append(box)
        prev = box
    last = out[-1]
    reach = reach_of(X1_TOP - last["top"])
    gap_x1 = snap(reach * K_MEAS - X1_GAP_MARGIN)
    x1_center = snap(last["x0"] - gap_x1 - X1_DEPTH * 0.5)
    return out, dict(center=x1_center, gap=gap_x1)


def report(boxes: list, x1_tgt: dict, include_x1: bool = True) -> dict:
    prev = SEG2_END
    rows = []
    worst, worst_name, tight, jumps, ferries = math.inf, "", 0, 0, 0
    tail = [] if not include_x1 else [dict(name="X1", top=X1_TOP, depth=X1_DEPTH, width=X1_WIDTH,
                                          z=X1_Z, x0=x1_tgt["center"] - X1_DEPTH * 0.5,
                                          x1=x1_tgt["center"] + X1_DEPTH * 0.5,
                                          z0=X1_Z - X1_WIDTH * 0.5, z1=X1_Z + X1_WIDTH * 0.5)]
    for b in boxes + tail:
        h = hop(prev, b)
        lc = landing_checks(prev, b, h)
        margin = h["reach"] * K_MEAS - h["required"]
        if b.get("ferry"):
            # 渡船跳：直跳**必须过不去**（余量 < 0），否则机关会被绕过
            if margin >= 0.0:
                print("  !! %s→%s 直跳余量 %.2f ≥ 0，渡船会被绕过"
                      % (prev["name"], b["name"], margin))
            rows.append(dict(name=b["name"], gap=h["required"], rise=h["rise"],
                             margin=margin, back=0.0, fwd=0.0, side=0.0,
                             lx=h["takeoff"][0], ok=True, x=b["x0"],
                             ferry=b["ferry"]))
            ferries += 1
            prev = b
            continue
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
    # 语义：上涨必须红、下跌必须绿（同花顺的红涨绿跌）。薛定谔块没有固定颜色，跳过。
    prev = SEG2_END
    for b in boxes:
        up = b["top"] >= prev["top"]
        if b["mat"] == "sch":
            prev = b
            continue
        is_red = b["mat"].startswith("up")
        if up != is_red:
            print("  !! %s 涨跌与颜色不一致（%s / %s）" % (b["name"], up, b["mat"]))
        prev = b
    tops = [SEG2_END["top"]] + [b["top"] for b in boxes]
    print("\n  同花顺 K 线区：%d 根蜡烛，台面 %.2f → 峰 %.2f → 谷 %.2f → %.2f"
          % (len(boxes), tops[0], max(tops), min(tops), tops[-1]))
    print("  起伏幅度（峰 - 谷）= %.2f m；x 跨度 %.1f m"
          % (max(tops) - min(tops), SEG2_END["x0"] - boxes[-1]["x0"]))
    print("  %-6s %8s %7s %8s %8s %8s %8s %8s  %s"
          % ("站", "间距", "抬升", "余量", "后", "前", "侧", "落点x", "方式"))
    for r in rows:
        print("  %-6s %8.2f %7.2f %8.2f %8.2f %8.2f %8.2f %8.2f  %s"
              % (r["name"], r["gap"], r["rise"], r["margin"], r["back"], r["fwd"],
                 r["side"], r["lx"],
                 "渡船·" + r.get("ferry", "") if r.get("ferry") else "跳"))
    print("\n  最紧 %s 余量 %.2f m（闸门 0.80）；紧张区 %d/%d；渡船 %d 处"
          % (worst_name, worst, tight, jumps, ferries))
    return dict(worst=worst, tight=tight, jumps=jumps, rows=rows, ferries=ferries)


# --- 第 4 段：比特币三线（分叉台 → 三道 → 结算台）-------------------------------
#
# 用户原话：「后面也要同花顺期货通，但是这次加上比特币。修改保证金初始是 10w；
# 后面的不能只是方块换颜色，要更多不同的方块，不同的方块移动变化逻辑，多条路线
# 选择，不是纯看操作了，而是要动脑子，决策路线。」
#
# 三道在 z 上拉开 **9 m**（−1 / −10 / −19）：板宽 3 m ⇒ 相邻两道的边缝 6 m，
# 而平地直跳射程只有 4.83 × 1.054 ≈ 5.09 m —— 再近一点就能横着跨道，
# 「三条路线」立刻作废。生成期 `check_branch()` 把这条卡死。
BRANCH_Z = (-20.5, 1.5)          # 分叉台 / 结算台的 z 范围（22 m 宽的大厅）
BRANCH_DEPTH = 5.0               # 分叉台 / 结算台的进深
BRANCH_J_GAP = 3.20              # K13 → 分叉台
BRANCH_M_GAP = 3.50              # 结算台 → X1
BRANCH_PLATE_DEPTH = 3.0
LANE_GAPS = (3.00, 2.60, 6.00)   # 分叉台→p1 / p1→p2 / p2→p3（第三段是渡船，直跳必须过不去）
BRANCH_NAME = "同花顺期货通 · 比特币"
LANES = [
    # `seq` 是牌子上的价目序列（%）：spot 只有一档（永不跳），swap 两档交替，
    # btc 四档轮转。顺序就是「第 1 块踩上去最常看到的那个数」，运行时按 `period` 轮。
    dict(key="A", prefix="SP", cn="现货道", note="稳", z=-1.0,
         tops=(2.00, 2.40, 2.40), width=3.0, kind="spot",
         seq="3.00", period=0.0, ferry="slide"),
    dict(key="B", prefix="PP", cn="永续道", note="时机", z=-10.0,
         tops=(2.00, 2.60, 3.20), width=3.0, kind="swap",
         seq="8.00,-5.00", period=3.0, ferry="lift"),
    # 2026-10-18 用户：「比特币杠杆调大点，但是变化快点」——波动从 −6~+9 拉到
    # −14~+22（3 倍杠杆的味道），周期从 3.6 s 砍到 **1.6 s**（每档 0.4 s，
    # 站在前一块板上已经等不起了，只能凭节奏跳）。
    dict(key="C", prefix="BC", cn="币圈道", note="赌", z=-19.0,
         tops=(2.00, 2.20, 2.20), width=2.8, kind="btc",
         seq="-14.00,-3.00,+9.00,+22.00", period=1.6, ferry="pulse"),
]
# 结算门槛（万）：三道里 A 注定够不着（+9.27%），B/C 靠时机才能过 —— 这才是「决策」
HEDGE_TARGET = 11.0


def branch_label(ln: dict) -> str:
    """牌子上的价目：`+3.00%` / `+8.00%/−5.00%` / `−6.00%…+9.00%`。"""
    seq = [float(v) for v in ln["seq"].split(",")]
    if len(seq) == 1:
        return "%+.2f%% 固定" % seq[0]
    if len(seq) == 2:
        return "%+.2f%% / %+.2f%% 交替" % (seq[0], seq[1])
    return "%+.0f%% ~ %+.0f%% 四档" % (min(seq), max(seq))


def branch_money(ln: dict, best: bool) -> float:
    """三道各 3 块，涨跌幅按乘法累计 → 期末保证金（万，起始 10 万）。"""
    seq = [float(v) for v in ln["seq"].split(",")]
    pct = max(seq) if best else min(seq)
    return 10.0 * (1.0 + pct / 100.0) ** 3


def layout_branch(k13: dict) -> dict:
    """从 K13 西边缘往西排：分叉台 → 三道（各 3 块 + 1 个渡船）→ 结算台。"""
    j = dict(name="J0", top=2.00, z0=BRANCH_Z[0], z1=BRANCH_Z[1],
             x1=snap(k13["x0"] - BRANCH_J_GAP))
    j["x0"] = snap(j["x1"] - BRANCH_DEPTH)
    lanes, lane_end = [], None
    for ln in LANES:
        plates, x = [], j["x0"]
        for i in range(3):
            gap = LANE_GAPS[i]
            x1 = snap(x - gap)
            x0 = snap(x1 - BRANCH_PLATE_DEPTH)
            plates.append(dict(
                name="%s%d" % (ln["prefix"], i + 1), x0=x0, x1=x1,
                z=ln["z"], z0=snap(ln["z"] - ln["width"] * 0.5),
                z1=snap(ln["z"] + ln["width"] * 0.5), top=ln["tops"][i],
                depth=BRANCH_PLATE_DEPTH, width=ln["width"], gap=gap,
                lane=ln, idx=i))
            x = x0
        lane_end = x if lane_end is None else min(lane_end, x)
        lanes.append(plates)
    m = dict(name="M0", top=2.00, z0=BRANCH_Z[0], z1=BRANCH_Z[1],
             x1=snap(lane_end - BRANCH_M_GAP))
    m["x0"] = snap(m["x1"] - BRANCH_DEPTH)
    return dict(j=j, m=m, lanes=lanes,
                x1=dict(center=snap(m["x0"] - BRANCH_M_GAP - X1_DEPTH * 0.5),
                        gap=BRANCH_M_GAP))


def check_branch(br: dict) -> None:
    """生成期把硬约束卡死：跨道够不着、渡船直跳过不去、三道收益算得出来。"""
    flat = reach_of(0.0) * K_MEAS
    for lo, hi in zip(br["lanes"], br["lanes"][1:]):
        gap = min(p["z0"] for p in lo) - max(p["z1"] for p in hi)
        if gap <= flat + 0.20:
            raise SystemExit("!! %s|%s 跨道缺口只有 %.2f m（平地直跳 %.2f m），能横着跨道"
                             % (lo[0]["name"], hi[0]["name"], gap, flat))
        print("  跨道缺口 %s|%s = %.2f m（平地直跳 %.2f m，够不着 ✓）"
              % (lo[0]["lane"]["key"], hi[0]["lane"]["key"], gap, flat))
    for plates in br["lanes"]:
        p2, p3 = plates[1], plates[2]
        ln = p2["lane"]
        reach = reach_of(p3["top"] - p2["top"]) * K_MEAS
        gap = LANE_GAPS[2]
        if reach >= gap:
            raise SystemExit("!! %s 渡船那道缝 %.2f m，直跳射程 %.2f m 能过去"
                             % (ln["key"], gap, reach))
        print("  %s %s：%d 块（%s），渡船 %s 缝 %.2f m（直跳 %.2f m）/ 期末 %.2f ~ %.2f 万"
              % (ln["key"], ln["cn"], len(plates), branch_label(ln), ln["ferry"],
                 gap, reach, branch_money(ln, False), branch_money(ln, True)))
    print("  结算门槛 %.2f 万 → 三道里能过的是：%s"
          % (HEDGE_TARGET,
             " / ".join(l["key"] for l in LANES if branch_money(l, True) >= HEDGE_TARGET)))


def _box_node(name: str, x0: float, x1: float, z0: float, z1: float, top: float,
              body: float, mat: str, meta: str = "") -> list:
    """一站 = StaticBody3D（原点在箱体中心）+ Mesh + Col（共用单位盒，靠 scale 拉）。"""
    cy = snap(top - body * 0.5)
    out = ['[node name="%s" type="StaticBody3D" parent="Route"]\n'
           'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)%s'
           % (name, _num(snap((x0 + x1) * 0.5)), _num(cy), _num(snap((z0 + z1) * 0.5)), meta)]
    xf = "Transform3D(%s, 0, 0, 0, %s, 0, 0, 0, %s, 0, 0, 0)" % (
        _num(x1 - x0), _num(body), _num(z1 - z0))
    out.append('[node name="Mesh" type="MeshInstance3D" parent="Route/%s"]\n'
               'transform = %s\nmaterial_override = SubResource("%s")\n'
               'mesh = SubResource("Box_unit")' % (name, xf, MATERIALS[mat][0]))
    out.append('[node name="Col" type="CollisionShape3D" parent="Route/%s"]\n'
               'transform = %s\nshape = SubResource("Shape_unit")' % (name, xf))
    return out


def build_branch_nodes(br: dict) -> list:
    """分叉台 / 三道 / 结算台 / 路牌。牌子上的数**由表算出来**，别手写。"""
    out = []
    body = 1.20
    out += _box_node("J0", br["j"]["x0"], br["j"]["x1"], br["j"]["z0"], br["j"]["z1"],
                     br["j"]["top"], body, "m_spot")
    out += _box_node("M0", br["m"]["x0"], br["m"]["x1"], br["m"]["z0"], br["m"]["z1"],
                     br["m"]["top"], body, "m_spot")
    for plates in br["lanes"]:
        ln = plates[0]["lane"]
        for p in plates:
            meta = chr(10) + "metadata/pct_kind = \"%s\"" % ln["kind"] \
                + chr(10) + "metadata/pct_seq = \"%s\"" % ln["seq"] \
                + chr(10) + "metadata/pct_period = %s" % _num(ln["period"]) \
                + chr(10) + "metadata/pct_phase = %s" % _num(0.6 * p["idx"]) \
                + chr(10) + "metadata/lane = \"%s\"" % ln["key"]
            out += _box_node(p["name"], p["x0"], p["x1"], p["z0"], p["z1"],
                             p["top"], body, "m_" + ln["kind"], meta)
            seq = [float(v) for v in ln["seq"].split(",")]
            col = "0.95, 0.25, 0.25, 1" if seq[0] >= 0.0 else "0.25, 0.9, 0.45, 1"
            out.append('[node name="Pct" type="Label3D" parent="Route/%s"]\n'
                       'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                       'pixel_size = 0.008\nbillboard = 1\nalpha_cut = 1\n'
                       'modulate = Color(%s)\ntext = "%+.2f%%"\nfont_size = 56\noutline_size = 14'
                       % (p["name"], _num(snap(body * 0.5 + 2.20)), col, seq[0]))
    # ---- 路牌 ----
    # ① 段起点：分叉台中间那根「第 4 段」桅杆
    bx, by, bz = br["j"]["x1"] - 1.20, br["j"]["top"] - 0.50, (br["j"]["z0"] + br["j"]["z1"]) * 0.5
    out.append('[node name="Beacon_J0" type="StaticBody3D" parent="Route"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)'
               % (_num(snap(bx)), _num(snap(by)), _num(snap(bz))))
    for nm, y, mat, mesh in [("Mast", "2.5", "Mat_tower", "Cyl_mast"),
                             ("Head", "5.3", "Mat_beacon", "Sphere_beacon")]:
        out.append('[node name="%s" type="MeshInstance3D" parent="Route/Beacon_J0"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                   'material_override = SubResource("%s")\nmesh = SubResource("%s")'
                   % (nm, y, mat, mesh))
    out.append('[node name="Col" type="CollisionShape3D" parent="Route/Beacon_J0"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 0)\n'
               'shape = SubResource("Shape_mast")')
    out.append('[node name="Sign" type="Label3D" parent="Route/Beacon_J0"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.2, 0)\n'
               'pixel_size = 0.01\nbillboard = 1\nalpha_cut = 1\n'
               'text = "第 4 段 · %s"\nfont_size = 64\noutline_size = 14' % BRANCH_NAME)
    # ② 三道各自的价目牌（挂在本道第 1 块正上方，站在分叉台上就能读）
    for plates in br["lanes"]:
        ln = plates[0]["lane"]
        p = plates[0]
        txt = "%s · %s%s每块 %s%s理论 %.2f 万（最差 %.2f）" % (
            ln["key"], ln["cn"], chr(10), branch_label(ln), chr(10),
            branch_money(ln, True), branch_money(ln, False))
        out.append('[node name="Sign_%s" type="Label3D" parent="Route/%s"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                   'pixel_size = 0.0075\nbillboard = 1\nalpha_cut = 1\n'
                   'text = "%s"\nfont_size = 44\noutline_size = 12'
                   % (ln["key"], p["name"], _num(snap(body * 0.5 + 4.20)), txt))
    # ③ 门槛牌：站在分叉台上必须先看见这条
    txt_j0 = "结算门槛：保证金 ≥ %.0f 万 → 解锁「对冲」%s未解锁：强平块 = 爆仓送回" % (
        HEDGE_TARGET, chr(10))
    out.append('[node name="Sign_J0" type="Label3D" parent="Route/J0"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
               'pixel_size = 0.008\nbillboard = 1\nalpha_cut = 1\n'
               'text = "%s"\nfont_size = 46\noutline_size = 12'
               % (_num(snap(body * 0.5 + 5.20)), txt_j0))
    # ④ 结算台那块牌（运行时由 parkour_futures.gd 改写成「本段结算：xx 万」）
    txt_m0 = "结算台" + chr(10) + "本段结算：—"
    out.append('[node name="Sign_M0" type="Label3D" parent="Route/M0"]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
               'pixel_size = 0.009\nbillboard = 1\nalpha_cut = 1\n'
               'text = "%s"\nfont_size = 56\noutline_size = 14'
               % (_num(snap(body * 0.5 + 2.60)), txt_m0))
    return out


# --- 第 5~7 段：期权 / A股 / 外汇 -------------------------------------------------
#
# 用户 2026-10-18：「后面阶段是期权交易，A股，外汇，自由发挥」。
# 三段都是**直线**（不再分叉），每段 4 块板，但每段换一套规则：
#   期权：权利金（小亏）→ 行权（大赚，**12 秒内**没摸到就作废）
#   A股：一字板 —— 板只有 1.2~1.4 m 宽、5~6 m 长，涨跌停 ±10%，只能沿着走
#   外汇：0.4~0.6 s 跳一次的汇率牌（等不了），杠杆块 ±14%
SECTIONS = [
    # ⚠️ 用户 2026-10-18：「后面这个阶段的三种东西，比比特币更加疯狂」——
    #    所以阈值全部比币圈道（−14 ~ +22 / 1.6 s）更狠：期权是「翻倍或归零」，
    #    A股是「天地板 ±20%」（创业板/科创板的涨跌停），外汇是「40% 杠杆 + 闪崩」。
    # ⚠️ 用户 2026-10-19：「第几段下面的描述不需要，挡视线了，都去掉」——
    #    原来每段桅杆上还有一块三行的 `Rule_*` 说明牌（就在段名下面），
    #    正好压在板子的价目牌上。规则文字只在 README 里留，场上不再生成。
    dict(name="期权交易", z=-1.70,
         plates=[
             dict(nm="OPT1", kind="opt_prem", seq="-1.00", period=0.0, top=2.00,
                  width=3.0, depth=3.0, gap=3.00),
             dict(nm="OPT2", kind="opt_prem", seq="-1.00", period=0.0, top=2.20,
                  width=3.0, depth=3.0, gap=2.80),
             dict(nm="OPT3", kind="opt_exer", seq="25.00", period=0.0, top=2.60,
                  width=3.0, depth=3.0, gap=3.00, deadline=8.0),
             dict(nm="OPT4", kind="opt_exer", seq="60.00", period=0.0, top=2.40,
                  width=3.0, depth=3.0, gap=2.80, deadline=8.0),
         ]),
    dict(name="A股", z=-1.70,
         plates=[
             dict(nm="AS1", kind="ash_up", seq="20.00", period=0.0, top=2.00,
                  width=1.4, depth=5.0, gap=3.00),
             dict(nm="AS2", kind="ash_lei", seq="20.00,-20.00", period=0.90, top=2.20,
                  width=1.2, depth=6.0, gap=2.80),
             dict(nm="AS3", kind="ash_dn", seq="-20.00", period=0.0, top=2.40,
                  width=1.2, depth=6.0, gap=3.00),
             dict(nm="AS4", kind="ash_lei", seq="20.00,-20.00", period=0.90, top=2.20,
                  width=1.4, depth=5.0, gap=2.80),
         ]),
    dict(name="外汇", z=-1.70,
         # 用户 2026-10-20：「外汇长一点点，暗网短一点点」→ 外汇 4 → 5 块，
         # 暗网 10 → 9 块（一加一减，总站数仍是 99，X1 之后的尾巴几乎不动）。
         plates=[
             dict(nm="FX1", kind="fx", seq="15.00,-15.00", period=0.50, top=2.00,
                  width=3.0, depth=3.0, gap=3.00),
             dict(nm="FX2", kind="fx_lev", seq="40.00,-40.00", period=0.30, top=2.30,
                  width=2.8, depth=3.0, gap=2.80),
             dict(nm="FX3", kind="fx_crash", seq="-30.00", period=0.0, top=2.00,
                  width=2.8, depth=3.0, gap=3.00),
             dict(nm="FX4", kind="fx", seq="15.00,-15.00", period=0.50, top=2.20,
                  width=3.0, depth=3.0, gap=2.80),
             dict(nm="FX5", kind="fx_lev", seq="40.00,-40.00", period=0.40, top=2.00,
                  width=2.8, depth=3.0, gap=3.00),
         ]),
    # 第 8 段「暗网黑市交易」：最长的一段（9 块板，2026-10-20 从 10 块减到 9 块），
    # 头顶有**比纳**（dark_boss.gd）一边跑一边打。比纳不吃「跳过去」那套 —— 它在上方 10 m，
    # 激光 + 炮弹。
    # ⚠️ 用户 2026-10-19：「比纳不能一开始就加载，得进入黑市才加载」→
    #    这里不再摆 `DarkBoss` 节点，只摆一个空的 `DarkGate`（dark_gate.gd）；
    #    玩家跑到闸门处才由它 `instantiate` 出比纳（见 build_section_nodes 末尾）。
    dict(name="暗网黑市交易", z=-1.70, boss=True, mat="m_spot_dark",
         plates=[
             dict(nm="DK1", kind="spot", seq="-0.80", period=0.0, top=2.00,
                  width=3.4, depth=3.0, gap=3.00),
             dict(nm="DK2", kind="spot", seq="-0.80", period=0.0, top=2.40,
                  width=2.8, depth=3.0, gap=3.00),
             dict(nm="DK3", kind="spot", seq="-0.80", period=0.0, top=2.00,
                  width=3.0, depth=3.0, gap=2.80),
             dict(nm="DK4", kind="spot", seq="-0.80", period=0.0, top=2.60,
                  width=3.0, depth=3.0, gap=3.00),
             dict(nm="DK5", kind="spot", seq="-0.80", period=0.0, top=3.00,
                  width=2.8, depth=3.0, gap=3.00),
             dict(nm="DK6", kind="spot", seq="-0.80", period=0.0, top=2.40,
                  width=3.4, depth=3.0, gap=2.80),
             dict(nm="DK7", kind="spot", seq="-0.80", period=0.0, top=2.00,
                  width=3.0, depth=3.0, gap=3.00),
             dict(nm="DK8", kind="spot", seq="-0.80", period=0.0, top=2.40,
                  width=3.0, depth=3.0, gap=2.80),
             dict(nm="DK9", kind="spot", seq="-0.80", period=0.0, top=2.80,
                  width=2.8, depth=3.0, gap=3.00),
         ]),
]
SECTION_GAP_FROM_M0 = 3.50


def layout_sections(start_x: float) -> dict:
    """从结算台 M0 的西边缘往西排三段（每段 4 块，直线）。"""
    x = start_x
    out = []
    for sec in SECTIONS:
        plist = []
        for p in sec["plates"]:
            x1 = snap(x - p["gap"])
            x0 = snap(x1 - p["depth"])
            plist.append(dict(p, x0=x0, x1=x1,
                              z0=snap(sec["z"] - p["width"] * 0.5),
                              z1=snap(sec["z"] + p["width"] * 0.5)))
            x = x0
        out.append(dict(sec=sec, plates=plist))
    return dict(sections=out, end_x=x)


def check_sections(secs: dict) -> None:
    """每段都要真的跳得过去（同一条直线，抬升 ≤ 0.5 m 的普通跳）。"""
    prev = None
    for item in secs["sections"]:
        for p in item["plates"]:
            if prev is not None:
                rise = p["top"] - prev["top"]
                reach = reach_of(rise) * K_MEAS
                need = p["gap"]
                if reach < need + 0.80:
                    raise SystemExit("!! %s→%s 余量只有 %.2f m（< 0.80）"
                                     % (prev["nm"], p["nm"], reach - need))
            prev = p
        print("  %s：%s（台面 %.2f → %.2f）"
              % (item["sec"]["name"],
                 " / ".join("%s %s" % (p["nm"], p["seq"]) for p in item["plates"]),
                 item["plates"][0]["top"], item["plates"][-1]["top"]))


def build_section_nodes(secs: dict, first_seg: int) -> list:
    """三段的路面 + 牌子 + 段起点桅杆。"""
    out = []
    body = 1.20
    for si, item in enumerate(secs["sections"]):
        sec = item["sec"]
        for idx, p in enumerate(item["plates"]):
            meta = (chr(10) + "metadata/pct_kind = \"%s\"" % p["kind"]
                    + chr(10) + "metadata/pct_seq = \"%s\"" % p["seq"]
                    + chr(10) + "metadata/pct_period = %s" % _num(p["period"])
                    + chr(10) + "metadata/pct_phase = %s" % _num(0.4 * idx)
                    + chr(10) + "metadata/lane = \"%s\"" % p["nm"][:2])
            if p.get("deadline"):
                meta += chr(10) + "metadata/deadline = %s" % _num(p["deadline"])
            out += _box_node(p["nm"], p["x0"], p["x1"], p["z0"], p["z1"], p["top"], body,
                             sec.get("mat", "m_" + p["kind"]), meta)
            seq = [float(v) for v in p["seq"].split(",")]
            col = "0.95, 0.25, 0.25, 1" if seq[0] >= 0.0 else "0.25, 0.9, 0.45, 1"
            out.append('[node name="Pct" type="Label3D" parent="Route/%s"]\n'
                       'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                       'pixel_size = 0.008\nbillboard = 1\nalpha_cut = 1\n'
                       'modulate = Color(%s)\ntext = "%+.2f%%"\nfont_size = 56\noutline_size = 14'
                       % (p["nm"], _num(snap(body * 0.5 + 2.20)), col, seq[0]))
        # 段起点桅杆（只留段名；原来下面那块三行规则牌已按用户要求删掉）
        f = item["plates"][0]
        bx = f["x1"] - 1.20
        bz = f["z1"] + 2.20
        out.append('[node name="Beacon_%s" type="StaticBody3D" parent="Route"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)'
                   % (sec["name"], _num(snap(bx)), _num(snap(f["top"] - 0.50)), _num(snap(bz))))
        for nm, y, mat, mesh in [("Mast", "2.5", "Mat_tower", "Cyl_mast"),
                                 ("Head", "5.3", "Mat_beacon", "Sphere_beacon")]:
            out.append('[node name="%s" type="MeshInstance3D" parent="Route/Beacon_%s"]\n'
                       'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n'
                       'material_override = SubResource("%s")\nmesh = SubResource("%s")'
                       % (nm, sec["name"], y, mat, mesh))
        out.append('[node name="Col" type="CollisionShape3D" parent="Route/Beacon_%s"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 0)\n'
                   'shape = SubResource("Shape_mast")' % sec["name"])
        out.append('[node name="Sign" type="Label3D" parent="Route/Beacon_%s"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.2, 0)\n'
                   'pixel_size = 0.01\nbillboard = 1\nalpha_cut = 1\n'
                   'text = "第 %d 段 · %s"\nfont_size = 60\noutline_size = 14'
                   % (sec["name"], first_seg + si, sec["name"]))
        if sec.get("boss"):
            # 黑市闸门：**空节点**，玩家跑到 x ≤ 闸门时才 `instantiate` 比纳。
            # 放在本段第一块板的东侧 +2 m（0.05 网格），y 取台面高度。
            out.append('[node name="DarkGate" type="Node3D" parent="Route"]\n'
                       'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\n'
                       'script = ExtResource("10_darkgate")\n'
                       'trigger_x = %s\nspawn_offset = Vector3(%s, %s, 0)'
                       % (_num(snap(f["x1"] + 2.0)), _num(snap(f["top"])),
                          _num(snap(sec["z"])), _num(snap(f["x1"] + 2.0)),
                          _num(snap(-12.0)), _num(snap(10.0))))
    return out


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
        # 薛定谔块挂元数据：运行时的 parkour_futures.gd 靠它找块
        extra = (chr(10) + "metadata/schrodinger = true") if b["mat"] == "sch" else ""
        out.append('[node name="%s" type="StaticBody3D" parent="Route"]\n'
                   'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)%s'
                   % (b["name"], _num(b["x0"] + b["depth"] * 0.5), _num(cy), _num(b["z"]), extra))
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
               'text = "第 3 段 · 同花顺期货通"\nfont_size = 64\noutline_size = 14')
    # 期货通总控：会动的方块 / 蓝块强平 / 薛定谔坍缩 / 负债 HUD 都在它里面
    out.append('[node name="Futures" type="Node3D" parent="."]' + chr(10)
               + 'script = ExtResource("7_futures")')
    return out


EXT_FUTURES = ('[ext_resource type="Script" path="res://scripts/parkour_futures.gd" '
               'id="7_futures"]')
## 黑市闸门（运行时才 instantiate 比纳）；`dark_boss.gd` 现在只挂在
## `scenes/dark_boss.tscn` 上，场景里不再直接引用它。
EXT_DARKGATE = '[ext_resource type="Script" path="res://scripts/dark_gate.gd" id="10_darkgate"]'
## 第 9~10 段「内存条市场」：装饰 + 天降内存条（`scripts/ram_market.gd`）。
## 它**只加装饰**，路线几何一个点都不动 —— 站台/碰撞/跳距还是原来那套。
EXT_RAMMARKET = ('[ext_resource type="Script" path="res://scripts/ram_market.gd" '
                 'id="11_rammarket"]')
# ⚠️ `parent` 必须写 `"."`（场景根的直接子节点），**不能写根节点名**。
#    写成 `parent="Parkour"` 时 Godot 4.7 会把它当成「带作用域的名字」，
#    实例化后节点变成 `Parkour#RamMarket` —— 名字对不上，`get_node("RamMarket")`
#    直接返回 null（本喵踩过一次，日志里只有一句「built = false」）。
RAM_MARKET_NODE = ('[node name="RamMarket" type="Node3D" parent="."]' + chr(10)
                   + 'script = ExtResource("11_rammarket")')
## 跑酷准备区（第 1 段跑道东口的金色垫子）：踏进去 = 同伴原地待命、爱丽丝单枪匹马。
## 位置固定在 (−9, 0, 4)：正好是 40×40 主平台靠西、跑道（x −20 ~ −10）入口前一步。
EXT_READYZONE = ('[ext_resource type="Script" path="res://scripts/parkour_ready_zone.gd" '
                 'id="12_readyzone"]')
# 2026-10-20：6×4 只盖住跑道东口，从屋子那边绕过来踩不到 → 扩到 13×8
# （x −19 ~ −6、z 0 ~ 8：整条 10 m 跑道几乎都在垫子上）
READY_ZONE_NODE = ('[node name="ReadyZone" type="Area3D" parent="."]' + chr(10)
                   + 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -12.5, 0, 4)' + chr(10)
                   + 'script = ExtResource("12_readyzone")' + chr(10)
                   + 'zone_size = Vector3(13, 3, 8)')


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


def _sec_starts(secs: dict, base: int) -> list:
    """第 5~8 段的段起点：每段板数不同（4/4/4/10），按实际板数累加。"""
    out, cursor = [], base
    for item in secs["sections"]:
        out.append(cursor)
        cursor += len(item["plates"])
    return out


def rewrite_arrays(text: str, boxes: list, br: dict, secs: dict) -> str:
    names = [c["name"] for c in boxes]
    # 第 4 段只有**现货道**进 `route`（它是「正统路线」，连续通关按它走）。
    # 永续道 / 币圈道的板**故意不进 route**：站在上面不算检查点，
    # 掉下去就回分叉台 —— 这正是「选路线」该有的手感（选错了重来只损失时间）。
    branch_names = ["J0"] + [p["name"] for p in br["lanes"][0]] + ["M0"]
    # 第 5~7 段是**直线**（没有分叉），12 块板全进 route
    sec_names = [p["nm"] for item in secs["sections"] for p in item["plates"]]
    route = (BASE_ROUTE[:INS_AT + 1] + names + branch_names + sec_names
             + BASE_ROUTE[INS_AT + 1:])
    nk = len(names)
    nb = len(branch_names)
    ns = len(sec_names)
    n = nk + nb + ns
    seg2 = int(BASE_SEGMENTS[2])
    base = seg2 + nk + nb
    segments = ([int(v) for v in BASE_SEGMENTS[:3]]
                + [seg2 + nk]                                     # 第 4 段：三道
                + _sec_starts(secs, base)                         # 第 5~8 段（板数不同）
                + [base + ns]                                     # 第 9 段（X 区）起点
                + [v + n for v in BASE_SEGMENTS[3:]])             # 原来的段 6~7
    seg_names = (BASE_SEG_NAMES[:2] + [FLUSH_SEG_NAME, BRANCH_NAME]
                 + [s["name"] for s in SECTIONS] + BASE_SEG_NAMES[2:])
    # ⚠️ 判据是「站号 ≥ 插入点」，不是「≥ 第 4 段起点」——F1/F2（26/27）也在插入点之后
    # 渡船跳（升降台 / 平移台）的落点也算机关跳：弹道核算跳过，交给真物理验收
    ferry = [INS_AT + 1 + i for i, c in enumerate(CANDLES) if c.get("ferry")]
    special = sorted(set([v + n if v >= INS_AT + 1 else v for v in BASE_SPECIAL]
                         + ferry + [route.index("SP3")]))
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
        # ⚠️ 牌子本体是 `Route/Beacon_C3/Sign`（`Label3D`），**名字叫 `Sign`**，
        #    所以只按 `nd["name"]` 匹配永远命中不了 —— 要按它的**宿主**桅杆判。
        #    （上一版就是这个 bug：C3/C4/C5 三块牌子一直写着「第 3/4/5 段」，
        #      而 HUD 上早就是第 9/10/11 段了。）
        host = nd["parent"].split("/")[1] if nd["parent"].startswith("Route/") else ""
        want = {"Beacon_C3": "第 9 段 · 终点", "Beacon_C4": "第 10 段 · 终点",
                "Beacon_C5": "第 11 段 · 终点", "SignPost": "跑酷 · 12 段 →",
                "SignText": "跑酷 · 12 段 →"}.get(nd["name"],
                    {"Beacon_C3": "第 9 段 · 终点", "Beacon_C4": "第 10 段 · 终点",
                     "Beacon_C5": "第 11 段 · 终点"}.get(host))
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


BRANCH_NODE = re.compile(r"^(J0|M0|(SP|PP|BC)[123]|Sign_[ABC]|Sign_[JM]0|Beacon_J0)$")


def is_branch_node(nd) -> bool:
    if BRANCH_NODE.match(nd["name"]):
        return True
    top = nd["parent"].split("/")[1] if "/" in nd["parent"] else ""
    return bool(BRANCH_NODE.match(top))


# 第 5~8 段：12 块板 + 四根桅杆（桅杆名是中文，单独列出来）
#
# ⚠️ 这里**必须把四段的桅杆都列全**：原来只写了期权/A股/外汇三根，
#    漏了「Beacon_暗网黑市交易」→ 每跑一次生成器就**再叠一根**，
#    跑到第 8 次时场上已经站着 8 根一模一样的桅杆、8 块「第 8 段」牌、
#    8 块叠在一起的说明牌 —— 用户看到的那团糊在一起的字就是这么来的。
SECTION_NODE = re.compile(r"^(OPT|AS|FX|DK)\d+$")
SECTION_NAMES = tuple(sec["name"] for sec in SECTIONS)
SECTION_HOSTS = tuple("Beacon_%s" % n for n in SECTION_NAMES) \
    + tuple("Rule_%s" % n for n in SECTION_NAMES)
## 会被重新生成 / 已经废弃的节点（`DarkBoss` 是旧版直接摆进场景的比纳，
## 现在是 `DarkGate` 运行时生成；两个名字都要清掉，生成器才可重入）
SECTION_SCRAP = ("DarkBoss", "DarkGate", "RamMarket", "ReadyZone")


def is_section_node(nd) -> bool:
    if SECTION_NODE.match(nd["name"]) or nd["name"] in SECTION_HOSTS:
        return True
    if nd["name"] in SECTION_SCRAP:
        return True
    top = nd["parent"].split("/")[1] if "/" in nd["parent"] else ""
    return bool(SECTION_NODE.match(top)) or top in SECTION_HOSTS


def main() -> None:
    dry = "--dry-run" in sys.argv
    boxes, _ = layout()
    br = layout_branch(boxes[-1])
    secs = layout_sections(br["m"]["x0"])
    x1 = dict(center=snap(secs["end_x"] - SECTION_GAP_FROM_M0 - X1_DEPTH * 0.5),
              gap=SECTION_GAP_FROM_M0)
    grid_check(boxes)
    check_branch(br)
    check_sections(secs)
    stats = report(boxes, x1, include_x1=False)
    if stats["worst"] < 0.80:
        raise SystemExit("!! 最紧的余量 %.2f < 0.80，先调 CANDLES 表" % stats["worst"])

    text = TSCN.read_text(encoding="utf-8")
    # 旧版把 `dark_boss.gd` 直接引在场景上（`DarkBoss` 节点）；现在改成运行时生成，
    # 这条 ext_resource 留着就是死引用 —— 顺手删掉。
    text = re.sub(r'(?m)^\[ext_resource type="Script" '
                  r'path="res://scripts/dark_boss\.gd" id="9_dark"\]' + chr(10) + '+',
                  '', text)
    for eid, ext in (('id="7_futures"', EXT_FUTURES), ('id="10_darkgate"', EXT_DARKGATE),
                     ('id="11_rammarket"', EXT_RAMMARKET),
                     ('id="12_readyzone"', EXT_READYZONE)):
        if eid not in text:
            # ext_resource 必须排在所有 sub_resource 之前（文本格式按块顺序解析）
            k = text.index("[sub_resource")
            k = text.rindex(chr(10), 0, k) + 1
            text = text[:k] + ext + chr(10) + chr(10) + text[k:]
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
                or nd["name"] == "Beacon_K1" or top == "Beacon_K1" or is_branch_node(nd) \
                or is_section_node(nd) \
                or (nd["name"] == "Futures" and nd["parent"] == "."):
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
    # ⚠️ 不能只「缺哪个补哪个」：改了 MATERIALS 里的颜色，旧定义还留在文件里就永远不生效
    #    （实测：暗网板改成近黑之后，运行时读到的还是上一次的 0.10/0.09/0.14）。
    #    所以按 id **整块替换**，缺的再补。
    fresh = {}
    for sub in build_subresources():
        fresh[re.search(r'id="([^"]+)"', sub).group(1)] = sub
    have = set()
    for i, ch in enumerate(gen):
        m = re.match(r'\[sub_resource [^\]]*id="([^"]+)"\]', ch)
        if not m:
            continue
        key = m.group(1)
        have.add(key)
        if key in fresh:
            gen[i] = fresh[key]
    add = [sub for key, sub in fresh.items() if key not in have]
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
    gen[c2_end + 1:c2_end + 1] = (build_nodes(boxes, x1) + build_branch_nodes(br)
                                  + build_section_nodes(secs, 5)
                                  + [RAM_MARKET_NODE, READY_ZONE_NODE])

    gen = bump_labels(gen)
    out = "\n".join(gen)
    out = rewrite_arrays(out, boxes, br, secs)
    out = re.sub(r"\n{3,}", "\n\n", out)

    print("\n  站数 %d → %d（K 段 %d 根蜡烛 + 三道 5 + 期权 4 / A股 4 / 外汇 5 + 暗网 9）；段数 6 → 12"
          % (len(BASE_ROUTE), len(BASE_ROUTE) + len(boxes) + 5
             + sum(len(s["plates"]) for s in SECTIONS), len(boxes)))
    if dry:
        print("  --dry-run：不写文件")
        return
    TSCN.write_text(out, encoding="utf-8")
    print("  已写入 %s" % TSCN.relative_to(ROOT))


if __name__ == "__main__":
    main()
