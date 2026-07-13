class_name CoopSync
extends Node

# Real-time collaboration layer for co-op sandbox rooms. Instantiated by
# BaseLevel ONLY when window.GAME_MODE == "coop", so sandbox / multiplayer /
# tutorial are entirely unaffected. Bridges per-unit edits between the two
# players over the JS transport (CoopRoom.tsx + a Supabase broadcast channel):
#
#   Outbound — on units_changed (debounced) we diff the whole board by uid and
#     emit one op per changed unit through window.coopSendOp:
#       {op:"upsert", uid, entry}   unit added or its serialized state changed
#       {op:"delete", uid}          unit removed
#     The full merged board is also handed to window.coopSaveSnapshot each pass
#     for durable persistence (the host is elected on the JS side).
#
#   Inbound — window.coopApplyOp(opJson), called by CoopRoom.tsx for the
#     PARTNER's ops, applies them by uid. A unit the local player is actively
#     dragging is left alone (their drag wins; last-writer-wins resolves it when
#     they release).
#
# Sync is per-unit last-writer-wins — no turn structure, fog, or win condition.
# It's an open, jointly-edited sandbox.
#
# Echo avoidance: `_known` holds the last-synced serialized entry per uid and is
# diffed both to FIND local changes and to ABSORB peer-applied ones. Because a
# unit respawned from a peer's entry can serialize to a byte-different-but-
# equivalent string (float formatting / key order), applying an op marks its uid
# in `_absorb`; the next diff folds the unit's canonical serialization into
# `_known` silently instead of bouncing it back — which would otherwise ping-pong
# forever between the two clients.

const _DIFF_DEBOUNCE_SEC := 0.15

var _level: BaseLevel
var _apply_cb: Variant = null
# uid -> serialized entry JSON string currently believed in sync with the peer.
var _known: Dictionary = {}
# uids to fold into _known on the next diff WITHOUT broadcasting (just applied
# from a peer op).
var _absorb: Dictionary = {}
var _diff_pending: bool = false
var _restored: bool = false


# Attach a CoopSync child to `level` iff we're in a co-op room. Lives here (not
# in BaseLevel) so the already-huge scene script carries no coop logic. Called
# deferred from BaseLevel._ready so terrain is ready before CoopSync restores.
static func attach_if_coop(level: Node) -> void:
	if not is_coop_mode() or level.has_node("CoopSync"):
		return
	var sync := CoopSync.new()
	sync.name = "CoopSync"
	level.add_child(sync)


# True inside a collaborative sandbox room (window.GAME_MODE == "coop"). Also
# read by Sandbox.gd to suppress the singleplayer intro popup.
static func is_coop_mode() -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("window.GAME_MODE")
	return v is String and (v as String) == "coop"


func _ready() -> void:
	_level = get_parent() as BaseLevel
	if _level == null:
		push_error("CoopSync expects a BaseLevel parent; got %s" % get_parent())
		return
	# Web-only: the whole transport is JS bridge + Supabase. Desktop/headless
	# builds have no bridge, so a coop scene there is just a local sandbox.
	if not OS.has_feature("web"):
		_restored = true
		return
	_register_apply_hook()
	await _restore_shared_board()
	GameEvents.units_changed.connect(_queue_diff)


# Expose window.coopApplyOp so CoopRoom.tsx can push the partner's ops straight
# into the scene. Stored on self to keep the Callable alive (create_callback
# returns a ref that's GC'd if dropped) — same pattern as BaseLevel's MP hooks.
func _register_apply_hook() -> void:
	var window: Variant = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	_apply_cb = JavaScriptBridge.create_callback(_on_js_apply_op)
	window.coopApplyOp = _apply_cb


# ── Restore the shared board on entry ──────────────────────────────────
# CoopRoom.tsx stashes collab_rooms.state_json on window.COLLAB_SNAPSHOT before
# boot; we rebuild the scene from it so a reload or a late joiner sees the room
# as it stands. Then seed the diff baseline from the live scene.
func _restore_shared_board() -> void:
	var raw = JavaScriptBridge.eval('window.getCoopSnapshot ? window.getCoopSnapshot() : ""')
	if raw is String and raw != "":
		var parsed = JSON.parse_string(raw)
		var units: Array = []
		if parsed is Dictionary:
			units = (parsed as Dictionary).get("units", [])
		elif parsed is Array:
			units = parsed
		if not units.is_empty():
			await _level.deserialize_units(units)
	_restored = true
	_seed_known_from_scene()


# Baseline the diff from whatever is in the scene now, so the first diff doesn't
# re-broadcast the restored board to the peer as brand-new units.
func _seed_known_from_scene() -> void:
	_known.clear()
	for entry in _level.serialize_units():
		var uid := _entry_uid(entry)
		if uid != "":
			_known[uid] = JSON.stringify(entry)


# ── Outbound: diff & broadcast ─────────────────────────────────────────
func _queue_diff() -> void:
	if not _restored or _diff_pending:
		return
	_diff_pending = true
	await get_tree().create_timer(_DIFF_DEBOUNCE_SEC).timeout
	_diff_pending = false
	_broadcast_diff()


func _broadcast_diff() -> void:
	if _level == null:
		return
	var current := {}
	for entry in _level.serialize_units():
		var uid := _entry_uid(entry)
		if uid != "":
			current[uid] = entry

	# Upserts: brand-new uid, or one whose serialized content changed. Absorbed
	# uids (just applied from a peer op) are folded in silently.
	for uid in current:
		var entry_json := JSON.stringify(current[uid])
		if _absorb.has(uid):
			_known[uid] = entry_json
			_absorb.erase(uid)
			continue
		if not _known.has(uid) or _known[uid] != entry_json:
			_known[uid] = entry_json
			_send_op({"op": "upsert", "uid": uid, "entry": current[uid]})

	# Deletes: a uid we were tracking that's gone from the scene now.
	for uid in _known.keys():
		if not current.has(uid):
			_known.erase(uid)
			_absorb.erase(uid)
			_send_op({"op": "delete", "uid": uid})

	_push_snapshot()


# Hand the full merged board to JS for durable persistence. The host debounces
# and writes it to collab_rooms.state_json; the guest's call no-ops (no impl
# registered). Double-stringify so quotes survive the eval'd source.
func _push_snapshot() -> void:
	var snapshot := {"units": _level.serialize_units(), "extra": {}}
	var snap_literal := JSON.stringify(JSON.stringify(snapshot))
	JavaScriptBridge.eval(
		"window.coopSaveSnapshot && window.coopSaveSnapshot(" + snap_literal + ")"
	)


func _send_op(op: Dictionary) -> void:
	var op_literal := JSON.stringify(JSON.stringify(op))
	JavaScriptBridge.eval("window.coopSendOp && window.coopSendOp(" + op_literal + ")")


# ── Inbound: apply a partner's op ──────────────────────────────────────
func _on_js_apply_op(args: Array) -> void:
	if args.size() < 1:
		return
	var raw := str(args[0])
	var op = JSON.parse_string(raw)
	if not (op is Dictionary):
		return
	var kind := str((op as Dictionary).get("op", ""))
	var uid := str((op as Dictionary).get("uid", ""))
	if uid == "":
		return
	match kind:
		"upsert":
			var entry = (op as Dictionary).get("entry", null)
			if entry is Dictionary:
				await _apply_upsert(uid, entry)
		"delete":
			_apply_delete(uid)


func _apply_upsert(uid: String, entry: Dictionary) -> void:
	var existing := _find_by_uid(uid)
	if existing != null:
		# Never yank a unit out from under the local player's active drag; their
		# drag wins and re-broadcasts on release (last-writer-wins).
		if existing._is_being_dragged:
			return
		existing.queue_free()
		await get_tree().process_frame
	_level._spawn_unit_from_entry(entry)
	# Fold this uid into the baseline on the next diff so the units_changed our
	# spawn just fired isn't echoed back to the peer.
	_absorb[uid] = true
	GameEvents.simulation_requested.emit()


func _apply_delete(uid: String) -> void:
	var existing := _find_by_uid(uid)
	if existing != null:
		existing.queue_free()
	_known.erase(uid)
	_absorb.erase(uid)
	GameEvents.simulation_requested.emit()


# ── Helpers ────────────────────────────────────────────────────────────
func _find_by_uid(uid: String) -> Unit:
	for child in _level.get_children():
		if child is Unit and str((child as Unit).physical_state.get(&"uid", "")) == uid:
			return child as Unit
	return null


func _entry_uid(entry: Variant) -> String:
	if not (entry is Dictionary):
		return ""
	var state = (entry as Dictionary).get("state", {})
	if state is Dictionary:
		return str((state as Dictionary).get("uid", ""))
	return ""
