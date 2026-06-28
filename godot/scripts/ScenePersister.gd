class_name ScenePersister
extends Node

# Auto-saves the parent BaseLevel's unit layout to the live "current" slot on
# every units_changed (debounced), and restores it on _ready. Drop this node
# as a child of any level that should persist its layout across page reloads
# — leave it out of structured/campaign levels that shouldn't autosave.
#
# Storage backend lives in client/app/lib/sandbox.ts, exposed to Godot via
# window.saveSandbox(json, mode) / window.getSandbox(). The `gamemode`
# @export below decides which slot namespace this persister's saves land in
# — sandbox scenes use "sandbox", a future mission scene would use "mission",
# etc. Slot filtering in the UI uses this same tag, so each mode shows only
# its own slots.

## Free-form mode tag pushed to the storage layer. Each level scene that
## wants persistence sets this in the editor on its ScenePersister child.
@export var gamemode: String = "sandbox"

const _DEBOUNCE_SEC := 0.4

var _level: BaseLevel
var _save_pending: bool = false


func _ready() -> void:
	_level = get_parent() as BaseLevel
	if _level == null:
		push_error("ScenePersister expects a BaseLevel parent; got %s" % get_parent())
		return
	GameEvents.units_changed.connect(_queue_save)
	_restore()


func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	await get_tree().create_timer(_DEBOUNCE_SEC).timeout
	_save_pending = false
	_save_now()


func _save_now() -> void:
	if not OS.has_feature("web") or _level == null:
		return
	var snapshot := {
		"units": _level.serialize_units(),
		"extra": _extra_save_data(),
	}
	# Double-stringify: inner produces the snapshot JSON; outer wraps it as a
	# JS string literal so quotes/backslashes survive into the eval'd source.
	var snapshot_json := JSON.stringify(snapshot)
	var js_literal := JSON.stringify(snapshot_json)
	var mode_literal := JSON.stringify(gamemode)
	JavaScriptBridge.eval(
		"window.saveSandbox && window.saveSandbox(" + js_literal + ", " + mode_literal + ")"
	)


func _restore() -> void:
	if not OS.has_feature("web") or _level == null:
		return
	var mode_literal := JSON.stringify(gamemode)
	var raw = JavaScriptBridge.eval(
		'window.getSandbox ? window.getSandbox(' + mode_literal + ') : ""'
	)
	if not (raw is String) or raw == "":
		_on_restore_complete(false)
		return

	var parsed = JSON.parse_string(raw)

	# Legacy shape: a bare units array, from saves made before "extra" existed.
	if parsed is Array:
		if parsed.is_empty():
			_on_restore_complete(false)
			return
		await _level.deserialize_units(parsed)
		_on_restore_complete(true)
		return

	if not (parsed is Dictionary):
		_on_restore_complete(false)
		return

	var units_snapshot: Array = parsed.get("units", [])
	var had_units := not units_snapshot.is_empty()
	if had_units:
		await _level.deserialize_units(units_snapshot)

	_apply_extra_data(parsed.get("extra", {}))
	_on_restore_complete(had_units)


func clear_save() -> void:
	if not OS.has_feature("web"):
		return
	var empty_json := JSON.stringify({"units": [], "extra": {}})
	var js_literal := JSON.stringify(empty_json)
	var mode_literal := JSON.stringify(gamemode)
	JavaScriptBridge.eval(
		"window.saveSandbox && window.saveSandbox(" + js_literal + ", " + mode_literal + ")"
	)


func _extra_save_data() -> Dictionary:
	return {}


func _apply_extra_data(_extra: Dictionary) -> void:
	pass


func _on_restore_complete(_restored_units: bool) -> void:
	pass
