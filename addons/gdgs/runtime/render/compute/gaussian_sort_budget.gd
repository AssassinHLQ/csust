@tool
extends RefCounted
class_name GaussianSortBudget

## Adaptive worst-case sort-slot budget (gsplat-stream addition).
##
## The Compute backend allocates sort key/value buffers for
## `point_count * MAX_SORT_ELEMENTS_PER_SPLAT` entries, where the constant is a
## worst-case "how many 16x16 tiles can one splat touch". That constant is a
## static 10 in the upstream fork, so a quiet scene pays for a worst case it
## never reaches: at 8M splats the sort buffers alone are ~1.2 GB.
##
## This class turns that constant into a measured, hysteretic budget:
##
##   * the projection shader already writes the true element count into the
##     histogram buffer's first uint (`sort_buffer_size`);
##   * the renderer reads it back on a cadence and asks this class for the
##     next frame's budget;
##   * the budget grows when the true count saturates the allocation and
##     shrinks once usage has been comfortably below capacity for a while.
##
## Pure logic on purpose: no RenderingDevice, no SceneTree. Every decision is
## reproducible and headless-testable (see tests/sort_budget_test.gd).

## Hard floor: even a quiet scene needs room for a few tiles per splat.
const MIN_ELEMENTS := 2
## Hard ceiling: matches the upstream worst-case constant.
const MAX_ELEMENTS := 10
## Where a fresh budget starts (mid-range: below the upstream worst case,
## above the floor).
const INITIAL_ELEMENTS := 6

## Grow as soon as usage crosses this fraction of capacity.
const GROW_THRESHOLD := 0.95
## Grow factor applied when saturated.
const GROW_FACTOR := 2.0
## Shrink only when usage has stayed below this fraction for `SHRINK_PATIENCE`.
const SHRINK_THRESHOLD := 0.55
## Shrink slowly so quality never visibly steps down.
const SHRINK_FACTOR := 0.8
## Consecutive quiet samples required before a shrink.
const SHRINK_PATIENCE := 30
## Capacity headroom applied when deriving a budget from a measured count.
const HEADROOM := 1.25

## Project setting overriding the starting budget, so a benchmark or a game can
## trade VRAM for headroom without touching code.
const SETTING_KEY := "gsplat/rendering/sort_elements_per_splat"

var elements: int = INITIAL_ELEMENTS
## Most recent measured elements-per-splat ratio (0 until a sample arrives).
var measured_per_splat: float = 0.0
## How many samples in a row have been "comfortably below capacity".
var _quiet_samples: int = 0
## Cumulative counters, useful for tests and for a debug HUD.
var grow_events: int = 0
var shrink_events: int = 0
var saturated_samples: int = 0


func _init() -> void:
	var configured := int(ProjectSettings.get_setting(SETTING_KEY, INITIAL_ELEMENTS))
	elements = clampi(configured, MIN_ELEMENTS, MAX_ELEMENTS)


## Capacity in sort elements for `point_count` splats at the current budget.
func capacity_elements(point_count: int) -> int:
	return maxi(point_count, 0) * elements


## Budget expressed as bytes for keys+values, matching the planner.
## Keys and values are each uint32 and each buffer keeps two ping-pong halves,
## so one element costs 8 B x 2 halves x 2 buffers = 16 B.
func capacity_bytes(point_count: int) -> int:
	return capacity_elements(point_count) * 16


## Feed one measured `sort_buffer_size` sample.
##
## measured_elements  the count the projection pass wrote this frame
## point_count        splats submitted this frame
## saturation_hit     true when the shader dropped splats because the
##                    allocation was full (the renderer knows this by comparing
##                    measured against capacity, but callers may pass it
##                    explicitly when the shader reports an overflow counter)
##
## Returns the budget that should be used for the NEXT allocation.
func sample(measured_elements: int, point_count: int, saturation_hit: bool = false) -> int:
	var n := maxi(point_count, 1)
	var measured := maxi(measured_elements, 0)
	measured_per_splat = float(measured) / float(n)

	var cap := capacity_elements(n)
	var saturated := saturation_hit
	if cap > 0 and float(measured) >= float(cap) * GROW_THRESHOLD:
		saturated = true

	if saturated:
		saturated_samples += 1
		_quiet_samples = 0
		# Always grow at least one step, and fit what we just measured plus
		# headroom. When the counter actually hit the cap we doubled, because
		# the true demand is unknown and one more step would saturate again.
		var derived := int(ceil(measured_per_splat * HEADROOM))
		var next := maxi(elements + 1, derived)
		if measured >= cap:
			next = maxi(next, int(ceil(float(elements) * GROW_FACTOR)))
		next = clampi(next, MIN_ELEMENTS, MAX_ELEMENTS)
		if next != elements:
			elements = next
			grow_events += 1
		return elements

	# Not saturated: consider a slow shrink.
	if cap > 0 and float(measured) < float(cap) * SHRINK_THRESHOLD:
		_quiet_samples += 1
		if _quiet_samples >= SHRINK_PATIENCE and elements > MIN_ELEMENTS:
			var next := int(floor(float(elements) * SHRINK_FACTOR))
			next = clampi(next, MIN_ELEMENTS, MAX_ELEMENTS)
			if next != elements:
				elements = next
				shrink_events += 1
			_quiet_samples = 0
	else:
		_quiet_samples = 0

	return elements


## Reset to the initial budget (e.g. when the scene changes completely).
func reset() -> void:
	elements = INITIAL_ELEMENTS
	measured_per_splat = 0.0
	_quiet_samples = 0
	grow_events = 0
	shrink_events = 0
	saturated_samples = 0


func describe() -> String:
	return "sort budget: elements=%d measured=%.2f/splat grows=%d shrinks=%d" % [
		elements, measured_per_splat, grow_events, shrink_events
	]


## Bytes saved on the sort buffers versus the upstream static budget of 10.
static func savings_bytes(point_count: int, elements: int) -> int:
	var upstream := maxi(point_count, 0) * MAX_ELEMENTS * 16
	var current := maxi(point_count, 0) * clampi(elements, MIN_ELEMENTS, MAX_ELEMENTS) * 16
	return upstream - current
