
@tool
class_name SquarePuzzleGrid
extends PuzzleGridBase


# ==================================================
# VISUAL SETTINGS
# ==================================================

@export var grid_color: Color = Color("#344456")
@export var axis_color: Color = Color("#60788c")
@export var background_color: Color = Color("#172434")


# ==================================================
# ROUTING SETTINGS
# ==================================================

const STEP_COST: int = 10
const TURN_COST: int = 6

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP
]


# ==================================================
# DRAW GRID
# ==================================================

func _draw() -> void:

	var width: float = (
		float(grid_columns - 1) * cell_size
	)

	var height: float = (
		float(grid_rows - 1) * cell_size
	)

	draw_rect(
		Rect2(
			Vector2.ZERO,
			Vector2(width, height)
		),
		background_color,
		true
	)

	for x in range(grid_columns):

		var line_x: float = x * cell_size

		var color: Color = grid_color

		if x == 0:
			color = axis_color

		draw_line(
			Vector2(line_x, 0),
			Vector2(line_x, height),
			color,
			1.0,
			true
		)

	for y in range(grid_rows):

		var line_y: float = y * cell_size

		var color: Color = grid_color

		if y == 0:
			color = axis_color

		draw_line(
			Vector2(0, line_y),
			Vector2(width, line_y),
			color,
			1.0,
			true
		)


# ==================================================
# CONNECTION VALIDATION
# ==================================================

func can_connect(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> bool:

	return (
		is_valid_cell(from_cell)
		and is_valid_cell(to_cell)
		and from_cell != to_cell
	)


# ==================================================
# AUTOMATIC PATHFINDING
# ==================================================

func get_connection_path(
	from_cell: Vector2i,
	to_cell: Vector2i,
	occupied_cells: Dictionary,
	reserved_cells: Dictionary = {}
) -> Array[Vector2i]:

	var empty_path: Array[Vector2i] = []

	if not can_connect(from_cell, to_cell):
		return empty_path

	# State: Vector3i(x, y, incoming direction).
	# -1 means the starting cell.

	var start_state := Vector3i(
		from_cell.x,
		from_cell.y,
		-1
	)

	var frontier: Array[Vector3i] = [
		start_state
	]

	var costs: Dictionary = {
		start_state: 0
	}

	var previous: Dictionary = {}
	var visited: Dictionary = {}

	var goal_state := Vector3i.ZERO
	var found: bool = false

	# Dijkstra search.
	# Costs favour shorter paths and fewer turns.

	while not frontier.is_empty():

		var best_index: int = 0
		var best_cost: int = 2147483647

		for index in range(frontier.size()):

			var candidate: Vector3i = frontier[index]
			var candidate_cost: int = int(
				costs[candidate]
			)

			if candidate_cost < best_cost:
				best_cost = candidate_cost
				best_index = index

		var current: Vector3i = frontier[best_index]

		frontier.remove_at(best_index)

		if visited.has(current):
			continue

		visited[current] = true

		var current_cell := Vector2i(
			current.x,
			current.y
		)

		if current_cell == to_cell:
			goal_state = current
			found = true
			break

		for direction_index in range(
			DIRECTIONS.size()
		):

			var direction: Vector2i = (
				DIRECTIONS[direction_index]
			)

			var next_cell: Vector2i = (
				current_cell + direction
			)

			if not is_valid_cell(next_cell):
				continue

			# Other placed nodes are obstacles.
			if (
				next_cell != from_cell
				and next_cell != to_cell
				and occupied_cells.has(next_cell)
			):
				continue

			# Other connections are obstacles.
			if (
				next_cell != from_cell
				and next_cell != to_cell
				and reserved_cells.has(next_cell)
			):
				continue

			var next_state := Vector3i(
				next_cell.x,
				next_cell.y,
				direction_index
			)

			if visited.has(next_state):
				continue

			var additional_cost: int = STEP_COST

			if (
				current.z != -1
				and current.z != direction_index
			):
				additional_cost += TURN_COST

			var new_cost: int = (
				int(costs[current])
				+ additional_cost
			)

			if (
				costs.has(next_state)
				and new_cost >= int(costs[next_state])
			):
				continue

			costs[next_state] = new_cost
			previous[next_state] = current

			if not frontier.has(next_state):
				frontier.append(next_state)

	if not found:
		return empty_path

	# ==================================================
	# RECONSTRUCT COMPLETE CELL PATH
	# ==================================================

	var reversed_cells: Array[Vector2i] = []

	var state: Vector3i = goal_state

	while true:

		reversed_cells.append(
			Vector2i(state.x, state.y)
		)

		if state == start_state:
			break

		if not previous.has(state):
			return empty_path

		state = previous[state]

	reversed_cells.reverse()

	# ==================================================
	# REDUCE TO CORNERS
	# ==================================================

	return simplify_path(reversed_cells)


# ==================================================
# REMOVE UNNECESSARY WAYPOINTS
# ==================================================

func simplify_path(
	cells: Array[Vector2i]
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []

	if cells.size() < 2:
		return result

	result.append(cells[0])

	var previous_direction: Vector2i = (
		cells[1] - cells[0]
	)

	for index in range(1, cells.size() - 1):

		var next_direction: Vector2i = (
			cells[index + 1] - cells[index]
		)

		if next_direction != previous_direction:

			result.append(cells[index])
			previous_direction = next_direction

	result.append(cells[cells.size() - 1])

	return result


# ==================================================
# PATH VALIDATION
# ==================================================

func is_path_clear(
	path: Array[Vector2i],
	occupied_cells: Dictionary,
	reserved_cells: Dictionary = {}
) -> bool:

	if path.size() < 2:
		return false

	var first_cell: Vector2i = path[0]
	var last_cell: Vector2i = path[path.size() - 1]

	for segment_index in range(path.size() - 1):

		var start_cell: Vector2i = path[segment_index]
		var end_cell: Vector2i = path[segment_index + 1]

		if not is_valid_cell(start_cell):
			return false

		if not is_valid_cell(end_cell):
			return false

		var difference: Vector2i = (
			end_cell - start_cell
		)

		if (
			difference.x != 0
			and difference.y != 0
		):
			return false

		var distance: int = maxi(
			absi(difference.x),
			absi(difference.y)
		)

		if distance == 0:
			return false

		var direction := Vector2i(
			signi(difference.x),
			signi(difference.y)
		)

		for step in range(distance + 1):

			var cell: Vector2i = (
				start_cell + direction * step
			)

			if not is_valid_cell(cell):
				return false

			if cell == first_cell or cell == last_cell:
				continue

			if occupied_cells.has(cell):
				return false

			if reserved_cells.has(cell):
				return false

	return true


# ==================================================
# EXPAND A PATH INTO INDIVIDUAL CELLS
# ==================================================

func get_path_cells(
	path: Array[Vector2i]
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []

	if path.size() < 2:
		return result

	for index in range(path.size() - 1):

		var start_cell: Vector2i = path[index]
		var end_cell: Vector2i = path[index + 1]

		var difference: Vector2i = (
			end_cell - start_cell
		)

		var distance: int = maxi(
			absi(difference.x),
			absi(difference.y)
		)

		if distance == 0:
			continue

		var direction := Vector2i(
			signi(difference.x),
			signi(difference.y)
		)

		for step in range(distance + 1):

			var cell: Vector2i = (
				start_cell + direction * step
			)

			if not result.has(cell):
				result.append(cell)

	return result


# ==================================================
# PORT DIRECTION
# ==================================================

func get_port_direction(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> String:

	if from_cell == to_cell:
		return ""

	if to_cell.x > from_cell.x:
		return "east"

	if to_cell.x < from_cell.x:
		return "west"

	if to_cell.y > from_cell.y:
		return "south"

	if to_cell.y < from_cell.y:
		return "north"

	return ""


# ==================================================
# EDITOR REDRAW
# ==================================================

func _process(_delta: float) -> void:

	if Engine.is_editor_hint():
		queue_redraw()
