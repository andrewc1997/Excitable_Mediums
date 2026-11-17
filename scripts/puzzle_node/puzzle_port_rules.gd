extends RefCounted

# Excitable Mediums - shared, deterministic bridge/rotor rules.
# Godot 4.3. No global class_name: preload this from the scripts that use it.
# A bridge is stored only once. Reversible traversal is a runtime option.

static func incident_links(
	uid: String,
	records: Array,
	nodes_by_id: Dictionary,
	allow_reverse: bool
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		var from_uid: String = str(record.get("from_uid", ""))
		var to_uid: String = str(record.get("to_uid", ""))
		var path: Array[Vector2i] = []
		for cell in record.get("path", []):
			path.append(cell)
		if path.size() < 2:
			continue
		if from_uid == uid:
			result.append({"to": to_uid, "path": path, "reversed": false})
		elif allow_reverse and to_uid == uid:
			path.reverse()
			result.append({"to": from_uid, "path": path, "reversed": true})
	return result


static func _direction(option: Dictionary, grid: PuzzleGridBase) -> Vector2:
	var path: Array = option.get("path", [])
	if path.size() < 2:
		return Vector2.ZERO
	return (grid.cell_to_local(path[1]) - grid.cell_to_local(path[0])).normalized()


static func sort_clockwise(options: Array[Dictionary], grid: PuzzleGridBase) -> void:
	# Godot screen Y increases downward, so increasing atan2 is clockwise.
	options.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var da: Vector2 = _direction(a, grid)
			var db: Vector2 = _direction(b, grid)
			var aa: float = atan2(da.y, da.x)
			var ab: float = atan2(db.y, db.x)
			if absf(aa - ab) > 0.00001:
				return aa < ab
			return str(a["to"]) < str(b["to"])
	)


static func sort_upper_first(options: Array[Dictionary], grid: PuzzleGridBase) -> void:
	# Same upper/lower ordering as the existing Alternating simulation.
	options.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var da: Vector2 = _direction(a, grid)
			var db: Vector2 = _direction(b, grid)
			if absf(da.y - db.y) > 0.00001:
				return da.y < db.y
			return str(a["to"]) < str(b["to"])
	)


static func get_rotor(
	uid: String,
	records: Array,
	nodes_by_id: Dictionary,
	grid: PuzzleGridBase,
	steps: int,
	allow_reverse: bool
) -> Dictionary:
	var ports: Array[Dictionary] = incident_links(
		uid, records, nodes_by_id, allow_reverse
	)
	sort_clockwise(ports, grid)
	if ports.size() < 3:
		return {"valid": false, "ports": ports, "outputs": []}

	# The as-authored inbound bridge is the unused output port at zero.
	# Each click moves that unused port clockwise; the other two send pulses.
	var original_inbound: String = ""
	for item in records:
		if not (item is Dictionary):
			continue
		if str(item.get("to_uid", "")) == uid:
			original_inbound = str(item.get("from_uid", ""))
			break
	var reference_index: int = 0
	for index in range(ports.size()):
		if str(ports[index]["to"]) == original_inbound:
			reference_index = index
			break

	var input_index: int = posmod(reference_index + steps, ports.size())
	var outputs: Array[Dictionary] = []
	for index in range(ports.size()):
		if index != input_index:
			outputs.append(ports[index])
	sort_upper_first(outputs, grid)
	return {
		"valid": true,
		"ports": ports,
		"input": ports[input_index],
		"input_index": input_index,
		"outputs": outputs
	}


static func next_alternating_branch(
	current_branch: int,
	old_rotor: Dictionary,
	new_rotor: Dictionary
) -> int:
	# When a 120-degree rotation finishes, keep the bright arm on
	# the *physically rotated* port instead of snapping to upper/lower.
	var old_outputs: Array = old_rotor.get("outputs", [])
	var old_ports: Array = old_rotor.get("ports", [])
	var new_outputs: Array = new_rotor.get("outputs", [])
	if old_outputs.is_empty() or old_ports.is_empty() or new_outputs.is_empty():
		return current_branch
	var selected: Dictionary = old_outputs[posmod(current_branch, old_outputs.size())]
	var index: int = -1
	for i in range(old_ports.size()):
		if str(old_ports[i]["to"]) == str(selected["to"]):
			index = i
			break
	if index < 0:
		return current_branch
	var target: Dictionary = old_ports[(index + 1) % old_ports.size()]
	for i in range(new_outputs.size()):
		if str(new_outputs[i]["to"]) == str(target["to"]):
			return i
	return current_branch


# Stable bridge identity does not depend on whether a pulse travels forward
# or backward. Builder forbids duplicate edges between the same two nodes.
static func bridge_key(a: String, b: String) -> String:
	if a < b:
		return a + "|" + b
	return b + "|" + a


# A Honeycomb alternator has THREE possible destinations, not two outputs
# and one permanent input. The enabled port advances clockwise per arrival.
static func three_way_ports(
	uid: String,
	records: Array,
	nodes_by_id: Dictionary,
	grid: PuzzleGridBase
) -> Array[Dictionary]:
	var ports: Array[Dictionary] = incident_links(
		uid, records, nodes_by_id, true
	)
	sort_clockwise(ports, grid)
	if ports.size() != 3:
		return []
	return ports
