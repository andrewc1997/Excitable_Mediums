
class_name BuilderConnections
extends Node2D

# ============================================================
# EXCITABLE MEDIUMS - BUILDER CONNECTIONS
# Godot 4.3
#
# Directed connection paths
# Animated travelling glow
# Smooth procedural corners
# ============================================================

@export_category("Connection Appearance")

@export var line_color: Color = Color("#38bdf8")

@export_range(1.0, 12.0, 0.5)
var line_width: float = 4.0

@export_range(0.0, 0.45, 0.01)
var corner_radius_cells: float = 0.24

@export_category("Travelling Glow")

@export var enable_line_glow: bool = true

@export_range(0.1, 10.0, 0.1)
var glow_speed: float = 1.8

@export_range(0.1, 3.0, 0.1)
var glow_length: float = 0.9

@export_range(0.0, 1.0, 0.05)
var glow_intensity: float = 0.35

@export var glow_color: Color = Color("#d4f7ff")

const SAMPLE_STEP: float = 0.10

var grid: PuzzleGridBase
var connections: Array[Dictionary] = []
var animation_time: float = 0.0


# ============================================================
# SETUP
# ============================================================

func setup(
	puzzle_grid: PuzzleGridBase
) -> void:

	grid = puzzle_grid
	queue_redraw()


func refresh_connections() -> void:
	queue_redraw()


func _process(delta: float) -> void:

	if grid == null:
		return

	if not enable_line_glow:
		return

	if connections.is_empty():
		return

	animation_time += delta
	queue_redraw()


# ============================================================
# DRAW CONNECTIONS
# ============================================================

func _draw() -> void:

	if grid == null:
		return

	for index in range(connections.size()):

		var connection: Dictionary = connections[index]
		var path: Array[Vector2i] = []

		for cell in connection["path"]:
			path.append(cell)

		if path.size() < 2:
			continue

		var length: float = get_path_length(path)

		if length <= 0.0:
			continue

		_draw_connection_line(path, length)

		if enable_line_glow:
			_draw_moving_glow(
				path,
				length,
				index
			)


# ============================================================
# BASE CONNECTION LINE
# ============================================================

func _draw_connection_line(
	path: Array[Vector2i],
	length: float
) -> void:

	var points := PackedVector2Array()

	var samples: int = maxi(
		2,
		int(ceil(length / SAMPLE_STEP)) + 1
	)

	for i in range(samples):

		var distance: float = (
			length * float(i) / float(samples - 1)
		)

		points.append(
			_visual_point_local(path, distance)
		)

	draw_polyline(
		points,
		line_color,
		line_width,
		true
	)


# ============================================================
# MOVING GLOW
# ============================================================

func _draw_moving_glow(
	path: Array[Vector2i],
	length: float,
	connection_index: int
) -> void:

	var head: float = fposmod(
		animation_time * glow_speed
		+ float(connection_index) * 0.67,
		length + glow_length
	)

	var tail: float = head - glow_length

	var start_distance: float = maxf(0.0, tail)
	var end_distance: float = minf(length, head)

	if end_distance <= start_distance:
		return

	var samples: int = maxi(
		2,
		int(ceil(
			(end_distance - start_distance)
			/ SAMPLE_STEP
		)) + 1
	)

	for i in range(samples - 1):

		var d0: float = lerpf(
			start_distance,
			end_distance,
			float(i) / float(samples - 1)
		)

		var d1: float = lerpf(
			start_distance,
			end_distance,
			float(i + 1) / float(samples - 1)
		)

		var middle: float = (d0 + d1) * 0.5

		var along_glow: float = clampf(
			(middle - tail)
			/ maxf(glow_length, 0.001),
			0.0,
			1.0
		)

		var brightness: float = (
			glow_intensity
			* pow(along_glow, 1.5)
		)

		var outer_color: Color = glow_color
		outer_color.a = brightness * 0.4

		var inner_color: Color = glow_color
		inner_color.a = brightness

		var p0: Vector2 = _visual_point_local(
			path, d0
		)

		var p1: Vector2 = _visual_point_local(
			path, d1
		)

		draw_line(
			p0, p1,
			outer_color,
			line_width + 6.0,
			true
		)

		draw_line(
			p0, p1,
			inner_color,
			line_width + 1.5,
			true
		)


# ============================================================
# PATH LENGTH IN GRID CELLS
#
# This remains unchanged by the visual rounding.
# Signal arrival times therefore stay identical.
# ============================================================

func get_path_length(
	path: Array[Vector2i]
) -> float:

	var total: float = 0.0

	for i in range(path.size() - 1):

		var difference: Vector2i = (
			path[i + 1] - path[i]
		)

		total += float(maxi(
			absi(difference.x),
			absi(difference.y)
		))

	return total


# ============================================================
# PUBLIC ROUNDED-PATH SAMPLER
#
# Used by both:
#   BuilderConnections: line and glow
#   TestLevel: moving pulse positions
#
# Input distance is in original grid-cell units.
# Return value is in GRID-LOCAL coordinates.
# ============================================================

func get_visual_point(
	path: Array[Vector2i],
	distance_cells: float
) -> Vector2:

	if grid == null or path.is_empty():
		return Vector2.ZERO

	if path.size() == 1:
		return grid.cell_to_local(path[0])

	var total_length: float = get_path_length(path)

	var distance: float = clampf(
		distance_cells,
		0.0,
		total_length
	)

	# --------------------------------------------
	# CHECK ROUNDED CORNERS
	# --------------------------------------------

	if corner_radius_cells > 0.0:

		var distance_to_corner: float = 0.0

		for i in range(1, path.size() - 1):

			var previous: Vector2 = Vector2(
				path[i] - path[i - 1]
			)

			var following: Vector2 = Vector2(
				path[i + 1] - path[i]
			)

			var previous_length: float = (
				previous.length()
			)

			var following_length: float = (
				following.length()
			)

			distance_to_corner += previous_length

			if (
				previous_length <= 0.0
				or following_length <= 0.0
			):
				continue

			var incoming: Vector2 = (
				previous / previous_length
			)

			var outgoing: Vector2 = (
				following / following_length
			)

			# No rounding on a straight segment
			# or a complete reversal.
			if absf(
				incoming.dot(outgoing)
			) > 0.001:
				continue

			var radius: float = minf(
				corner_radius_cells,
				minf(
					previous_length * 0.45,
					following_length * 0.45
				)
			)

			var corner_start: float = (
				distance_to_corner - radius
			)

			var corner_end: float = (
				distance_to_corner + radius
			)

			if (
				distance < corner_start
				or distance > corner_end
			):
				continue

			var t: float = clampf(
				(distance - corner_start)
				/ (2.0 * radius),
				0.0,
				1.0
			)

			var corner: Vector2 = (
				grid.cell_to_local(path[i])
			)

			var radius_pixels: float = (
				radius * grid.cell_size
			)

			var start_point: Vector2 = (
				corner
				- incoming * radius_pixels
			)

			var end_point: Vector2 = (
				corner
				+ outgoing * radius_pixels
			)

			# Quadratic Bezier with the original
			# sharp corner as the control point.
			var inverse: float = 1.0 - t

			return (
				start_point * inverse * inverse
				+ corner * 2.0 * inverse * t
				+ end_point * t * t
			)

	# --------------------------------------------
	# STRAIGHT PARTS OF PATH
	# --------------------------------------------

	var travelled: float = 0.0

	for i in range(path.size() - 1):

		var start_point: Vector2 = (
			grid.cell_to_local(path[i])
		)

		var end_point: Vector2 = (
			grid.cell_to_local(path[i + 1])
		)

		var difference: Vector2i = (
			path[i + 1] - path[i]
		)

		var length: float = float(maxi(
			absi(difference.x),
			absi(difference.y)
		))

		if length <= 0.0:
			continue

		if distance <= travelled + length:

			var t: float = clampf(
				(distance - travelled) / length,
				0.0,
				1.0
			)

			return start_point.lerp(
				end_point,
				t
			)

		travelled += length

	return grid.cell_to_local(
		path[path.size() - 1]
	)


# ============================================================
# CONVERT VISUAL POINT TO THIS NODE'S SPACE
# ============================================================

func _visual_point_local(
	path: Array[Vector2i],
	distance_cells: float
) -> Vector2:

	return to_local(
		grid.to_global(
			get_visual_point(path, distance_cells)
		)
	)
