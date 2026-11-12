
class_name PuzzleGridBase
extends Node2D


# ==================================================
# GRID SETTINGS
# ==================================================

@export var grid_columns: int = 18
@export var grid_rows: int = 12
@export var cell_size: float = 64.0


# ==================================================
# COORDINATE CONVERSION
# ==================================================

func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * cell_size,
		cell.y * cell_size
	)


func local_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(
		roundi(point.x / cell_size),
		roundi(point.y / cell_size)
	)


# ==================================================
# GRID VALIDATION
# ==================================================

func is_valid_cell(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_columns
		and cell.y < grid_rows
	)


# ==================================================
# CONNECTION VALIDATION
# ==================================================

func can_connect(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> bool:
	return false


# ==================================================
# PATH GENERATION
# ==================================================

func get_connection_path(
	from_cell: Vector2i,
	to_cell: Vector2i,
	occupied_cells: Dictionary,
	reserved_cells: Dictionary = {}
) -> Array[Vector2i]:
	return []

# ==================================================
# PORT IDENTIFICATION
# ==================================================

func get_port_direction(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> String:
	return ""
