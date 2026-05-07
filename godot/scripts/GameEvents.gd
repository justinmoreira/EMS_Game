extends Node

# Global event bus. Signals here are emitted from outside this class by design,
# so the per-signal `unused_signal` warnings are spurious.

# Existing
@warning_ignore("unused_signal")
signal units_changed
@warning_ignore("unused_signal")
signal tutorial_filter_sidebar(allowed_ids: Array)

# Selection
@warning_ignore("unused_signal")
signal unit_selected(unit: Node)
@warning_ignore("unused_signal")
signal selection_cleared

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
