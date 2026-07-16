extends Node

# Global event bus + small amount of cross-cutting state (selection).
# Signals here are emitted from outside this class by design, so the
# per-signal `unused_signal` warnings are spurious.

# ── Existing / unit updates ───────────────────
@warning_ignore("unused_signal")
signal units_changed

@warning_ignore("unused_signal")
signal unit_placed(unit: Node)

@warning_ignore("unused_signal")
signal unit_selected(unit: Node)

@warning_ignore("unused_signal")
signal unit_deleted(unit: Node)

@warning_ignore("unused_signal")
signal unit_attribute_changed(unit: Node, attribute_name: String, new_value: Variant)

# ── Tutorial filters ──────────────────────────
# IMPORTANT:
# New main branch Sidebar.gd expects UnitDefinition ids, not Sidebar.EntityType.
# Use: [&"transceiver"], [&"jammer"], [&"sensor"], or [] to unlock all.
@warning_ignore("unused_signal")
signal tutorial_filter_sidebar(allowed_ids: Array)

# Use attribute names/ids:
# ["frequency"], ["power"], ["height"], ["bandwidth"], ["sensitivity"], etc.
@warning_ignore("unused_signal")
signal tutorial_filter_attributes(allowed_attributes: Array)

# ── Selection (single source of truth) ─────────
# Both BaseLevel (visual highlight) and Sidebar (attribute panel) read from
# `selected_unit` via the `selection_changed` signal. `selected_unit == null`
# means nothing selected. Always go through `select(unit)` / `clear_selection()`
# so the signal stays in sync with the field.
var selected_unit: Node = null

@warning_ignore("unused_signal")
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


# ── UI button intents ─────────────────────────
# Sidebar emits, BaseLevel acts.
@warning_ignore("unused_signal")
signal simulation_requested

@warning_ignore("unused_signal")
signal reset_requested

@warning_ignore("unused_signal")
signal delete_requested(unit: Node)

signal confirm_pressed(unit: Node)

signal detection_hints_toggled(enabled: bool)

# ── Link / layout / simulation events ─────────
# Drag-press clears stale link visuals before the new drag-release sim.
# LinkRenderer wires this to clear_all so Unit.gd stays decoupled from
# the SimulationManager singleton.
@warning_ignore("unused_signal")
signal links_clear_requested

# Sidebar publishes its width on resize so BaseLevel can update layout
# without a global find_child reach.
@warning_ignore("unused_signal")
signal sidebar_resized(width: float)

# Sim broadcast — SimulationManager emits, renderers/listeners react.
@warning_ignore("unused_signal")
signal simulation_complete(link_results: Array, detect_results: Array)

# Message relay — Sidebar emits send_requested; MessageRelay computes per-receiver
# delay (higher frequency = faster) and emits message_dispatched, which the
# renderer animates as a traveling pulse. Educational: visualize the benefit
# of higher transmitter frequency.
@warning_ignore("unused_signal")
signal message_send_requested(from_unit: Node)
@warning_ignore("unused_signal")
signal message_dispatched(from_unit: Node, to_unit: Node, delay: float)

# Multiplayer SUBMIT — Sidebar emits when the user presses the header
# button in MP mode. BaseLevel serializes the current unit layout and
# bridges the JSON to JS (window.mpSubmitBoard → window.submitMpAction).
@warning_ignore("unused_signal")
signal mp_submit_requested

# Multiplayer placement cap — BaseLevel emits when the one-unit-per-turn
# limit is reached (or the match ends). Sidebar greys the entity tray, the
# same way the tutorial disables placement.
@warning_ignore("unused_signal")
signal mp_placement_locked(locked: bool)
