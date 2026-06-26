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
	# Multiplayer shares the same level scene but persists its state in the
	# matches/match_actions tables — never to the sandbox localStorage slot.
	# Skip both the autosave hookup and the restore so an MP session can't
	# clobber (or be seeded by) the player's sandbox snapshot.
	if _is_multiplayer():
		return
	GameEvents.units_changed.connect(_queue_save)
	_restore()


func _is_multiplayer() -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("window.GAME_MODE")
	return v is String and (v as String) == "multiplayer"


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
	var snapshot := _level.serialize_units()
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
	var raw = JavaScriptBridge.eval('window.getSandbox ? window.getSandbox() : ""')
	if not (raw is String) or raw == "":
		return
	var snapshot = JSON.parse_string(raw)
	if not (snapshot is Array) or snapshot.is_empty():
		return
	_level.deserialize_units(snapshot)
