extends RefCounted

# Excitable Mediums - static puzzle-design checks (Godot 4.3).
# This does NOT execute the pulse simulation or prove solvability.
# Input is the same Dictionary produced by LevelTools.export_level_data().

static func inspect(data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var nodes: Dictionary = {}
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	var begin_ids: Array[String] = []
	var target_ids: Array[String] = []
	var node_records: Array = data.get("nodes", [])
	var connection_records: Array = data.get("connections", [])
	var two_way: bool = bool(data.get("allow_reverse_travel", false))

	for entry in node_records:
		if not (entry is Dictionary):
			errors.append("Invalid node entry.")
			continue
		var uid: String = str(entry.get("id", ""))
		if uid.is_empty():
			errors.append("Node has no ID.")
			continue
		if nodes.has(uid):
			errors.append("Duplicate node ID: %s." % uid)
			continue
		nodes[uid] = entry
		outgoing[uid] = []
		incoming[uid] = []
		var kind: int = int(entry.get("kind", -1))
		if kind == PuzzleNode.Kind.BEGIN:
			begin_ids.append(uid)
		elif kind == PuzzleNode.Kind.TARGET:
			target_ids.append(uid)

	if begin_ids.is_empty():
		errors.append("At least one Begin node is required.")
	if target_ids.is_empty():
		errors.append("At least one Goal Target is required.")

	var seen_edges: Dictionary = {}
	for connection in connection_records:
		if not (connection is Dictionary):
			errors.append("Invalid connection entry.")
			continue
		var from_uid: String = str(connection.get("from", ""))
		var to_uid: String = str(connection.get("to", ""))
		if not nodes.has(from_uid) or not nodes.has(to_uid):
			errors.append("Connection has a missing endpoint: %s -> %s." % [from_uid, to_uid])
			continue
		if from_uid == to_uid:
			errors.append("Self-connection on %s." % from_uid)
			continue
		var endpoints: Array[String] = [from_uid, to_uid]
		endpoints.sort()
		var edge_key: String = "%s|%s" % [endpoints[0], endpoints[1]]
		if seen_edges.has(edge_key):
			errors.append("Duplicate connection between %s and %s." % [from_uid, to_uid])
			continue
		seen_edges[edge_key] = true
		# Simulation uses from_uid -> to_uid for pulse propagation.
		outgoing[from_uid].append(to_uid)
		incoming[to_uid].append(from_uid)
		if two_way:
			outgoing[to_uid].append(from_uid)
			incoming[from_uid].append(to_uid)
		if int(nodes[to_uid].get("kind", -1)) == PuzzleNode.Kind.BEGIN:
			errors.append("Connection points into Begin node %s." % to_uid)

	# A paired Wormhole is an additional directed edge in both directions.
	# It is not rendered as a bridge, but it IS reachable by pulses.
	for uid in nodes.keys():
		var entry: Dictionary = nodes[uid]
		if int(entry.get("kind", -1)) != PuzzleNode.Kind.WORMHOLE:
			continue
		var paired_uid: String = str(entry.get("wormhole_pair", ""))
		if not nodes.has(paired_uid):
			errors.append("Wormhole %s has no valid partner." % uid)
			continue
		var other: Dictionary = nodes[paired_uid]
		if int(other.get("kind", -1)) != PuzzleNode.Kind.WORMHOLE or str(other.get("wormhole_pair", "")) != uid:
			errors.append("Wormhole %s needs a reciprocal Wormhole partner." % uid)
			continue
		outgoing[uid].append(paired_uid)
		incoming[paired_uid].append(uid)

	# Union of reachable vertices from every Begin. This structural
	# check does not assume every Begin must produce a winning run.
	var visited: Dictionary = {}
	var queue: Array[String] = []
	for begin_id in begin_ids:
		visited[begin_id] = true
		queue.append(begin_id)

	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		for neighbor in outgoing.get(current, []):
			var next_uid: String = str(neighbor)
			if not visited.has(next_uid):
				visited[next_uid] = true
				queue.append(next_uid)

	for uid in target_ids:
		if not visited.has(uid) and not begin_ids.is_empty():
			errors.append("Goal Target %s has no path from any Begin." % uid)

	# Decoy starts are permitted; warn only when a start has no
	# graph route to a Goal at all. Simulation solvability is separate.
	if begin_ids.size() > 1 and not target_ids.is_empty():
		for begin_id in begin_ids:
			var start_seen: Dictionary = {}
			start_seen[begin_id] = true
			var start_queue: Array[String] = [begin_id]
			var start_cursor: int = 0
			while start_cursor < start_queue.size():
				var current: String = start_queue[start_cursor]
				start_cursor += 1
				for neighbor in outgoing.get(current, []):
					var next_uid: String = str(neighbor)
					if not start_seen.has(next_uid):
						start_seen[next_uid] = true
						start_queue.append(next_uid)
			var reaches_goal: bool = false
			for goal_id in target_ids:
				if start_seen.has(goal_id):
					reaches_goal = true
					break
			if not reaches_goal:
				warnings.append("Begin node %s has no path to a Goal (possibly intentional)." % begin_id)

	for uid in nodes.keys():
		var entry: Dictionary = nodes[uid]
		var kind: int = int(entry.get("kind", -1))
		var outputs_count: int = outgoing[uid].size()
		var inputs_count: int = incoming[uid].size()
		var degree: int = outputs_count + inputs_count
		if degree == 0:
			warnings.append("%s is isolated (no connections)." % uid)
		elif not visited.has(uid) and not begin_ids.is_empty():
			warnings.append("%s is in a disconnected section of the grid." % uid)

		if kind == PuzzleNode.Kind.BEGIN and outputs_count == 0:
			errors.append("Begin node %s has no outgoing connections." % uid)
		elif kind == PuzzleNode.Kind.SPLITTER:
			var required: int = int(entry.get("inputs", 1))
			var produced: int = int(entry.get("outputs", 2))
			if inputs_count < required or outputs_count < produced:
				warnings.append("Splitter %s: %d/%d incoming and %d/%d outgoing connection(s)." % [uid, inputs_count, required, outputs_count, produced])
		elif kind == PuzzleNode.Kind.ALTERNATING and outputs_count < 2:
			warnings.append("Alternating node %s has %d outgoing connection(s); it needs two exits to alternate." % [uid, outputs_count])
		elif kind == PuzzleNode.Kind.TARGET and degree == 0:
			# The disconnection error above is sufficient when a Begin exists.
			pass

	return {
		"errors": errors,
		"warnings": warnings,
		"node_count": nodes.size(),
		"connection_count": connection_records.size(),
		"goal_count": target_ids.size(),
		"reachable_count": visited.size()
	}
