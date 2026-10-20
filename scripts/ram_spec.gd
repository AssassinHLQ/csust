class_name RamSpec
extends RefCounted
## 内存条**规格**与**估价**（纯函数，不碰场景）。
##
## 用户 2026-10-20：「内存条是可拾取的，每次捡到内存条，随机是 ddr3 / ddr4 / ddr5，
## 内存容量随机是 2g / 4g / 8g / 16g / 32g / 64g……每次随机是 ecc 服务器内存条、
## 非 ecc 普通台式内存条。捡到的内存条换算成为资产，价格行情自己查网络。」
##
## 所以一根条子 = 三个独立维度：
##   `ddr` ∈ {DDR3, DDR4, DDR5}　`gb` ∈ {2, 4, 8, 16, 32, 64}　`ecc` ∈ {false, true}
## **组合数 = 3 × 6 × 2 = 36 种**（用户口算成 125 = 5³，那是三个五维轴才对得上的数；
## 这里按他给的三个轴实现，见 `combo_count()`）。
##
## ── 估价（元，2026-10 行情）──
## 2025 年 Q2 起 AI 算力把消费级 DRAM 产能吸干，2026 年 10 月的真实行情：
##   · 华强北 2026-10-07：DDR4 16G 去年 100 多元 → **现在最低 600 多元**；
##     DDR5 16G 最便宜时 200 多元 → **现在最低 1400 元以上**；DDR3 金士顿某款
##     去年 218 元 → 现在 499 元。（证券时报/界面新闻，2026-10-08）
##   · DDR5 32G：2025-10 约 500 多元 → 2026-03 已 **3500 元**（南方网/千龙 2026-03-20）。
##   · 服务器 DDR5：64G RDIMM 行情预期**破 1 万元**；DDR4 32G RECC 2026-01 约
##     1000~1500 元一根（Chiphell 2025-12~2026-01 成交反馈）。
## 所以这里用「元/GB 基准 × 容量系数 × ECC 系数」，不用线性单价 —— 大容量条在
## 缺货年份溢价更狠（64G 系数 1.30，2G 0.85）。
##
## ⚠️ 一个**故意的简化**：现实里 DDR3 RECC 拆机条（服务器退役）比同容量的消费级
##    DDR3 还便宜（量太大、没人要），这里仍按「ECC = 服务器条，略贵」处理
##    （DDR3 只贵 15%）。要还原现实的话把 `ECC_FACTOR["DDR3"]` 改成 0.75。
##
## 价格全是**整数元**、取整到 10 元；资产账户按元累加（保证金/负债仍是「万」）。

const DDRS := ["DDR3", "DDR4", "DDR5"]
const SIZES := [2, 4, 8, 16, 32, 64]

## 元/GB 基准（2026-10 行情，取各代「主流容量」的中间价）
const BASE_PER_GB := {
	"DDR3": 45.0,
	"DDR4": 40.0,
	"DDR5": 95.0,
}
## 大容量溢价：缺货年份 32G/64G 的单 GB 价反而更贵
const SIZE_FACTOR := {
	2: 0.85,
	4: 0.90,
	8: 1.00,
	16: 1.05,
	32: 1.15,
	64: 1.30,
}
## ECC（服务器 RDIMM）相对同代消费条的系数 —— DDR5 服务器条最离谱
const ECC_FACTOR := {
	"DDR3": 1.15,
	"DDR4": 1.15,
	"DDR5": 1.60,
}


## 抽一根：三个维度各自均匀。`ecc` 为 true 就是「ECC 服务器条」。
static func roll(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"ddr": DDRS[rng.randi_range(0, DDRS.size() - 1)],
		"gb": int(SIZES[rng.randi_range(0, SIZES.size() - 1)]),
		"ecc": rng.randf() < 0.5,
	}


## 36 —— 三个维度所有组合。自检直接拿它跟 3×6×2 对账。
static func combo_count() -> int:
	return DDRS.size() * SIZES.size() * 2


static func all_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ddr in DDRS:
		for gb in SIZES:
			for ecc in [false, true]:
				out.append({"ddr": ddr, "gb": gb, "ecc": ecc})
	return out


## 牌面文字：`DDR5 32G ECC 服务器条` / `DDR4 8G 非 ECC 台式条`
static func describe(spec: Dictionary, short := false) -> String:
	var ddr := String(spec.get("ddr", "DDR4"))
	var gb := int(spec.get("gb", 8))
	var ecc := bool(spec.get("ecc", false))
	if short:
		return "%s %dG %s" % [ddr, gb, "ECC" if ecc else "非ECC"]
	return "%s %dG %s" % [ddr, gb, "ECC 服务器条" if ecc else "非 ECC 台式条"]


## 一根值多少元（取整到 10 元）。
##
## 例：DDR3 2G 非ECC → 80；DDR4 16G 非ECC → 670；DDR5 16G 非ECC → 1600；
##     DDR5 32G ECC → 3500；DDR5 64G ECC → 12650（顶配≈1.27 万）。
static func price_yuan(spec: Dictionary) -> int:
	var ddr := String(spec.get("ddr", "DDR4"))
	var gb := int(spec.get("gb", 8))
	var ecc := bool(spec.get("ecc", false))
	var base: float = float(BASE_PER_GB.get(ddr, 40.0))
	var size_f: float = float(SIZE_FACTOR.get(gb, 1.0))
	var ecc_f: float = float(ECC_FACTOR.get(ddr, 1.0)) if ecc else 1.0
	return int(round(base * float(gb) * size_f * ecc_f / 10.0)) * 10


## 万为单位（给保证金那套账户做换算用）
static func price_wan(spec: Dictionary) -> float:
	return float(price_yuan(spec)) / 10000.0
