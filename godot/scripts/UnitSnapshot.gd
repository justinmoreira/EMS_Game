class_name UnitSnapshot
extends RefCounted

# Pure, JSON-friendly (de)serialization of a Unit's physical_state.
#
# Lives apart from BaseLevel so the round-trip is unit-testable headlessly and,
# crucially, so EVERY physical_state key survives it — attributes,
# owner_player_id, immutable, placed_turn, anything. The previous BaseLevel
# path rebuilt units via Object.set(), which routes through Unit._set() and
# silently drops any key that isn't a declared definition attribute; that's
# what reset pre-placed/custom units to defaults on reload (bug E).
#
# Snapshot entry shape:  { "type": <definition id>, "state": <state dict> }
# In `state`, world_uv is encoded as {"x", "y"} for JSON; every other value is
# stored verbatim.


static func to_entry(unit) -> Dictionary:
	return {"type": String(unit.definition.id), "state": state_to_json(unit.physical_state)}


static func state_to_json(physical_state: Dictionary) -> Dictionary:
	var state: Dictionary = physical_state.duplicate()
	var uv = state.get(&"world_uv", null)
	if uv is Vector2:
		state[&"world_uv"] = {"x": uv.x, "y": uv.y}
	return state


# Rebuild a physical_state dict from a stored entry. Keys are forced to
# StringName because Godot Dictionaries treat &"power" and "power" as distinct
# keys and Unit.get_value() looks up with StringNames — JSON parsing yields
# String keys, so without this every restored attribute would read as unset.
static func state_from_entry(entry: Dictionary) -> Dictionary:
	var raw: Dictionary = entry.get("state", {})
	var state := {}
	for k in raw:
		var key := StringName(String(k))
		if key == &"world_uv":
			var uv_raw = raw[k]
			if uv_raw is Dictionary:
				state[&"world_uv"] = Vector2(
					float((uv_raw as Dictionary).get("x", 0.0)),
					float((uv_raw as Dictionary).get("y", 0.0))
				)
			elif uv_raw is Vector2:
				state[&"world_uv"] = uv_raw
		else:
			state[key] = raw[k]
	return state
