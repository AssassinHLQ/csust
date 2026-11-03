#!/usr/bin/env bash
# 模拟「克隆下来没有游戏开发部模型」——把 models/gamedev_room/ 整个目录挪出工程，
# 跑探针 + 整局冒烟，结束时无论成败都还原（trap EXIT）。
set -u
cd "$(dirname "$0")/.." || exit 1

BAK="../_tmp_gamedev_bak"
SRC="models/gamedev_room"
mkdir -p "$BAK"

restore() {
	if [ -d "$BAK/gamedev_room" ]; then
		mv -f "$BAK/gamedev_room" "$SRC"
	fi
	if [ -f "$SRC/gamedev_room.glb" ]; then
		printf '[restore] 已还原  %s B\n' "$(stat -c%s "$SRC/gamedev_room.glb")"
	else
		echo "[restore] !! 还原失败：$SRC/gamedev_room.glb 不见了"
	fi
	rmdir "$BAK" 2>/dev/null
}
trap restore EXIT

if [ -d "$SRC" ]; then
	mv -f "$SRC" "$BAK/"
fi

echo "=== 模拟克隆后（models/gamedev_room/ 不在）==="
if [ -e "$SRC/gamedev_room.glb" ]; then echo "!! 没挪走"; else echo "模型：已挪走"; fi
echo

bash _tools/run_probe.sh res://scripts/_verify_gamedev_optional.gd 2>&1 \
	| grep -E "^\[gdopt\]|SCRIPT ERROR|Parse Error|Failed loading" || true

echo
echo "=== 整局启动（模型不在）==="
bash _tools/boot_check.sh 240 2>&1 \
	| grep -Ei "SCRIPT ERROR|Parse Error|ERROR:|Failed loading" | head -20
echo "--- 冒烟结束（上面为空即无报错）---"
