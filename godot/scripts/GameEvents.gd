extends Node

# Global event bus + small amount of cross-cutting state (selection).
# Signals here are emitted from outside this class by design, so the
# per-signal `unused_signal` warnings are spurious.

# ── Existing
@warning_ignore("unused_signal")
signal units_changed
@warning_ignore("unused_signal")
signal tutorial_filter_sidebar(allowed_ids: Array)

# ── Selection (single source of truth)
# Both BaseLevel (visual highlight) and Sidebar (attribute panel) read from
# `selected_unit` via the `selection_changed` signal. `selected_unit == null`
# means nothing selected. Always go through `select(unit)` / `clear_selection()`
# so the signal stays in sync with the field.
var selected_unit: Node = null
signal selection_changed(unit: Node)


func select(unit: Node) -> void:
	if selected_unit == unit:
		return
	selected_unit = unit
	selection_changed.emit(unit)


func clear_selection() -> void:
	if selected_unit == null:
		return
	selected_unit = null
	selection_changed.emit(null)


# UI button intents — Sidebar emits, BaseLevel acts.
@warning_ignore("unused_signal")
signal simulation_requested
@warning_ignore("unused_signal")
signal reset_requested
@warning_ignore("unused_signal")
signal delete_requested(unit: Node)

# Sidebar publishes its width on resize so BaseLevel can update layout
# without a global find_child reach.
@warning_ignore("unused_signal")
signal sidebar_resized(width: float)

# Sim broadcast — SimulationManager emits, renderers/listeners react.
@warning_ignore("unused_signal")
signal simulation_complete(link_results: Array, detect_results: Array)
