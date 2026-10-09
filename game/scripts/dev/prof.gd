class_name Prof
extends RefCounted
## Coarse profiler for headless runs (--profile=1): time spent per named section.

static var enabled := false
static var _totals := {}
static var _counts := {}


static func start() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func stop(key: String, started: int) -> void:
	if not enabled:
		return
	_totals[key] = _totals.get(key, 0) + Time.get_ticks_usec() - started
	_counts[key] = _counts.get(key, 0) + 1


static func report(frames: int) -> void:
	var keys := _totals.keys()
	keys.sort_custom(func(a, b) -> bool: return _totals[a] > _totals[b])
	for key in keys:
		print("  %-28s %8.3f ms/frame  %8d calls" % [key, _totals[key] / 1000.0 / maxi(1, frames), _counts[key]])
	_totals.clear()
	_counts.clear()
