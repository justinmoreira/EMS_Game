class_name WinEvaluator
extends RefCounted

# Pure win-condition logic for the multiplayer "complete your line" mode.
#
# Each player owns a PRIVATE line: an immutable SOURCE transceiver in one corner
# and an immutable TARGET sensor in the opposite one (host runs TL→BR, guest
# TR→BL, so the lines cross). A player completes their line by building a chain
# of their own relays (transceivers) that carries their source's signal to their
# target — and they can drop jammers to sever the opponent's chain.
#
# A line is "complete" when, BFS-ing from its SOURCE over SUCCESS links through
# only that player's own transceivers, it reaches a transceiver the line's TARGET
# can detect. Every jammer on the board is fed into the link physics, so either
# player's jammers can break either line.
#
# Win rule (see evaluate): the FIRST resolved turn in which exactly ONE line is
# complete — "the only connection" — decides the match. Both complete at once is
# not a win; neither is nobody complete.
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


# Decide the outcome of the just-resolved turn for two PRIVATE lines.
#
# Each player has their own source→target pair and their own relays; a player's
# relays only extend their own line. `jammers` is every jammer on the board, so
# either player's jammers can sever either line. The match is decided the first
# turn exactly ONE line is complete ("the only connection").
static func evaluate(
	sim,
	my_source,
	my_target,
	my_relays: Array,
	opp_source,
	opp_target,
	opp_relays: Array,
	jammers: Array
) -> int:
	var my_txs: Array = [my_source]
	my_txs.append_array(my_relays)
	var mine := chain_connected(sim, my_source, my_target, my_txs, jammers)

	var theirs := false
	if is_instance_valid(opp_source) and is_instance_valid(opp_target):
		var opp_txs: Array = [opp_source]
		opp_txs.append_array(opp_relays)
		theirs = chain_connected(sim, opp_source, opp_target, opp_txs, jammers)

	if mine and not theirs:
		return OUTCOME_MINE
	if theirs and not mine:
		return OUTCOME_ENEMY
	return OUTCOME_NONE
