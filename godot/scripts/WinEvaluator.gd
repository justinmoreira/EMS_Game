class_name WinEvaluator
extends RefCounted

# Pure win-condition logic for the multiplayer "establish the link" mode.
#
# The board carries two immutable, neutral units placed deterministically from
# the match seed: a SOURCE transceiver (transmitter) and a TARGET sensor. Each
# player races to build a chain that carries the source's signal to the target
# — relays (their own transceivers) extend reach, jammers (anyone's) break it.
#
# A side "has a connection" when, BFS-ing out from the SOURCE over SUCCESS links
# that pass only through the SOURCE and that side's own transceivers, it reaches
# a transceiver the TARGET sensor can detect. All jammers on the board are fed
# into the link physics, so the opponent's jammers can sever your chain even
# though their transceivers aren't part of it.
#
# Win rule (see evaluate): the FIRST resolved turn in which exactly ONE side is
# connected — "the only connection" — decides the match. Both connected at once
# is not a win; neither is nobody connected.
#
# Everything here is a static function over a SimulationManager instance, so it
# is fully exercisable headlessly (SimulationManager.calculate_link /
# calculate_detection both tolerate a null terrain).

const OUTCOME_NONE := 0
const OUTCOME_MINE := 1
const OUTCOME_ENEMY := 2
const OUTCOME_DRAW := 3


# BFS connectivity from `source` to "detected by `target`" through `own_txs`
# (which MUST include `source`). `jammers` is every jammer on the board.
# (Named chain_connected, not is_connected, to avoid shadowing Object's.)
static func chain_connected(sim, source, target, own_txs: Array, jammers: Array) -> bool:
	if source == null or target == null:
		return false
	var success := SimulationManager.LinkState.SUCCESS
	var visited := {}
	var queue: Array = [source]
	visited[source.get_instance_id()] = true
	while not queue.is_empty():
		var u = queue.pop_back()
		if u == null or not is_instance_valid(u):
			continue
		# Reached the target if its sensor detects this node.
		if sim.calculate_detection(target, u):
			return true
		for v in own_txs:
			if v == null or v == u or not is_instance_valid(v):
				continue
			if visited.has(v.get_instance_id()):
				continue
			# A hop counts if either direction links successfully — the chain is
			# undirected for reachability purposes.
			var fwd: int = sim.calculate_link(u, v, jammers)
			var rev: int = sim.calculate_link(v, u, jammers)
			if fwd == success or rev == success:
				visited[v.get_instance_id()] = true
				queue.append(v)
	return false


# Partition the board and decide the outcome of the just-resolved turn.
#
#   source / target          immutable neutral units
#   all_transceivers         every transceiver Unit on the board (incl. source)
#   all_jammers              every jammer Unit on the board
#   my_id / opp_id           owner_player_id strings ("" opp_id ⇒ solo/testing)
#
# Ownership lives in physical_state.owner_player_id; the immutable source has
# none and is shared by both sides.
static func evaluate(
	sim, source, target, all_transceivers: Array, all_jammers: Array, my_id: String, opp_id: String
) -> int:
	var mine := connectivity_for(sim, source, target, all_transceivers, all_jammers, my_id)
	var theirs := false
	if opp_id != "":
		theirs = connectivity_for(sim, source, target, all_transceivers, all_jammers, opp_id)

	if mine and not theirs:
		return OUTCOME_MINE
	if theirs and not mine:
		return OUTCOME_ENEMY
	return OUTCOME_NONE


# Connectivity for a single side: source + that side's transceivers only.
static func connectivity_for(
	sim, source, target, all_transceivers: Array, all_jammers: Array, side_id: String
) -> bool:
	var side_txs: Array = []
	if source != null:
		side_txs.append(source)
	for t in all_transceivers:
		if t == null or t == source or not is_instance_valid(t):
			continue
		var owner_v = t.physical_state.get(&"owner_player_id", null)
		# A side owns a transceiver when its owner tag matches. With an empty
		# side_id (solo/headless test), unowned transceivers count as "mine".
		if side_id == "":
			if owner_v == null:
				side_txs.append(t)
		elif owner_v is String and String(owner_v) == side_id:
			side_txs.append(t)
	return chain_connected(sim, source, target, side_txs, all_jammers)
