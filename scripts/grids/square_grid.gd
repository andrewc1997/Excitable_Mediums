@tool
class_name SquarePuzzleGrid
extends PuzzleGridBase

# ============================================================
# EXCITABLE MEDIUMS - EM9 GRID
# Godot 4.3
#
# Square and Horizontal Rhombus.
# Rhombus includes a real left-hand terminal.
# Transparent appearance; no filled background.
# ============================================================

@export_category("Grid Geometry")

@export_enum("Square", "Horizontal Rhombus", "Honeycomb")
var grid_type: int = 0:
	set(value):
		grid_type = clampi(value, 0, 2)
		queue_redraw()

@export_range(20.0, 160.0, 1.0)
var rhombus_half_width: float = 70.0:
	set(value):
		rhombus_half_width = maxf(20.0, value)
		queue_redraw()

@export_range(10.0, 100.0, 1.0)
var rhombus_half_height: float = 26.0:
	set(value):
		rhombus_half_height = maxf(10.0, value)
		queue_redraw()

@export_category("Appearance")

@export var grid_color: Color = Color("#377CAA70")
@export var axis_color: Color = Color("#287CB090")

@export_range(0.5, 4.0, 0.1)
var line_width: float = 1.3:
	set(value):
		line_width = maxf(0.5, value)
		queue_redraw()

const GRID_DOT_RADIUS: float = 2.0

const STEP_COST: int = 10
const TURN_COST: int = 6

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP
]

# ============================================================
# GRID TYPE
# ============================================================

func set_grid_type(value: int) -> void:
	grid_type = value
	queue_redraw()


func is_rhombus() -> bool:
	return grid_type == 1


func is_honeycomb() -> bool:
	return grid_type == 2


# ============================================================
# SPECIAL LEFT TERMINAL
#
# A single extra real cell at (-1, rows - 1).
#
# Its only neighbour is (0, rows - 1).
# The link is horizontal on screen.
# ============================================================

func get_left_terminal() -> Vector2i:
	return Vector2i(-1, grid_rows - 1)


func get_left_anchor() -> Vector2i:
	return Vector2i(0, grid_rows - 1)


func is_left_terminal(cell: Vector2i) -> bool:
	return cell == get_left_terminal()


# ============================================================
# COORDINATE CONVERSION
# ============================================================

func cell_to_local(cell: Vector2i) -> Vector2:

	if is_honeycomb():
		# Two honeycomb vertices per pair: A (even x) and B (odd x).
		# This is a regular flat-top hexagonal lattice, NOT a square overlay.
		var pair_index: int = floori(float(cell.x) / 2.0)
		var vertex_type: int = posmod(cell.x, 2)
		var row_offset: float = 1.5 * float(posmod(cell.y, 2))
		var px: float = (
			3.0 * float(pair_index)
			+ row_offset
			+ float(vertex_type)
		) * cell_size
		var py: float = (
			float(cell.y) * sqrt(3.0) * 0.5 * cell_size
		)
		return Vector2(px, py)

	if not is_rhombus():
		return Vector2(
			float(cell.x) * cell_size,
			float(cell.y) * cell_size
		)

	if is_left_terminal(cell):
		return Vector2(
			-rhombus_half_width * 2.0,
			float(grid_rows - 1) * rhombus_half_height
		)

	var q: float = float(cell.x)
	var r: float = float(cell.y)

	var origin_x: float = (
		float(grid_rows - 1) * rhombus_half_width
	)

	return Vector2(
		origin_x + (q - r) * rhombus_half_width,
		(q + r) * rhombus_half_height
	)


func local_to_cell(point: Vector2) -> Vector2i:

	if is_honeycomb():
		# Brute-force nearest junction: at most 40x40 candidates.
		# Deliberately refuse clicks in the middle of a hexagonal face.
		var best_cell := Vector2i(-1, -1)
		var best_distance_sq: float = INF
		for y in range(grid_rows):
			for x in range(grid_columns):
				var candidate := Vector2i(x, y)
				var distance_sq: float = point.distance_squared_to(
					cell_to_local(candidate)
				)
				if distance_sq < best_distance_sq:
					best_distance_sq = distance_sq
					best_cell = candidate
		var snap_radius: float = cell_size * 0.60
		if best_distance_sq > snap_radius * snap_radius:
			return Vector2i(-1, -1)
		return best_cell

	if not is_rhombus():
		return Vector2i(
			roundi(point.x / maxf(cell_size, 1.0)),
			roundi(point.y / maxf(cell_size, 1.0))
		)

	var origin_x: float = (
		float(grid_rows - 1) * rhombus_half_width
	)

	var horizontal: float = (
		(point.x - origin_x) / rhombus_half_width
	)

	var vertical: float = (
		point.y / rhombus_half_height
	)

	var q: float = (horizontal + vertical) * 0.5
	var r: float = (vertical - horizontal) * 0.5

	var base_q: int = roundi(q)
	var base_r: int = roundi(r)

	var closest := Vector2i(-1, -1)
	var closest_distance: float = INF

	for dq in range(-2, 3):
		for dr in range(-2, 3):

			var candidate := Vector2i(
				base_q + dq,
				base_r + dr
			)

			if not is_valid_cell(candidate):
				continue

			var distance: float = (
				point.distance_squared_to(
					cell_to_local(candidate)
				)
			)

			if distance < closest_distance:
				closest_distance = distance
				closest = candidate

	# Include the extra terminal when choosing
	# the nearest visible grid point.
	var terminal: Vector2i = get_left_terminal()

	var terminal_distance: float = (
		point.distance_squared_to(
			cell_to_local(terminal)
		)
	)

	if terminal_distance < closest_distance:
		return terminal

	return closest


# ============================================================
# GRID VALIDATION
# ============================================================

func is_valid_cell(cell: Vector2i) -> bool:

	if is_rhombus() and is_left_terminal(cell):
		return true

	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_columns
		and cell.y < grid_rows
	)


func get_grid_pixel_size() -> Vector2:

	if is_honeycomb():
		var largest := Vector2.ZERO
		for y in range(grid_rows):
			for x in range(grid_columns):
				var point: Vector2 = cell_to_local(Vector2i(x, y))
				largest.x = maxf(largest.x, point.x)
				largest.y = maxf(largest.y, point.y)
		return largest

	if not is_rhombus():
		return Vector2(
			float(grid_columns - 1) * cell_size,
			float(grid_rows - 1) * cell_size
		)

	var steps: float = (
		float(grid_columns + grid_rows - 2)
	)

	return Vector2(
		(steps + 2.0) * rhombus_half_width,
		steps * rhombus_half_height
	)


func get_grid_center() -> Vector2:

	if is_honeycomb():
		return get_grid_pixel_size() * 0.5

	if not is_rhombus():
		return get_grid_pixel_size() * 0.5

	return Vector2(
		get_grid_pixel_size().x * 0.5
			- rhombus_half_width * 2.0,
		get_grid_pixel_size().y * 0.5
	)


# ============================================================
# NEIGHBOURS
# ============================================================

func get_neighbors(
	cell: Vector2i
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []

	if not is_valid_cell(cell):
		return result

	if is_honeycomb():
		# Every interior junction has exactly three graph neighbours:
		# one horizontal partner and two angled edges (above/below).
		var horizontal_x: int = cell.x + 1 if cell.x % 2 == 0 else cell.x - 1
		var diagonal_x: int = cell.x - 1 if cell.y % 2 == 0 else cell.x + 1
		for candidate in [
			Vector2i(horizontal_x, cell.y),
			Vector2i(diagonal_x, cell.y - 1),
			Vector2i(diagonal_x, cell.y + 1)
		]:
			if is_valid_cell(candidate):
				result.append(candidate)
		return result

	# The terminal has exactly one exit.
	if is_rhombus() and is_left_terminal(cell):
		result.append(get_left_anchor())
		return result

	# The left anchor has an extra horizontal exit.
	if is_rhombus() and cell == get_left_anchor():
		result.append(get_left_terminal())

	for direction in DIRECTIONS:

		var candidate: Vector2i = cell + direction

		if is_valid_cell(candidate):
			if not result.has(candidate):
				result.append(candidate)

	return result


func are_neighbors(
	a: Vector2i,
	b: Vector2i
) -> bool:
	return get_neighbors(a).has(b)


# ============================================================
# DRAW GRID
# ============================================================

func _draw() -> void:

	if is_honeycomb():
		_draw_honeycomb()
	elif is_rhombus():
		_draw_rhombus()
	else:
		_draw_square()


func _draw_square() -> void:

	var width: float = (
		float(grid_columns - 1) * cell_size
	)

	var height: float = (
		float(grid_rows - 1) * cell_size
	)

	for x in range(grid_columns):

		var px: float = float(x) * cell_size

		draw_line(
			Vector2(px, 0.0),
			Vector2(px, height),
			axis_color if x == 0 else grid_color,
			line_width,
			true
		)

	for y in range(grid_rows):

		var py: float = float(y) * cell_size

		draw_line(
			Vector2(0.0, py),
			Vector2(width, py),
			axis_color if y == 0 else grid_color,
			line_width,
			true
		)

	for x in range(grid_columns):
		for y in range(grid_rows):

			draw_circle(
				cell_to_local(Vector2i(x, y)),
				GRID_DOT_RADIUS,
				axis_color
			)


func _draw_rhombus() -> void:

	for q in range(grid_columns):
		for r in range(grid_rows):

			var cell := Vector2i(q, r)
			var start: Vector2 = cell_to_local(cell)

			var down_right := cell + Vector2i(1, 0)

			if is_valid_cell(down_right):
				draw_line(
					start,
					cell_to_local(down_right),
					axis_color if r == 0 else grid_color,
					line_width,
					true
				)

			var down_left := cell + Vector2i(0, 1)

			if is_valid_cell(down_left):
				draw_line(
					start,
					cell_to_local(down_left),
					axis_color if q == 0 else grid_color,
					line_width,
					true
				)

			draw_circle(
				start,
				GRID_DOT_RADIUS,
				axis_color
			)

	# Horizontal extension to the left.
	var terminal: Vector2i = get_left_terminal()
	var anchor: Vector2i = get_left_anchor()

	draw_line(
		cell_to_local(terminal),
		cell_to_local(anchor),
		grid_color,
		line_width,
		true
	)

	draw_circle(
		cell_to_local(terminal),
		GRID_DOT_RADIUS,
		axis_color
	)


# ============================================================
# HONEYCOMB: DRAW ONLY THE ACTUAL GRAPH EDGES
# ============================================================

func _draw_honeycomb() -> void:
	for y in range(grid_rows):
		for x in range(grid_columns):
			var cell := Vector2i(x, y)
			var origin: Vector2 = cell_to_local(cell)
			for neighbor in get_neighbors(cell):
				# Each undirected lattice edge is drawn once.
				if neighbor.y > y or (neighbor.y == y and neighbor.x > x):
					draw_line(
						origin,
						cell_to_local(neighbor),
						grid_color,
						line_width,
						true
					)
			draw_circle(origin, GRID_DOT_RADIUS, axis_color)


# ============================================================
# HONEYCOMB: ONE OF SIX ON-SCREEN DIRECTIONS
# ============================================================

func _honey_direction_index(a: Vector2i, b: Vector2i) -> int:
	var delta: Vector2 = cell_to_local(b) - cell_to_local(a)
	if delta.length_squared() < 0.001:
		return -1
	if absf(delta.y) < 0.001:
		return 0 if delta.x > 0.0 else 3
	if delta.y > 0.0:
		return 1 if delta.x > 0.0 else 2
	return 5 if delta.x > 0.0 else 4


# ============================================================
# CONNECTION VALIDATION
# ============================================================

func can_connect(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> bool:

	return (
		is_valid_cell(from_cell)
		and is_valid_cell(to_cell)
		and from_cell != to_cell
	)


# ============================================================
# ROUTING
#
# Dijkstra routing using real neighbours.
# The terminal is a real node in the search.
# ============================================================

func get_connection_path(
	from_cell: Vector2i,
	to_cell: Vector2i,
	occupied_cells: Dictionary,
	reserved_cells: Dictionary = {}
) -> Array[Vector2i]:

	var empty_path: Array[Vector2i] = []

	if not can_connect(from_cell, to_cell):
		return empty_path

	var start_state := Vector3i(
		from_cell.x,
		from_cell.y,
		-1
	)

	var frontier: Array[Vector3i] = [start_state]
	var costs: Dictionary = {start_state: 0}
	var previous: Dictionary = {}
	var visited: Dictionary = {}

	var goal_state := Vector3i.ZERO
	var found: bool = false

	while not frontier.is_empty():

		var best_index: int = 0
		var best_cost: int = 2147483647

		for index in range(frontier.size()):

			var candidate: Vector3i = frontier[index]
			var cost: int = int(costs[candidate])

			if cost < best_cost:
				best_cost = cost
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

		var neighbours: Array[Vector2i] = (
			get_neighbors(current_cell)
		)

		for next_cell in neighbours:

			if (
				next_cell != from_cell
				and next_cell != to_cell
				and occupied_cells.has(next_cell)
			):
				continue

			if (
				next_cell != from_cell
				and next_cell != to_cell
				and reserved_cells.has(next_cell)
			):
				continue

			var change: Vector2i = (
				next_cell - current_cell
			)

			var direction_index: int = -1
			if is_honeycomb():
				direction_index = _honey_direction_index(current_cell, next_cell)
			else:
				direction_index = DIRECTIONS.find(change)

			if direction_index < 0:
				continue

			var next_state := Vector3i(
				next_cell.x,
				next_cell.y,
				direction_index
			)

			if visited.has(next_state):
				continue

			var extra_cost: int = STEP_COST

			if (
				current.z != -1
				and current.z != direction_index
			):
				extra_cost += TURN_COST

			var new_cost: int = (
				int(costs[current]) + extra_cost
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

	return simplify_path(reversed_cells)


# ============================================================
# PATH HELPERS
# ============================================================

func simplify_path(
	cells: Array[Vector2i]
) -> Array[Vector2i]:

	# Honeycomb paths must keep every real intermediate vertex.
	# Skipping vertices would make path length and routing invalid.
	if is_honeycomb():
		return cells

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


func get_path_cells(
	path: Array[Vector2i]
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []

	if is_honeycomb():
		if path.size() < 2:
			return result
		for i in range(path.size() - 1):
			if not are_neighbors(path[i], path[i + 1]):
				return []
			if i == 0:
				result.append(path[i])
			result.append(path[i + 1])
		return result

	if path.size() < 2:
		return result

	for index in range(path.size() - 1):

		var start_cell: Vector2i = path[index]
		var end_cell: Vector2i = path[index + 1]

		var difference: Vector2i = (
			end_cell - start_cell
		)

		if (
			difference.x != 0
			and difference.y != 0
		):
			return []

		var distance: int = maxi(
			absi(difference.x),
			absi(difference.y)
		)

		if distance == 0:
			return []

		# A segment touching the terminal must
		# be exactly its permitted horizontal edge.
		if (
			is_rhombus()
			and (
				is_left_terminal(start_cell)
				or is_left_terminal(end_cell)
			)
		):
			if not are_neighbors(start_cell, end_cell):
				return []

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


func is_path_clear(
	path: Array[Vector2i],
	occupied_cells: Dictionary,
	reserved_cells: Dictionary = {}
) -> bool:

	if path.size() < 2:
		return false

	var cells: Array[Vector2i] = get_path_cells(path)

	if cells.is_empty():
		return false

	var first_cell: Vector2i = path[0]
	var last_cell: Vector2i = path[path.size() - 1]

	for cell in cells:

		if not is_valid_cell(cell):
			return false

		if cell == first_cell or cell == last_cell:
			continue

		if occupied_cells.has(cell):
			return false

		if reserved_cells.has(cell):
			return false

	return true


# ============================================================
# PORT IDENTIFICATION
# ============================================================

func get_port_direction(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> String:

	var difference: Vector2i = to_cell - from_cell

	if difference == Vector2i.ZERO:
		return ""

	if is_honeycomb():
		var direction: int = _honey_direction_index(from_cell, to_cell)
		match direction:
			0: return "east"
			1: return "south_east"
			2: return "south_west"
			3: return "west"
			4: return "north_west"
			5: return "north_east"
		return ""

	if is_rhombus():

		if (
			is_left_terminal(from_cell)
			or is_left_terminal(to_cell)
		):
			return (
				"east" if difference.x > 0
				else "west"
			)

		if difference.x != 0 and difference.y != 0:
			return ""

		if difference.x > 0:
			return "south_east"

		if difference.x < 0:
			return "north_west"

		if difference.y > 0:
			return "south_west"

		if difference.y < 0:
			return "north_east"

		return ""

	if difference.x > 0:
		return "east"

	if difference.x < 0:
		return "west"

	if difference.y > 0:
		return "south"

	if difference.y < 0:
		return "north"

	return ""


func _process(_delta: float) -> void:

	if Engine.is_editor_hint():
		queue_redraw()
