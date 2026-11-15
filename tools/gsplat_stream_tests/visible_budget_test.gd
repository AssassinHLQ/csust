extends SceneTree

## Headless test for the adaptive culled-buffer budget (gsplat-stream addition).
##   godot --headless --path . --script tests/visible_budget_test.gd

const Budget := preload("res://addons/gdgs/runtime/render/compute/gaussian_visible_budget.gd")
const Plan := preload("res://addons/gdgs/runtime/render/compute/gaussian_memory_plan.gd")

const HD := Vector2i(1920, 1080)


func _initialize() -> void:
	var failures: PackedStringArray = []
	var n := 10_000_000

	# --- Fresh state ---------------------------------------------------------
	var b: Budget = Budget.new()
	if absf(b.fraction - Budget.INITIAL_FRACTION) > 1e-6:
		failures.append("initial fraction should be %.2f" % Budget.INITIAL_FRACTION)
	if b.capacity(n) <= 0:
		failures.append("capacity should be positive")

	# --- Saturation grows ----------------------------------------------------
	var start := b.fraction
	var grown := b.sample(b.capacity(n), n)
	if grown <= start:
		failures.append("saturated sample should grow the fraction (%.2f -> %.2f)" % [start, grown])
	if b.grow_events <= 0:
		failures.append("grow_events should count growth")

	# --- Growth is capped at 100% -------------------------------------------
	var hot: Budget = Budget.new()
	for i in 100:
		hot.sample(n, n, true)
	if hot.fraction > 1.0 + 1e-6:
		failures.append("fraction exceeded 1.0: %.3f" % hot.fraction)

	# --- Shrink needs patience and is floored --------------------------------
	var quiet: Budget = Budget.new()
	var quiet_start := quiet.fraction
	for i in Budget.SHRINK_PATIENCE - 1:
		quiet.sample(int(n * 0.1), n)
	if absf(quiet.fraction - quiet_start) > 1e-6:
		failures.append("shrank before patience")

	quiet.sample(int(n * 0.1), n)
	if quiet.fraction >= quiet_start:
		failures.append("should shrink after patience (%.2f -> %.2f)" % [quiet_start, quiet.fraction])

	var floor_b: Budget = Budget.new()
	for i in 5000:
		floor_b.sample(0, n)
	if floor_b.fraction < Budget.MIN_FRACTION - 1e-6:
		failures.append("fraction fell below MIN_FRACTION: %.3f" % floor_b.fraction)

	# --- A typical orbit settles --------------------------------------------
	# Camera orbits a cloud where ~55% of splats are in view.
	var scene: Budget = Budget.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var settled_frames := -1
	for frame in 400:
		var visible := int(n * (0.55 + rng.randf_range(-0.08, 0.08)))
		scene.sample(visible, n)
		if settled_frames < 0 and frame > Budget.SHRINK_PATIENCE and scene.fraction < 0.8:
			settled_frames = frame
	if settled_frames < 0:
		failures.append("visible budget never settled below its initial 75%")
	if scene.fraction < Budget.MIN_FRACTION - 1e-6 or scene.fraction > 1.0 + 1e-6:
		failures.append("settled fraction out of range: %.3f" % scene.fraction)

	# --- Savings vs the upstream full allocation ----------------------------
	var saved := Budget.savings_bytes(n, scene.fraction)
	if saved <= 0:
		failures.append("expected positive savings at %.2f%%" % (scene.fraction * 100.0))

	print("--- adaptive culled budget (10M splats) ---")
	print("  initial %.0f%%  min %.0f%%  settled %.0f%% after %d frames"
		% [Budget.INITIAL_FRACTION * 100.0, Budget.MIN_FRACTION * 100.0,
		   scene.fraction * 100.0, settled_frames])
	print("  culled buffer: %.0f MB saved (%.0f MB -> %.0f MB)"
		% [saved / (1024.0 * 1024.0),
		   n * 48 / (1024.0 * 1024.0),
		   scene.capacity_bytes(n) / (1024.0 * 1024.0)])

	# --- Combined 10M footprint ---------------------------------------------
	# degree 2 + sort budget 4 + culled at the settled fraction.
	print("--- 10M footprint, degree 2 ---")
	var upstream: Dictionary = Plan.compute(n, 10, -1, HD, 1, 1.0)
	var optimized: Dictionary = Plan.compute(n, 4, 2, HD, 1, scene.fraction)
	print("  upstream (canonical, max_elem 10, full culled): %6.0f MB" % float(upstream["total_mb"]))
	print("  optimized (deg2, max_elem 4, culled %.0f%%):      %6.0f MB  (%.2fx)"
		% [scene.fraction * 100.0, float(optimized["total_mb"]),
		   float(upstream["total_mb"]) / float(optimized["total_mb"])])

	# The objective is <= 2048 MB for 10M.
	if float(optimized["total_mb"]) > 2048.0:
		failures.append(
			"10M optimized footprint %.0f MB still exceeds the 2048 MB target"
			% float(optimized["total_mb"])
		)

	# --- Planner sanity: fraction only affects the culled buffer -------------
	var full: Dictionary = Plan.compute(n, 4, 2, HD, 1, 1.0)
	if int(full["buffers"]["culled_splats"]) != n * 48:
		failures.append("full fractional culled buffer should be point_count * 48")

	if failures.is_empty():
		print("visible budget test passed")
		quit(0)
	else:
		for failure in failures:
			push_error("visible budget test: %s" % failure)
		quit(1)
