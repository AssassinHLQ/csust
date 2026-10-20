class_name RamSpec
extends RefCounted
## 内存条**规格**与**估价**（纯函数，不碰场景）。
##
## 用户 2026-10-20：「内存条是可拾取的，每次捡到内存条，随机是 ddr3 / ddr4 / ddr5，
## 内存容量随机是 2g / 4g / 8g / 16g / 32g / 64g……每次随机是 ecc 服务器内存条、
## 非 ecc 普通台式内存条。捡到的内存条换算成为资产，价格行情自己查网络。」
## 当天第二轮补：「价格我看看，应该不对，频率也加上」。
##
## 第三轮（同一天，用户拿实际成交价逐项核对）：
##   · **DDR3 严重高估**：DDR3 1600 **8G ≈ 70 元、4G ≈ 20 元**（「网上经常有人组 4×4
##     代替 8×2」，捡垃圾多年的经验）；16G 约 137 元，服务器 ECC REG 16G 178~188 元。
##     原来表里 8G 报 360、16G 报 720，是实际行情的 2~5 倍。
##   · **DDR4 基本可用**：8G 全新 219~409 / 拆机更低；16G 389（促销）~759（金士顿）；
##     32G「1300 元起步」。原表的 640 / 1380 落在合理区间，只是上沿偏乐观。
##   · **DDR5 64G 必须分 ECC**：消费级 64G DDR5-5600 实付 ~7994 元（威刚，10-18）；
##     而服务器 **64G DDR5-5600 ECC RDIMM 公开标价 18,595~18,999 元** ——
##     原表上限 11480 连 ECC 下限的 62% 都不到。
##
## 所以现在的模型：
##   `元/GB 基准 × 各代容量系数 × 频率系数 × ECC 系数（**按代 × 容量**）`
## ECC 系数不再是「一个代一个数」—— DDR5 从 16G 的 1.6 一路涨到 64G 的 2.35，
## 因为服务器大容量 RDIMM 在缺货年份溢价最狠。
##
## ⚠️ 频率档不是每代 6 档：DDR3 1333/1600/1866、DDR4 2133/2400/2666/3200、
##    DDR5 4800/5600/6400/7200 —— 都是各自代真实卖过的 JEDEC/XMP 档位。
## **组合数 = (3 + 4 + 4) × 6 容量 × 2 ECC = 132 种**。
##
## 价格取整：< 100 元取整到 1 元，≥ 100 元取整到 10 元（不然 DDR3 2G 会和 ECC 版
## 四舍五入成同一个数）。

const DDRS := ["DDR3", "DDR4", "DDR5"]
const SIZES := [2, 4, 8, 16, 32, 64]
## 各代真实频率档（JEDEC / XMP）
const FREQS := {
	"DDR3": [1333, 1600, 1866],
	"DDR4": [2133, 2400, 2666, 3200],
	"DDR5": [4800, 5600, 6400, 7200],
}

## 元/GB 基准（2026-10 行情，取各代「主流容量 / 主流频率」的中间价）
##   DDR3：8G 70 元 → 8.75 元/GB
##   DDR4：16G 640 元 → 40 元/GB
##   DDR5：16G 1600 元 → 100 元/GB
const BASE_PER_GB := {
	"DDR3": 8.75,
	"DDR4": 40.0,
	"DDR5": 100.0,
}

## 容量系数（**按代分开**：DDR3 的小容量是拆机边角料，4G 比 8G 的单 GB 价还低）
const SIZE_FACTOR := {
	"DDR3": {2: 0.46, 4: 0.57, 8: 1.00, 16: 1.00, 32: 1.07, 64: 1.11},
	"DDR4": {2: 0.55, 4: 0.65, 8: 0.68, 16: 1.00, 32: 1.08, 64: 1.15},
	"DDR5": {2: 0.55, 4: 0.70, 8: 0.80, 16: 1.00, 32: 1.095, 64: 1.25},
}
## 频率系数：以本代主流档为 1.0
const FREQ_FACTOR := {
	"DDR3": {1333: 0.92, 1600: 1.00, 1866: 1.08},
	"DDR4": {2133: 0.90, 2400: 0.95, 2666: 1.00, 3200: 1.10},
	"DDR5": {4800: 0.92, 5600: 1.00, 6400: 1.10, 7200: 1.22},
}
## ECC（服务器 RDIMM）相对同代同容量消费条的系数 —— **按代 × 容量**
##
## 关键锚点：DDR5 5600 **64G ECC** ≈ 18,800 元 / 消费级 8,000 元 = **2.35×**；
## DDR3 16G ECC 182 / 消费级 140 ≈ 1.3×（服务器退役条量太大，反而没那么贵）。
const ECC_FACTOR := {
	"DDR3": {2: 1.60, 4: 1.60, 8: 1.50, 16: 1.30, 32: 1.20, 64: 1.10},
	"DDR4": {2: 1.50, 4: 1.40, 8: 1.30, 16: 1.20, 32: 1.25, 64: 1.40},
	"DDR5": {2: 1.50, 4: 1.50, 8: 1.50, 16: 1.60, 32: 1.80, 64: 2.35},
}


## 抽一根：代 → 该代的频率档 → 容量 → ECC，各自均匀。
static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var ddr: String = String(DDRS[rng.randi_range(0, DDRS.size() - 1)])
	var freqs: Array = FREQS[ddr]
	return {
		"ddr": ddr,
		"freq": int(freqs[rng.randi_range(0, freqs.size() - 1)]),
		"gb": int(SIZES[rng.randi_range(0, SIZES.size() - 1)]),
		"ecc": rng.randf() < 0.5,
	}


## 132 —— 11 个（代, 频率）组合 × 6 容量 × 2 ECC。自检直接拿它跟实抽对账。
static func combo_count() -> int:
	var n := 0
	for ddr in DDRS:
		n += (FREQS[ddr] as Array).size()
	return n * SIZES.size() * 2


static func all_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ddr in DDRS:
		for freq in FREQS[ddr]:
			for gb in SIZES:
				for ecc in [false, true]:
					out.append({"ddr": ddr, "freq": int(freq), "gb": gb, "ecc": ecc})
	return out


## 牌面文字：`DDR5 5600 64G ECC 服务器条` / `DDR3 1600 8G 非 ECC 台式条`
static func describe(spec: Dictionary, short := false) -> String:
	var ddr := String(spec.get("ddr", "DDR4"))
	var freq := int(spec.get("freq", 2666))
	var gb := int(spec.get("gb", 8))
	var ecc := bool(spec.get("ecc", false))
	if short:
		return "%s %d %dG %s" % [ddr, freq, gb, "ECC" if ecc else "非ECC"]
	return "%s %d %dG %s" % [ddr, freq, gb, "ECC 服务器条" if ecc else "非 ECC 台式条"]


## 一根值多少元。
##
## 锚点（2026-10）：
##   DDR3 1600 4G 非ECC → 20　　DDR3 1600 8G 非ECC → 70　　DDR3 1600 16G ECC → 180
##   DDR4 2666 8G → 220　　DDR4 2666 16G → 640　　DDR4 2666 32G → 1380
##   DDR5 5600 16G → 1600　　DDR5 5600 32G → 3500
##   DDR5 5600 64G 非ECC → 8000（威刚实付 7994）　**ECC → 18800**（RDIMM 18595~18999）
static func price_yuan(spec: Dictionary) -> int:
	var ddr := String(spec.get("ddr", "DDR4"))
	var freq := int(spec.get("freq", 2666))
	var gb := int(spec.get("gb", 8))
	var ecc := bool(spec.get("ecc", false))
	var base: float = float(BASE_PER_GB.get(ddr, 40.0))
	var size_tab: Dictionary = SIZE_FACTOR.get(ddr, {})
	var freq_tab: Dictionary = FREQ_FACTOR.get(ddr, {})
	var ecc_tab: Dictionary = ECC_FACTOR.get(ddr, {})
	var v := base * float(gb) * float(size_tab.get(gb, 1.0)) \
		* float(freq_tab.get(freq, 1.0))
	if ecc:
		v *= float(ecc_tab.get(gb, 1.5))
	return int(round(v)) if v < 100.0 else int(round(v / 10.0)) * 10


## 万为单位（给保证金那套账户做换算用）
static func price_wan(spec: Dictionary) -> float:
	return float(price_yuan(spec)) / 10000.0
