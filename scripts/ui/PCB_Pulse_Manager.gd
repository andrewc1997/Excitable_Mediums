
extends Node


# ==================================================
# RANDOM FIRING SETTINGS
# ==================================================

@export_category("Random Firing")

@export var enabled: bool = true

@export var min_delay: float = 1.5
@export var max_delay: float = 4.0

@export_range(1, 20, 1)
var max_simultaneous: int = 2

@export var avoid_repeating: bool = true


# ==================================================
# VARIABLES
# ==================================================

var last_circuit: Node = null


# ==================================================
# READY
# ==================================================

func _ready() -> void:
	_firing_loop()


# ==================================================
# RANDOM FIRING LOOP
# ==================================================

func _firing_loop() -> void:

	while is_inside_tree():

		var delay: float = randf_range(
			minf(min_delay, max_delay),
			maxf(min_delay, max_delay)
		)

		await get_tree().create_timer(
			maxf(delay, 0.05)
		).timeout

		if not is_inside_tree():
			return

		if enabled:
			_fire_random_circuit()


# ==================================================
# SELECT RANDOM CIRCUIT
# ==================================================

func _fire_random_circuit() -> void:

	var available: Array[Node] = []
	var active_count: int = 0

	for circuit in get_parent().get_children():

		if not circuit.has_method("fire_pulse"):
			continue

		if circuit.get("is_active") == true:
			active_count += 1
		else:
			available.append(circuit)

	# Respect simultaneous limit
	if active_count >= max_simultaneous:
		return

	if available.is_empty():
		return

	# Prevent immediate repetition
	if avoid_repeating and available.size() > 1:
		available.erase(last_circuit)

	if available.is_empty():
		return

	var selected: Node = available.pick_random()

	last_circuit = selected

	selected.call("fire_pulse")
