#!/usr/bin/env bash
# 模拟「克隆下来没有那张图」——把 gamedev_room.jpg 和它的 .import 一起挪出工程，
# 跑 _verify_optional_poster.gd，结束时无论成败都还原（trap EXIT）。
set -u
cd "$(dirname "$0")/.." || exit 1

BAK="../_tmp_poster_bak"
mkdir -p "$BAK"

restore() {
	local ok=1
	[ -f "$BAK/gamedev_room.jpg" ] && { mv -f "$BAK/gamedev_room.jpg" assets/story/gamedev_room.jpg; ok=0; }
	[ -f "$BAK/gamedev_room.jpg.import" ] && { mv -f "$BAK/gamedev_room.jpg.import" assets/story/gamedev_room.jpg.import; ok=0; }
	if [ -f assets/story/gamedev_room.jpg ]; then
		printf '[restore] 已还原  %s B\n' "$(stat -c%s assets/story/gamedev_room.jpg)"
	else
		echo "[restore] !! 还原失败：assets/story/gamedev_room.jpg 不见了"
	fi
	rmdir "$BAK" 2>/dev/null
}
trap restore EXIT

mv -f assets/story/gamedev_room.jpg "$BAK/" 2>/dev/null
mv -f assets/story/gamedev_room.jpg.import "$BAK/" 2>/dev/null

echo "=== 模拟克隆后（图和 .import 都不在）==="
if [ -e assets/story/gamedev_room.jpg ]; then echo "!! 没挪走"; else echo "jpg        : 已挪走"; fi
if [ -e assets/story/gamedev_room.jpg.import ]; then echo "!! 没挪走"; else echo ".import    : 已挪走"; fi
echo

bash _tools/run_probe.sh res://scripts/_verify_optional_poster.gd 2>&1 \
	| grep -E "^\[optposter\]|SCRIPT ERROR|Parse Error|Failed loading" || true

echo
echo "=== 整局启动（图不在）==="
bash _tools/boot_check.sh 240 2>&1 \
	| grep -Ei "SCRIPT ERROR|Parse Error|ERROR:|Failed loading" | head -20
echo "--- 冒烟结束（上面为空即无报错）---"
