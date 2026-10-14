"""列出 GLB 里的动画 / 骨骼 / 网格信息（只读 JSON chunk，不需要 Blender）。"""
import json
import struct
import sys


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("not a glb: %s" % path)
    off = 12
    js = None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        off += clen
    return js, version, length


def fmt(v):
    if v is None:
        return "?"
    return ", ".join("%.3f" % x for x in v)


def report(path):
    print("=" * 78)
    print("GLB: %s" % path)
    try:
        g, version, length = read_glb(path)
    except Exception as exc:  # noqa: BLE001
        print("  读取失败: %s" % exc)
        return
    print("  版本 %s, 文件 %d 字节" % (version, length))
    print("  节点 %d, 网格 %d, 蒙皮 %d, 材质 %d, 动画 %d, 形态目标网格 %d" % (
        len(g.get("nodes", [])), len(g.get("meshes", [])), len(g.get("skins", [])),
        len(g.get("materials", [])), len(g.get("animations", [])),
        sum(1 for m in g.get("meshes", []) if any("targets" in p for p in m.get("primitives", []))),
    ))

    accessors = g.get("accessors", [])
    nodes = g.get("nodes", [])

    for si, skin in enumerate(g.get("skins", [])):
        print("  蒙皮[%d] 关节 %d，骨架根 = %s" % (
            si, len(skin.get("joints", [])),
            nodes[skin["skeleton"]].get("name", "?") if "skeleton" in skin else "?",
        ))

    anims = g.get("animations", [])
    if not anims:
        print("  ** 没有任何动画 **")
    for ai, anim in enumerate(anims):
        chans = anim.get("channels", [])
        samplers = anim.get("samplers", [])
        tmin, tmax = None, None
        paths = {}
        targets = {}
        for ch in chans:
            tgt = ch.get("target", {})
            paths[tgt.get("path", "?")] = paths.get(tgt.get("path", "?"), 0) + 1
            nname = nodes[tgt["node"]].get("name", "node%d" % tgt["node"]) if "node" in tgt else "?"
            targets[nname] = targets.get(nname, 0) + 1
            s = samplers[ch["sampler"]]
            acc = accessors[s["input"]]
            lo = acc.get("min", [None])[0]
            hi = acc.get("max", [None])[0]
            if lo is not None:
                tmin = lo if tmin is None else min(tmin, lo)
            if hi is not None:
                tmax = hi if tmax is None else max(tmax, hi)
        print("  动画[%d] '%s'：%d 通道，时长 %.3f → %.3f s（%.3f s）" % (
            ai, anim.get("name", "?"), len(chans),
            tmin if tmin is not None else -1, tmax if tmax is not None else -1,
            (tmax - tmin) if (tmin is not None and tmax is not None) else -1,
        ))
        print("        通道类型: %s" % ", ".join("%s×%d" % (k, v) for k, v in sorted(paths.items())))
        top = sorted(targets.items(), key=lambda kv: -kv[1])[:8]
        print("        涉及节点(前8): %s%s" % (
            ", ".join("%s×%d" % (k, v) for k, v in top),
            " …" if len(targets) > 8 else "",
        ))

    print("  顶层节点: %s" % ", ".join(
        n.get("name", "?") for n in nodes if n.get("name")
    )[:400])


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
