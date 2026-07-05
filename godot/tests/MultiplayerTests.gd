extends "res://tests/BaseTest.gd"

# Covers the two headless-verifiable pillars of the multiplayer mode:
#   1. UnitSnapshot round-trip preserves EVERY physical_state key through a
#      real JSON encode/decode (bug E: attributes reset to default on reload).
#   2. WinEvaluator's source→target connectivity + outcome logic, driven by a
#      deterministic stub sim so the result doesn't hinge on physics tuning.


# Scripted stand-in for SimulationManager: link/detection answers are set up
# per test, so WinEvaluator's graph logic is tested in isolation.
class StubSim:
	extends RefCounted
	var _links := {}
	var _detected := {}

	func link(a, b) -> void:
		_links[_pkey(a, b)] = true

	func detect(tx) -> void:
		_detected[tx.get_instance_id()] = true

	func _pkey(a, b) -> String:
		var ia: int = a.get_instance_id()
		var ib: int = b.get_instance_id()
		return "%d|%d" % ([ia, ib] if ia < ib else [ib, ia])

	func calculate_link(a, b, _jammers):
		if _links.get(_pkey(a, b), false):
			return SimulationManager.LinkState.SUCCESS
		return SimulationManager.LinkState.FAILED_OUT_OF_RANGE

	# Mirror the real SimulationManager.calculate_detection signature
	# (receiver, transmitter, jammers) -> Dictionary so these tests exercise the
	# shape WinEvaluator actually calls, instead of masking an arity mismatch.
	func calculate_detection(_sensor, tx, _jammers) -> Dictionary:
		var d: bool = _detected.get(tx.get_instance_id(), false)
		return {"detected": d, "fully_detected": d}


# Units are built with Unit.new() and never added to the tree, so they're
# orphan Nodes — free() them at the end of each test or Godot reports
# "resources still in use at exit" (which the runner treats as a failure).
var _spawned: Array = []


func _track(u):
	_spawned.append(u)
	return u


func _free_spawned() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _ready() -> void:
	test_snapshot_round_trip()
	test_win_direct()
	test_win_none()
	test_win_relay_mine_only()
	test_win_both_connected_is_no_win()
	test_win_enemy_only()
	test_win_jammed_chain_breaks()
	_free_spawned()


# ── Bug E: full attribute persistence across a JSON round-trip ────────────
func test_snapshot_round_trip() -> void:
	print("\nRunning Snapshot Round-Trip Tests (bug E)...")

	var unit: Unit = _track(
		make_unit(
			"sensor",
			Vector2.ZERO,
			{
				&"sensitivity": 8,
				&"height": 9,
				&"tuning_frequency": 1234.0,
				&"sensor_bandwidth": 2,
				&"unit_name": "My Sensor",
			}
		)
	)
	# Non-attribute state the old set()-based restore would have dropped.
	unit.physical_state[&"owner_player_id"] = "player-1"
	unit.physical_state[&"immutable"] = true
	unit.physical_state[&"placed_turn"] = 3
	unit.physical_state[&"world_uv"] = Vector2(0.25, 0.75)

	# Encode → real JSON string → decode → rebuild state, exactly like the DB path.
	var entry := UnitSnapshot.to_entry(unit)
	var json := JSON.stringify(entry)
	var parsed: Variant = JSON.parse_string(json)
	assert_true(parsed is Dictionary, "Round-trip JSON parses back to a Dictionary.")
	var state := UnitSnapshot.state_from_entry(parsed)

	assert_eq(state.get(&"sensitivity"), 8, "sensitivity preserved (attribute).")
	assert_eq(state.get(&"height"), 9, "height preserved (attribute).")
	assert_approx(
		float(state.get(&"tuning_frequency", 0.0)), 1234.0, 0.001, "tuning_frequency preserved."
	)
	assert_eq(state.get(&"sensor_bandwidth"), 2, "enum bandwidth preserved.")
	assert_eq(state.get(&"unit_name"), "My Sensor", "string unit_name preserved.")
	assert_eq(
		state.get(&"owner_player_id"), "player-1", "owner_player_id preserved (non-attribute)."
	)
	assert_eq(state.get(&"immutable"), true, "immutable flag preserved (non-attribute).")
	assert_eq(state.get(&"placed_turn"), 3, "placed_turn preserved (non-attribute).")
	assert_true(state.get(&"world_uv") is Vector2, "world_uv decoded back to Vector2.")
	assert_approx(state.get(&"world_uv").x, 0.25, 0.001, "world_uv.x preserved.")
	assert_approx(state.get(&"world_uv").y, 0.75, 0.001, "world_uv.y preserved.")

	# StringName lookup is the crux of bug E: JSON keys come back as Strings,
	# but get_value() reads with StringNames. Prove a rebuilt unit reads them.
	var restored: Unit = _track(make_unit("sensor", Vector2.ZERO, {}))
	restored.physical_state = state
	assert_eq(
		restored.get_value(&"sensitivity"), 8, "Rebuilt unit reads sensitivity via StringName."
	)
	assert_eq(
		restored.get_value(&"unit_name"), "My Sensor", "Rebuilt unit reads name via StringName."
	)
	print("")


# ── Win condition: private-line completion & outcome ─────────────────────
# Each test builds my line (my_src→my_tgt + my relays) and the opponent's line
# (opp_src→opp_tgt + their relays); evaluate() decides the turn.


func _imm_tx() -> Unit:
	var u := make_unit("transceiver", Vector2.ZERO, {})
	u.physical_state[&"immutable"] = true
	return _track(u)


func _imm_sensor() -> Unit:
	var u := make_unit("sensor", Vector2.ZERO, {})
	u.physical_state[&"immutable"] = true
	return _track(u)


func _relay() -> Unit:
	return _track(make_unit("transceiver", Vector2.ZERO, {}))


func test_win_direct() -> void:
	print("Running Win: my target sees my source directly...")
	var sim := StubSim.new()
	var msrc := _imm_tx()
	var mtgt := _imm_sensor()
	var osrc := _imm_tx()
	var otgt := _imm_sensor()
	sim.detect(msrc)  # my target sees my source
	var outcome := WinEvaluator.evaluate(sim, msrc, mtgt, [], osrc, otgt, [], [])
	assert_eq(outcome, WinEvaluator.OUTCOME_MINE, "My line complete, opp empty ⇒ MINE.")


func test_win_none() -> void:
	print("Running Win: neither line complete...")
	var sim := StubSim.new()
	var msrc := _imm_tx()
	var mtgt := _imm_sensor()
	var osrc := _imm_tx()
	var otgt := _imm_sensor()
	var outcome := WinEvaluator.evaluate(sim, msrc, mtgt, [], osrc, otgt, [], [])
	assert_eq(outcome, WinEvaluator.OUTCOME_NONE, "Nothing detected ⇒ NONE.")


func test_win_relay_mine_only() -> void:
	print("Running Win: my relay completes my line...")
	var sim := StubSim.new()
	var msrc := _imm_tx()
	var mtgt := _imm_sensor()
	var osrc := _imm_tx()
	var otgt := _imm_sensor()
	var r1 := _relay()
	sim.link(msrc, r1)  # my source links to my relay
	sim.detect(r1)  # my target detects my relay (not the source)
	var outcome := WinEvaluator.evaluate(sim, msrc, mtgt, [r1], osrc, otgt, [], [])
	assert_eq(outcome, WinEvaluator.OUTCOME_MINE, "My relay bridges my line ⇒ MINE.")


func test_win_both_connected_is_no_win() -> void:
	print("Running Win: both lines complete is not 'the only connection'...")
	var sim := StubSim.new()
	var msrc := _imm_tx()
	var mtgt := _imm_sensor()
	var osrc := _imm_tx()
	var otgt := _imm_sensor()
	var r1 := _relay()
	var r2 := _relay()
	sim.link(msrc, r1)
	sim.detect(r1)
	sim.link(osrc, r2)
	sim.detect(r2)
	var outcome := WinEvaluator.evaluate(sim, msrc, mtgt, [r1], osrc, otgt, [r2], [])
	assert_eq(outcome, WinEvaluator.OUTCOME_NONE, "Both lines complete ⇒ NONE.")


func test_win_enemy_only() -> void:
	print("Running Win: only the opponent's line is complete...")
	var sim := StubSim.new()
	var msrc := _imm_tx()
	var mtgt := _imm_sensor()
	var osrc := _imm_tx()
	var otgt := _imm_sensor()
	var r2 := _relay()
	sim.link(osrc, r2)
	sim.detect(r2)
	var outcome := WinEvaluator.evaluate(sim, msrc, mtgt, [], osrc, otgt, [r2], [])
	assert_eq(outcome, WinEvaluator.OUTCOME_ENEMY, "Only opp line complete ⇒ ENEMY.")


func test_win_jammed_chain_breaks() -> void:
	print("Running Win: a severed link denies my line...")
	var sim := StubSim.new()
	var msrc := _imm_tx()
	var mtgt := _imm_sensor()
	var osrc := _imm_tx()
	var otgt := _imm_sensor()
	var r1 := _relay()
	# My target detects my relay, but the source→relay hop is down (jammed), so
	# the relay is unreachable from my source and my line isn't complete.
	sim.detect(r1)
	var outcome := WinEvaluator.evaluate(sim, msrc, mtgt, [r1], osrc, otgt, [], [])
	assert_eq(outcome, WinEvaluator.OUTCOME_NONE, "Detected-but-unlinked relay ⇒ NONE.")
	print("")
