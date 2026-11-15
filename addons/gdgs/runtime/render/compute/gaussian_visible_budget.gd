@tool
extends RefCounted
class_name GaussianVisibleBudget

## Adaptive capacity for the culled-splat buffer (gsplat-stream addition).
##
## Upstream allocates `culled_splats` for every submitted splat
## (`point_count * 48 B`) but only writes entries for splats that survive
## frustum + projection culling. Everything outside the view pays 48 B/splat for
## nothing: at 10M splats that is 480 MB, mostly holes.
##
## The fork compacts: the projection pass claims an index from an atomic counter
## and stores that index in the sort keys, so the render pass keeps reading
## `culled_buffer[sort_key_value]` unchanged. That makes the buffer only need
## room for the *visible* count, which this class predicts.
##
## Same shape as GaussianSortBudget: measure -> grow on saturation with
## headroom, shrink slowly once usage has been comfortably low, all clamped.
## Pure logic, headless-testable (see tests/visible_budget_test.gd).

## Never allocate less than this fraction of point_count, so a camera turn that
## suddenly faces the whole cloud does not drop splats for several frames.
const MIN_FRACTION := 0.25
## Start here; the governor converges within a few readbacks.
const INITIAL_FRACTION := 0.75
## Usage above this fraction of capacity counts as saturated.
const GROW_THRESHOLD := 0.95
const GROW_FACTOR := 1.5
## Usage below this fraction of capacity means we hold more than 1/HEADROOM of
## slack, so the fraction may come down. Must stay above `1/HEADROOM` (0.87)
## only loosely — a value near it makes the governor oscillate; 0.80 leaves a
## quiet band and still converges to ~MIN_FRACTION..HEADROOM x visible.
const SHRINK_THRESHOLD := 0.8
const SHRINK_FACTOR := 0.85
const SHRINK_PATIENCE := 30
const HEADROOM := 1.15
## Smoothing for the shrink decision. Per-frame visible counts jitter (a camera
## pan, a splat entering the frustum); deciding on a single sample would keep
## resetting the patience counter and the fraction would never come down.
const EMA_ALPHA := 0.05

## Project setting overriding the starting fraction (VRAM vs. robustness).
const SETTING_KEY := "gsplat/rendering/visible_fraction"
## Must match RasterizeData in gsplat_projection.glsl / gaussian_memory_plan.gd.
const BYTES_PER_CULLED_SPLAT := 48

var fraction: float = INITIAL_FRACTION
var measured_visible: int = 0
var measured_fraction: float = 0.0
## Smoothed visible fraction, the quantity shrink decisions actually use.
var ema_fraction: float = 0.0
var grow_events: int = 0
var shrink_events: int = 0
var saturated_samples: int = 0
var _quiet_samples: int = 0
var _ema_initialized := false


func _init() -> void:
	var configured := float(ProjectSettings.get_setting(SETTING_KEY, INITIAL_FRACTION))
	fraction = clampf(configured, MIN_FRACTION, 1.0)


## Entries the culled buffer must hold for `point_count` submitted splats.
func capacity(point_count: int) -> int:
	var n := maxi(point_count, 0)
	return int(ceil(float(n) * fraction))


## Bytes of the culled buffer at this fraction.
func capacity_bytes(point_count: int) -> int:
	return capacity(point_count) * BYTES_PER_CULLED_SPLAT


## Feed one measured visible-splat count (the projection pass counter).
## Returns the fraction the next allocation should use.
func sample(visible_count: int, point_count: int, saturation_hit: bool = false) -> float:
	var n := maxi(point_count, 1)
	var visible := clampi(visible_count, 0, n)
	measured_visible = visible
	measured_fraction = float(visible) / float(n)
	if not _ema_initialized:
		ema_fraction = measured_fraction
		_ema_initialized = true
	else:
		ema_fraction = lerpf(ema_fraction, measured_fraction, EMA_ALPHA)

	var cap := capacity(n)
	var saturated := saturation_hit
	if cap > 0 and visible >= int(ceil(float(cap) * GROW_THRESHOLD)):
		saturated = true

	if saturated:
		saturated_samples += 1
		_quiet_samples = 0
		var derived := measured_fraction * HEADROOM
		var next := maxf(fraction + 0.05, derived)
		if visible >= cap:
			next = maxf(next, fraction * GROW_FACTOR)
		next = clampf(next, MIN_FRACTION, 1.0)
		if not is_equal_approx(next, fraction):
			fraction = next
			grow_events += 1
		return fraction

	if fraction > 0.0 and ema_fraction < fraction * SHRINK_THRESHOLD:
		_quiet_samples += 1
		if _quiet_samples >= SHRINK_PATIENCE and fraction > MIN_FRACTION:
			var next := clampf(fraction * SHRINK_FACTOR, MIN_FRACTION, 1.0)
			if not is_equal_approx(next, fraction):
				fraction = next
				shrink_events += 1
			_quiet_samples = 0
	else:
		_quiet_samples = 0

	return fraction


func reset() -> void:
	fraction = INITIAL_FRACTION
	measured_visible = 0
	measured_fraction = 0.0
	grow_events = 0
	shrink_events = 0
	saturated_samples = 0
	_quiet_samples = 0


func describe() -> String:
	return "visible budget: %.0f%% (measured %.0f%% of %d, grows=%d shrinks=%d)" % [
		fraction * 100.0, measured_fraction * 100.0, measured_visible,
		grow_events, shrink_events
	]


## Bytes saved versus allocating for every submitted splat.
static func savings_bytes(point_count: int, fraction_now: float) -> int:
	var upstream := maxi(point_count, 0) * BYTES_PER_CULLED_SPLAT
	var current := int(ceil(float(maxi(point_count, 0)) * clampf(fraction_now, MIN_FRACTION, 1.0))) * BYTES_PER_CULLED_SPLAT
	return upstream - current
