
extends Node2D


# ==================================================
# NODE REFERENCES
# ==================================================

@onready var graph: ExcitableGraph = $Graph

@onready var simulation: ExcitableSimulationManager = (
	$SimulationManager
)

@onready var status_label: Label = (
	$CanvasLayer/UI/StatusLabel
)

@onready var tick_label: Label = (
	$CanvasLayer/UI/TickLabel
)

@onready var reset_button: Button = (
	$CanvasLayer/UI/ResetButton
)

@onready var replay_button: Button = (
	$CanvasLayer/UI/ReplayButton
)


# ==================================================
# READY
# ==================================================

func _ready() -> void:
	# Connect graph interaction.
	graph.node_clicked.connect(
		_on_graph_node_clicked
	)

	# Connect simulation signals.
	simulation.status_changed.connect(
		_on_status_changed
	)

	simulation.tick_changed.connect(
		_on_tick_changed
	)

	simulation.simulation_finished.connect(
		_on_simulation_finished
	)

	# Connect UI buttons.
	reset_button.pressed.connect(
		_on_reset_button_pressed
	)

	replay_button.pressed.connect(
		_on_replay_button_pressed
	)

	# Initialise simulation.
	simulation.setup(graph)


# ==================================================
# GRAPH INPUT
# ==================================================

func _on_graph_node_clicked(node_id: int) -> void:
	if simulation.running:
		return

	simulation.start_from_node(node_id)


# ==================================================
# SIMULATION SIGNALS
# ==================================================

func _on_status_changed(message: String) -> void:
	status_label.text = message


func _on_tick_changed(tick: int) -> void:
	tick_label.text = "Tick: %d" % tick


func _on_simulation_finished(won: bool) -> void:
	if won:
		print("Puzzle completed!")
	else:
		print("Puzzle failed!")


# ==================================================
# BUTTONS
# ==================================================

func _on_reset_button_pressed() -> void:
	simulation.reset_simulation()


func _on_replay_button_pressed() -> void:
	simulation.replay_last()
