
@tool
extends Node2D

# ============================================================
# EXCITABLE MEDIUMS
# X-STRETCHED HORIZONTAL RHOMBUS GRID
# Godot 4.3
#
# Standalone geometry and interaction test.
#
# Each visible vertex is a logical grid position.
# The only legal neighbours follow visible edges.
#
# No hidden square-grid routing.
# No automatic signal routing.
# ============================================================

@export_category("Grid Dimensions")

@export_range(2, 30, 1)
var grid_columns: int = 6:
	set(value):
		grid_columns = maxi(2, value)
		queue_redraw()

@export_range(2, 30, 1)
var grid_rows: int = 6:
	set(value):
		grid_rows = maxi(2, value)
		queue_redraw()


# ============================================================
# RHOMBUS PROPORTIONS
# ============================================================

@export_category("Rhombus Shape")

@export_range(20.0, 150.0, 1.0)
var horizontal_half_width: float = 70.0:
	set(value):
		horizontal_half_width = maxf(20.0, value)
		queue_redraw()

@export_range(10.0, 100.0, 1.0)
var vertical_half_height: float = 26.0:
	set(value):
		vertical_half_height = maxf(10.0, value)
		queue_redraw()


# ============================================================
# APPEARANCE
# ============================================================

@export_category("Appearance")

@export var connection_color: Color = Color("#315672")
@export var point_color: Color = Color("#6489a3")
@export var selected_color: Color = Color("#49d9ed")
@export var neighbour_color: Color = Color("#86efac")

@export_range(1.0, 5.0, 0.5)
var line_width: float = 1.5

@export_range(1.0, 10.0, 0.5)
var point_radius: float = 3.0

@export_range(4.0, 20.0, 1.0)
var selection_radius: float = 9.0

@export var show_coordinates: bool = false:
	set(value):
		show_coordinates = value
		queue_redraw()


# ============================================================
# SELECTION
# ============================================================

var selected_cell: Vector2i = Vector2i(-1, -1)
var hovered_cell: Vector2i = Vector2i(-1, -1)

const INVALID_CELL := Vector2i(-1, -1)


# ============================================================
# GRID POSITIONING
#
# q = first lattice coordinate
# r = second lattice coordinate
#
# Increasing q: down-right
# Increasing r: down-left
#
# The shape is controlled directly by its
# visible horizontal and vertical dimensions.
# ============================================================

func grid_origin() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size

	var grid_centre := Vector2(
		viewport_size.x * 0.5,
		viewport_size.y * 0.5
	)

	var q_centre: float = float(grid_columns - 1) * 0.5
	var r_centre: float = float(grid_rows - 1) * 0.5

	var lattice_centre := Vector2(
		(q_centre - r_centre) * horizontal_half_width,
		(q_centre + r_centre) * vertical_half_height
	)

	return grid_centre - lattice_centre

func cell_to_local(cell: Vector2i) -> Vector2:

	var q: float = float(cell.x)
	var r: float = float(cell.y)

	return grid_origin() + Vector2(
		(q - r) * horizontal_half_width,
		(q + r) * vertical_half_height
	)


# ============================================================
# SCREEN POSITION TO GRID CELL
#
# Inverse of the actual rhombus mapping.
#
# No square-grid approximation is involved.
# ============================================================

func local_to_cell(point: Vector2) -> Vector2i:

	var relative: Vector2 = point - grid_origin()

	var horizontal: float = (
		relative.x / horizontal_half_width
	)

	var vertical: float = (
		relative.y / vertical_half_height
	)

	var q: float = (horizontal + vertical) * 0.5
	var r: float = (vertical - horizontal) * 0.5

	# Search the nearest candidate lattice vertices.
	# This also handles the skewed spacing correctly.

	var base_q: int = int(round(q))
	var base_r: int = int(round(r))

	var closest_cell: Vector2i = INVALID_CELL
	var closest_distance: float = INF

	for dq in range(-1, 2):
		for dr in range(-1, 2):

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
				closest_cell = candidate

	return closest_cell


# ============================================================
# VALID POSITIONS
# ============================================================

func is_valid_cell(cell: Vector2i) -> bool:

	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_columns
		and cell.y < grid_rows
	)


# ============================================================
# EXACTLY FOUR LEGAL NEIGHBOURS
#
# These correspond to visible lattice edges.
# ============================================================

func get_neighbors(
	cell: Vector2i
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []

	if not is_valid_cell(cell):
		return result

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(0, -1)
	]

	for direction in directions:

		var candidate: Vector2i = (
			cell + direction
		)

		if is_valid_cell(candidate):
			result.append(candidate)

	return result


# ============================================================
# ADJACENCY CHECK
# ============================================================

func are_neighbors(
	a: Vector2i,
	b: Vector2i
) -> bool:

	if not is_valid_cell(a):
		return false

	if not is_valid_cell(b):
		return false

	return get_neighbors(a).has(b)


# ============================================================
# DIRECTION NAME
#
# Explicit visual direction, not NESW.
# ============================================================

func get_direction_name(
	a: Vector2i,
	b: Vector2i
) -> String:

	if not are_neighbors(a, b):
		return "Invalid"

	var difference: Vector2i = b - a

	match difference:

		Vector2i(1, 0):
			return "Down Right"

		Vector2i(0, 1):
			return "Down Left"

		Vector2i(-1, 0):
			return "Up Left"

		Vector2i(0, -1):
			return "Up Right"

	return "Invalid"


# ============================================================
# DRAW
# ============================================================

func _draw() -> void:

	_draw_grid_edges()
	_draw_grid_vertices()
	_draw_hover()
	_draw_selection()


# ============================================================
# DRAW VISIBLE EDGES
# ============================================================

func _draw_grid_edges() -> void:

	for q in range(grid_columns):
		for r in range(grid_rows):

			var cell := Vector2i(q, r)

			var start: Vector2 = (
				cell_to_local(cell)
			)

			# Increasing q = down-right edge.
			var down_right := cell + Vector2i(1, 0)

			if is_valid_cell(down_right):

				draw_line(
					start,
					cell_to_local(down_right),
					connection_color,
					line_width,
					true
				)

			# Increasing r = down-left edge.
			var down_left := cell + Vector2i(0, 1)

			if is_valid_cell(down_left):

				draw_line(
					start,
					cell_to_local(down_left),
					connection_color,
					line_width,
					true
				)


# ============================================================
# DRAW ALL VALID LATTICE VERTICES
# ============================================================

func _draw_grid_vertices() -> void:

	var font: Font = ThemeDB.fallback_font

	for q in range(grid_columns):
		for r in range(grid_rows):

			var cell := Vector2i(q, r)
			var point: Vector2 = cell_to_local(cell)

			draw_circle(
				point,
				point_radius,
				point_color
			)

			if show_coordinates:

				draw_string(
					font,
					point + Vector2(7.0, -7.0),
					"%d,%d" % [q, r],
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					10,
					point_color
				)


# ============================================================
# HOVER PREVIEW
# ============================================================

func _draw_hover() -> void:

	if not is_valid_cell(hovered_cell):
		return

	var centre: Vector2 = (
		cell_to_local(hovered_cell)
	)

	draw_arc(
		centre,
		selection_radius + 3.0,
		0.0,
		TAU,
		32,
		selected_color.darkened(0.25),
		1.5,
		true
	)


# ============================================================
# SELECTED CELL AND AVAILABLE NEIGHBOURS
# ============================================================

func _draw_selection() -> void:

	if not is_valid_cell(selected_cell):
		return

	var centre: Vector2 = (
		cell_to_local(selected_cell)
	)

	var neighbors: Array[Vector2i] = (
		get_neighbors(selected_cell)
	)

	# Highlight every legal outgoing direction.
	for neighbor in neighbors:

		var endpoint: Vector2 = (
			cell_to_local(neighbor)
		)

		draw_line(
			centre,
			endpoint,
			neighbour_color,
			3.0,
			true
		)

		draw_circle(
			endpoint,
			7.0,
			neighbour_color
		)

	# Selected position.
	draw_circle(
		centre,
		selection_radius,
		selected_color
	)

	draw_arc(
		centre,
		selection_radius + 4.0,
		0.0,
		TAU,
		32,
		Color.WHITE,
		2.0,
		true
	)


# ============================================================
# INPUT
# ============================================================

func _unhandled_input(event: InputEvent) -> void:

	if Engine.is_editor_hint():
		return

	if event is InputEventMouseMotion:

		var candidate: Vector2i = (
			_get_cell_under_mouse()
		)

		if candidate != hovered_cell:

			hovered_cell = candidate
			queue_redraw()

	if event is InputEventMouseButton:

		if (
			event.button_index != MOUSE_BUTTON_LEFT
			or not event.pressed
		):
			return

		selected_cell = _get_cell_under_mouse()

		if is_valid_cell(selected_cell):

			print(
				"Selected rhombus cell: ",
				selected_cell
			)

			for neighbor in get_neighbors(selected_cell):

				print(
					"  ",
					get_direction_name(
						selected_cell,
						neighbor
					),
					" -> ",
					neighbor
				)

		queue_redraw()


# ============================================================
# POINTER PICKING
# ============================================================

func _get_cell_under_mouse() -> Vector2i:

	var position: Vector2 = get_local_mouse_position()

	var candidate: Vector2i = (
		local_to_cell(position)
	)

	if not is_valid_cell(candidate):
		return INVALID_CELL

	var distance: float = (
		position.distance_to(
			cell_to_local(candidate)
		)
	)

	# Reject clicks too far from any visible vertex.
	var picking_radius: float = minf(
		horizontal_half_width * 0.45,
		vertical_half_height * 0.75
	)

	if distance > picking_radius:
		return INVALID_CELL

	return candidate
