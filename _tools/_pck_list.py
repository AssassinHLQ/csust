import struct, sys

P = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\build\arisu.pck"
f = open(P, "rb")

magic = f.read(4)
assert magic == b"GDPC", "不是 Godot pck: %r" % magic
pack_version, = struct.unpack("<I", f.read(4))
vmaj, vmin, vpat = struct.unpack("<III", f.read(12))
flags, = struct.unpack("<I", f.read(4))
file_base, = struct.unpack("<Q", f.read(8))
f.read(16 * 4)
file_count, = struct.unpack("<I", f.read(4))

print("pck_version=%d  godot=%d.%d.%d  files=%d  file_base=0x%X"
      % (pack_version, vmaj, vmin, vpat, file_count, file_base))

paths = []
for i in range(file_count):
    plen, = struct.unpack("<I", f.read(4))
    raw = f.read(plen)
    pad = (4 - (plen % 4)) % 4
    if pad:
        f.read(pad)
    off, size = struct.unpack("<QQ", f.read(16))
    f.read(16)  # md5
    if pack_version >= 2:
        f.read(4)  # flags
    paths.append((raw.decode("utf-8", "replace"), size, off))

print("\n--- 前 8 条（自检解析是否正确）---")
for p_, s, o in paths[:8]:
    print("  %10d  %s" % (s, p_))

def report(label, pred):
    hit = [(p_, s) for p_, s, o in paths if pred(p_)]
    tot = sum(s for _, s in hit)
    print("\n%s : %d 个, 合计 %.1f MB" % (label, len(hit), tot / 1048576.0))
    return hit, tot

chunks, csz = report("splatdata/campus_chunks10w/*.bin",
                     lambda p_: p_.startswith("res://splatdata/campus_chunks10w/") and p_.endswith(".bin"))
manif, msz = report("chunks.json", lambda p_: p_.endswith("campus_chunks10w/chunks.json"))
sog, ssz = report("*.sogdata", lambda p_: p_.endswith(".sogdata"))
coarse, cosz = report("campus_ggs_q4.bin", lambda p_: p_.endswith("campus_ggs_q4.bin"))
full, fsz = report("campus_ggs.bin（应该不在包里）", lambda p_: p_.endswith("campus_ggs.bin"))

print("\n--- 关键文件逐个确认 ---")
for name in ("res://splatdata/room609.sogdata",
             "res://splatdata/school_playable.sogdata",
             "res://splatdata/campus_chunks10w/chunks.json",
             "res://splatdata/campus_chunks10w/Chunk_0_0.bin",
             "res://splatdata/campus_chunks10w/Chunk_9_9.bin",
             "res://campus_ggs_q4.bin",
             "res://campus_ggs.bin"):
    found = [s for p_, s, o in paths if p_ == name]
    print("  [%s] %10s  %s" % ("OK " if found else "缺 ", (found[0] if found else "-"), name))

print("\n--- 未预期的 splatdata 残留 ---")
for p_, s, o in paths:
    if p_.startswith("res://splatdata/") and not (
        p_.endswith("room609.sogdata")
        or p_.endswith("school_playable.sogdata")
        or p_.startswith("res://splatdata/campus_chunks10w/")
    ):
        print("  %10d  %s" % (s, p_))

print("\n--- 包里最大的 12 个文件 ---")
for p_, s, o in sorted(paths, key=lambda x: -x[1])[:12]:
    print("  %10.1f MB  %s" % (s / 1048576.0, p_))

print("\n=== 汇总 ===")
print("  splatdata 小计 : %.1f MB" % ((csz + msz + ssz + cosz) / 1048576.0))
print("  包内文件总数   : %d" % file_count)
