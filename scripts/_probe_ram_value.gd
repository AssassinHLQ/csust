extends SceneTree
## 算内存条的期望总价：枚举全部规格组合，均价 × 可捡根数。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var specs := RamSpec.all_specs()
	var total := 0
	var lo := 1 << 30
	var hi := 0
	for s in specs:
		var p := RamSpec.price_yuan(s)
		total += p
		lo = mini(lo, p)
		hi = maxi(hi, p)
	var avg := float(total) / float(specs.size())
	print("[ram] 组合 %d 种　单根 ¥%d ~ ¥%d　均价 ¥%.0f" % [specs.size(), lo, hi, avg])
	for n in [16, 56, 72]:
		print("[ram] 捡 %d 根 → 期望 ¥%s" % [n, _fmt(avg * n)])
	quit(0)


func _fmt(v: float) -> String:
	if v >= 10000.0:
		return "%.1f 万" % (v / 10000.0)
	return "%.0f 元" % v
