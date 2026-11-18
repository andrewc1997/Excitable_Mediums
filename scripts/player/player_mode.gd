extends Node2D

const PortRules = preload("res://scripts/puzzle_node/puzzle_port_rules.gd")
const CampaignManagerScript = preload("res://scripts/player/campaign_manager.gd")

# ============================================================
# EXCITABLE MEDIUMS - CLEAN STANDALONE PLAYER MODE
# Godot 4.3
#
# Scene hierarchy (create manually):
#   PlayerMode (Node2D, this script)
#
# The working Builder scene is instanced internally to reuse its
# level importer, grid, connections, nodes and pulse simulation.
# All editor UI and the playtest toolbar remain hidden.
# There is deliberately NO in-game top bar.
#
# Controls:
#   Click an editable Alternating node: flip its first route before launch
#   Click an editable Splitter: rotate its two output ports clockwise
#   Click a Begin node: launch from that start
#   Space / Escape: pause or resume
#   R: retry the same start
#   Backspace: choose a different Begin node
#
# Future Blender companion can use another CanvasLayer.
# ============================================================

@export_category("Level Setup")
@export_file("*.tscn") var builder_scene_path: String = "res://scenes/builder/builder.tscn"
@export_file("*.json") var level_file_path: String = "res://levels/level_001.json"
# Kept to preserve older PlayerMode scene Inspector data. Campaign order
# now comes from res://levels/campaign_manifest.json, NOT this property.
@export_file("*.json") var next_level_path: String = "res://levels/level_002_loop.json"
@export var resume_campaign_on_start: bool = true
@export var developer_allow_locked_levels: bool = false

@export_category("Screen Framing")
@export_range(0.0, 200.0, 1.0) var screen_margin: float = 44.0
@export_range(0.0, 250.0, 1.0) var world_padding: float = 50.0
@export_range(0.1, 5.0, 0.05) var maximum_zoom: float = 2.5

@export_category("Player Node Appearance")
# Independent of camera zoom, connection routing and node animations.
@export_range(0.35, 1.0, 0.01) var player_node_scale: float = 0.62

@export_category("Alternating Switch Animation")
@export_range(1.05, 1.80, 0.01) var switch_pickup_scale: float = 1.30
@export_range(0.0, 25.0, 0.5) var switch_pickup_height: float = 9.0
@export_range(0.05, 0.50, 0.01) var switch_pickup_seconds: float = 0.15
@export_range(0.10, 1.00, 0.01) var switch_rotation_seconds: float = 0.38
@export_range(0.05, 0.50, 0.01) var switch_putdown_seconds: float = 0.22

@export_category("Interactive Node Hover")
# Player Mode only. Ordinary/non-interactive nodes remain stationary.
@export_range(0.0, 15.0, 0.5) var node_hover_lift: float = 5.0
@export_range(1.0, 1.20, 0.01) var node_hover_scale: float = 1.07
@export_range(0.0, 3.0, 0.1) var node_hover_bob: float = 0.8
@export_range(0.5, 8.0, 0.1) var node_hover_bob_speed: float = 2.8
@export_range(2.0, 30.0, 1.0) var node_hover_smoothness: float = 12.0

@export_category("Level Transitions")
@export var auto_advance_on_success: bool = true
@export_range(0.0, 5.0, 0.1) var completion_hold_seconds: float = 1.3
@export_range(0.1, 4.0, 0.1) var puzzle_fade_out_seconds: float = 1.8
@export_range(0.1, 4.0, 0.1) var puzzle_fade_in_seconds: float = 1.8

var campaign_manager: Node
var builder: Node2D
var test_level: Node2D
var level_tools: Node
var puzzle_grid: PuzzleGridBase

var ready_to_play: bool = false
var result_was_shown: bool = false
var transitioning: bool = false

# One player-operated switch may animate at a time. Keep the actual
# first-branch setting unchanged until the node lands.
var switch_turning: bool = false
var switch_tween: Tween
var switch_node: PuzzleNode
var switch_holder: Node2D
var switch_holder_base_scale: Vector2 = Vector2.ONE
var switch_holder_base_position: Vector2 = Vector2.ZERO
var switch_holder_base_rotation: float = 0.0
var node_hover_clock: float = 0.0

var pause_layer: CanvasLayer
var result_layer: CanvasLayer
var result_heading: Label
var result_description: Label
var result_next_button: Button
var result_retry_button: Button
var result_reset_button: Button

# Draggable bridge blockers: an unobtrusive bottom-left inventory.
var blocker_layer: CanvasLayer
var blocker_tray: PanelContainer
var blocker_token: Button
var blocker_ghost: Label
var blocker_total: int = 0
var blocker_remaining: int = 0
var blocker_dragging: bool = false
var blocker_feedback: Label
var blocker_notice_layer: CanvasLayer
var blocker_notice: Label
var blocker_notice_tween: Tween
var blocker_return_tween: Tween

# Campaign menu is deliberately modal: no permanent top bar.
var level_select_layer: CanvasLayer
var level_select_root: Control
var level_select_list: VBoxContainer
var level_select_summary: Label
var level_select_paused_by_menu: bool = false


# ============================================================
# STARTUP
# ============================================================

func _ready() -> void:
	# Own the campaign state centrally without changing the scene tree
	# manually. If an Autoload already exists, reuse it.
	campaign_manager = get_node_or_null("/root/CampaignManager")
	if campaign_manager == null:
		campaign_manager = CampaignManagerScript.new()
		campaign_manager.name = "CampaignManager"
		get_tree().root.add_child(campaign_manager)
	# The menu and next-level lookup must never receive an empty manager
	# simply because the manifest was loaded too early.
	campaign_manager.call("ensure_ready")
	_create_pause_overlay()
	_create_result_overlay()
	_create_bridge_blocker_inventory()
	_create_level_select_overlay()
	get_viewport().size_changed.connect(_request_level_fit)
	call_deferred("_boot")


func _boot() -> void:
	if not ResourceLoader.exists(builder_scene_path):
		_show_setup_error("Builder scene not found:\n" + builder_scene_path)
		return

	var scene: PackedScene = load(builder_scene_path) as PackedScene
	if scene == null:
		_show_setup_error("Could not open Builder scene:\n" + builder_scene_path)
		return

	builder = scene.instantiate() as Node2D
	if builder == null:
		_show_setup_error("The Builder scene needs a Node2D root.")
		return

	builder.hide()
	add_child(builder)

	# The existing Builder UI, LevelTools and TestLevel initialise
	# with call_deferred(), so let them finish before importing data.
	var systems_ready: bool = false
	for _attempt in range(30):
		await get_tree().process_frame
		if not is_instance_valid(builder):
			return

		level_tools = builder.get_node_or_null("LevelTools")
		test_level = builder.get_node_or_null("TestLevel") as Node2D
		puzzle_grid = builder.get_node_or_null("Grid") as PuzzleGridBase
		if level_tools == null or test_level == null or puzzle_grid == null:
			continue
		if level_tools.get("overlay") != null and test_level.get("test_bar") != null:
			systems_ready = true
			break

	if not systems_ready:
		_show_setup_error("Builder LevelTools or TestLevel failed to initialise.")
		return

	_load_level(_resolve_startup_level_path())


func _resolve_startup_level_path() -> String:
	var requested: String = level_file_path.strip_edges()
	if campaign_manager == null:
		return requested
	var levels: Array = campaign_manager.call("get_all_levels")
	if levels.is_empty():
		return requested
	var first_path: String = str(levels[0].get("path", ""))
	var resume: String = str(campaign_manager.call("get_resume_path"))
	if requested.is_empty():
		return resume
	# Developer sandboxes (e.g. Wormhole tests) remain independent of
	# unlocks and never get redirected into the campaign.
	if not bool(campaign_manager.call("is_campaign_path", requested)):
		return requested
	if resume_campaign_on_start and requested == first_path:
		return resume
	# A different path explicitly selected in the Inspector is a
	# developer test override. Do not break existing Level 003 testing.
	return requested


func _process(_delta: float) -> void:
	if not ready_to_play or not is_instance_valid(test_level) or transitioning:
		return

	if level_select_layer != null and level_select_layer.visible:
		pause_layer.hide()
		blocker_layer.hide()
		return

	_update_interactable_node_hover(_delta)

	var finished: bool = bool(test_level.get("finished"))
	var running: bool = bool(test_level.get("running"))
	var paused: bool = bool(test_level.get("paused"))

	if blocker_layer != null:
		blocker_layer.visible = (blocker_remaining > 0 and
			_has_player_blocker_slots() and not finished and
			not pause_layer.visible and not result_layer.visible)
	if finished:
		pause_layer.hide()
		if not result_was_shown:
			_show_final_result()
	else:
		# Unlike the old HUD, this appears only when actually paused.
		if running and paused:
			pause_layer.show()
		else:
			pause_layer.hide()


# ============================================================
# LOAD A LEVEL INTO THE SAME PUZZLE ENGINE
# ============================================================

func _load_level(path: String, preserve_background: bool = false) -> bool:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty():
		_show_setup_error("No level file was specified.")
		return false

	if not FileAccess.file_exists(clean_path):
		_show_setup_error(
			"Level file not found:\n" + clean_path
			+ "\n\nCopy the JSON level into your project's levels folder."
		)
		return false

	var file: FileAccess = FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		_show_setup_error("Cannot read level file:\n" + clean_path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_show_setup_error("Invalid JSON level:\n" + clean_path)
		return false

	var data: Dictionary = parsed
	var validation_error: String = level_tools.validate_level(data)
	if not validation_error.is_empty():
		_show_setup_error(
			"Level validation failed for " + clean_path + ":\n" + validation_error
		)
		return false

	_cancel_player_switch_animation()
	blocker_dragging = false
	if blocker_return_tween != null:
		blocker_return_tween.kill()
		blocker_return_tween = null
	if blocker_ghost != null:
		blocker_ghost.hide()
	if builder != null and builder.connection_layer.has_method("set_player_drag_active"):
		builder.connection_layer.set_player_drag_active(false)
	ready_to_play = false
	result_was_shown = false
	pause_layer.hide()
	result_layer.hide()
	if blocker_notice != null:
		blocker_notice.hide()
	if not preserve_background:
		builder.hide()

	if bool(test_level.get("test_mode")):
		test_level.exit_test_mode()

	level_tools.apply_level_data(data)
	blocker_total = int(data.get("player_blocker_count", 0))
	blocker_remaining = blocker_total
	blocker_dragging = false
	blocker_ghost.hide()
	if blocker_feedback != null:
		blocker_feedback.text = str(data.get("player_hint", "Drag a blocker onto an open bridge socket."))
	_apply_player_node_scale()
	test_level.enter_test_mode()

	if not bool(test_level.get("test_mode")):
		_show_setup_error("The puzzle simulation did not enter test mode.")
		return false

	# PlayerMode handles clicks; leave the existing pulse engine active.
	# Large state/refractory rings are hidden in Player Mode.
	test_level.set_process_input(false)
	test_level.set("show_node_state_rings", false)
	test_level.queue_redraw()

	var editor_test_bar: Control = test_level.get("test_bar") as Control
	if editor_test_bar != null:
		editor_test_bar.hide()

	level_file_path = clean_path
	builder.show()
	ready_to_play = true
	_update_bridge_blocker_inventory()
	call_deferred("_fit_level_to_screen")
	print("PlayerMode: loaded ", clean_path)
	return true


func _level_name(path: String) -> String:
	if campaign_manager != null:
		var entry: Dictionary = campaign_manager.call("get_entry_by_path", path)
		if not entry.is_empty():
			return "%s - %s" % [
				str(entry["id"]).replace("_", " ").to_upper(),
				str(entry["title"])
			]
	return path.get_file().get_basename().replace("_", " ").capitalize()


# ============================================================
# LEVEL PROGRESSION - MANIFEST DRIVEN, NO HARDCODED PATHS
# ============================================================

func _get_next_level_path() -> String:
	if campaign_manager == null:
		return ""
	return str(campaign_manager.call("get_next_level_path", level_file_path))


func _next_level() -> void:
	if transitioning:
		return
	var next_path: String = _get_next_level_path()
	if next_path.is_empty():
		result_description.text += "\n\nNo next level has been configured."
		return
	if not FileAccess.file_exists(next_path):
		result_description.text = "Next level is missing:\n" + next_path
		return
	# The result dialog disappears before fading the puzzle itself.
	result_layer.hide()
	transitioning = true
	call_deferred("_run_level_transition", next_path, false)


# ============================================================
# SHRINK NODES WITHOUT TOUCHING THEIR INTERNAL ANIMATIONS
# ============================================================

func _apply_player_node_scale() -> void:
	# The PuzzleNode script drives its own scale when nodes pop or
	# reset, so setting node.scale would be overwritten. Instead,
	# put each node at (0, 0) inside a scaled parent at the old
	# position. The child's animations remain fully functional.
	var container: Node2D = builder.get_node_or_null("PlacedNodes") as Node2D
	if container == null:
		return

	var factor: float = clampf(player_node_scale, 0.35, 1.0)
	for value in builder.nodes_by_id.values():
		var node: PuzzleNode = value as PuzzleNode
		if not is_instance_valid(node):
			continue
		var old_position: Vector2 = node.position
		var wrapper := Node2D.new()
		wrapper.name = "PlayerVisualScale"
		wrapper.set_meta("em_player_visual_wrapper", true)
		container.add_child(wrapper)
		wrapper.position = old_position
		wrapper.scale = Vector2.ONE * factor
		node.reparent(wrapper, false)
		node.position = Vector2.ZERO
		node.scale = Vector2.ONE


# ============================================================
# INTERACTABLE NODE HOVER - PLAYER MODE ONLY
# Uses the existing PlayerVisualScale holder for a little extra size,
# and the PuzzleNode's position for a slight lift. The PuzzleNode
# itself still owns its activation pop/rotation animations.
# ============================================================

func _can_player_interact_with_node(node: PuzzleNode) -> bool:
	if not is_instance_valid(node):
		return false
	if node.kind == PuzzleNode.Kind.BEGIN:
		return true
	if not node.player_editable:
		return false
	if node.kind == PuzzleNode.Kind.ALTERNATING:
		return true
	if node.kind == PuzzleNode.Kind.SPLITTER:
		if not bool(test_level.get("allow_reverse_connections")):
			return false
		var rotor: Dictionary = PortRules.get_rotor(
			node.node_uid, builder.connection_layer.connections,
			builder.nodes_by_id, puzzle_grid,
			int(node.port_rotation_steps), true
		)
		return bool(rotor.get("valid", false))
	return false


func _hovered_interactable_uid(screen_point: Vector2) -> String:
	if not ready_to_play or not is_instance_valid(builder):
		return ""
	if not is_instance_valid(test_level):
		return ""
	if transitioning or switch_turning or blocker_dragging:
		return ""
	if result_layer.visible or pause_layer.visible:
		return ""
	if bool(test_level.get("finished")):
		return ""
	if not str(test_level.get("selected_start_id")).is_empty():
		return ""

	var camera: Camera2D = builder.get_node_or_null("Camera2D") as Camera2D
	var camera_zoom: float = camera.zoom.x if camera != null else 1.0
	var hit_radius: float = maxf(22.0, 23.0 * camera_zoom * player_node_scale)
	var best_uid: String = ""
	var best_distance: float = INF

	for key in builder.nodes_by_id.keys():
		var node: PuzzleNode = builder.nodes_by_id[key] as PuzzleNode
		if not is_instance_valid(node):
			continue
		# Test the unshifted wrapper centre so a bobbing node doesn't
		# flicker in/out of hover at the edge of the hit area.
		var holder: Node2D = node.get_parent() as Node2D
		var visual_center: Vector2 = node.get_global_transform_with_canvas().origin
		if holder != null and holder.has_meta("em_player_visual_wrapper"):
			visual_center = holder.get_global_transform_with_canvas().origin
		var distance: float = screen_point.distance_to(visual_center)
		if distance > hit_radius or distance >= best_distance:
			continue
		if not _can_player_interact_with_node(node):
			continue
		best_uid = str(key)
		best_distance = distance

	return best_uid


func _update_interactable_node_hover(delta: float) -> void:
	node_hover_clock += delta
	var hovered_uid: String = _hovered_interactable_uid(
		get_viewport().get_mouse_position()
	)
	var speed: float = maxf(0.1, node_hover_smoothness)
	var blend: float = 1.0 - exp(-speed * delta)
	var base_scale: Vector2 = Vector2.ONE * clampf(player_node_scale, 0.35, 1.0)

	for key in builder.nodes_by_id.keys():
		var node: PuzzleNode = builder.nodes_by_id[key] as PuzzleNode
		if not is_instance_valid(node):
			continue
		var holder: Node2D = node.get_parent() as Node2D
		if holder == null or not holder.has_meta("em_player_visual_wrapper"):
			continue
		# The click-to-rotate Tween owns this holder until it settles.
		if switch_turning and node == switch_node:
			continue

		var hovered: bool = str(key) == hovered_uid
		var desired_scale: Vector2 = base_scale
		var desired_y: float = 0.0
		if hovered:
			desired_scale *= node_hover_scale
			desired_y = -node_hover_lift + sin(
				node_hover_clock * node_hover_bob_speed
			) * node_hover_bob

		holder.scale = holder.scale.lerp(desired_scale, blend)
		node.position.y = lerpf(node.position.y, desired_y, blend)


# ============================================================
# FADE ONLY THE PUZZLE; LEAVE THE BACKGROUND VISIBLE
# ============================================================

func _set_node_opacity(opacity: float) -> void:
	# The node layer and animated pulse effects disappear together.
	# The background grid/background layer are deliberately untouched.
	if not is_instance_valid(builder):
		return
	var alpha: float = clampf(opacity, 0.0, 1.0)
	for path in ["PlacedNodes", "TestLevel"]:
		var item: CanvasItem = builder.get_node_or_null(path) as CanvasItem
		if item == null:
			continue
		var tint: Color = item.modulate
		tint.a = alpha
		item.modulate = tint


func _set_bridge_opacity(opacity: float) -> void:
	# Only authored connections fade; not the decorative background.
	if not is_instance_valid(builder):
		return
	var item: CanvasItem = builder.get_node_or_null("Connections") as CanvasItem
	if item == null:
		return
	var tint: Color = item.modulate
	tint.a = clampf(opacity, 0.0, 1.0)
	item.modulate = tint


func _run_level_transition(path: String, wait_for_completion: bool) -> void:
	# OUT: actual bridges -> nodes + pulse effects.
	blocker_layer.hide()
	# IN:  nodes + pulse effects -> actual bridges.
	# Background is never faded or replaced.
	if wait_for_completion and completion_hold_seconds > 0.0:
		await get_tree().create_timer(completion_hold_seconds).timeout
	if not is_inside_tree():
		return

	var node_out_seconds: float = maxf(0.05, puzzle_fade_out_seconds * 0.55)
	var bridge_out_seconds: float = maxf(0.05, puzzle_fade_out_seconds * 0.45)
	var bridge_in_seconds: float = maxf(0.05, puzzle_fade_in_seconds * 0.45)
	var node_in_seconds: float = maxf(0.05, puzzle_fade_in_seconds * 0.55)

	var fade_out: Tween = create_tween()
	fade_out.tween_method(
		Callable(self, "_set_bridge_opacity"),
		1.0, 0.0, bridge_out_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_out.tween_method(
		Callable(self, "_set_node_opacity"),
		1.0, 0.0, node_out_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished
	if not is_inside_tree():
		return

	_set_node_opacity(0.0)
	_set_bridge_opacity(0.0)
	if not _load_level(path, true):
		_set_bridge_opacity(1.0)
		_set_node_opacity(1.0)
		transitioning = false
		return

	# LevelTools can defer its editor camera fit. Apply our own
	# once the new puzzle has been instanced, while still invisible.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_fit_level_to_screen()
	# CampaignManager owns progression. No per-level Inspector edits.

	# Explicitly reset transparency on the new nodes and bridges
	# before starting the two sequential fade-in stages.
	_set_node_opacity(0.0)
	_set_bridge_opacity(0.0)
	var fade_in: Tween = create_tween()
	fade_in.tween_method(
		Callable(self, "_set_node_opacity"),
		0.0, 1.0, node_in_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_in.tween_method(
		Callable(self, "_set_bridge_opacity"),
		0.0, 1.0, bridge_in_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	if not is_inside_tree():
		return
	_set_bridge_opacity(1.0)
	_set_node_opacity(1.0)
	transitioning = false
	_update_bridge_blocker_inventory()


# ============================================================
# FIT THE ACTUAL NETWORK TO THE ENTIRE WINDOW
# ============================================================

func _request_level_fit() -> void:
	# Keep the modal UI sized to the game window when resizing.
	if is_instance_valid(level_select_root):
		level_select_root.size = get_viewport_rect().size
	if ready_to_play:
		# LevelTools may also fit the editor camera on resize.
		# Run ours deferred so the player-specific fit wins.
		call_deferred("_fit_level_to_screen")


func _fit_level_to_screen() -> void:
	if not ready_to_play or not is_instance_valid(builder):
		return
	if not is_instance_valid(puzzle_grid):
		return

	var camera: Camera2D = builder.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	# Only used nodes and paths are included in the bounds.
	# Empty honeycomb edges are not included.
	var points: Array[Vector2] = []
	for value in builder.nodes_by_id.values():
		var node: PuzzleNode = value as PuzzleNode
		if is_instance_valid(node):
			points.append(node.global_position)

	for connection in builder.connection_layer.connections:
		for cell in connection.get("path", []):
			var lattice_cell: Vector2i = cell
			points.append(
				puzzle_grid.to_global(puzzle_grid.cell_to_local(lattice_cell))
			)

	if points.is_empty():
		return

	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)

	var board_center: Vector2 = (minimum + maximum) * 0.5
	var padded_size: Vector2 = maximum - minimum
	padded_size += Vector2.ONE * world_padding * 2.0

	# No top bar, so all four screen margins can be equal.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var usable_size: Vector2 = viewport_size - Vector2.ONE * screen_margin * 2.0
	if usable_size.x <= 80.0 or usable_size.y <= 80.0:
		return

	var desired_zoom: float = minf(
		usable_size.x / maxf(padded_size.x, 1.0),
		usable_size.y / maxf(padded_size.y, 1.0)
	)
	var zoom_value: float = clampf(desired_zoom, 0.01, maximum_zoom)

	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * zoom_value
	camera.global_position = board_center
	camera.make_current()
	camera.reset_smoothing()


# ============================================================
# PLAYER-BLOCKER DRAG-AND-DROP INVENTORY (NO SCENE CHANGES)
# ============================================================

func _create_bridge_blocker_inventory() -> void:
	blocker_layer = CanvasLayer.new()
	blocker_layer.name = "BridgeBlockerInventory"
	blocker_layer.layer = 90
	add_child(blocker_layer)

	blocker_tray = PanelContainer.new()
	blocker_tray.name = "BlockerTray"
	blocker_layer.add_child(blocker_tray)
	blocker_tray.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	blocker_tray.offset_left = 20.0
	blocker_tray.offset_right = 190.0
	blocker_tray.offset_top = -67.0
	blocker_tray.offset_bottom = -16.0

	var row := HBoxContainer.new()
	blocker_tray.add_child(row)
	blocker_token = Button.new()
	blocker_token.name = "DragBlocker"
	blocker_token.text = "✕  Drag blocker ×0"
	blocker_token.tooltip_text = "Drag onto a hollow bridge slot to block future crossings"
	blocker_token.custom_minimum_size = Vector2(165.0, 37.0)
	row.add_child(blocker_token)

	blocker_ghost = Label.new()
	blocker_ghost.name = "BlockerDragGhost"
	blocker_ghost.text = "✕"
	blocker_ghost.add_theme_font_size_override("font_size", 26)
	blocker_ghost.add_theme_color_override("font_color", Color("#FF9A76"))
	blocker_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker_layer.add_child(blocker_ghost)
	blocker_ghost.hide()

	# Short contextual guidance only in levels with blocker tokens.
	blocker_feedback = Label.new()
	blocker_feedback.name = "BlockerInstruction"
	blocker_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blocker_feedback.add_theme_color_override("font_color", Color("#34576B"))
	blocker_feedback.add_theme_font_size_override("font_size", 13)
	blocker_layer.add_child(blocker_feedback)
	blocker_feedback.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	blocker_feedback.offset_left = 210.0
	blocker_feedback.offset_right = 680.0
	blocker_feedback.offset_top = -72.0
	blocker_feedback.offset_bottom = -14.0

	# Separate layer ensures a placement confirmation remains visible
	# briefly even after the last inventory token has been consumed.
	blocker_notice_layer = CanvasLayer.new()
	blocker_notice_layer.name = "BridgeBlockerFeedback"
	blocker_notice_layer.layer = 95
	add_child(blocker_notice_layer)
	blocker_notice = Label.new()
	blocker_notice.name = "BlockerNotice"
	blocker_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blocker_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker_notice.add_theme_font_size_override("font_size", 17)
	blocker_notice_layer.add_child(blocker_notice)
	blocker_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	blocker_notice.offset_left = -240.0
	blocker_notice.offset_right = 240.0
	blocker_notice.offset_top = -92.0
	blocker_notice.offset_bottom = -50.0
	blocker_notice.hide()
	blocker_layer.hide()


func _has_player_blocker_slots() -> bool:
	if not is_instance_valid(builder) or not is_instance_valid(level_tools):
		return false
	var modes: Dictionary = level_tools.get("bridge_modes")
	var blocked: Dictionary = {}
	if is_instance_valid(test_level):
		blocked = test_level.get("player_blocked_bridges")
	for record in builder.connection_layer.connections:
		var key: String = PortRules.bridge_key(str(record["from_uid"]), str(record["to_uid"]))
		if int(modes.get(key, 0)) == 5 and not blocked.has(key):
			return true
	return false


func _update_bridge_blocker_inventory() -> void:
	if blocker_token == null:
		return
	blocker_token.text = "✕  Drag blocker ×%d" % blocker_remaining
	blocker_token.disabled = blocker_remaining <= 0
	blocker_layer.visible = (blocker_remaining > 0 and _has_player_blocker_slots())


func _begin_blocker_drag(screen_position: Vector2) -> void:
	if blocker_remaining <= 0 or switch_turning or bool(test_level.get("finished")):
		return
	if result_layer.visible or pause_layer.visible:
		return
	if blocker_return_tween != null:
		blocker_return_tween.kill()
		blocker_return_tween = null
	blocker_dragging = true
	blocker_ghost.modulate.a = 1.0
	blocker_ghost.scale = Vector2.ONE
	blocker_ghost.show()
	blocker_token.modulate.a = 0.45
	if builder.connection_layer.has_method("set_player_drag_active"):
		builder.connection_layer.set_player_drag_active(true)
	_update_blocker_drag(screen_position)


func _update_blocker_drag(screen_position: Vector2) -> void:
	var hovered: String = _player_slot_at_screen_position(screen_position)
	var ghost_target: Vector2 = screen_position
	if not hovered.is_empty():
		# Magnetic cursor: as the pointer gets close, the token visibly
		# snaps toward the exact midpoint of the valid bridge socket.
		ghost_target = screen_position.lerp(_player_slot_screen_position(hovered), 0.83)
		blocker_ghost.scale = Vector2.ONE * 1.15
		blocker_ghost.add_theme_color_override("font_color", Color("#21D69C"))
		blocker_feedback.text = "Release to seal this bridge. In-flight pulses will finish."
	else:
		blocker_ghost.scale = Vector2.ONE
		blocker_ghost.add_theme_color_override("font_color", Color("#F08D75"))
		blocker_feedback.text = "Move over a glowing socket to place your blocker."
	blocker_ghost.position = ghost_target + Vector2(-10.0, -20.0)
	if builder.connection_layer.has_method("set_player_slot_preview"):
		builder.connection_layer.set_player_slot_preview(hovered)


func _finish_blocker_drag(screen_position: Vector2) -> void:
	# Always release the drag state, including an invalid drop.
	var key: String = _player_slot_at_screen_position(screen_position)
	blocker_dragging = false
	blocker_token.modulate.a = 1.0
	if builder.connection_layer.has_method("set_player_slot_preview"):
		builder.connection_layer.set_player_slot_preview("")
	if builder.connection_layer.has_method("set_player_drag_active"):
		builder.connection_layer.set_player_drag_active(false)
	if key.is_empty():
		_return_blocker_ghost_to_tray()
		_show_blocker_notice("Find a glowing socket — blocker returned", false)
		return
	blocker_ghost.hide()
	blocker_ghost.scale = Vector2.ONE
	if test_level.place_player_bridge_blocker(key):
		blocker_remaining -= 1
		_update_bridge_blocker_inventory()
		if builder.connection_layer.has_method("flash_player_blocker_placement"):
			builder.connection_layer.flash_player_blocker_placement(key)
		_show_blocker_notice("Bridge sealed — %d blocker(s) left" % blocker_remaining, true)
	else:
		_show_blocker_notice("That bridge can no longer be blocked", false)


func _return_blocker_ghost_to_tray() -> void:
	# Invalid drop: glide the token back without spending it.
	if blocker_return_tween != null:
		blocker_return_tween.kill()
	blocker_ghost.modulate.a = 1.0
	blocker_ghost.scale = Vector2.ONE
	blocker_ghost.show()
	var tray_position: Vector2 = blocker_token.get_global_rect().get_center()
	blocker_return_tween = create_tween().set_parallel(true)
	blocker_return_tween.tween_property(
		blocker_ghost, "position", tray_position + Vector2(-10.0, -20.0), 0.24
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	blocker_return_tween.tween_property(
		blocker_ghost, "modulate:a", 0.0, 0.24
	)
	blocker_return_tween.chain().tween_callback(Callable(blocker_ghost, "hide"))


func _player_slot_screen_position(bridge_id: String) -> Vector2:
	if not is_instance_valid(builder) or not is_instance_valid(puzzle_grid):
		return Vector2.ZERO
	for record in builder.connection_layer.connections:
		var key: String = PortRules.bridge_key(str(record["from_uid"]), str(record["to_uid"]))
		if key != bridge_id:
			continue
		var path: Array[Vector2i] = []
		for cell in record.get("path", []):
			path.append(cell)
		if path.size() < 2:
			break
		var length: float = builder.connection_layer.get_path_length(path)
		var grid_point: Vector2 = builder.connection_layer.get_visual_point(path, length * 0.5)
		return puzzle_grid.get_global_transform_with_canvas() * grid_point
	return Vector2.ZERO


func _show_blocker_notice(message: String, success: bool) -> void:
	if blocker_notice == null:
		return
	if blocker_notice_tween != null:
		blocker_notice_tween.kill()
	blocker_notice.text = message
	blocker_notice.add_theme_color_override(
		"font_color", Color("#127D69") if success else Color("#C45443")
	)
	blocker_notice.modulate.a = 1.0
	blocker_notice.show()
	blocker_notice_tween = create_tween()
	blocker_notice_tween.tween_interval(1.1)
	blocker_notice_tween.tween_property(blocker_notice, "modulate:a", 0.0, 0.55)
	blocker_notice_tween.tween_callback(blocker_notice.hide)


func _player_slot_at_screen_position(screen_position: Vector2) -> String:
	if not is_instance_valid(builder) or not is_instance_valid(puzzle_grid):
		return ""
	var modes: Dictionary = level_tools.get("bridge_modes")
	var blocked: Dictionary = test_level.get("player_blocked_bridges")
	var best: String = ""
	var nearest: float = 32.0
	for record in builder.connection_layer.connections:
		var key: String = PortRules.bridge_key(str(record["from_uid"]), str(record["to_uid"]))
		if int(modes.get(key, 0)) != 5 or blocked.has(key):
			continue
		var path: Array[Vector2i] = []
		for cell in record.get("path", []):
			path.append(cell)
		if path.size() < 2:
			continue
		var length: float = builder.connection_layer.get_path_length(path)
		var grid_point: Vector2 = builder.connection_layer.get_visual_point(path, length * 0.5)
		var screen_point: Vector2 = puzzle_grid.get_global_transform_with_canvas() * grid_point
		var distance: float = screen_position.distance_to(screen_point)
		if distance < nearest:
			best = key
			nearest = distance
	return best


func _restore_blockers_on_retry() -> void:
	blocker_remaining = blocker_total
	blocker_dragging = false
	if blocker_return_tween != null:
		blocker_return_tween.kill()
		blocker_return_tween = null
	blocker_ghost.modulate.a = 1.0
	blocker_ghost.scale = Vector2.ONE
	blocker_ghost.hide()
	if blocker_token != null:
		blocker_token.modulate.a = 1.0
	if is_instance_valid(builder) and builder.connection_layer.has_method("set_player_slot_preview"):
		builder.connection_layer.set_player_slot_preview("")
	if is_instance_valid(builder) and builder.connection_layer.has_method("set_player_drag_active"):
		builder.connection_layer.set_player_drag_active(false)
	_update_bridge_blocker_inventory()


# ============================================================
# BEGIN NODE INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not ready_to_play or not is_instance_valid(test_level) or transitioning:
		return

	# The level selector captures input while open. Simulation is paused
	# on entry, so no switches/blocker placements happen underneath it.
	if level_select_layer != null and level_select_layer.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_L:
				_close_level_select()
				get_viewport().set_input_as_handled()
		return

	# Player drops blockers on authored bridge slots, including while
	# pulses are moving. Already in-flight pulses complete as normal.
	if blocker_dragging:
		if event is InputEventMouseMotion:
			_update_blocker_drag(event.position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				_finish_blocker_drag(event.position)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if blocker_token != null and blocker_layer.visible:
				if blocker_token.get_global_rect().has_point(event.position):
					_begin_blocker_drag(event.position)
					get_viewport().set_input_as_handled()
					return

	# No extra input while an Alternating Node is rotating.
	if switch_turning:
		return

	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		match event.keycode:
			KEY_L:
				_open_level_select()
				get_viewport().set_input_as_handled()
			KEY_SPACE, KEY_ESCAPE:
				if not result_layer.visible:
					_toggle_pause()
					get_viewport().set_input_as_handled()
			KEY_R:
				_retry()
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				_reset_to_begin_selection()
				get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if result_layer.visible or pause_layer.visible:
		return
	if not str(test_level.get("selected_start_id")).is_empty():
		return

	# Use the exact same eligibility and stable hit area as the hover.
	var closest_uid: String = _hovered_interactable_uid(event.position)
	if closest_uid.is_empty():
		return

	var chosen: PuzzleNode = builder.nodes_by_id[closest_uid] as PuzzleNode
	match chosen.kind:
		PuzzleNode.Kind.ALTERNATING:
			_animate_player_rotor(chosen)
		PuzzleNode.Kind.SPLITTER:
			_animate_player_rotor(chosen)
		PuzzleNode.Kind.BEGIN:
			# Launch locks further edits until Retry or Choose Start.
			test_level._start_from(closest_uid)
	get_viewport().set_input_as_handled()


# ============================================================
# CLICK ROTOR - ALTERNATING / SPLITTER
# Honeycomb +120 degrees; square/rhombus +90 degrees.
# No dragging, bridge rerouting, or repositioning.
# ============================================================

func _cancel_player_switch_animation() -> void:
	if switch_tween != null:
		switch_tween.kill()
		switch_tween = null

	if is_instance_valid(switch_holder):
		switch_holder.position = switch_holder_base_position
		switch_holder.rotation = switch_holder_base_rotation
		switch_holder.scale = switch_holder_base_scale

	if is_instance_valid(switch_node):
		switch_node.player_switch_animating = false
		switch_node.queue_redraw()

	switch_turning = false
	switch_node = null
	switch_holder = null


func _animate_player_rotor(node: PuzzleNode) -> void:
	if switch_turning or not is_instance_valid(node):
		return
	if not node.player_editable:
		return
	if node.kind != PuzzleNode.Kind.ALTERNATING and node.kind != PuzzleNode.Kind.SPLITTER:
		return
	# Rotating a Splitter must change its actual two active output ports,
	# which requires the level's explicit two-way bridge setting.
	if node.kind == PuzzleNode.Kind.SPLITTER:
		if not bool(test_level.get("allow_reverse_connections")):
			push_warning("This level needs Two-way bridges enabled to rotate Splitters.")
			return
		var splitter_rotor: Dictionary = PortRules.get_rotor(
			node.node_uid, builder.connection_layer.connections,
			builder.nodes_by_id, puzzle_grid,
			int(node.port_rotation_steps), true
		)
		if not bool(splitter_rotor.get("valid", false)):
			push_warning("The Splitter needs at least three attached bridges.")
			return

	# Player Mode places each PuzzleNode inside PlayerVisualScale.
	# Animating this holder avoids fighting PuzzleNode's existing
	# activation/pop animations, which modify the node's own scale.
	var holder: Node2D = node.get_parent() as Node2D
	if holder == null or not holder.has_meta("em_player_visual_wrapper"):
		return

	switch_turning = true
	switch_node = node
	switch_holder = holder
	switch_holder_base_position = holder.position
	switch_holder_base_rotation = holder.rotation
	switch_holder_base_scale = holder.scale

	var turn_degrees: float = 90.0
	var live_grid: SquarePuzzleGrid = puzzle_grid as SquarePuzzleGrid
	if live_grid != null and live_grid.is_honeycomb():
		turn_degrees = 120.0

	# Keep only the intended ports illuminated during the turn.
	node.player_switch_animating = true
	node.queue_redraw()

	var raised_position: Vector2 = (
		switch_holder_base_position + Vector2.UP * switch_pickup_height
	)
	var raised_scale: Vector2 = (
		switch_holder_base_scale * switch_pickup_scale
	)
	var final_rotation: float = (
		switch_holder_base_rotation + deg_to_rad(turn_degrees)
	)

	var tween: Tween = create_tween()
	switch_tween = tween

	# Lift slightly above the bridge and enlarge.
	tween.tween_property(
		holder, "scale", raised_scale, switch_pickup_seconds
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(
		holder, "position", raised_position, switch_pickup_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# The hover lift is relative to the node. Centre it smoothly before
	# the rotation so it spins around its middle rather than orbiting.
	tween.parallel().tween_property(
		node, "position", Vector2.ZERO, switch_pickup_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Clockwise positive rotation (Godot's 2D Y axis points down).
	tween.tween_property(
		holder, "rotation", final_rotation, switch_rotation_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# A short soft squash, followed by a tiny settling bounce.
	tween.tween_property(
		holder, "scale",
		switch_holder_base_scale * 0.93,
		switch_putdown_seconds * 0.50
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(
		holder, "position",
		switch_holder_base_position,
		switch_putdown_seconds * 0.50
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(
		holder, "scale",
		switch_holder_base_scale,
		switch_putdown_seconds * 0.50
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tween.finished
	if not is_inside_tree() or not is_instance_valid(node):
		return
	if not is_instance_valid(holder) or switch_tween != tween:
		return

	# Update actual port choices BEFORE the visual wrapper resets.
	# The same physical port that was bright now remains bright after
	# its 120-degree rotation; do not auto-correct to upper/lower.
	var step_count: int = 3 if turn_degrees == 120.0 else 4
	var old_steps: int = int(node.port_rotation_steps)
	var next_steps: int = posmod(old_steps + 1, step_count)
	if node.kind == PuzzleNode.Kind.ALTERNATING:
		# Honeycomb two-way has three ports: the rotation step alone
		# selects the next bright arm. Do not flip the old 2-choice flag.
		if not (turn_degrees == 120.0 and bool(test_level.get("allow_reverse_connections"))):
			node.alternating_first_branch = 1 - int(node.alternating_first_branch)
		node.set_alternating_display(-1)
	node.port_rotation_steps = next_steps
	holder.rotation = switch_holder_base_rotation
	holder.position = switch_holder_base_position
	holder.scale = switch_holder_base_scale
	node.player_switch_animating = false
	node.refresh_visuals()

	switch_tween = null
	switch_node = null
	switch_holder = null
	switch_turning = false


# ============================================================
# PLAYER ACTIONS
# ============================================================

func _toggle_pause() -> void:
	if not ready_to_play or result_layer.visible:
		return
	if str(test_level.get("selected_start_id")).is_empty():
		return
	if bool(test_level.get("finished")):
		return
	test_level._toggle_pause()
	if bool(test_level.get("paused")):
		pause_layer.show()
	else:
		pause_layer.hide()


func _retry() -> void:
	if not ready_to_play or transitioning:
		return
	pause_layer.hide()
	result_layer.hide()
	result_was_shown = false
	_restore_blockers_on_retry()
	if str(test_level.get("selected_start_id")).is_empty():
		_reset_to_begin_selection()
		return
	test_level._replay()


func _reset_to_begin_selection() -> void:
	if not ready_to_play or transitioning:
		return
	pause_layer.hide()
	result_layer.hide()
	result_was_shown = false
	_restore_blockers_on_retry()
	test_level._reset_run_state()
	test_level.selected_start_id = ""


# ============================================================
# COMPLETION SCREEN
# ============================================================

func _show_final_result() -> void:
	if not ready_to_play:
		return
	result_was_shown = true

	# The existing EM9 test engine records its outcome in this label:
	# "SUCCESS at tick ..." or "FAILED at tick ...".
	var engine_status: String = ""
	var internal_status: Label = test_level.get("status_label") as Label
	if internal_status != null:
		engine_status = internal_status.text

	var success: bool = engine_status.begins_with("SUCCESS")
	var tick: int = int(test_level.get("current_tick"))
	var reason: String = str(test_level.get("failure_reason"))

	if success:
		# Persist immediately, BEFORE asking the manager for the next
		# unlocked level. Custom/sandbox levels are ignored by the manager.
		if campaign_manager != null:
			campaign_manager.call("mark_level_completed", level_file_path, tick)
		result_heading.text = "PUZZLE COMPLETED"
		result_description.text = (
			_level_name(level_file_path)
			+ "\nCompleted at tick %d.\n%s" % [tick, reason]
		)
	else:
		result_heading.text = "TRY AGAIN"
		result_description.text = (
			"Run ended at tick %d.\n%s" % [tick, reason]
		)

	var next_path: String = _get_next_level_path()
	var next_exists: bool = (
		success
		and not next_path.is_empty()
		and FileAccess.file_exists(next_path)
	)
	result_next_button.visible = next_exists

	# With automatic progression, keep the completed puzzle on
	# screen briefly, then dissolve only its nodes/connections.
	if next_exists and auto_advance_on_success:
		transitioning = true
		call_deferred("_run_level_transition", next_path, true)
		return

	# Don't silently hide the next-level option if its JSON is missing.
	if success and not next_path.is_empty() and not next_exists:
		result_description.text += (
			"\n\nNEXT LEVEL FILE MISSING:\n" + next_path
			+ "\nCopy its JSON file into res://levels/."
		)
		push_warning("PlayerMode: next level missing: " + next_path)

	result_retry_button.show()
	result_reset_button.show()
	result_layer.show()


func _show_setup_error(message: String) -> void:
	push_error("PlayerMode: " + message)
	ready_to_play = false
	pause_layer.hide()
	result_heading.text = "COULD NOT LOAD LEVEL"
	result_description.text = message
	result_next_button.hide()
	result_retry_button.hide()
	result_reset_button.hide()
	result_layer.show()


# ============================================================
# UI - ONLY MODAL PAUSE AND RESULTS; NO TOP BAR
# ============================================================

func _make_button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _create_pause_overlay() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.name = "PauseOverlay"
	pause_layer.layer = 150
	add_child(pause_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.13, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(shade)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	pause_layer.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360.0, 160.0)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = "PAUSED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	_make_button(row, "Resume", _toggle_pause)
	_make_button(row, "Retry", _retry)
	_make_button(row, "Adjust Switches / Choose Start", _reset_to_begin_selection)
	_make_button(row, "Levels", _open_level_select)
	pause_layer.hide()


func _create_result_overlay() -> void:
	result_layer = CanvasLayer.new()
	result_layer.name = "ResultOverlay"
	result_layer.layer = 200
	add_child(result_layer)

	var dim := ColorRect.new()
	dim.name = "Dimmer"
	dim.color = Color(0.02, 0.07, 0.15, 0.67)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.name = "CentreDialog"
	result_layer.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 230.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	margin.add_child(column)

	result_heading = Label.new()
	result_heading.text = "RESULT"
	result_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_heading.add_theme_font_size_override("font_size", 27)
	column.add_child(result_heading)

	result_description = Label.new()
	result_description.text = ""
	result_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(result_description)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	result_next_button = _make_button(row, "Next Level", _next_level)
	result_retry_button = _make_button(row, "Retry Same Start", _retry)
	result_reset_button = _make_button(row, "Adjust Switches / Choose Start", _reset_to_begin_selection)
	_make_button(row, "Levels", _open_level_select)
	result_layer.hide()


# ============================================================
# CAMPAIGN LEVEL SELECTION - RUNTIME UI, NO EXTRA .TSCN
# Press L, or use "Levels" from Pause / Result.
# ============================================================

func _create_level_select_overlay() -> void:
	level_select_layer = CanvasLayer.new()
	level_select_layer.name = "CampaignLevelSelect"
	level_select_layer.layer = 240
	add_child(level_select_layer)

	# CanvasLayer is not a Control: give its UI an actual full-viewport
	# Control parent. Without this, PRESET_FULL_RECT can leave the menu
	# at its minimum panel dimensions in the top-left corner.
	level_select_root = Control.new()
	level_select_root.name = "FullScreenUI"
	level_select_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_select_layer.add_child(level_select_root)
	level_select_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_select_root.size = get_viewport_rect().size

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.13, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	level_select_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_select_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 430.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = "SELECT A LEVEL"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)

	level_select_summary = Label.new()
	level_select_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(level_select_summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480.0, 285.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	level_select_list = VBoxContainer.new()
	level_select_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_select_list.add_theme_constant_override("separation", 8)
	scroll.add_child(level_select_list)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)
	_make_button(footer, "Back to Puzzle  (L / Esc)", _close_level_select)

	level_select_layer.hide()


func _refresh_level_select() -> void:
	if campaign_manager == null or level_select_list == null:
		return
	for child in level_select_list.get_children():
		level_select_list.remove_child(child)
		child.queue_free()

	var levels: Array = campaign_manager.call("get_all_levels")
	var completed_count: int = int(campaign_manager.call("get_completed_count"))
	level_select_summary.text = "%d / %d completed" % [completed_count, levels.size()]

	for entry_value in levels:
		var entry: Dictionary = entry_value
		var path: String = str(entry.get("path", ""))
		var unlocked: bool = bool(campaign_manager.call("is_level_unlocked", path))
		var selectable: bool = unlocked or developer_allow_locked_levels
		var finished: bool = bool(campaign_manager.call("is_level_completed", path))
		var file_exists: bool = FileAccess.file_exists(path)
		var best: int = int(campaign_manager.call("get_best_ticks", path))

		var level_id: String = str(entry.get("id", ""))
		var display_number: String = level_id.replace("level_", "")
		var label: String = "%s   %s" % [display_number, str(entry.get("title", level_id))]
		if finished:
			label += "    ✓ Completed"
			if best >= 0:
				label += " (%d ticks)" % best
		elif not unlocked:
			label += "    🔒 Locked"
		elif not file_exists:
			label += "    [JSON missing]"
		else:
			label += "    Ready"
		if path == level_file_path:
			label += "    • Current"

		var button := Button.new()
		button.text = label
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(460.0, 44.0)
		button.disabled = not selectable or not file_exists
		button.tooltip_text = str(entry.get("description", ""))
		button.pressed.connect(_select_campaign_level.bind(path))
		level_select_list.add_child(button)

	if levels.is_empty():
		var notice := Label.new()
		notice.text = "No campaign levels found. Check levels/campaign_manifest.json."
		level_select_list.add_child(notice)


func _open_level_select() -> void:
	if not ready_to_play or transitioning or level_select_layer.visible:
		return
	level_select_paused_by_menu = false
	if is_instance_valid(test_level):
		if bool(test_level.get("running")) and not bool(test_level.get("paused")) and not bool(test_level.get("finished")):
			test_level._toggle_pause()
			level_select_paused_by_menu = true
	_refresh_level_select()
	pause_layer.hide()
	blocker_layer.hide()
	level_select_layer.show()


func _close_level_select() -> void:
	if not level_select_layer.visible:
		return
	level_select_layer.hide()
	if level_select_paused_by_menu and is_instance_valid(test_level):
		if bool(test_level.get("paused")) and not bool(test_level.get("finished")):
			test_level._toggle_pause()
	level_select_paused_by_menu = false


func _select_campaign_level(path: String) -> void:
	if transitioning or campaign_manager == null:
		return
	if not developer_allow_locked_levels:
		if not bool(campaign_manager.call("is_level_unlocked", path)):
			return
	if not FileAccess.file_exists(path):
		return

	# Do NOT resume the outgoing level; we are about to replace it.
	level_select_layer.hide()
	level_select_paused_by_menu = false
	pause_layer.hide()
	result_layer.hide()
	transitioning = true
	call_deferred("_run_level_transition", path, false)
