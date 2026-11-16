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

	if begin_ids.size() != 1:
		errors.append("Exactly one Begin node is required (found %d)." % begin_ids.size())
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
		if int(nodes[to_uid].get("kind", -1)) == PuzzleNode.Kind.BEGIN:
			errors.append("Connection points into Begin node %s." % to_uid)

	var visited: Dictionary = {}
	if begin_ids.size() == 1:
		var queue: Array[String] = [begin_ids[0]]
		visited[begin_ids[0]] = true
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
		if not visited.has(uid) and begin_ids.size() == 1:
			errors.append("Goal Target %s has no connection path from Begin." % uid)

	for uid in nodes.keys():
		var entry: Dictionary = nodes[uid]
		var kind: int = int(entry.get("kind", -1))
		var outputs_count: int = outgoing[uid].size()
		var inputs_count: int = incoming[uid].size()
		var degree: int = outputs_count + inputs_count
		if degree == 0:
			warnings.append("%s is isolated (no connections)." % uid)
		elif not visited.has(uid) and begin_ids.size() == 1:
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
