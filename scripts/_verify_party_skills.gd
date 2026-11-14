extends SceneTree
## 验「四名队友各带一个技能、大冷却，伤害独立于普通射击」。
##
## 用现成的 game.tscn（平地 + BossPig），**不掺普通射击**：
## 先把四把枪的 enabled 全关掉，再逐个 `debug_force_skill` 读 Boss 掉血。
## 这一条同时也验证了 game.tscn 里给每把枪配的 skill / attack_interval。
##
## 跑法：godot --headless --path . --script res://scripts/_verify_party_skills.gd -- --splat=off

## 技能设计值（改 `companion_gun.gd` 里的常量时要同步改这里）
const EXPECT := {
	"grenade": 270.0,   # 3 × 90
	"snipe": 240.0,
	"shred": 240.0,     # 12 × 20
	"rail": 220.0,
}
const ATTACK_INTERVAL := 0.30

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	var pig := game.get_node_or_null("BossPig") as Node3D
	if pig == null:
		print("  [FAIL] game.tscn 里没有 BossPig")
		quit(1)
		return
	pig.set_process(false)
	pig.set("max_health", 99999.0)
	pig.set("health", 99999.0)

	var party: Array[Companion] = []
	for c in game.get_children():
		if c is Companion:
			party.append(c as Companion)
	_check(party.size() == 4, "场上 4 名同伴（实测 %d）" % party.size())

	# 排在 pig 南侧 4 m 一字排开、统一面对 −Z；关掉跟随物理免得边打边挪
	var center := pig.global_position + Vector3(0, 0, 4.0)
	for i in party.size():
		var c := party[i]
		c.set_physics_process(false)
		c.global_position = Vector3(center.x + (float(i) - 1.5) * 1.0, 0.05, center.z)
		c.rotation.y = PI
		var g := c.get_node_or_null("Gun")
		if g != null:
			g.set("enabled", false)
	await _wait_frames(3)

	var kinds: Array[String] = []
	var dmg_ok := true
	var speed_ok := true
	for c in party:
		var g := c.get_node_or_null("Gun")
		if g == null:
			_check(false, "%s 没挂 Gun" % c.display_name)
			continue
		var kind := String(g.call("skill_name"))
		kinds.append("%s=%s" % [c.display_name, kind])
		if not is_equal_approx(float(g.get("attack_interval")), ATTACK_INTERVAL):
			speed_ok = false
		var hp0 := float(pig.get("health"))
		g.call("debug_force_skill", pig)
		await _wait_seconds(1.4)
		var dealt := hp0 - float(pig.get("health"))
		var want := float(EXPECT.get(kind, -1.0))
		var ok := want >= 0.0 and absf(dealt - want) <= 1.0
		print("  [%s] %s 技能 %s：扣血 %.0f（期望 %.0f）" % [
			"PASS" if ok else "FAIL", c.display_name, kind, dealt, want])
		if not ok:
			dmg_ok = false
	_check(dmg_ok, "四个技能都按设计伤害命中")
	var uniq := {}
	for s in kinds:
		uniq[s] = true
	_check(uniq.size() == 4, "四个人的技能互不相同（%s）" % ", ".join(kinds))
	_check(speed_ok, "四人攻速都是 %.2f s/发" % ATTACK_INTERVAL)

	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _wait_frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _wait_seconds(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame
