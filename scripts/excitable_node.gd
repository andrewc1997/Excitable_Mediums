
class_name ExcitableNodeData
extends RefCounted


# ==================================================
# NODE TYPES
# ==================================================

enum NodeType {
	NORMAL,
	SPLITTER,
	ALTERNATING,
	STRAIGHT_THROUGH,
	FIXED_SWITCH
}


# ==================================================
# NODE PROPERTIES
# ==================================================

var node_id: int
var position: Vector2

var node_type: NodeType = NodeType.NORMAL
var is_target: bool = false

var activation_cap: int = 1
var activation_count: int = 0

var last_activation_tick: int = -1000000

# Alternating node memory.
var route_cursor: int = 0

# Splitter settings.
var required_inputs: int = 1
var output_count: int = 2

# Failure state.
var is_broken: bool = false


# ==================================================
# INITIALISATION
# ==================================================

func _init(
	p_id: int,
	p_position: Vector2,
	p_target: bool = false,
	p_cap: int = 1,
	p_type: NodeType = NodeType.NORMAL,
	p_required_inputs: int = 1,
	p_output_count: int = 2
) -> void:

	node_id = p_id
	position = p_position

	is_target = p_target
	activation_cap = maxi(1, p_cap)

	node_type = p_type

	required_inputs = maxi(1, p_required_inputs)
	output_count = maxi(1, p_output_count)


# ==================================================
# RESET
# ==================================================

func reset() -> void:

	activation_count = 0
	last_activation_tick = -1000000

	route_cursor = 0
	is_broken = false


# ==================================================
# ACTIVATION
# ==================================================

func can_activate(
	current_tick: int,
	refractory_ticks: int
) -> bool:

	if is_broken:
		return false

	if activation_count >= activation_cap:
		return false

	if activation_count > 0:

		var ticks_since: int = (
			current_tick - last_activation_tick
		)

		if ticks_since <= refractory_ticks:
			return false

	return true


func try_activate(
	current_tick: int,
	refractory_ticks: int
) -> bool:

	if not can_activate(
		current_tick,
		refractory_ticks
	):
		return false

	activation_count += 1
	last_activation_tick = current_tick

	return true


# ==================================================
# SPLITTER INPUT VALIDATION
# ==================================================

func accepts_input_count(count: int) -> bool:

	if node_type != NodeType.SPLITTER:
		return true

	return count == required_inputs


func break_node() -> void:
	is_broken = true


# ==================================================
# TARGET
# ==================================================

func has_reached_target() -> bool:
	return is_target and activation_count > 0


# ==================================================
# ROUTING
# ==================================================

func get_outgoing_neighbors(
	neighbors: Array[int],
	incoming_sources: Dictionary
) -> Array[int]:

	var outgoing: Array[int] = []

	if is_target or is_broken:
		return outgoing

	if neighbors.is_empty():
		return outgoing

	match node_type:

		# ==========================================
		# NORMAL
		# ==========================================

		NodeType.NORMAL:

			for neighbor_id in neighbors:

				if incoming_sources.has(neighbor_id):
					continue

				outgoing.append(neighbor_id)
				break


		# ==========================================
		# SPLITTER
		# ==========================================

		NodeType.SPLITTER:

			for neighbor_id in neighbors:

				if incoming_sources.has(neighbor_id):
					continue

				outgoing.append(neighbor_id)

				if outgoing.size() >= output_count:
					break


		# ==========================================
		# ALTERNATING
		# ==========================================

		NodeType.ALTERNATING:

			var count: int = neighbors.size()

			for offset in range(count):

				var index: int = (
					route_cursor + offset
				) % count

				var neighbor_id: int = neighbors[index]

				if incoming_sources.has(neighbor_id):
					continue

				outgoing.append(neighbor_id)

				route_cursor = (
					index + 1
				) % count

				break


		# ==========================================
		# FUTURE TYPES
		# ==========================================

		NodeType.STRAIGHT_THROUGH:
			pass

		NodeType.FIXED_SWITCH:
			pass

	return outgoing
