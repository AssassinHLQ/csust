extends SceneTree

## Headless test for the adaptive sort-slot budget (gsplat-stream addition).
##   godot --headless --path . --script tests/sort_budget_test.gd
##
## Pure policy logic: no RenderingDevice, no display server.

const Budget := preload("res://addons/gdgs/runtime/render/compute/gaussian_sort_budget.gd")


func _initialize() -> void:
	var failures: PackedStringArray = []

	# --- Fresh state ---------------------------------------------------------
	var b: Budget = Budget.new()
	if b.elements != Budget.INITIAL_ELEMENTS:
		failures.append("initial budget should be %d" % Budget.INITIAL_ELEMENTS)

	# --- Saturation grows the budget ----------------------------------------
	var n := 1_000_000
	var cap := b.capacity_elements(n)
	var before := b.elements
	var grown := b.sample(cap, n)  # exactly at capacity -> saturated
	if grown <= before:
		failures.append("saturated sample should grow the budget (%d -> %d)" % [before, grown])
	if b.grow_events <= 0:
		failures.append("grow_events should count the growth")

	# --- Growth is capped ----------------------------------------------------
	var hot: Budget = Budget.new()
	for i in 200:
		hot.sample(hot.capacity_elements(n) * 2, n, true)
	if hot.elements > Budget.MAX_ELEMENTS:
		failures.append("budget exceeded MAX_ELEMENTS: %d" % hot.elements)

	# --- Quiet usage shrinks only after patience ----------------------------
	var quiet: Budget = Budget.new()
	var start := quiet.elements
	for i in Budget.SHRINK_PATIENCE - 1:
		quiet.sample(int(n * 1), n)  # 1 element/splat: far below capacity
	if quiet.elements != start:
		failures.append("budget shrank before SHRINK_PATIENCE (%d -> %d)" % [start, quiet.elements])

	quiet.sample(int(n * 1), n)  # one more sample crosses the patience line
	if quiet.elements >= start:
		failures.append("budget should shrink after patience (%d -> %d)" % [start, quiet.elements])
	if quiet.shrink_events <= 0:
		failures.append("shrink_events should count the shrink")

	# --- Shrink is floored ---------------------------------------------------
	var floor_b: Budget = Budget.new()
	for i in 2000:
		floor_b.sample(0, n)
	if floor_b.elements < Budget.MIN_ELEMENTS:
		failures.append("budget fell below MIN_ELEMENTS: %d" % floor_b.elements)

	# --- A realistic scene profile settles ----------------------------------
	# 2M splats, average 1.8 tiles/splat with a small tail, starting from the
	# upstream worst case: the governor should notice the spare room and come
	# down, then stay put.
	var scene: Budget = Budget.new()
	scene.elements = Budget.MAX_ELEMENTS
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var settled := -1
	for frame in 400:
		var per_splat := 1.8 + rng.randf_range(-0.3, 0.9)
		var measured := int(2_000_000 * per_splat)
		scene.sample(measured, 2_000_000)
		if settled < 0 and frame > Budget.SHRINK_PATIENCE and scene.elements <= 4:
			settled = frame
	if settled < 0:
		failures.append("governor never came down from MAX_ELEMENTS on a quiet scene")
	if scene.elements < Budget.MIN_ELEMENTS or scene.elements > Budget.MAX_ELEMENTS:
		failures.append("settled budget out of range: %d" % scene.elements)

	# --- Savings accounting --------------------------------------------------
	var saved := Budget.savings_bytes(8_000_000, 4)
	var expected := 8_000_000 * (Budget.MAX_ELEMENTS - 4) * 16
	if saved != expected:
		failures.append("savings_bytes mismatch: %d != %d" % [saved, expected])
	var saved_mb := saved / (1024.0 * 1024.0)

	print("--- adaptive sort budget ---")
	print("  initial=%d  max=%d  patience=%d" % [Budget.INITIAL_ELEMENTS, Budget.MAX_ELEMENTS, Budget.SHRINK_PATIENCE])
	print("  quiet-scene example settled at %d elements after %d frames" % [scene.elements, settled])
	print("  8M splats at 4 elements saves %.0f MB of sort buffers" % saved_mb)

	# --- Integration with the VRAM planner -----------------------------------
	var Plan := preload("res://addons/gdgs/runtime/render/compute/gaussian_memory_plan.gd")
	var hd := Vector2i(1920, 1080)
	var upstream: Dictionary = Plan.compute(8_000_000, Budget.MAX_ELEMENTS, 2, hd, 1)
	var adapted: Dictionary = Plan.compute(8_000_000, scene.elements, 2, hd, 1)
	print("  8M deg2: worst-case %.0f MB -> adaptive(%d) %.0f MB (%.2fx)"
		% [float(upstream["total_mb"]), scene.elements, float(adapted["total_mb"]),
		   float(upstream["total_mb"]) / float(adapted["total_mb"])])

	if failures.is_empty():
		print("sort budget test passed")
		quit(0)
	else:
		for failure in failures:
			push_error("sort budget test: %s" % failure)
		quit(1)
